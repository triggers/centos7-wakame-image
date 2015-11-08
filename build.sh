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

export SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)" || reportfailed


: ${skip_rest_if_already_done:=eval ((\$?))||exit 0} # exit (sub)process if return code is 0

CENTOSISO="CentOS-7-x86_64-Minimal-1503-01.iso"
ISOMD5="d07ab3e615c66a8b2e9a50f4852e6a77"
CENTOSMIRROR="http://ftp.iij.ad.jp/pub/linux/centos/7/isos/x86_64/"

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

simple-yum-install()
{
    package="$1"
    (
	[ -f "$SCRIPT_DIR/03-kccs-additions/flag-$package-installed" ]
	$skip_rest_if_already_done
	set -e
	"$SCRIPT_DIR/ssh-shortcut.sh" yum install -y $package
	"$SCRIPT_DIR/ssh-shortcut.sh" rpm -qi $package  # make sure rpm thinks it installed
	touch "$SCRIPT_DIR/03-kccs-additions/flag-$package-installed"
    ) ; prev-cmd-failed "Error while installing $package"
}

run-mita-script-remotely()
{
    scriptpath="$1"

    echo
    echo "Running script in VM:  $scriptpath"
    
    "$SCRIPT_DIR/ssh-shortcut.sh" <<REMOTESCRIPT
# Copied from vmbuilder/kvm/rhel/6/functions/distro.sh
set -x
date
$(< "$SCRIPT_DIR/copied-from-vmbuilder/distro.sh")

## The above scripts require run_in_target() which is defined
## in vmapp/tmp/vmbuilder/kvm/rhel/6/functions/utils.sh and
## uses chroot.  We are executing directly on the OS, so
## include a pass-through version of run_in_target():

$( cat <<'VERBATIM' # make it unnecessary to excape all the dollar signs:
  function run_in_target() {
    local chroot_dir=$1; shift; local args="$*"
    bash -e -c "${args}" ##  Just run without chroot
  }
  export -f run_in_target

  ## Many of the scripts also use chroot directly:
  chroot() { shift ; "$@" ; }  # disable chroot
VERBATIM
)

# The first parameter to scripts is supposed to be the chroot
# directory, so it must exist to pass error checking.  For the
# run_in_target calls, it is ignored.  For the non-run_in_target
# calls, it has to be "/" so when it gets prepended to paths, it comes
# out as "//", which is equivalent to "/".

# call script with one parameter (/)
set -x
set -- "/"
$(< "$scriptpath")
REMOTESCRIPT
}

######################################################################
## Build Steps
######################################################################

(
    [ -f "$SCRIPT_DIR/01-minimal-image/$CENTOSISO" ] &&
	[[ "$(< "$SCRIPT_DIR/01-minimal-image/$CENTOSISO.md5")" = *$ISOMD5* ]]
    $skip_rest_if_already_done
    set -e
    if [ -f "$CENTOSISO" ]; then
	# to avoid the download while debugging
	cp -al "$CENTOSISO" "$SCRIPT_DIR/01-minimal-image/$CENTOSISO"
    else
	curl --fail "$CENTOSMIRROR/$CENTOSISO" -o "$SCRIPT_DIR/01-minimal-image/$CENTOSISO"
    fi
    md5sum "$SCRIPT_DIR/01-minimal-image/$CENTOSISO" >"$SCRIPT_DIR/01-minimal-image/$CENTOSISO.md5"
) ; prev-cmd-failed "Error while downloading ISO image"

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
) ; prev-cmd-failed "Error while creating custom ks file with ssh key"

(
    [ -f "$SCRIPT_DIR/01-minimal-image/minimal-image.raw" ] || \
	    [ -f "$SCRIPT_DIR/01-minimal-image/minimal-image.raw.tar.gz" ]
    $skip_rest_if_already_done
    set -e
    cd "$SCRIPT_DIR/01-minimal-image/"
    time ./centos-kickstart-build.sh "$CENTOSISO" ks-sshpair.cfg tmp.raw 1024M
    cp -al tmp.raw minimal-image.raw
) ; prev-cmd-failed "Error while installing minimal image with kickstart"

