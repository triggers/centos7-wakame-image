#!/bin/bash
#
# requires:
#  bash
#
set -e

declare chroot_dir=$1

chroot $1 $SHELL -ex <<EOS
  # for this project specific version
  zabbix_version=1.8.16

  [[ -n "${zabbix_version}" ]] && {
    zabbix_version="-${zabbix_version}"
  }

  yum install -y \
     zabbix${zabbix_version} \
     zabbix-agent${zabbix_version}
EOS

chroot $1 $SHELL -ex <<EOS
  chkconfig zabbix-agent on
  chkconfig --list zabbix-agent
EOS
