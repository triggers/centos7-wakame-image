#!/bin/bash
#
# requires:
#  bash
#
set -e

declare chroot_dir=$1

cat <<-'EOS' >> ${chroot_dir}/etc/rc.d/rc.local
        # need to start td-agent after running /etc/wakame-init
	/etc/init.d/td-agent start
	EOS
cat ${chroot_dir}/etc/rc.d/rc.local
