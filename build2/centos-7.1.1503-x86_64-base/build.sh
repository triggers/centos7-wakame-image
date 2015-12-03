#!/bin/bash -x

# set reportfailed, $skip_rest_if_already_done, etc.
source "$CODEDIR/bin/simple-bash-steps-defaults.source"

CENTOSISO="CentOS-7-x86_64-Minimal-1503-01.iso"
ISOMD5="d07ab3e615c66a8b2e9a50f4852e6a77"
CENTOSMIRROR="http://ftp.iij.ad.jp/pub/linux/centos/7/isos/x86_64/"

######################################################################
## Directory Paths
######################################################################

export CODEDIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd -P)" || reportfailed
export DATADIR="$CODEDIR/output"

# put the current directory someplace unwritable to force use
# of the above variables
cd -P /proc/self

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
	$starting_step "yum install -y $1"
	[ -f "$CODEDIR/03-kccs-additions/flag-$package-installed" ]
	$skip_rest_if_already_done
	set -e
	"$CODEDIR/bin/ssh-shortcut.sh" yum install -y $package
	"$CODEDIR/bin/ssh-shortcut.sh" rpm -qi $package  # make sure rpm thinks it installed
	touch "$CODEDIR/03-kccs-additions/flag-$package-installed"
    ) ; prev_cmd_failed "Error while installing $package"
}

run-mita-script-remotely()
{
    scriptpath="$1"

    echo
    echo "Running script in VM:  $scriptpath"

    "$CODEDIR/bin/ssh-shortcut.sh" <<REMOTESCRIPT
# Copied from vmbuilder/kvm/rhel/6/functions/distro.sh
set -x
date
$(< "$CODEDIR/copied-from-vmbuilder/distro.sh")

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

generate-copy-file-script()
{
    pathlocal="$1"
    pathinvm="$2"
    perms="$3"

    # using base64 to allow for zero length files (and maybe binary data)
    set +x # next line produces too much trace data
    contents="$(base64 "$pathlocal")" || {
	# cause error in script that will be caught later
	echo "file-not-found: ${pathlocal##*/}"
    }

    cat <<SCRIPT
mkdir -p "${pathinvm%/*}"

base64 -d >$pathinvm <<'EOF'
$contents
EOF

chmod $perms $pathinvm

SCRIPT
}

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
    $starting_step "Download CentOS ISO install image"
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
    $starting_step "Generate ssh key pair and kickstart file"
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
) ; prev_cmd_failed "Error while creating custom ks file with ssh key"

(
    $starting_step "Install minimal image with kickstart"
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
    $starting_step "Tar minimal image"
    [ -f "$DATADIR/minimal-image.raw.tar.gz" ]
    $skip_rest_if_already_done
    set -e
    cd "$DATADIR/"
    time tar czSvf minimal-image.raw.tar.gz minimal-image.raw
) ; prev_cmd_failed "Error while tarring minimal image"