#!/bin/bash
#
# requires:
#  bash
#

chroot $1 $SHELL -ex <<'EOS'
  chkconfig iptables off
  chkconfig ip6tables off
EOS
