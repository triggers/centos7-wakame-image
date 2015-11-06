#!/bin/bash
#
# requires:
#  bash
#
set -e

declare chroot_dir=$1

# release package version should be defined for wakame-vdc rpms
vdc_yum_repo_uri=${vdc_yum_repo_uri:-http://mita.dlc.wakame.axsh.jp/packages/rhel/6/devrelease/current/}
rpm_package=$(curl ${vdc_yum_repo_uri}index.html | grep wakame-init | awk -F '"' '{print $2}')

chroot $1 $SHELL -ex <<EOS
  rpm -ivh ${vdc_yum_repo_uri}${rpm_package}
EOS

chroot $1 $SHELL -ex <<EOS
  chkconfig wakame-init on
  chkconfig --list wakame-init
EOS

