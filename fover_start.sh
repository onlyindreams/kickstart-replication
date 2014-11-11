#! /bin/bash
#***************************************
#* fover_start.sh *
#***************************************
#[description]
#フェイルオーバ(縮退運転動作)を行うスクリプトです。
#非障害サーバで実行することで、PostgreSQLが縮退モードに切り替わります。
#また、マスタの初回起動時のコマンドとしても使用可能です。
#[usage]
#fover_start.sh [node]
#[history]
#2012/04/06 第１版作成
#2013/04/02 第２版作成
## DBが起動していなければ縮退モードとして起動するよう変更。
#2014/07/24 第2.1版作成
## nodeを引数として指定するよう変更

if [ $# -ne 1 ];
then
   echo "argument error." >&2
   echo "USAGE: $0 [node]" >&2
   exit 1
fi

export NODE=$1

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

# 対象DBが起動しているか確認します
${PGHOME}/bin/pg_ctl -D ${PGDATA} status 1>/dev/null 2>&1 </dev/null
if [ $? -ne 0 ]
then
    #DBが起動していなければ縮退モードでの通常起動を行います。
    ./mode_changer.sh failover ${NODE}
    ${PGHOME}/bin/pg_ctl -D ${PGDATA} -w -o " -p ${PGPORT} " start
    if [ $? -ne 0 ]
    then
        echo "start failed." >&2
        exit 1
    fi
else
    #DBが起動していればpromoteするか通常起動を行うか判断します。

    # recovery.confが存在するか確認します
    # 存在すればpg_ctl promoteコマンドを実行します
    if [ -f ${PGDATA}/recovery.conf ]
    then
        ${PGHOME}/bin/pg_ctl -w -D ${PGDATA} promote 1>/dev/null 2>&1 </dev/null
        if [ $? -ne 0 ]
        then
            echo "promote failed." >&2
            exit 1
        fi 
    fi
    # 縮退モードに移行します。
    ./mode_changer.sh failover ${NODE}

fi

exit $?
