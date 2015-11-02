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

## Public wakame build

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
	{
	    [ -f "$SCRIPT_DIR/02-image-plus-wakame-init/kvm.pid" ] &&
		kill -0 $(< "$SCRIPT_DIR/02-image-plus-wakame-init/kvm.pid") 2>/dev/null
	}
    $skip_rest_if_already_done
    set -e
    cd "$SCRIPT_DIR/02-image-plus-wakame-init/"
    ./runscript.sh >kvm.stdout 2>kvm.stderr &
    sleep 10
    kill -0 $(< "$SCRIPT_DIR/02-image-plus-wakame-init/kvm.pid")
    for (( i=1 ; i<20 ; i++ )); do
	tryssh="$("$SCRIPT_DIR/ssh-shortcut.sh" echo it-worked)" || :
	[ "$tryssh" = "it-worked" ] && break
	echo "$i/20 - Waiting 10 more seconds for ssh to connect..."
	sleep 10
    done
    [[ "$tryssh" = "it-worked" ]]
) || reportfailed "Error while booting fresh minimal image"

(
    [ -f "$SCRIPT_DIR/02-image-plus-wakame-init/flag-wakame-init-installed" ]
    $skip_rest_if_already_done
    set -e
    repoURL=https://raw.githubusercontent.com/axsh/wakame-vdc/develop/rpmbuild/yum_repositories/wakame-vdc-stable.repo
    "$SCRIPT_DIR/ssh-shortcut.sh" curl "$repoURL" -o /etc/yum.repos.d/wakame-vdc-stable.repo --fail
    "$SCRIPT_DIR/ssh-shortcut.sh" yum install -y wakame-init
    touch "$SCRIPT_DIR/02-image-plus-wakame-init/flag-wakame-init-installed"
) || reportfailed "Error while installing wakame-init"

(
    [ -f "$SCRIPT_DIR/02-image-plus-wakame-init/flag-shutdown" ]
    $skip_rest_if_already_done
    set -e
    "$SCRIPT_DIR/ssh-shortcut.sh" shutdown -P now
    for (( i=1 ; i<20 ; i++ )); do
	kill -0 $(< "$SCRIPT_DIR/02-image-plus-wakame-init/kvm.pid") 2>/dev/null || break
	echo "$i/20 - Waiting 2 more seconds for KVM to exit..."
	sleep 2
    done
    kill -0 $(< "$SCRIPT_DIR/02-image-plus-wakame-init/kvm.pid") 2>/dev/null && exit
    touch "$SCRIPT_DIR/02-image-plus-wakame-init/flag-shutdown"
) || reportfailed "Error while shutting down VM"


## KCCS build
(
    [ -f "$SCRIPT_DIR/03-kccs-additions/minimal-image.qcow2" ]
    $skip_rest_if_already_done
    set -e
    cd "$SCRIPT_DIR/03-kccs-additions/"
    cp "$SCRIPT_DIR/01-minimal-image/runscript.sh" .
    tar -xzvf "$SCRIPT_DIR/01-minimal-image/minimal-image.qcow2.tar.gz"
    sed -i 's/tmp.qcow2/minimal-image.qcow2/' runscript.sh
) || reportfailed "Error while extracting fresh minimal image for KCCS additions"

(
    [ -f "$SCRIPT_DIR/03-kccs-additions/flag-finished-additions" ] ||
	{
	    [ -f "$SCRIPT_DIR/03-kccs-additions/kvm.pid" ] &&
		kill -0 $(< "$SCRIPT_DIR/03-kccs-additions/kvm.pid") 2>/dev/null
	}
    $skip_rest_if_already_done
    set -e
    cd "$SCRIPT_DIR/03-kccs-additions/"
    ./runscript.sh >kvm.stdout 2>kvm.stderr &
    sleep 10
    kill -0 $(< "$SCRIPT_DIR/03-kccs-additions/kvm.pid")
    for (( i=1 ; i<20 ; i++ )); do
	tryssh="$("$SCRIPT_DIR/ssh-shortcut.sh" echo it-worked)" || :
	[ "$tryssh" = "it-worked" ] && break
	echo "$i/20 - Waiting 10 more seconds for ssh to connect..."
	sleep 10
    done
    [[ "$tryssh" = "it-worked" ]]
) || reportfailed "Error while booting fresh minimal image for KCCS additions"

(
    # This is a duplicate of the above wakame-init step.  This is easier than
    # copying the image from 03-kccs-additions.
    [ -f "$SCRIPT_DIR/03-kccs-additions/flag-wakame-init-installed" ]
    $skip_rest_if_already_done
    set -e
    repoURL=https://raw.githubusercontent.com/axsh/wakame-vdc/develop/rpmbuild/yum_repositories/wakame-vdc-stable.repo
    "$SCRIPT_DIR/ssh-shortcut.sh" curl "$repoURL" -o /etc/yum.repos.d/wakame-vdc-stable.repo --fail
    "$SCRIPT_DIR/ssh-shortcut.sh" yum install -y wakame-init
    touch "$SCRIPT_DIR/03-kccs-additions/flag-wakame-init-installed"
) || reportfailed "Error while installing wakame-init"


(
    [ -f "$SCRIPT_DIR/03-kccs-additions/flag-td-agent-installed" ]
    $skip_rest_if_already_done
    set -e
    # from http://docs.fluentd.org/articles/install-by-rpm
    "$SCRIPT_DIR/ssh-shortcut.sh" <<EOF
    curl -L https://toolbelt.treasuredata.com/sh/install-redhat-td-agent2.sh | sh
EOF
    touch "$SCRIPT_DIR/03-kccs-additions/flag-td-agent-installed"
) || reportfailed "Error while installing wakame-init"


$tmptmp # temporary hack while writing/debugging

## final packaging
(
    [ -f "$SCRIPT_DIR/99-package-for-wakame-vdc/centos-7.x86_64.kvm.md.raw.tar.gz" ]
    $skip_rest_if_already_done
    set -e
    cp -al "$SCRIPT_DIR/02-image-plus-wakame-init/minimal-image.qcow2" \
       "$SCRIPT_DIR/99-package-for-wakame-vdc/centos-7.x86_64.kvm.md.raw"
    cd "$SCRIPT_DIR/99-package-for-wakame-vdc/"
    tar czvf centos-7.x86_64.kvm.md.raw.tar.gz centos-7.x86_64.kvm.md.raw
    md5sum centos-7.x86_64.kvm.md.raw.tar.gz >centos-7.x86_64.kvm.md.raw.tar.gz.md5
    md5sum centos-7.x86_64.kvm.md.raw        >centos-7.x86_64.kvm.md.raw.md5
) || reportfailed "Error while booting tarring image"

(
    [ -f "$SCRIPT_DIR/99-package-for-wakame-vdc/centos-7.x86_64.kvm.md.raw.tar.gz.install.sh" ]
    $skip_rest_if_already_done
    set -e
    cd "$SCRIPT_DIR/99-package-for-wakame-vdc/"
    ./output-image-install-script.sh centos-7.x86_64.kvm.md.raw.tar.gz
) || reportfailed "Error while creating install script for image"
