#!/bin/bash
#
# requires:
#  bash
#
set -e

declare chroot_dir=$1

# create 6.5 updates repofile.
cat <<'EOS' > $1/etc/yum.repos.d/centos-6.5-update.repo
#released updates
[updates-6.5]
name=CentOS-6.5 - Updates
baseurl=http://vault.centos.org/6.5/updates/$basearch
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6
EOS

chroot $1 $SHELL -ex <<EOS
  yum clean metadata --disablerepo='*' --enablerepo='updates-6.5'
  yum repolist
  yum update -y bash openssl
EOS

# remove 6.5 updates repofile.
rm -f $1/etc/yum.repos.d/centos-6.5-update.repo

