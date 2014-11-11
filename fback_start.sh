#! /bin/bash
#***************************************
#* fback_start.sh *
#***************************************
#[description]
#引数に応じたモードでスタンバイPostgreSQLのフェイルバックを行います
#障害サーバで実行します
#縮退稼動中サーバへパスフレーズなしでsshログインが可能である必要があります
#
#rebuild...スタンバイサーバを再構築します.
#         以前プライマリサーバであったサーバのフェイルバックや、
#         WALアーカイブを行なっていない場合はこのコマンドを実行して
#         ください.
#         WALアーカイブを行っている場合は、データベース自体の容量
#         が大きい、または停止期間中に多くのトランザクションが実行
#         されている場合はこのモードを使用してください。
#walreply...スタンバイサーバの停止期間が短い場合は、WALアーカイブの
#         同期をとらずに回復処理を実施します。スタンバイ側の停止期間
#         が長く、マスタ側のWALアーカイブを同期する必要がある場合は
#         マスタ側のWALアーカイブをスタンバイ側にコピー後、その
#         アーカイブを使用してリカバリ処理を行います。ただし、停止
#         期間中に多くのトランザクションが実行されている場合完全同期
#         まで時間を多く要する可能性があります.
#         以前プライマリサーバであったサーバに対しては実行できません.
#         スタンバイ側の最新のWALがマスタ側に見つけられなかった場合
#         スクリプトは2を返却します。
#revive  ...まず、wareplyモードを実行し、walreplyモードでは復旧不可
#         の場合に、rebuildモードを実行します。
#
#[usage]
#fback_start.sh [rebuild|walreply|revive] [node]
#[history]
#2012/04/09 第１版作成
#2013/04/02 第２版作成　
## 1.simpleモードをwalreplyモードに統合
## 2.幾つかの不具合箇所を修正
## 3.walreplyモードにおいて、マスタ側にWALを見つけられ
## なかった場合、またrecovery.confが存在しなかった場合
## の戻り値を1 -> 2に変更。
## 4.reviveモードの追加。まずwalreplyを試し、
## 失敗したらrebuildを実行します。
#2013/11/29 第2.1版作成
## REMOTEPATH変数削除。readlinkによりパスを求める。
## 全てのノードで同一パス上にスクリプトが置かれる前提とする
## 同一ノード上でレプリケーション構成を構築する場合を考慮
## してノード別のディレクトリに分けて保存し、NODE変数に
## 読み込むpgrepli.confを切り替える
#2014/07/24 第2.2版作成
## nodeを引数として指定するよう変更

if [ $# -ne 2 ];
then
   echo "ARGUMENT ERROR" >&2
   echo "USAGE: $0 [rebuild|walreply|revive] [node]" >&2
   exit 1
fi

export NODE=$2


if [ ! "${NODE}" ];
then
    echo "export node0/node1 to \"NODE\" " >&2
    exit 1
fi

ulimit -s unlimited

#
# PostgreSQL's Parameters
#
CONF=pgrepli.conf
if [ -f ${CONF} ]
then
    . ${CONF}
else
    echo "${CONF} not found." >&2
    exit 1
fi

MODE=$1
SCRIPTPATH=`readlink -f $(dirname $0)`

#
# スタンバイデータ再構築モード
#
rebuild(){

    #すでに起動していれば実行しない
    ${PGHOME}/bin/pg_ctl -D ${PGDATA} status 1>/dev/null 2>&1 </dev/null
    if [ $? -eq 0 ]
    then
        echo "this server is already running" >&2
        return 1
    fi

    #スタンバイデータを退避する
    #退避先にデータが残っていたら削除する
    rm -rf  ${PGDATA}.1
    if [ -d ${PGDATA} ];
    then
        mv -f ${PGDATA} ${PGDATA}.1
    fi
    #pg_basebackupコマンドでデータ同期を行う
    ${PGHOME}/bin/pg_basebackup -D ${PGDATA} --xlog -h ${WALSTREAM_FIP} -p ${PGRPORT} -U ${PGUSER}
    #失敗したら終了する
    if [ $? -ne 0 ]
    then
        echo "base backup failed" >&2
        rm -rf ${PGDATA}
        mv ${PGDATA}.1 ${PGDATA} #ロールバック
        return 1
    fi    

    #recovery.conf作成
    echo "standby_mode=on" > ${PGDATA}/recovery.conf
    echo "primary_conninfo='host=${WALSTREAM_FIP} port=${PGRPORT} user=${PGUSER}'" >> ${PGDATA}/recovery.conf
    #echo "restore_command='cp -f ${ARCHIVEDIR}/%f %p'" >> ${PGDATA}/recovery.conf
    echo "recovery_target_timeline='latest'" >> ${PGDATA}/recovery.conf

    #スタンバイ用の設定ファイルを適用する
    ./mode_changer.sh standby ${NODE}
    if [ $? -ne 0 ];
    then
        return $?
    fi

    #スタンバイを起動する
    ${PGHOME}/bin/pg_ctl -D ${PGDATA} -w -o " -p ${PGPORT} " start

    #プライマリに接続しモードチェンジを行う
    PNODE=
    case ${NODE} in
    node0)
        PNODE=node1
        ;;
    node1)
        PNODE=node0
        ;;
    esac
    ssh ${WALSTREAM_FIP} "cd ${SCRIPTPATH};./mode_changer.sh primary ${PNODE}"
    return $?
}