(
    [ -f "$SCRIPT_DIR/01-minimal-image/minimal-image.raw.tar.gz" ]
    $skip_rest_if_already_done
    set -e
    cd "$SCRIPT_DIR/01-minimal-image/"
    time tar czSvf minimal-image.raw.tar.gz minimal-image.raw
) ; prev-cmd-failed "Error while tarring minimal image"

## Public wakame build

(
    [ -f "$SCRIPT_DIR/02-image-plus-wakame-init/minimal-image.raw" ]
    $skip_rest_if_already_done
    set -e
    cd "$SCRIPT_DIR/02-image-plus-wakame-init/"
    cp "$SCRIPT_DIR/01-minimal-image/runscript.sh" .
    tar xzvf "$SCRIPT_DIR/01-minimal-image/minimal-image.raw.tar.gz"
    sed -i 's/tmp.raw/minimal-image.raw/' runscript.sh
) ; prev-cmd-failed "Error while extracting fresh minimal image"

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
) ; prev-cmd-failed "Error while booting fresh minimal image"

(
    [ -f "$SCRIPT_DIR/02-image-plus-wakame-init/flag-wakame-init-installed" ]
    $skip_rest_if_already_done
    set -e
    repoURL=https://raw.githubusercontent.com/axsh/wakame-vdc/develop/rpmbuild/yum_repositories/wakame-vdc-stable.repo
    "$SCRIPT_DIR/ssh-shortcut.sh" curl "$repoURL" -o /etc/yum.repos.d/wakame-vdc-stable.repo --fail
    "$SCRIPT_DIR/ssh-shortcut.sh" yum install -y net-tools
    "$SCRIPT_DIR/ssh-shortcut.sh" yum install -y wakame-init
    "$SCRIPT_DIR/ssh-shortcut.sh" <<<"$(declare -f patch-wakame-init; echo patch-wakame-init)"
    touch "$SCRIPT_DIR/02-image-plus-wakame-init/flag-wakame-init-installed"
) ; prev-cmd-failed "Error while installing wakame-init"

(
    [ -f "$SCRIPT_DIR/02-image-plus-wakame-init/flag-shutdown" ]
    $skip_rest_if_already_done
    set -e
    kill -0 $(< "$SCRIPT_DIR/02-image-plus-wakame-init/kvm.pid") 2>/dev/null || \
	reportfailed "Expecting KVM process to be running now"
    # the next ssh always returns error, so mask it from set -e
    "$SCRIPT_DIR/ssh-shortcut.sh" shutdown -P now || true
    for (( i=1 ; i<20 ; i++ )); do
	kill -0 $(< "$SCRIPT_DIR/02-image-plus-wakame-init/kvm.pid") 2>/dev/null || break
	echo "$i/20 - Waiting 2 more seconds for KVM to exit..."
	sleep 2
    done
    kill -0 $(< "$SCRIPT_DIR/02-image-plus-wakame-init/kvm.pid") 2>/dev/null && exit 1
    touch "$SCRIPT_DIR/02-image-plus-wakame-init/flag-shutdown"
) ; prev-cmd-failed "Error while shutting down VM"


## KCCS build
(
    [ -f "$SCRIPT_DIR/03-kccs-additions/minimal-image.raw" ]
    $skip_rest_if_already_done
    set -e
    cd "$SCRIPT_DIR/03-kccs-additions/"
    cp "$SCRIPT_DIR/01-minimal-image/runscript.sh" .
    tar xzvf "$SCRIPT_DIR/01-minimal-image/minimal-image.raw.tar.gz"
    sed -i 's/tmp.raw/minimal-image.raw/' runscript.sh
) ; prev-cmd-failed "Error while extracting fresh minimal image for KCCS additions"

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
) ; prev-cmd-failed "Error while booting fresh minimal image for KCCS additions"

