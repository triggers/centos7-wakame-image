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
    tar xzvf "$CODEDIR/base-image-dir/minimal-image.raw.tar.gz"
    sed -i 's/tmp.raw/minimal-image.raw/' "./runscript.sh"
) ; prev_cmd_failed "Error while extracting fresh minimal image"
