#!/bin/bash
#
# requires:
#  bash
#
set -e

declare chroot_dir=$1

cat <<'EOS' > $1/etc/yum.repos.d/td.repo
[treasuredata]
name=TreasureData
baseurl=http://packages.treasure-data.com/redhat/$basearch
gpgcheck=0
EOS

# * [2013/09] td-agent-1.1.13 hva(instance-host), uservm
td_agent_version=${td_agent_version:-1.1.13}

# make sure to define td-agent version
case "${td_agent_version}" in
""|latest)
   td_agent_version=
   ;;
*)
   td_agent_version="-${td_agent_version}"
   ;;
esac

chroot $1 $SHELL -ex <<EOS
  # [2013/08/12] in order to avoid the following error.
  # > Error Downloading Packages:
  # > libxslt-1.1.26-2.el6.x86_64: failure: Packages/libxslt-1.1.26-2.el6.x86_64.rpm from base: [Errno 256] No more mirrors to try.
  yum clean metadata --disablerepo='*' --enablerepo='base'

  yum repolist
  yum install -y td-agent${td_agent_version}
  chkconfig --list td-agent
EOS
