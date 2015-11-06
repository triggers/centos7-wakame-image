#!/bin/bash
#
# requires:
#  bash
#
set -e

declare chroot_dir=$1

# create 6.6 updates repofile.
cat <<'EOS' > $1/etc/yum.repos.d/centos-6.6-update.repo
#released updates
[updates-6.6]
name=CentOS-6.6 - Updates
mirrorlist=http://mirrorlist.centos.org/?release=6&arch=$basearch&repo=updates
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6
EOS

chroot $1 $SHELL -ex <<EOS
  yum clean metadata --disablerepo='*' --enablerepo='updates-6.6'
  yum repolist
  yum update -y glibc glibc-common glibc-devel glibc-headers
EOS

# remove 6.6 updates repofile.
rm -f $1/etc/yum.repos.d/centos-6.6-update.repo