# add user 
(
    [ -f "$SCRIPT_DIR/03-kccs-additions/flag-add-user" ]
    $skip_rest_if_already_done
    set -e
    set -x
    "$SCRIPT_DIR/ssh-shortcut.sh" <<REMOTESCRIPT
# Copied from vmbuilder/kvm/rhel/6/functions/distro.sh
set -x
date
$(< "$SCRIPT_DIR/copied-from-vmbuilder/distro.sh")

## The above scripts require run_in_target() which is defined
## in vmapp/tmp/vmbuilder/kvm/rhel/6/functions/utils.sh and
## uses chroot.  We are executing directly on the OS, so
## include a pass-through version of run_in_target():

$( cat <<'VERBATIM' # make it unnecessary to excape all the dollar signs:

  function run_in_target() {
    local chroot_dir=$1; shift; local args="$*"
    ##  [[ -d "${chroot_dir}" ]] || { echo "[ERROR] directory not found: ${chroot_dir} (${BASH_SOURCE[0]##*/}:${LINENO})" >&2; return 1; }
  
    ##  chroot ${chroot_dir} bash -e -c "${args}"
  
    ##  do this instead:
    bash -e -c "${args}"
  }
  export -f run_in_target

VERBATIM
)

# The first parameter to gouc-user.sh needs is supposed
# to be the chroot, so it must exist to pass error checking.
# For the run_in_target calls, it is ignored.  For
# the non-run_in_target calls, it has to be "/" so
# when it gets prepended to paths, it comes out as "//",
# which is equivalent to "/".

# call gouc-user.sh with one parameter (/)
set -x
set -- "/"
$(< "$SCRIPT_DIR/copied-from-mita-tools/gouc-user.sh")

REMOTESCRIPT
    
    touch "$SCRIPT_DIR/03-kccs-additions/flag-add-user"
) ; prev-cmd-failed "Error while adding user account"

(
    [ -f "$SCRIPT_DIR/03-kccs-additions/flag-copy-step" ]
    $skip_rest_if_already_done
    set -e
    repoURL=https://raw.githubusercontent.com/axsh/wakame-vdc/develop/rpmbuild/yum_repositories/wakame-vdc-stable.repo
    "$SCRIPT_DIR/ssh-shortcut.sh" <<REMOTESCRIPT
set -e

cat >/etc/default/wakame-init <<'EOF'
$(< "$SCRIPT_DIR/copied-from-mita-tools/sento_std/guestroot/etc/default/wakame-init")
EOF
chmod 644 /etc/default/wakame-init

mkdir -p /etc/zabbix
cat >/etc/zabbix/zabbix_agentd.conf.tmpl <<'EOF'
$(< "$SCRIPT_DIR/copied-from-mita-tools/sento_std/zabbix_agentd.conf.tmpl")
EOF
chmod 644 /etc/zabbix/zabbix_agentd.conf.tmpl

mkdir -p /etc/td-agent
cat >/etc/td-agent/td-agent <<'EOF'
$(< "$SCRIPT_DIR/copied-from-mita-tools/sento_std/td-agent.conf")
EOF
chmod 644 /etc/td-agent/td-agent

REMOTESCRIPT
    touch "$SCRIPT_DIR/03-kccs-additions/flag-copy-step"
) ; prev-cmd-failed "Error while installing wakame-init"

(
    [ -f "$SCRIPT_DIR/03-kccs-additions/flag-ran-xexecscript.d-scripts" ]
    $skip_rest_if_already_done
    set -e
    repoURL=https://raw.githubusercontent.com/axsh/wakame-vdc/develop/rpmbuild/yum_repositories/wakame-vdc-stable.repo
    find "$SCRIPT_DIR/copied-from-mita-tools/xexecscript.d/" -name '*.sh' | \
	while read ln; do
	    run-mita-script-remotely "$ln"
	done
    touch "$SCRIPT_DIR/03-kccs-additions/flag-ran-xexecscript.d-scripts"
) ; prev-cmd-failed "Error while running xexecscript.d scripts"

