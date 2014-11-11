#! /bin/bash

ulimit -s unlimited

#
# PostgreSQL's Parameters
#
NODE=node0
CONF=pgrepli.conf
if [ -f ${CONF} ]
then
    . ${CONF} 
else
    echo "${CONF} not found." >&2
    exit 1
fi

#postgresql.conf.masterファイルの作成

echo "#----------------------------------------------------------------------">>postgresql.conf.tmp
echo "# MY REPLICATION SETTING OPTIONS                                       ">>postgresql.conf.tmp
echo "#----------------------------------------------------------------------">>postgresql.conf.tmp
echo "log_line_prefix = '%t [master] %p '                          #* add *#" >>postgresql.conf.tmp
echo "max_wal_senders = 1                                          #* add *#" >>postgresql.conf.tmp
echo "synchronous_standby_names = '*'                              #* add *#" >>postgresql.conf.tmp
echo "hot_standby = on                                             #* add *#" >>postgresql.conf.tmp
echo "archive_mode = on                                            #* add *#" >>postgresql.conf.tmp
echo "wal_level = hot_standby                                      #* add *#" >>postgresql.conf.tmp
echo "archive_command = 'cp %p ${ARCHIVEDIR}/%f'                   #* add *#" >>postgresql.conf.tmp
echo "wal_keep_segments = 0                                        #* add *#" >>postgresql.conf.tmp

mv postgresql.conf.tmp "${PRM_CONFIG}"
echo "${PRM_CONFIG} has created."

#postgresql.conf.slaveファイルの作成

echo "#---------------------------------------------------------------------">>postgresql.conf.tmp
echo "# MY REPLICATION SETTING OPTIONS                                      ">>postgresql.conf.tmp
echo "#---------------------------------------------------------------------">>postgresql.conf.tmp
echo "log_line_prefix = '%t [slave] %p '                           #* add *#" >>postgresql.conf.tmp
echo "max_wal_senders = 1                                          #* add *#" >>postgresql.conf.tmp
echo "hot_standby = on                                             #* add *#" >>postgresql.conf.tmp
echo "archive_mode = on                                            #* add *#" >>postgresql.conf.tmp
echo "wal_level = hot_standby                                      #* add *#" >>postgresql.conf.tmp

mv postgresql.conf.tmp "${STB_CONFIG}"
echo "${STB_CONFIG} has created."

#postgresql.conf.unitファイルの作成

echo "#---------------------------------------------------------------------">>postgresql.conf.tmp
echo "# MY REPLICATION SETTING OPTIONS                                      ">>postgresql.conf.tmp
echo "#---------------------------------------------------------------------">>postgresql.conf.tmp
echo "log_line_prefix = '%t [unit] %p '                            #* add *#" >>postgresql.conf.tmp
echo "max_wal_senders = 1                                          #* add *#" >>postgresql.conf.tmp
echo "wal_keep_segments = 100                                      #* add *#" >>postgresql.conf.tmp
echo "hot_standby = on                                             #* add *#" >>postgresql.conf.tmp
echo "archive_mode = on                                            #* add *#" >>postgresql.conf.tmp
echo "wal_level = hot_standby                                      #* add *#" >>postgresql.conf.tmp
echo "archive_command = ':'                                        #* add *#" >>postgresql.conf.tmp

mv postgresql.conf.tmp "${UNI_CONFIG}"
echo "${UNI_CONFIG} has created."

