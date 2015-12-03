#!/bin/bash

# set reportfailed, $skip_rest_if_already_done, etc.
source "$CODEDIR/bin/simple-bash-steps-defaults.source"

CENTOSISO="CentOS-7-x86_64-Minimal-1503-01.iso"
ISOMD5="d07ab3e615c66a8b2e9a50f4852e6a77"
CENTOSMIRROR="http://ftp.iij.ad.jp/pub/linux/centos/7/isos/x86_64/"

######################################################################
## Directory Paths
######################################################################

export CODEDIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)" || reportfailed
export DATADIR="/proc/self"  # i.e. not set yet

# put the current directory someplace unwritable to force use
# of the above variables
cd -P /proc/self

######################################################################
## Build Steps
######################################################################


"$CODEDIR/centos-7.1.1503-x86_64-base/build.sh"

"$CODEDIR/centos-7.1.1503-x86_64/build.sh"
