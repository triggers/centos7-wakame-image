#!/bin/bash

install_iso="$1"
kickstart_file="$2"
target_image="$3"
memory="$4"

reportfailed()
{
    echo "Script failed...exiting. ($*)" 1>&2
    exit 255
}

# Minimal parameter checking to catch typos:
[ -f "$install_iso" ] || reportfailed "Iso ($install_iso) not found."
[[ "$install_iso" == *.iso ]] || \
    [[ "$install_iso" == *.ISO ]] || reportfailed "First parameter does not end in .iso"

[ -f "$kickstart_file" ] || reportfailed "Iso ($kickstart_file) not found."
[[ "$kickstart_file" == *.cfg ]] || reportfailed "First parameter does not end in .cfg"

[ -f "$target_image" ] && reportfailed "$target_image already exists"

[[ "$memory" == *M ]] || reportfailed "Fourth parameter (memory) should end with M, e.g. 1024M"

# Make sure it is writable
touch "$target_image" || reportfailed "Could not create '$target_image' (the third parameter)"

export TARGET_DIR="$(cd "$(dirname "$(readlink -f "$target_dir")")" && pwd -P)" || reportfail

KSFPY="$TARGET_DIR/kickstart_floppy.img"

(
    set -e
    dd if=/dev/zero of="$KSFPY" count=1440 bs=1k
    /sbin/mkfs.msdos "$KSFPY"
    mcopy -i "$KSFPY" "$kickstart_file" ::/ks.cfg
    mdir -i "$KSFPY"
) || reportfail "Problem while creating floppy with kickstart file"


(
    set -e
    rm -f "$target_image"
    qemu-img create -f raw "$target_image" 10000M
) || reportfail "Problem while creating empty qcow2 image"

binlist=(
    /usr/libexec/qemu-kvm
    /usr/bin/qemu-kvm
)
for i in "${binlist[@]}"; do
    if [ -f "$i" ]; then
	KVMBIN="$i"
	break
    fi
done

# TODO: parameterize more of the KVM parameters
kvmcmdline=(
    "$KVMBIN"
    -name ksvm

    -fda "$KSFPY"
    -device virtio-net,netdev=user.0
    -drive "file=$target_image,if=virtio,cache=writeback,discard=ignore"

    -m "$memory"
    -machine type=pc,accel=kvm

    -netdev user,id=user.0,hostfwd=tcp::2224-:22
    -monitor telnet:0.0.0.0:4567,server,nowait
    -vnc 0.0.0.0:47
    )

cat >runscript.sh <<EOF
${kvmcmdline[@]} &
echo "\$!" >kvm.pid
wait
EOF

chmod +x runscript.sh

"${kvmcmdline[@]}" -boot once=d -cdrom "$install_iso" >kvm.stdout 2>kvm.stderr &
echo "$!" >kvm.pid

sleep 15

# send "<tab><space>ks=hd:fd0:/ks.cfg"
for k in tab spc k s equal h d shift-semicolon f d 0 shift-semicolon  slash k s dot c f g ret
do
    echo sendkey $k | nc 127.0.0.1 4567
    sleep 1
done
echo "Finished sending key presses"

# NOTE: Sometimes all the keys above are typed OK and the ks.cfg file
# is read in OK, but the installation does not start until the user
# clicks on the "Begin" button.  One possible cause could be the VNC
# windows being open and some UI events being sent to the graphical
# installer, which senses the human there and politely asks for
# confirmation.

# Update: Nope. Did not work even with no vncviewer connected.  Looks like
# alt-B will select that button.  Seems to take at least 20 seconds to get
# to that screen so....

sleep 60
echo sendkey alt-b | nc 127.0.0.1 4567

echo
echo "Just sent an extra alt-b just in case"
echo "it is stuck on the confirm install screen"
echo
echo "Now waiting for kvm to exit. (FYI, ^c will kill KVM)"
wait

# discover the supported keys by doing:
#   telnet 127.0.0.1 4567
#   sendkey <tab>
# Here is the result:
# (qemu) sendkey 
# 0              1              2              3              4              
# 5              6              7              8              9              
# a              again          alt            alt_r          altgr          
# altgr_r        apostrophe     asterisk       b              backslash      
# backspace      bracket_left   bracket_right  c              caps_lock      
# comma          compose        copy           ctrl           ctrl_r         
# cut            d              delete         dot            down           
# e              end            equal          esc            f              
# f1             f10            f11            f12            f2             
# f3             f4             f5             f6             f7             
# f8             f9             find           front          g              
# grave_accent   h              help           home           i              
# insert         j              k              kp_0           kp_1           
# kp_2           kp_3           kp_4           kp_5           kp_6           
# kp_7           kp_8           kp_9           kp_add         kp_decimal     
# kp_divide      kp_enter       kp_multiply    kp_subtract    l              
# left           less           lf             m              menu           
# meta_l         meta_r         minus          n              num_lock       
# o              open           p              paste          pause          
# pgdn           pgup           print          props          q              
# r              ret            right          s              scroll_lock    
# semicolon      shift          shift_r        slash          spc            
# stop           sysrq          t              tab            u              
# undo           unmapped       up             v              w              
# x              y              z              
