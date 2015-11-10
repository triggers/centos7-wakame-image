#!/bin/bash
#
# requires:
#  bash
#

# The technique for centos7: (and maybe centos6)
# https://wiki.centos.org/FAQ/CentOS5
# https://wiki.centos.org/FAQ/CentOS6

cat >>/etc/sysctl.conf <<'EOF'
#
# from https://wiki.centos.org/FAQ/CentOS7:
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF

exit 0 # the above replaces the one below

# The technique below was for centos5:
# https://wiki.centos.org/FAQ/CentOS5

cat <<EOS > $1/etc/modprobe.d/disable-ipv6.conf
install ipv6 /bin/true
EOS

cat <<EOS >> $1/etc/sysconfig/network
NETWORKING_IPV6=no
IPV6INIT=no
EOS