(
    [ -f "$SCRIPT_DIR/03-kccs-additions/flag-wakame-init-installed" ]
    $skip_rest_if_already_done
    set -e
    repoURL=https://raw.githubusercontent.com/axsh/wakame-vdc/develop/rpmbuild/yum_repositories/wakame-vdc-stable.repo
    "$SCRIPT_DIR/ssh-shortcut.sh" yum install -y net-tools
    "$SCRIPT_DIR/ssh-shortcut.sh" <<REMOTESCRIPT
chroot() { shift ; "\$@" ; }  # disable chroot
# call the script with one parameter (/)
set -x
set -- "/"
$(< "$SCRIPT_DIR/copied-from-mita-tools/install_wakame-init.sh")
REMOTESCRIPT
    "$SCRIPT_DIR/ssh-shortcut.sh" <<<"$(declare -f patch-wakame-init; echo patch-wakame-init)"
    touch "$SCRIPT_DIR/03-kccs-additions/flag-wakame-init-installed"
) ; prev-cmd-failed "Error while installing wakame-init"
exit

for p in bash openssl openssl098e glibc-common glibc; do
    simple-yum-install $p
done

(
    [ -f "$SCRIPT_DIR/03-kccs-additions/flag-td-agent-installed" ]
    $skip_rest_if_already_done
    set -e
    # from http://docs.fluentd.org/articles/install-by-rpm
    "$SCRIPT_DIR/ssh-shortcut.sh" <<EOF
    # we are already root and sudo complains about no tty , so strip sudo from the script
    curl -L https://toolbelt.treasuredata.com/sh/install-redhat-td-agent2.sh | sed 's/sudo//' | sh
EOF
    "$SCRIPT_DIR/ssh-shortcut.sh" rpm -qi td-agent  # make sure rpm thinks it installed
    touch "$SCRIPT_DIR/03-kccs-additions/flag-td-agent-installed"
) ; prev-cmd-failed "Error while installing td-agent"

# Zabbix
# http://www.unixmen.com/how-to-install-zabbix-server-on-centos-7/
(
    [ -f "$SCRIPT_DIR/03-kccs-additions/flag-zabbix-installed" ]
    $skip_rest_if_already_done
    set -e
    "$SCRIPT_DIR/ssh-shortcut.sh" yum install -y epel-release
    "$SCRIPT_DIR/ssh-shortcut.sh" rpm --import http://repo.zabbix.com/RPM-GPG-KEY-ZABBIX
    "$SCRIPT_DIR/ssh-shortcut.sh" rpm -Uv  http://repo.zabbix.com/zabbix/2.4/rhel/7/x86_64/zabbix-release-2.4-1.el7.noarch.rpm

    "$SCRIPT_DIR/ssh-shortcut.sh" yum install -y zabbix
    "$SCRIPT_DIR/ssh-shortcut.sh" yum install -y zabbix-agent
    # TODO: double check the next line.  An install specific to Centos 7 does not seem to be available
    "$SCRIPT_DIR/ssh-shortcut.sh" rpm -Uvh http://repo.zabbix.jp/relatedpkgs/rhel6/x86_64/zabbix-jp-release-6-6.noarch.rpm    

    # make sure rpm thinks all was installed
    "$SCRIPT_DIR/ssh-shortcut.sh" rpm -qi zabbix  
    "$SCRIPT_DIR/ssh-shortcut.sh" rpm -qi zabbix-agent
    "$SCRIPT_DIR/ssh-shortcut.sh" rpm -qi zabbix-jp-release
    touch "$SCRIPT_DIR/03-kccs-additions/flag-zabbix-installed"
    touch "$SCRIPT_DIR/03-kccs-additions/flag-finished-additions"
) ; prev-cmd-failed "Error while installing zabbix"

