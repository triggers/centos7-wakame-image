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
## Build Steps
######################################################################

# set reportfailed, $skip_rest_if_already_done, etc.
source "$CODEDIR/bin/simple-defaults-for-bashsteps.source"

source "$CODEDIR/build.conf"

(
    $starting_dependents "Build centos-7.1.1503-x86_64-base image"
    (
	$starting_checks "Create output directory"
	[  -d "$DATADIR" ]
	$skip_rest_if_already_done
	mkdir "$DATADIR"
    ) ; prev_cmd_failed

    (
	$starting_checks "Download CentOS ISO install image"
	[ -f "$DATADIR/$CENTOSISO" ] &&
	    [[ "$(< "$DATADIR/$CENTOSISO.md5")" = *$ISOMD5* ]]
	$skip_rest_if_already_done
	set -e
	if [ -f "$CODEDIR/$CENTOSISO" ]; then
	    # to avoid the download while debugging
	    cp -al "$CODEDIR/$CENTOSISO" "$DATADIR/$CENTOSISO"
	else
	    curl --fail "$CENTOSMIRROR/$CENTOSISO" -o "$DATADIR/$CENTOSISO"
	fi
	md5sum "$DATADIR/$CENTOSISO" >"$DATADIR/$CENTOSISO.md5"
    ) ; prev_cmd_failed "Error while downloading ISO image"

    (
	$starting_checks "Generate ssh key pair and kickstart file"
	[ -f "$DATADIR/ks-sshpair.cfg" ]
	$skip_rest_if_already_done
	set -e
	[ -f "$DATADIR/tmp-sshkeypair" ] || ssh-keygen -f "$DATADIR/tmp-sshkeypair" -N ""
	ks_text="$(cat "$CODEDIR/anaconda-ks.cfg")"
	sshkey_text="$(cat "$DATADIR/tmp-sshkeypair.pub")"
	cat >"$DATADIR/ks-sshpair.cfg" <<EOF
$ks_text

%post
ls -l /root/  >/tmp.listing
mkdir /root/.ssh
chmod 700 /root/.ssh
cat >/root/.ssh/authorized_keys <<EOS
$sshkey_text
EOS
%end
EOF
	cp "$CODEDIR/bin/ssh-shortcut.sh" "$DATADIR"
    ) ; prev_cmd_failed "Error while creating custom ks file with ssh key"

    (
	$starting_checks "Install minimal image with kickstart"
	[ -f "$DATADIR/minimal-image.raw" ] || \
	    [ -f "$DATADIR/minimal-image.raw.tar.gz" ]
	$skip_rest_if_already_done
	set -e
	cd "$DATADIR"  # centos-kickstart-build.sh creates files in the current $(pwd)
	time "$CODEDIR/bin/centos-kickstart-build.sh" \
	     "$CENTOSISO" "ks-sshpair.cfg" "tmp.raw" 1024M
	cp -al "tmp.raw" "minimal-image.raw"
    ) ; prev_cmd_failed "Error while installing minimal image with kickstart"

    (
	$starting_checks "Tar minimal image"
	[ -f "$DATADIR/minimal-image.raw.tar.gz" ]
	$skip_rest_if_already_done
	set -e
	cd "$DATADIR/"
	time tar czSvf minimal-image.raw.tar.gz minimal-image.raw
    ) ; prev_cmd_failed "Error while tarring minimal image"

    $starting_checks
    true # this step just groups the above steps
    $skip_rest_if_already_done
)
