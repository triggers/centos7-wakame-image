#!/bin/bash
#
# requires:
#  bash
#
set -e

declare chroot_dir=$1

chroot $1 $SHELL -ex <<'EOS'
  # make sure to set NOZEROCONF=yes.
  sed  -i "s,^NOZEROCONF=.*,," /etc/sysconfig/network
  echo NOZEROCONF=yes >> /etc/sysconfig/network
  cat /etc/sysconfig/network
EOS