( # TODO: refactor this
    [ -f "$SCRIPT_DIR/03-kccs-additions/flag-shutdown" ]
    $skip_rest_if_already_done
    set -e
    kill -0 $(< "$SCRIPT_DIR/03-kccs-additions/kvm.pid") 2>/dev/null || \
	reportfailed "Expecting KVM process to be running now"
    # the next ssh always returns error, so mask it from set -e
    "$SCRIPT_DIR/ssh-shortcut.sh" shutdown -P now || true
    for (( i=1 ; i<20 ; i++ )); do
	kill -0 $(< "$SCRIPT_DIR/03-kccs-additions/kvm.pid") 2>/dev/null || break
	echo "$i/20 - Waiting 2 more seconds for KVM to exit..."
	sleep 2
    done
    kill -0 $(< "$SCRIPT_DIR/03-kccs-additions/kvm.pid") 2>/dev/null && exit 1
    touch "$SCRIPT_DIR/03-kccs-additions/flag-shutdown"
) ; prev-cmd-failed "Error while shutting down VM"

$tmptmp # temporary hack while writing/debugging

package-steps()
{
    source="$1"
    target="$2"
    targetDIR="${2%/*}"
    targetNAME="${2##*/}"
    qcowtarget="${target%.raw.tar.gz}.qcow2.gz"
    qcowNAME="${qcowtarget##*/}"
    (
	[ -f "$target" ]
	$skip_rest_if_already_done
	set -e
	cp -al "$source" "${target%.tar.gz}"
	cd "$targetDIR"
	tar czSvf "$target" "${targetNAME%.tar.gz}"
	md5sum "${targetNAME}" >"${targetNAME}".md5
	md5sum "${targetNAME%.tar.gz}" >"${targetNAME%.tar.gz}".md5
    ) ; prev-cmd-failed "Error while booting tarring image: $targetNAME"
    
    (
	[ -f "$target".install.sh ]
	$skip_rest_if_already_done
	set -e
	cd "$targetDIR"
	../output-image-install-script.sh "$targetNAME"
    ) ; prev-cmd-failed "Error while creating install script for raw image: $targetNAME"

    (
	[ -f "${qcowtarget%.gz}" ] || [ -f "$qcowtarget" ]
	$skip_rest_if_already_done
	set -e
	cd "$targetDIR"
	[ -f "${target%.tar.gz}" ]

	# remember the size of the raw file, since it is hard to get that
	# information from the qcow2.gz file without expanding it
	lsout="$(ls -l "${target%.tar.gz}")" && read t1 t2 t3 t4 fsize rest <<<"$lsout"
	echo "$fsize" >"${target%.raw.tar.gz}".qcow2.rawsize
	
	qemu-img convert -f raw -O qcow2 -o compat=0.10 "${target%.tar.gz}" "${qcowtarget%.gz}"
	md5sum "${qcowtarget%.gz}" >"${qcowtarget%.gz}".md5
	ls -l "${qcowtarget%.gz}" >"${qcowtarget%.gz}".lsl
    ) ; prev-cmd-failed "Error converting image to qcow2 format: $targetNAME"

    (
	[ -f "$qcowtarget" ]
	$skip_rest_if_already_done
	set -e
	cd "$targetDIR"
	gzip "${qcowtarget%.gz}"
	md5sum "$qcowtarget" >"$qcowtarget".md5
    ) ; prev-cmd-failed "Error while running gzip on the qcow2 image: $qcowtarget"

    (
	[ -f "$qcowtarget".gz.install.sh ]
	$skip_rest_if_already_done
	set -e
	cd "$targetDIR"
	../output-qcow-image-install-script.sh "$qcowNAME"
    ) ; prev-cmd-failed "Error while creating install script for qcow image: $qcowtarget"
}

export UUID=centos7
package-steps \
    "$SCRIPT_DIR/02-image-plus-wakame-init/minimal-image.raw" \
    "$SCRIPT_DIR/99-package-for-wakame-vdc/centos-7.x86_64.kvm.md.raw.tar.gz"

export UUID=centos71std
package-steps \
    "$SCRIPT_DIR/03-kccs-additions/minimal-image.raw" \
    "$SCRIPT_DIR/99k-package-for-kccs/centos71std-01.15111.raw.tar.gz"

