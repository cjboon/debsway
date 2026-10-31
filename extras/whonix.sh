#!/bin/bash
# Whonix for KVM: Tor runs in one VM (Whonix-Gateway) and your apps in
# another (Whonix-Workstation) whose only network is the Gateway, so even
# a hacked browser can't learn your real IP address. Everything runs as
# your user (libvirt's qemu:///session); no root daemon, no host network
# setup.
#
# Before the first boot, this writes into the images:
#   Gateway:     a bridge if you need one (it asks first; obfs4 with lines
#                you paste, or Snowflake; the Gateway has no webtunnel
#                client), so its first connection uses it. Whonix 18
#                connects to Tor at first boot; if you need a bridge but
#                have none yet, Tor is kept off until you turn it on.
#   Workstation: Tor Browser at Safest with JavaScript off.
# Nothing is mounted: the images are edited with qemu-img and debugfs.
#
# The download (about 1.9 GB) is checked against Whonix's signing key and
# kept in ../offline/whonix, so a reinstall doesn't fetch it again.
#
# Usage: bash whonix.sh            download (if needed) and install
#        bash whonix.sh --fetch    only download and check, for later
#        bash whonix.sh --remove
# summary: Whonix Gateway + Workstation VMs (1.9 GB download)
# status: bin:whonix
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$DEBSWAY_DIR/lib/appimage.sh"
need_user

