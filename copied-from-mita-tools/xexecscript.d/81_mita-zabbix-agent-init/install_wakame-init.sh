#!/bin/bash
#
# requires:
#  bash
#
set -e

declare chroot_dir=$1

cat <<-'EOS' >> ${chroot_dir}/etc/rc.d/rc.local
	/etc/init.d/zabbix-agent stop
	Hostname=$(cat /metadata/meta-data/instance-id)
	ListenIP=$(cat /metadata/meta-data/local-ipv4)
	Server="$(echo $(cat /metadata/meta-data/x-monitoring/zabbix-servers) | sed "s/ /,/g;")"
	sed "s,^Hostname=.*,Hostname=${Hostname},; s,^ListenIP=.*,ListenIP=${ListenIP},; s/^Server=.*/Server=${Server}/;" /etc/zabbix/zabbix_agentd.conf.tmpl > /etc/zabbix/zabbix_agentd.conf
	/etc/init.d/zabbix-agent start
	EOS
cat ${chroot_dir}/etc/rc.d/rc.local
