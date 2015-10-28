#!/bin/bash

reportfailed()
{
    echo "Script failed...exiting. ($*)" 1>&2
    exit 255
}

export SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)" || reportfail


: ${skip_rest_if_already_done:=eval ((\$?))||exit 0} # exit (sub)process if return code is 0

CENTOSISO="CentOS-7-x86_64-Minimal-1503-01.iso"
ISOMD5="d07ab3e615c66a8b2e9a50f4852e6a77"
CENTOSMIRROR="http://ftp.iij.ad.jp/pub/linux/centos/7/isos/x86_64/"

(
    [ -f "$SCRIPT_DIR/01-minimal-image/$CENTOSISO" ] &&
	[[ "$(< "$SCRIPT_DIR/01-minimal-image/$CENTOSISO.md5")" = *$ISOMD5* ]]
    $skip_rest_if_already_done
    set -e
    curl --fail "$CENTOSMIRROR/$CENTOSISO" -o "$SCRIPT_DIR/01-minimal-image/$CENTOSISO"
    md5sum "$SCRIPT_DIR/01-minimal-image/$CENTOSISO" >"$SCRIPT_DIR/01-minimal-image/$CENTOSISO.md5"
) || reportfailed "Error while downloading ISO image"

(
    [ -f "$SCRIPT_DIR/01-minimal-image/ks-sshpair.cfg" ]
    $skip_rest_if_already_done
    set -e
    cd "$SCRIPT_DIR/01-minimal-image/"
    [ -f tmp-sshkeypair ] || ssh-keygen -f tmp-sshkeypair -N ""
    cat >ks-sshpair.cfg <<EOF
$(< anaconda-ks.cfg)

%post
ls -l /root/  >/tmp.listing
mkdir /root/.ssh
chmod 700 /root/.ssh
cat >/root/.ssh/authorized_keys <<EOS
$(< tmp-sshkeypair.pub)
EOS
%end
EOF
) || reportfailed "Error while creating custom ks file with ssh key"

(
    [ -f "$SCRIPT_DIR/01-minimal-image/minimal-image.qcow2" ]
    $skip_rest_if_already_done
    set -e
    cd "$SCRIPT_DIR/01-minimal-image/"
    time ./centos-kickstart-build.sh "$CENTOSISO" ks-sshpair.cfg tmp.qcow2 1024M
    cp -al tmp.qcow2 minimal-image.qcow2
) || reportfailed "Error while installing minimal image with kickstart"

(
    [ -f "$SCRIPT_DIR/01-minimal-image/minimal-image.qcow2.tar.gz" ]
    $skip_rest_if_already_done
    set -e
    cd "$SCRIPT_DIR/01-minimal-image/"
    time tar czSvf minimal-image.qcow2.tar.gz minimal-image.qcow2
) || reportfailed "Error while tarring minimal image"

(
    [ -f "$SCRIPT_DIR/02-image-plus-wakame-init/minimal-image.qcow2" ]
    $skip_rest_if_already_done
    set -e
    cd "$SCRIPT_DIR/02-image-plus-wakame-init/"
    cp "$SCRIPT_DIR/01-minimal-image/runscript.sh" .
    tar -xzvf "$SCRIPT_DIR/01-minimal-image/minimal-image.qcow2.tar.gz"
    sed -i 's/tmp.qcow2/minimal-image.qcow2/' runscript.sh
) || reportfailed "Error while extracting fresh minimal image"

(
    [ -f "$SCRIPT_DIR/02-image-plus-wakame-init/flag-wakame-init-installed" ] ||
	[ -f "$SCRIPT_DIR/02-image-plus-wakame-init/kvm.pid" ] &&
	    kill -0 $(< "$SCRIPT_DIR/02-image-plus-wakame-init/kvm.pid") 2>/dev/null
    $skip_rest_if_already_done
    set -e
    cd "$SCRIPT_DIR/02-image-plus-wakame-init/"
    ./runscript.sh >kvm.stdout 2>kvm.stderr &
    sleep 10
    kill -0 $(< "$SCRIPT_DIR/02-image-plus-wakame-init/kvm.pid")
) || reportfailed "Error while booting fresh minimal image"
