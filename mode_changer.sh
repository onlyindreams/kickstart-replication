#! /bin/bash
#***************************************
#* mode_changer.sh *
#***************************************
#[description]
#引数に応じたモードにPostgreSQLを変更する
#起動および停止処理は行わない
#primary...プライマリサーバモード
#standby...スタンバイサーバモード
#failover...縮退サーバモード
#[usage]
#mode_changer.sh [primary|standby|failover]
#[history]
#2012/04/09 第１版作成
#2013/04/01 第２版作成
## 1.DBが起動していなくても設定ファイルのコピー処理
## を実施可能になるように変更
#2014/07/24 第2.1版作成
## 設定ファイルをinclude識別子で読み込ませるよう変更
## nodeを引数として指定するよう変更

if [ $# -ne 2 ];
then
   echo "argument error." >&2
   echo "USAGE: $0 [primary|standby|failover] [node]" >&2
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

if [ $# -ne 2 ]
then
    echo "argument error." >&2
    exit 1
fi

MODE=$1

#モードに応じたconfを配置
case "${MODE}" in
    "primary" )
        sed -i "s/\(^include[ ].*\)/\#\1 #removed/g" ${PGDATA}/postgresql.conf
        sed -i "s/^\#\(include\)[ ].*/\1 '"${PRM_CONFIG//\//\\\/}"'/g" ${PGDATA}/postgresql.conf
        if [ -z "`grep -e ^include ${PGDATA}/postgresql.conf`" ];
        then
          echo "include '${PRM_CONFIG}'" >> ${PGDATA}/postgresql.conf
        fi
	;;
    "standby" )
        sed -i "s/\(^include[ ].*\)/\#\1 #removed/g" ${PGDATA}/postgresql.conf
        sed -i "s/^\#\(include\)[ ].*/\1 '"${STB_CONFIG//\//\\\/}"'/g" ${PGDATA}/postgresql.conf
        if [ -z "`grep -e ^include ${PGDATA}/postgresql.conf`" ];
        then
          echo "include '${STB_CONFIG}'" >> ${PGDATA}/postgresql.conf
        fi
	;;
    "failover" )
        sed -i "s/\(^include[ ].*\)/\#\1 #removed/g" ${PGDATA}/postgresql.conf
        sed -i "s/^\#\(include\)[ ].*/\1 '"${UNI_CONFIG//\//\\\/}"'/g" ${PGDATA}/postgresql.conf
        if [ -z "`grep -e ^include ${PGDATA}/postgresql.conf`" ];
        then
          echo "include '${UNI_CONFIG}'" >> ${PGDATA}/postgresql.conf
        fi        
        ;;
    * )
        echo "invalid mode:${MODE}" >&2
        exit 1
        ;;
esac


#DBが起動していればリロード処理を行う
${PGHOME}/bin/pg_ctl -D ${PGDATA} status 1>/dev/null 2>&1 </dev/null 
if [ $? -eq 0 ]
then
    #PostgreSQLのリロードを行う
    ${PGHOME}/bin/pg_ctl -D ${PGDATA} reload 1>/dev/null 2>&1 </dev/null
    if [ $? -ne 0 ]
        then
        echo "reload failed." >&2
        exit 1
    fi
fi

exit 0
