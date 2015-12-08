#!/bin/bash

[ -d "$CODEDIR" ] && [ -n "$DATADIR" ] || {
    echo "($0)" 1>&2
    echo "This step expects calling script to set up environment" 1>&2
    exit 255
}

$starting_checks "Generate ssh key pair and kickstart file"
[ -f "$DATADIR/ks-sshpair.cfg" ]
$skip_rest_if_already_done
set -e
[ -f "$DATADIR/tmp-sshkeypair" ] || ssh-keygen -f "$DATADIR/tmp-sshkeypair" -N ""
ks_text="$(cat "$CODEDIR/anaconda-ks.cfg")"
sshkey_text="$(cat "$DATADIR/tmp-sshkeypair.pub")"
cp "$CODEDIR/anaconda-ks.cfg" "$DATADIR/ks-sshpair.cfg"

cp "$CODEDIR/bin/ssh-shortcut.sh" "$DATADIR"
