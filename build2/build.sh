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
## Functions
######################################################################

# This function is piped and run through ssh below
patch-wakame-init()
{
    org="$(cat /etc/wakame-init)"
    beforeNICequals="${org%nic=*}"
    afterNICequals="${org##*nic=}"
    # Now rewrite the line by inserting new code and commenting out the old code
    {
	echo -n "$beforeNICequals"
	# the grep will output something like this: /sys/class/net/nestbr0/address:b6:21:21:a2:8f:bf
	echo -n 'IFS=/ read xempty xsys xclass xnet nic therest <<<"$(grep "$mac" /sys/class/net/*/address)" ## '
	echo  "$afterNICequals"
    } >/etc/wakame-init
}

######################################################################
## Build Steps
######################################################################


"$CODEDIR/centos-7.1.1503-x86_64-base/build.sh"

"$CODEDIR/centos-7.1.1503-x86_64/build.sh"

exit

## Public wakame build

(
    $starting_step "Install wakame-init to public image"
    [ -f "$DATADIR/flag-wakame-init-installed" ]
    $skip_rest_if_already_done
    set -e
    repoURL=https://raw.githubusercontent.com/axsh/wakame-vdc/develop/rpmbuild/yum_repositories/wakame-vdc-stable.repo
    "$CODEDIR/bin/ssh-shortcut.sh" curl "$repoURL" -o /etc/yum.repos.d/wakame-vdc-stable.repo --fail
    "$CODEDIR/bin/ssh-shortcut.sh" yum install -y net-tools
    "$CODEDIR/bin/ssh-shortcut.sh" yum install -y wakame-init
    "$CODEDIR/bin/ssh-shortcut.sh" <<<"$(declare -f patch-wakame-init; echo patch-wakame-init)"
    touch "$DATADIR/flag-wakame-init-installed"
) ; prev_cmd_failed "Error while installing wakame-init"

(
    $starting_step "Shutdown VM for public image installation"
    [ -f "$DATADIR/flag-shutdown" ]
    $skip_rest_if_already_done
    set -e
    kill -0 $(< "$DATADIR/kvm.pid") 2>/dev/null || \
	reportfailed "Expecting KVM process to be running now"
    # the next ssh always returns error, so mask it from set -e
    "$CODEDIR/bin/ssh-shortcut.sh" shutdown -P now || true
    for (( i=1 ; i<20 ; i++ )); do
	kill -0 $(< "$DATADIR/kvm.pid") 2>/dev/null || break
	echo "$i/20 - Waiting 2 more seconds for KVM to exit..."
	sleep 2
    done
    kill -0 $(< "$DATADIR/kvm.pid") 2>/dev/null && exit 1
    touch "$DATADIR/flag-shutdown"
) ; prev_cmd_failed "Error while shutting down VM"


## KCCS build


package-steps()
{
    source="$1"
    target="$2"
    targetDIR="${2%/*}"
    targetNAME="${2##*/}"
    qcowtarget="${target%.raw.tar.gz}.qcow2.gz"
    qcowNAME="${qcowtarget##*/}"
    (
	$starting_step "Tar *.tar.gz file"
	[ -f "$target" ]
	$skip_rest_if_already_done
	set -e
	cd "$DATADIR/"
	cp -al "$source" "${target%.tar.gz}"
	cd "$targetDIR"
	tar czSvf "$target" "${targetNAME%.tar.gz}"
	md5sum "${targetNAME}" >"${targetNAME}".md5
	md5sum "${targetNAME%.tar.gz}" >"${targetNAME%.tar.gz}".md5
    ) ; prev_cmd_failed "Error while packaging raw.tar.gz file"

    (
	$starting_step "Create install script for *.raw.tar.gz file"
	[ -f "$target".install.sh ]
	$skip_rest_if_already_done
	set -e
	cd "$targetDIR"
	"$CODEDIR/bin/output-image-install-script.sh" "$targetNAME"
    ) ; prev_cmd_failed "Error while creating install script for raw image: $targetNAME"

    (
	$starting_step "Convert image to qcow2 format"
	[ -f "${qcowtarget%.gz}" ] || [ -f "$qcowtarget" ]
	$skip_rest_if_already_done
	set -e
	cd "$targetDIR"
	[ -f "${target%.tar.gz}" ]

	# remember the size of the raw file, since it is hard to get that
	# information from the qcow2.gz file without expanding it
	lsout="$(ls -l "${target%.tar.gz}")" && read t1 t2 t3 t4 fsize rest <<<"$lsout"
	echo "$fsize" >"${target%.raw.tar.gz}".qcow2.rawsize

	# The compat option is not in older versions of qemu-img.  Assume that
	# if the option is not there, it defaults to use options that work
	# with the KVM in Wakame-vdc.
	qemu-img convert -f raw -O qcow2 -o compat=0.10 "${target%.tar.gz}" "${qcowtarget%.gz}" || \
	    qemu-img convert -f raw -O qcow2 "${target%.tar.gz}" "${qcowtarget%.gz}"
	md5sum "${qcowtarget%.gz}" >"${qcowtarget%.gz}".md5
	ls -l "${qcowtarget%.gz}" >"${qcowtarget%.gz}".lsl
    ) ; prev_cmd_failed "Error converting image to qcow2 format: $targetNAME"

    (
	$starting_step "Gzip qcow2 image"
	[ -f "$qcowtarget" ]
	$skip_rest_if_already_done
	set -e
	cd "$targetDIR"
	gzip "${qcowtarget%.gz}"
	md5sum "$qcowtarget" >"$qcowtarget".md5
    ) ; prev_cmd_failed "Error while running gzip on the qcow2 image: $qcowtarget"

    (
	$starting_step "Create install script for *.qcow.gz file"
	[ -f "$qcowtarget".install.sh ]
	$skip_rest_if_already_done
	set -e
	cd "$targetDIR"
	"$CODEDIR/bin/output-qcow-image-install-script.sh" "$qcowNAME"
    ) ; prev_cmd_failed "Error while creating install script for qcow image: $qcowtarget"
}

export UUID=centos7
package-steps \
    "$DATADIR/minimal-image.raw" \
    "$DATADIR/centos-7.x86_64.kvm.md.raw.tar.gz"