#
# WALアーカイブ同期モード
#
walreply(){
    #recovery.confが存在するか確認する
    if [ ! -f ${PGDATA}/recovery.conf ]
    then
        echo "this mode can execute only on a standby server" >&2
        return 2
    fi

    #すでに起動していれば実行しない
    ${PGHOME}/bin/pg_ctl  -D ${PGDATA} status 1>/dev/null 2>&1 </dev/null
    if [ $? -eq 0 ]
    then
        echo "this server is already running" >&2
        return 1
    fi

    #リカバリに必要なWALがリモートサーバに存在するか確認する
    INDISPENSABLE_WAL=`ls -1t ${PGDATA}/pg_xlog | grep "[0-9,A-F]\{24\}$" | head -1`
    #まずは相手サーバのpg_xlogを調べる
    ssh ${WALSTREAM_FIP} "ls -1 ${PGRDATA}/pg_xlog | grep '${INDISPENSABLE_WAL}'" 1>/dev/null 2>&1 </dev/null
    if [ $? -ne 0 ]
    then
        #次に相手サーバのアーカイブディレクトリを調べる
        ssh ${WALSTREAM_FIP} "ls -1 ${ARCHIVEDIR} | grep '${INDISPENSABLE_WAL}'" 1>/dev/null 2>&1 </dev/null
        if [ $? -ne 0 ]
            then
            echo "Since WAL required for recovery does not exist, this mode cannot be used" >&2
            return 2
        fi
        #アーカイブからのリカバリが必要であるため、WALアーカイブをスタンバイ側にコピーする。
        echo "WAL ARCHIVE SYNCHRONIZING..."
        rsync -av -e ssh ${WALSTREAM_FIP}:${ARCHIVEDIR}/ ${PGDATA}/pg_xlog/
        echo "Done."
    fi

    #スタンバイを起動する
    ${PGHOME}/bin/pg_ctl -D ${PGDATA} -w -o " -p ${PGPORT} " start

    #プライマリに接続しモードチェンジを行う
    PNODE=
    case ${NODE} in
    node0)
        PNODE=node1
        ;;
    node1)
        PNODE=node0
        ;;
    esac
    ssh ${WALSTREAM_FIP} "cd ${SCRIPTPATH};./mode_changer.sh primary ${PNODE}"
    return $?
}


#モードに応じたフェイルバックを実行
case "${MODE}" in
    "rebuild" )
        rebuild
        ;;
    "walreply" )
        walreply
        ;;
    "revive"   )
        walreply 2>/dev/null
        if [ $? -eq 2 ];
        then
            rebuild
        fi
        ;;
    * )
        echo "invalid mode:${MODE}" >&2
        echo "USAGE: $0 [rebuild|walreply|revive] [node]" >&2
        exit 1
        ;;
esac

exit $?

