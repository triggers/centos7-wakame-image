#!/bin/bash
#
# requires:
#  bash
#
set -e

declare chroot_dir=$1

chroot $1 $SHELL -ex <<EOS
  case "$(sed -e 's/.*release \(.*\) .*/\1/' ${chroot_dir}/etc/redhat-release)" in
    5.*) rpm -qa zabbix-jp-release* | egrep -q zabbix-jp-release || { rpm -Uvh http://repo.zabbix.jp/relatedpkgs/rhel5/x86_64/zabbix-jp-release-5-6.noarch.rpm; } ;;
    6.*) rpm -qa zabbix-jp-release* | egrep -q zabbix-jp-release || { rpm -Uvh http://repo.zabbix.jp/relatedpkgs/rhel6/x86_64/zabbix-jp-release-6-6.noarch.rpm; } ;;
  esac
  yum repolist
EOS
