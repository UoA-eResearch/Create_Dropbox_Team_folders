#!/bin/bash
#Run from cron (crontab -l)
#1 8,12,16,20 * * * /home/dropbox/bin/cron.sh > /home/dropbox/log/last_run.log 2>&1
#
base_dir="/home/dropbox"
# Now need a proxy to get out
. ${base_dir}/conf/proxy

RM="/bin/rm"
LOCKFILE="${base_dir}/bin/lockfile"
TMP_DIR="/tmp"
LOCK_PID_FILE=${TMP_DIR}/dropbox_cleanup.lock
log_date=`/bin/date "+%Y-%m-%d-%H"`
base_dir="/home/figshare/dropbox_gen_groups_from_ldap"

${LOCKFILE} ${LOCK_PID_FILE} $$
if [ $? != 0 ] ; then  exit 0 ; fi

/bin/date > ${base_dir}/log/cleanup_${log_date}.log
${base_dir}/bin/gone.rb >> ${base_dir}/log/cleanup_${log_date}.log 2>&1
/bin/date >> ${base_dir}/log/cleanup_${log_date}.log

${RM} -f ${LOCK_PID_FILE}
