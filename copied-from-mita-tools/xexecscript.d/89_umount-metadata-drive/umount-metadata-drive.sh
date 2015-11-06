#!/bin/bash
#
# requires:
#  bash
#
set -e

declare chroot_dir=$1

# always "md"
metadata_type=md

cat <<-EOS >> ${chroot_dir}/etc/rc.d/rc.local
	# need to umount /metadata after running /etc/wakame-init
	umount /metadata
	EOS
cat ${chroot_dir}/etc/rc.d/rc.local
