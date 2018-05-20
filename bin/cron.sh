#!/bin/sh
#Run from cron (crontab -l)
#1 8,12,16,20 * * * /home/figshare/dropbox_gen_groups_from_ldap/bin/cron.sh > /home/figshare/dropbox_gen_groups_from_ldap/log/last_run.log 2>&1
#
log_date=`/bin/date "+%Y-%m-%d-%H"`
base_dir="/home/figshare/dropbox_gen_groups_from_ldap"
/bin/date > ${base_dir}/log/run_${log_date}.log
${base_dir}/bin/add_ldap_group_to_dropbox.rb >> ${base_dir}/log/run_${log_date}.log 2>&1
/bin/date >> ${base_dir}/log/run_${log_date}.log
#
/usr/bin/find ${base_dir}/log -mtime +30 -exec rm -f {} \;
