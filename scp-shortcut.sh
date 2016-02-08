#!/bin/bash

# TODO: remove hardcoded port here and in other scripts

reportfailed()
{
    echo "Script failed...exiting. ($*)" 1>&2
    exit 255
}

export SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)" || reportfailed

scp -P 2224 -i "$SCRIPT_DIR/01-minimal-image/tmp-sshkeypair" "$@" root@127.0.0.1:/tmp/.

