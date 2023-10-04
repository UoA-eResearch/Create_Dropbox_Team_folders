#!/bin/bash
#Run from cron (crontab -l)
#1 8,12,16,20 * * * /home/figshare/dropbox_gen_groups_from_ldap/bin/cron.sh > /home/figshare/dropbox_gen_groups_from_ldap/log/last_run.log 2>&1
#
export no_proxy=localhost,127.0.0.1,localaddress,.auckland.ac.nz,keystone.rc.nectar.org.au
export https_proxy=http://squid.auckland.ac.nz:3128
export http_proxy=http://squid.auckland.ac.nz:3128
#
RM="/bin/rm"
LOCKFILE="/home/figshare/bin/lockfile"
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
