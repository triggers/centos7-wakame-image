#!/bin/bash

reportfailed()
{
    echo "Script failed...exiting. ($*)" 1>&2
    exit 255
}

prev-cmd-failed()
{
    # this is needed because '( cmd1 ; cmd2 ; set -e ; cmd3 ; cmd4 ) || reportfailed'
    # does not work because the || disables set -e, even inside the subshell!
    # see http://unix.stackexchange.com/questions/65532/why-does-set-e-not-work-inside
    # A workaround is to do  '( cmd1 ; cmd2 ; set -e ; cmd3 ; cmd4 ) ; prev-cmd-failed'
    (($? == 0)) || reportfailed "$*"
}

export SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)" || reportfail


: ${skip_rest_if_already_done:=eval ((\$?))||exit 0} # exit (sub)process if return code is 0

if [ "$1" == default ]; then
    ./build.sh
    # default to public image
    image_full_path="$(readlink -f "99-package-for-wakame-vdc/centos-7.x86_64.kvm.md.raw.tar.gz")" || reportfail "problem with default image"
    testuuid=centos7
else
    image_full_path="$(readlink -f "$1")" || reportfail "problem with $1"
    [ -f "$image_full_path" ] || reportfail "$1 is not a file"
    [ -f "$image_full_path".install.sh ] || "Image's *.install.sh script is not in same directory"
    testuuid="$2"
fi
    
fname="${image_full_path##*/}"

[ -d /var/lib/wakame-vdc/images/ ] || reportfail "wakame image directory not found"

# TODO: be smarter about if the existing image is the same as $image_full_path
if [ -f "/var/lib/wakame-vdc/images/$fname" ]; then
    mv "/var/lib/wakame-vdc/images/$fname" \
       "/var/lib/wakame-vdc/images/$fname-$(date +%y%m%d-%H%M%S)"
fi

(
    [ -f "/var/lib/wakame-vdc/images/$fname" ]
    $skip_rest_if_already_done
    set -e
    cp -al "$image_full_path" "/var/lib/wakame-vdc/images/$fname" 2>/dev/null ||
	cp "$image_full_path" "/var/lib/wakame-vdc/images/$fname"
    bash "$image_full_path".install.sh auto
) ; prev-cmd-failed "Error while moving image to /var/lib/wakame-vdc/images/"

[ "$testuuid" == "" ] && exit

(
    false
    $skip_rest_if_already_done
    set -e
    source mussel-utils.source
    bootone "$testuuid"
) ; prev-cmd-failed "Error while booting image"
