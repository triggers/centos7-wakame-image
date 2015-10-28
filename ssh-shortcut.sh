#!/bin/bash

# TODO: remove hardcoded port here and in other scripts

export SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)" || reportfail

ssh root@127.0.0.1 -p 2224 -i "$SCRIPT_DIR/01-minimal-image/tmp-sshkeypair"

