#!/bin/bash
#
# requires:
#  bash
#

chroot $1 $SHELL -ex <<'EOS'
  chkconfig iptables off
EOS