# WHONIX_FPR (pins.sh): Patrick Schleizer, signs all Whonix releases
KEY_URL=$WHONIX_KEY_URL
EDITION=LXQt
SAVED="$DEBSWAY_DIR/offline/whonix"
KEY="$SAVED/derivative.asc"
IMAGES="$HOME/.local/share/libvirt/images"
VIRSH=(virsh -c qemu:///session)
GW=Whonix-Gateway
WS=Whonix-Workstation

# From whonix.org/wiki/KVM, for Debian trixie (minus safe-rm)
KVM_PKGS=(qemu-system-x86 qemu-system-gui qemu-system-modules-spice qemu-utils
    libvirt-daemon libvirt-daemon-driver-qemu libvirt-daemon-driver-storage
    libvirt-daemon-driver-nodedev libvirt-clients virt-manager
    gir1.2-spiceclientgtk-3.0 passt ovmf swtpm swtpm-tools)
# Unpacking and editing the images
TOOL_PKGS=(xz-utils e2fsprogs fdisk)

defined() { "${VIRSH[@]}" dominfo "$1" >/dev/null 2>&1; }

# ---- download and check ----

saved_archive() {
    local f
    for f in "$SAVED"/Whonix-"$EDITION"-*.Intel_AMD64.qcow2.libvirt.xz; do
        [ -f "$f" ] && echo "$f"
    done | sort -V | tail -1
}

check_archive() {
    [ -f "$1" ] && [ -f "$1.asc" ] && [ -f "$KEY" ] &&
        verify_detached "$WHONIX_FPR" "$KEY" "$1.asc" "$1"
}

fetch_whonix() {
    local version name url have
    say "Checking the newest Whonix"
    version=$(wget -qO- https://www.whonix.org/wiki/KVM |
        grep -o "download/libvirt/[0-9.]*/Whonix-$EDITION-[0-9.]*\.Intel_AMD64" |
        sed 's|.*/Whonix-[^-]*-\(.*\)\.Intel_AMD64|\1|' | sort -uV | tail -1) || true
    [[ $version =~ ^[0-9]+(\.[0-9]+)+$ ]] || die "Couldn't read the newest version from whonix.org."
    note "Newest: $version"
    name="Whonix-$EDITION-$version.Intel_AMD64.qcow2.libvirt.xz"
    url="https://www.whonix.org/download/libvirt/$version/$name"
    mkdir -p "$SAVED"
    wget -qO "$KEY.part" "$KEY_URL" || die "Couldn't download the signing key from $KEY_URL"
    mv "$KEY.part" "$KEY"
    if check_archive "$SAVED/$name"; then
        note "Already saved and verified: $SAVED/$name"
        return 0
    fi
    say "Downloading Whonix $version (about 1.9 GB)"
    wget -q -c -O "$SAVED/$name.part" "$url" || die "Download failed: $url"
    wget -qO "$SAVED/$name.asc" "$url.asc" || die "Download failed: $url.asc"
    if ! verify_detached "$WHONIX_FPR" "$KEY" "$SAVED/$name.asc" "$SAVED/$name.part"; then
        rm -f "$SAVED/$name.part" "$SAVED/$name.asc"
        die "The signature didn't check out, so the download was deleted."
    fi
    mv "$SAVED/$name.part" "$SAVED/$name"
    # Keep only the newest
    for have in "$SAVED"/Whonix-"$EDITION"-*.libvirt.xz; do
        [ "$have" = "$SAVED/$name" ] || rm -f "$have" "$have.asc"
    done
    note "Saved and verified: $SAVED/$name"
}

# ---- editing the images before first boot ----

# image_put IMAGE FILE DEST...: copies each local FILE to DEST (root:root,
# 0644, directories created) in the image's root filesystem. The qcow2 is
# turned into a sparse raw file for debugfs, checked with e2fsck, and
# turned back.
image_put() {
    local img=$1 raw="$1.raw" cmds start fs dir src dest bad
    shift
    qemu-img convert -O raw "$img" "$raw"
    start=$(sfdisk -d "$raw" | sed -n 's/.*start= *\([0-9]*\),.*name="primary".*/\1/p')
    [ -n "$start" ] || { rm -f "$raw"; die "Couldn't find the root partition in $img."; }
    fs="$raw?offset=$((start * 512))"
    cmds=$(mktemp)
    while [ $# -ge 2 ]; do
        src=$1 dest=$2
        shift 2
        dir=$(dirname -- "$dest")
        if ! debugfs -R "stat $dir" "$fs" 2>/dev/null | grep -q 'Type: directory'; then
            printf 'mkdir %s\nsif %s uid 0\nsif %s gid 0\nsif %s mode 040755\n' "$dir" "$dir" "$dir" "$dir" >>"$cmds"
        fi
        printf 'rm %s\nwrite %s %s\nsif %s uid 0\nsif %s gid 0\nsif %s mode 0100644\n' \
            "$dest" "$src" "$dest" "$dest" "$dest" "$dest" >>"$cmds"
        printf '%s\n' "$src" "$dest" >>"$cmds.check"
    done
    debugfs -w -f "$cmds" "$fs" >/dev/null 2>&1 || true
    # debugfs doesn't fail on errors, so read every file back
    bad=
    while read -r src && read -r dest; do
        if ! cmp -s "$src" <(debugfs -R "cat $dest" "$fs" 2>/dev/null) ||
            ! debugfs -R "stat $dest" "$fs" 2>/dev/null | grep -q 'User: *0 *Group: *0'; then
            bad=$dest
            break
        fi
    done <"$cmds.check"
    rm -f "$cmds" "$cmds.check"
    if [ -n "$bad" ]; then
        rm -f "$raw"
        die "Couldn't write $bad into $img."
    fi
    if ! e2fsck -fn "$fs" >/dev/null 2>&1; then
        rm -f "$raw"
        die "The filesystem in $img didn't check out after editing it."
    fi
    qemu-img convert -O qcow2 -o cluster_size=2M,extended_l2=on "$raw" "$img.new"
    rm -f "$raw"
    mv "$img.new" "$img"
}

# Prints "SOURCE DEST" for the file to put in the Gateway, or nothing when
# the Gateway should just connect to Tor by itself at first boot
gateway_config() {
    local work=$1
    if [ "$BRIDGE_TYPE" != none ]; then
        {
            echo "# Written by debsway extras/whonix.sh before the first boot."
            tor_bridge_config
        } >"$work/50_user.conf"
        echo "$work/50_user.conf /usr/local/etc/torrc.d/50_user.conf"
    elif $BRIDGE_WANTED; then
        # They need a bridge but have none yet. Whonix's own off switch:
        # Tor Control Panel turns it to 0
        {
            echo "# Written by debsway extras/whonix.sh: Tor stays off until you"
            echo "# turn it on in Tor Control Panel (Anon Connection Wizard)."
            echo "DisableNetwork 1"
        } >"$work/40_tor_control_panel.conf"
        echo "$work/40_tor_control_panel.conf /usr/local/etc/torrc.d/40_tor_control_panel.conf"
    fi
}

# ---- remove ----

if [ "${1:-}" = --remove ]; then
    # Asked first, before anything is changed
    delete_disks=false
    if ls "$IMAGES"/Whonix-*.qcow2 >/dev/null 2>&1 &&
        ask "Also delete the Whonix disks, and everything saved inside the VMs ($IMAGES/Whonix-*.qcow2)?" n; then
        delete_disks=true
    fi
    for vm in "$WS" "$GW"; do
        if defined "$vm"; then
            "${VIRSH[@]}" destroy "$vm" >/dev/null 2>&1 || true
            "${VIRSH[@]}" undefine "$vm" >/dev/null
            note "Removed the $vm VM."
        fi
    done
    if $delete_disks; then
        rm -f "$IMAGES"/Whonix-Gateway.qcow2 "$IMAGES"/Whonix-Workstation.qcow2
        "${VIRSH[@]}" pool-refresh default >/dev/null 2>&1 || true
        note "Deleted."
    elif ls "$IMAGES"/Whonix-*.qcow2 >/dev/null 2>&1; then
        note "Kept the disks in $IMAGES. Installing again asks before replacing them."
    fi
    remove_bin whonix
    # KVM and virt-manager go too, unless mockvps-kvm or another script needs them
    apt_purge
    [ ! -d "$SAVED" ] || note "The saved download stays in $SAVED; delete it yourself if you like."
    exit
fi

if [ "${1:-}" = --fetch ]; then
    fetch_whonix
    exit
fi

# ---- install ----

[ -e /dev/kvm ] || die "No /dev/kvm: turn on virtualization (VT-x / AMD-V) in the firmware settings."

say "Installing KVM and virt-manager"
apt_install "${KVM_PKGS[@]}" "${TOOL_PKGS[@]}"
for g in kvm libvirt; do
    if getent group "$g" >/dev/null && ! id -nG | grep -qw "$g"; then
        sudo adduser "$(id -un)" "$g" >/dev/null
        warn "Added you to the $g group. Log out and back in once for it to apply."
    fi
done
# From whonix.org/wiki/KVM: no core dumps, and no limits libvirt can't set
# as a normal user
if [ ! -f "$HOME/.config/libvirt/qemu.conf" ]; then
    mkdir -p "$HOME/.config/libvirt"
    printf 'max_core = 0\nmax_processes = 0\nmax_files = 0\n' >"$HOME/.config/libvirt/qemu.conf"
fi

if defined "$GW" && defined "$WS"; then
    note "Whonix is already installed."
    install_bin whonix
    note "Start it with: whonix   (Tor settings: whonix gateway)"
    exit 0
fi

# Disks kept by an earlier --remove hold whatever was saved inside the VMs:
# a fresh install would put new ones in their place
if [ -e "$IMAGES/$GW.qcow2" ] || [ -e "$IMAGES/$WS.qcow2" ]; then
    warn "Whonix disks from before are in $IMAGES, with whatever was saved inside the VMs."
    ask "Replace them with fresh ones (what is inside them is lost)?" n ||
        die "Kept them; nothing was installed. Move them out of $IMAGES to install a fresh Whonix next to them."
fi

archive=$(saved_archive)
if [ -n "$archive" ] && check_archive "$archive"; then
    note "Using the saved, verified download: $archive"
else
    fetch_whonix
    archive=$(saved_archive)
fi

say "Unpacking Whonix"
mkdir -p "$IMAGES"
work=$(mktemp -d "$IMAGES/.whonix.XXXXXX")
trap 'rm -rf "$work"' EXIT
tar -xSf "$archive" -C "$work"
note "Whonix's license and disclaimer: $work/WHONIX_BINARY_LICENSE_AGREEMENT, WHONIX_DISCLAIMER"
if ! ask "Have you read them, and do you accept them?" y; then
    die "Not installed."
fi
mv "$work"/Whonix-Gateway-*.qcow2 "$work/gw.qcow2"
mv "$work"/Whonix-Workstation-*.qcow2 "$work/ws.qcow2"

say "Gateway bridges"
note "Whonix 18 connects to Tor at its first boot, so this is the time to say if it needs a bridge."
pick_bridges whonix
gw_src='' gw_dest=''
read -r gw_src gw_dest < <(gateway_config "$work") || true
if [ -n "$gw_src" ]; then image_put "$work/gw.qcow2" "$gw_src" "$gw_dest"; fi
if [ "$BRIDGE_TYPE" != none ]; then
    note "The Gateway's first connection goes through a bridge: $(bridge_summary)."
elif $BRIDGE_WANTED; then
    warn "No bridge chosen: Tor on the Gateway stays off until you turn it on with: whonix gateway"
else
    note "No bridge: the Gateway connects to Tor directly at its first boot."
fi

say "Workstation Tor Browser"
image_put "$work/ws.qcow2" "$DEBSWAY_DIR/data/tor-browser-safest.js" /usr/local/etc/torbrowser.d/user.js
note "Its Tor Browser starts at the Safest level with JavaScript off, every time."

say "Setting up the VMs"
if ! "${VIRSH[@]}" pool-info default >/dev/null 2>&1; then
    "${VIRSH[@]}" pool-define-as default dir --target "$IMAGES" >/dev/null
fi
"${VIRSH[@]}" pool-autostart default >/dev/null
"${VIRSH[@]}" pool-start default >/dev/null 2>&1 || true
mv "$work/gw.qcow2" "$IMAGES/$GW.qcow2"
mv "$work/ws.qcow2" "$IMAGES/$WS.qcow2"
"${VIRSH[@]}" pool-refresh default >/dev/null
"${VIRSH[@]}" define "$work/$GW.xml" >/dev/null
"${VIRSH[@]}" define "$work/$WS.xml" >/dev/null
install_bin whonix

note "Installed. Start Whonix with: whonix   (or Super+d, then whonix)"
note "Change Tor settings with: whonix gateway    Shut down: whonix stop"
