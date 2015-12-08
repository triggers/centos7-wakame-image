#!/bin/bash

######################################################################
## Directory Paths
######################################################################

export CODEDIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)" || reportfailed
export DATADIR="$CODEDIR/output"

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
## Inline Steps
######################################################################

# set reportfailed, $skip_rest_if_already_done, etc.
source "$CODEDIR/bin/simple-defaults-for-bashsteps.source"

(
    $starting_dependents "Build centos-7.1.1503-x86_64 image"

    "$CODEDIR/build-base-image-dir/build.sh" ; prev_cmd_failed

    (
	$starting_checks "Create output directory"
	[ -d "$DATADIR" ]
	$skip_rest_if_already_done
	mkdir "$DATADIR"
    ) ; prev_cmd_failed

    (
	$starting_checks "Extract minimal image to start public image build"
	[ -f "$DATADIR/minimal-image.raw" ]
	$skip_rest_if_already_done
	set -e
	cd "$DATADIR"
	cp "$CODEDIR/base-image-dir/runscript.sh" .
	cp "$CODEDIR/base-image-dir/tmp-sshkeypair" .
	cp "$CODEDIR/base-image-dir/ssh-shortcut.sh" .
	tar xzvf "$CODEDIR/base-image-dir/minimal-image.raw.tar.gz"
	sed -i 's/tmp.raw/minimal-image.raw/' "./runscript.sh"
    ) ; prev_cmd_failed "Error while extracting fresh minimal image"

    (
	$starting_checks "Boot VM to set up for installing public extras"
	[ -f "$DATADIR/flag-wakame-init-installed" ] ||
	    {
		[ -f "$DATADIR/kvm.pid" ] &&
		    kill -0 $(< "$DATADIR/kvm.pid") 2>/dev/null
	    }
	$skip_rest_if_already_done
	set -e
	cd "$DATADIR/"
	./runscript.sh >kvm.stdout 2>kvm.stderr &
	echo "$!" >"$DATADIR/kvm.pid"
	sleep 10
	kill -0 $(< "$DATADIR/kvm.pid")
	for (( i=1 ; i<20 ; i++ )); do
	    tryssh="$("$DATADIR/ssh-shortcut.sh" echo it-worked)" || :
	    [ "$tryssh" = "it-worked" ] && break
	    echo "$i/20 - Waiting 10 more seconds for ssh to connect..."
	    sleep 10
	done
	[[ "$tryssh" = "it-worked" ]]
    ) ; prev_cmd_failed "Error while booting fresh minimal image"

    (
	$starting_checks "Install wakame-init to public image"
	[ -f "$DATADIR/flag-wakame-init-installed" ]
	$skip_rest_if_already_done
	set -e
	repoURL=https://raw.githubusercontent.com/axsh/wakame-vdc/develop/rpmbuild/yum_repositories/wakame-vdc-stable.repo
	"$DATADIR/ssh-shortcut.sh" curl "$repoURL" -o /etc/yum.repos.d/wakame-vdc-stable.repo --fail
	"$DATADIR/ssh-shortcut.sh" yum install -y net-tools
	"$DATADIR/ssh-shortcut.sh" yum install -y wakame-init
	"$DATADIR/ssh-shortcut.sh" <<<"$(declare -f patch-wakame-init; echo patch-wakame-init)"
	touch "$DATADIR/flag-wakame-init-installed"
    ) ; prev_cmd_failed "Error while installing wakame-init"

    (
	$starting_checks "Shutdown VM for public image installation"
	[ -f "$DATADIR/flag-shutdown" ]
	$skip_rest_if_already_done
	set -e
	kill -0 $(< "$DATADIR/kvm.pid") 2>/dev/null || \
	    reportfailed "Expecting KVM process to be running now"
	# the next ssh always returns error, so mask it from set -e
	"$DATADIR/ssh-shortcut.sh" shutdown -P now || true
	for (( i=1 ; i<20 ; i++ )); do
	    kill -0 $(< "$DATADIR/kvm.pid") 2>/dev/null || break
	    echo "$i/20 - Waiting 2 more seconds for KVM to exit..."
	    sleep 2
	done
	kill -0 $(< "$DATADIR/kvm.pid") 2>/dev/null && exit 1
	touch "$DATADIR/flag-shutdown"
    ) ; prev_cmd_failed "Error while shutting down VM"

    export UUID=centos7
    "$CODEDIR/set-of-steps/steps-for-packaging.sh" \
	"$DATADIR/minimal-image.raw" \
	"$DATADIR/centos-7.x86_64.kvm.md.raw.tar.gz"

    $starting_checks
    true # this step just groups the above steps
    $skip_rest_if_already_done
)
