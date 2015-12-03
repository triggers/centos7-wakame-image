#!/bin/bash -x

# set reportfailed, $skip_rest_if_already_done, etc.
source "$CODEDIR/bin/simple-bash-steps-defaults.source"

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

(
    $starting_step "Create output directory"
    [  -d "$DATADIR" ]
    $skip_rest_if_already_done
    mkdir "$DATADIR"
) ; prev_cmd_failed

(
    $starting_step "Extract minimal to start public image build"
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
    $starting_step "Boot VM to set up for installing public extras"
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
