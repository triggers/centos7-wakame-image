#!/bin/bash
#
# requires:
#  bash
#
set -e

declare chroot_dir=$1
declare user_name=gouc-user

create_user_account    ${chroot_dir} ${user_name} 1000 1000
configure_sudo_sudoers ${chroot_dir} ${user_name} NOPASSWD:
