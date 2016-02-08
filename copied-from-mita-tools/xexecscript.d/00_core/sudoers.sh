#!/bin/bash
#
# requires:
#  bash
#
set -e

declare chroot_dir=$1

requiretty=0
configure_sudo_requiretty ${chroot_dir} ${requiretty} 
