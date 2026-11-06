#!/bin/bash
# Whonix for KVM: Tor runs in one VM (Whonix-Gateway) and your apps in
# another (Whonix-Workstation) whose only network is the Gateway, so even
# a hacked browser can't learn your real IP address. Everything runs as
# your user (libvirt's qemu:///session); no root daemon, no host network
# setup.
#
# Before the first boot, this writes into the images:
#   Both:        a rule for acpid: the power button (whonix stop presses it) shuts
#                the VM down cleanly. Left to Whonix's desktop, it opens a dialog.
#   Gateway:     a bridge if you need one (it asks first; obfs4 with lines
#                you paste, or Snowflake; the Gateway has no webtunnel
#                client), so its first connection uses it. Whonix 18
#                connects to Tor at first boot; if you need a bridge but
#                have none yet, Tor is kept off until you turn it on.
#   Workstation: Tor Browser at Safest with JavaScript off, and Feather
#                (Monero; Feather's build for Tails and Whonix, its signature
#                checked). Electrum (Bitcoin) comes with Whonix.
# Nothing is mounted: the images are edited with qemu-img and debugfs.
#
# The download (about 1.9 GB) is checked against Whonix's signing key and
# kept in ../offline/whonix, so a reinstall doesn't fetch it again.
#
# Usage: bash whonix.sh            download (if needed) and install
#        bash whonix.sh --fetch    only download and check, for later
#        bash whonix.sh --bridges  installed already: choose the Gateway's bridge again
#        bash whonix.sh --remove
#        bash whonix.sh --manual   the steps to do it by hand
# summary: Whonix Gateway + Workstation VMs (1.9 GB download)
# security: most
# status: bin:whonix
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$WREN_DIR/lib/appimage.sh"
# The Gateway's network card of Wren Linux's (see "the Gateway's outside network")
GW_NET_SOCK="$HOME/.local/state/wren/whonix-gateway-net.sock"
GW_NET_MAC=52:54:00:57:52:4e
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

# WHONIX_FPR (pins.sh): Patrick Schleizer, signs all Whonix releases
KEY_URL=$WHONIX_KEY_URL
EDITION=LXQt
SAVED="$OFFLINE_DIR/whonix"
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
TOOL_PKGS=(xz-utils e2fsprogs fdisk acl)

defined() { "${VIRSH[@]}" dominfo "$1" >/dev/null 2>&1; }

# ---- download and check ----

# saved_archive: the newest download kept in SAVED, or nothing. (With none there,
# the loop's last test fails; under pipefail that failed the whole line, and
# set -e ended the install without a word, before the download.)
saved_archive() {
    local f
    for f in "$SAVED"/Whonix-"$EDITION"-*.Intel_AMD64.qcow2.libvirt.xz; do
        if [ -f "$f" ]; then echo "$f"; fi
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

# image_put IMAGE [--exec] FILE DEST... [--edit DEST SED-EXPR]...: copies each
# local FILE to DEST (root:root, 0644, or 0755 after --exec; directories
# created) in the image's root filesystem; --edit changes a file already there
# with sed (and fails if it isn't there). The qcow2 is
# turned into a sparse raw file for debugfs, checked with e2fsck, and
# turned back.
image_put() {
    local img=$1 raw="$1.raw" cmds start fs dir src dest bad mode need free
    shift
    # Room for the raw copy and the new qcow2, each about the size of what the
    # image holds: checked first, so a full disk never leaves a cut-off image
    # in place of the real one
    need=$(qemu-img info --output=json "$img" | python3 -I -c 'import json,sys; print(json.load(sys.stdin)["actual-size"] * 2 // 1048576 + 512)')
    free=$(df -Pm "${img%/*}" | awk 'NR == 2 { print $4 }')
    [ "$free" -ge "$need" ] ||
        die "Editing $img needs about $need MB free next to it; there are $free. Nothing was changed."
    qemu-img convert -O raw "$img" "$raw" ||
        { rm -f "$raw"; die "Couldn't unpack $img (is the disk full?). Nothing was changed."; }
    start=$(sfdisk -d "$raw" | sed -n 's/.*start= *\([0-9]*\),.*name="primary".*/\1/p')
    [ -n "$start" ] || { rm -f "$raw"; die "Couldn't find the root partition in $img."; }
    fs="$raw?offset=$((start * 512))"
    # A VM switched off without shutting down (whonix stop --force does that)
    # leaves its file system for its next boot to put
    # right: a journal to replay, orphaned files to clear. Edited before that, the
    # boot could undo the edit, or the edit spoil what the boot puts right: so it
    # must check out first, and it is said how to let the VM do that
    if debugfs -R features "$fs" 2>/dev/null | grep -qw needs_recovery || ! e2fsck -fn "$fs" >/dev/null 2>&1; then
        rm -f "$raw"
        die "$img was switched off without shutting down, so it can't be edited safely yet. Start it once (whonix gateway, or whonix), shut it down from inside, then run this again. Nothing was changed."
    fi
    cmds=$(mktemp)
    while [ $# -ge 2 ]; do
        mode=0644
        if [ "$1" = --exec ]; then mode=0755; shift; fi
        if [ "$1" = --edit ]; then
            src=$(mktemp)
            debugfs -R "cat $2" "$fs" >"$src" 2>/dev/null && [ -s "$src" ] ||
                { rm -f "$raw" "$src"; die "Couldn't read $2 from $img."; }
            sed -i -e "$3" "$src"
            dest=$2
            shift 3
        else
            src=$1 dest=$2
            shift 2
        fi
        dir=$(dirname -- "$dest")
        if ! debugfs -R "stat $dir" "$fs" 2>/dev/null | grep -q 'Type: directory'; then
            printf 'mkdir %s\nsif %s uid 0\nsif %s gid 0\nsif %s mode 040755\n' "$dir" "$dir" "$dir" "$dir" >>"$cmds"
        fi
        printf 'rm %s\nwrite %s %s\nsif %s uid 0\nsif %s gid 0\nsif %s mode 0100%s\n' \
            "$dest" "$src" "$dest" "$dest" "$dest" "$dest" "${mode#0}" >>"$cmds"
        printf '%s\n' "$src" "$dest" "$mode" >>"$cmds.check"
    done
    debugfs -w -f "$cmds" "$fs" >/dev/null 2>&1 || true
    # debugfs doesn't fail on errors, so read every file back
    bad=
    while read -r src && read -r dest && read -r mode; do
        if ! cmp -s "$src" <(debugfs -R "cat $dest" "$fs" 2>/dev/null) ||
            ! debugfs -R "stat $dest" "$fs" 2>/dev/null | grep -q 'User: *0 *Group: *0' ||
            ! debugfs -R "stat $dest" "$fs" 2>/dev/null | grep -q "Mode: *$mode"; then
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
    # (a failed write must never take the image's place)
    if ! qemu-img convert -O qcow2 -o cluster_size=2M,extended_l2=on "$raw" "$img.new"; then
        rm -f "$raw" "$img.new"
        die "Couldn't write $img back (is the disk full?). It is unchanged."
    fi
    rm -f "$raw"
    mv "$img.new" "$img"
}

# workstation_feather WORK: Feather's build for Tails and Whonix (no Tor of
# its own: it uses the Gateway's) into WORK/feather.AppImage, from the hash
# list signed by Feather's key (FEATHER_FPR in pins.sh), as extras/feather-wallet.sh
# checks it. Fails, with a warning, rather than stopping the install.
workstation_feather() {
    local work=$1 version file files=https://featherwallet.org/files/releases
    command -v gpg >/dev/null || apt_install gpg
    version=$(latest_github_tag feather-wallet/feather) || version=
    if ! [[ $version =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
        warn "Couldn't find the latest Feather version on GitHub (or it didn't look like one)."
        return 1
    fi
    file=feather-$version-a.AppImage
    if ! wget -q --show-progress -O "$work/feather-hashes.txt" "$files/hashes-$version.txt" ||
        ! wget -q --show-progress -O "$work/$file" "$files/linux-appimage-a/$file"; then
        warn "Downloading Feather $version failed."
        return 1
    fi
    if ! verify_clearsigned "$FEATHER_FPR" "$FEATHER_KEY_URL" "$work/feather-hashes.txt" "$work/feather-sums.txt"; then
        warn "Feather's hash list isn't signed by Feather's key."
        return 1
    fi
    check_sha256 "$work/feather-sums.txt" "$file" "$work/$file" || return 1
    mv "$work/$file" "$work/feather.AppImage"
    FEATHER_VERSION=$version
}

# ---- the Gateway's outside network ----
# Whonix's libvirt file gives the Gateway <interface type='user'>: libvirt then
# starts passt with its defaults, and libvirt can't give passt any other option.
# With those defaults, the Gateway's address for your router leads to this
# computer's loopback instead, every port of it (a hacked Gateway could reach
# what listens only there: Tor's port, the VMs' consoles, ...), and nothing
# answers DNS, so Snowflake (and webtunnel, meek) never connects: Whonix's
# "nameserver 10.0.2.3" is VirtualBox's own DNS. So the Gateway gets a network
# card of Wren Linux's instead, connected to a passt that bin/whonix starts with
# Whonix's fixed addresses, IPv4 only, no DHCP, nothing of this computer mapped
# in (--no-map-gw), and one address, 10.0.2.3, where only DNS (port 53) is
# forwarded, to the resolver this computer uses (Unbound, with secure DNS on).
# Its socket is in your home: passt's AppArmor profile allows it there
# (GW_NET_SOCK and GW_NET_MAC, at the top, for --manual too).

# gateway_net_xml IN OUT [SLOT]: the Gateway's libvirt file IN without its
# libvirt-run network card; with SLOT (a free slot on the main PCI bus, as
# 0x1e), with Wren Linux's card in it instead, on that bus: the main bus is
# enumerated before the root ports libvirt puts its cards behind, so it is eth0,
# the Gateway's outside card. Run on a file that has it already, it is the same.
gateway_net_xml() {
    python3 -I - "$1" "$2" "${3:-}" "$GW_NET_SOCK" "$GW_NET_MAC" <<'PYX'
import json, re, sys
src, out, slot, sock, mac = sys.argv[1:6]
x = open(src).read()
x = re.sub(r"\n?[ \t]*<interface type=['\"]user['\"]>.*?</interface>", "", x, flags=re.S)
x = re.sub(r"\n?[ \t]*<qemu:commandline>.*?</qemu:commandline>", "", x, flags=re.S)
if "xmlns:qemu=" not in x:
    x = re.sub(r"<domain\b", "<domain xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0'", x, count=1)
if slot:
    assert re.fullmatch(r"0x[0-9a-f]{2}", slot), slot
    netdev = {"type": "stream", "id": "wren-gw-netdev", "server": False, "reconnect-ms": 1000,
              "addr": {"type": "unix", "path": sock}}
    device = {"driver": "virtio-net-pci", "netdev": "wren-gw-netdev", "id": "wren-gw-net",
              "mac": mac, "bus": "pcie.0", "addr": slot}
    args = "".join("    <qemu:arg value='%s'/>\n" % a.replace("&", "&amp;").replace("'", "&apos;")
                   for a in ("-netdev", json.dumps(netdev), "-device", json.dumps(device)))
    x = re.sub(r"</domain>\s*$", "  <qemu:commandline>\n%s  </qemu:commandline>\n</domain>\n" % args, x)
open(out, "w").write(x)
PYX
}

# gateway_net_define XML: defines the Gateway from XML with Wren Linux's network
# card, in a slot of the main PCI bus that libvirt left free
gateway_net_define() {
    local x=$1 slot
    gateway_net_xml "$x" "$x.base" || die "Couldn't read the Gateway's libvirt file."
    "${VIRSH[@]}" define "$x.base" >/dev/null || die "libvirt didn't take the Gateway's settings."
    slot=$("${VIRSH[@]}" dumpxml --inactive "$GW" | python3 -I -c '
import re, sys
used = {int(s, 16) for s in re.findall(r"<address type=.pci. domain=.0x0000. bus=.0x00. slot=.(0x[0-9a-f]+).", sys.stdin.read())}
print(next(("0x%02x" % n for n in range(0x1e, 0x02, -1) if n not in used), ""))')
    [ -n "$slot" ] || die "No free slot on the Gateway's main PCI bus."
    "${VIRSH[@]}" dumpxml --inactive "$GW" >"$x.defined"
    gateway_net_xml "$x.defined" "$x.wren" "$slot"
    "${VIRSH[@]}" define "$x.wren" >/dev/null || die "libvirt didn't take the Gateway's network card."
    rm -f "$x.base" "$x.defined" "$x.wren"
}

# gateway_has_wren_net: the Gateway is defined with Wren Linux's network card
gateway_has_wren_net() { "${VIRSH[@]}" dumpxml --inactive "$GW" 2>/dev/null | grep -q 'wren-gw-net'; }

# bridge_needs_dns: the chosen bridge reaches the Tor network through names the
# Gateway must look up (Snowflake's broker and STUN servers, webtunnel's URL,
# meek's front), not only through addresses in its lines
bridge_needs_dns() { case $BRIDGE_TYPE in snowflake | webtunnel | meek) return 0 ;; esac; return 1; }

# The webtunnel program, lyrebird: the Gateway has none, and Whonix ships none
# (Debian has no package of it). It comes from the Tor Project's repository onto
# this computer (add_torproject_repo: TORPROJECT_FPR, an apt pin for lyrebird
# only), where its updates install themselves, and a copy is written into the
# Gateway. That copy isn't updated by Whonix: the version written in is kept
# here, and bin/whonix says when the one here is newer (--bridges copies it in
# again). Tor's AppArmor profile in Whonix 18 already lets Tor run it.
LYREBIRD_COPY="$HOME/.local/state/wren/whonix-lyrebird-version"
gateway_lyrebird() {
    LYREBIRD_VERSION=
    [ "$BRIDGE_TYPE" = webtunnel ] || return 0
    add_torproject_repo
    apt_install lyrebird
    [ -x /usr/bin/lyrebird ] || die "lyrebird didn't install, so the Gateway can't use webtunnel."
    GW_FILES+=(--exec /usr/bin/lyrebird /usr/bin/lyrebird)
    LYREBIRD_VERSION=$(dpkg-query -W -f='${Version}' lyrebird)
}

# lyrebird_record: after the Gateway's files are written (and only then), the
# lyrebird version now in it, or none
lyrebird_record() {
    if [ -n "${LYREBIRD_VERSION:-}" ]; then
        mkdir -p "${LYREBIRD_COPY%/*}"
        printf '%s\n' "$LYREBIRD_VERSION" >"$LYREBIRD_COPY"
    else
        rm -f "$LYREBIRD_COPY"
    fi
}

# webtunnel_note: what webtunnel on the Gateway is, said when it is chosen
webtunnel_note() {
    [ "$BRIDGE_TYPE" = webtunnel ] || return 0
    note "webtunnel on Whonix is experimental: Whonix doesn't ship it, so Wren Linux copies"
    note "lyrebird (the Tor Project's, its signature checked) into the Gateway. Whonix's own"
    note "updates won't update that copy: whonix tells you when a newer one is out, and"
    note "wrenctl install whonix --bridges (Gateway shut down) copies it in again."
}

# gateway_config WORK: fills GW_FILES with image_put's arguments for the Gateway:
# its bridge lines (or none), Tor on or held off, and its own DNS. Whonix keeps
# the Gateway's DNS off; it is turned on only for a bridge that needs it, and
# then 10.0.2.3 is where passt hands DNS (and only DNS) to this computer's
# resolver (bin/whonix). Each file is written whole, so choosing again (--bridges)
# leaves nothing of the choice before.
gateway_config() {
    local work=$1
    {
        echo "# Written by Wren Linux extras/whonix.sh: the Gateway's bridge ($(bridge_summary))."
        tor_bridge_config
    } >"$work/50_user.conf"
    if $BRIDGE_WANTED && [ "$BRIDGE_TYPE" = none ]; then
        # They need a bridge but have none yet. Whonix's own off switch:
        # Tor Control Panel turns it to 0
        printf '%s\n' "# Written by Wren Linux extras/whonix.sh: Tor stays off until you" \
            "# turn it on in Tor Control Panel (Anon Connection Wizard)." "DisableNetwork 1"
    else
        printf '%s\n' "# Written by Wren Linux extras/whonix.sh: Tor connects (Tor Control Panel can change this)." "DisableNetwork 0"
    fi >"$work/40_tor_control_panel.conf"
    GW_FILES=("$work/50_user.conf" /usr/local/etc/torrc.d/50_user.conf
        "$work/40_tor_control_panel.conf" /usr/local/etc/torrc.d/40_tor_control_panel.conf
        "$WREN_DIR/data/whonix-power-button" /etc/acpi/events/wren-power-button)
    if bridge_needs_dns; then
        GW_FILES+=(--edit /etc/resolv.conf.whonix 's/^#nameserver 10\.0\.2\.3$/nameserver 10.0.2.3/')
    else
        GW_FILES+=(--edit /etc/resolv.conf.whonix 's/^nameserver 10\.0\.2\.3$/#nameserver 10.0.2.3/')
    fi
    gateway_lyrebird
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
    rm -f "$LYREBIRD_COPY"
    # KVM and virt-manager go too, unless mockvps-kvm or another script needs them
    apt_purge
    remove_torproject_repo_if_unused
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
    if getent group "$g" >/dev/null && ! id -nG "$(id -un)" | grep -qw "$g"; then
        sudo adduser "$(id -un)" "$g" >/dev/null
        note "Added you to the $g group (it applies in full from your next login)."
    fi
done
# The VMs need /dev/kvm. The desktop session usually has it already (logind
# gives the person at the screen access); if not, the new kvm group only counts
# from the next login, so allow it now for this boot, and whonix works at once.
if [ -e /dev/kvm ] && [ ! -w /dev/kvm ]; then
    sudo setfacl -m "u:$(id -un):rw" /dev/kvm 2>/dev/null ||
        warn "Can't use /dev/kvm yet: log out and back in once, then run: whonix"
fi
# From whonix.org/wiki/KVM: no core dumps, and no limits libvirt can't set
# as a normal user
if [ ! -f "$HOME/.config/libvirt/qemu.conf" ]; then
    mkdir -p "$HOME/.config/libvirt"
    printf 'max_core = 0\nmax_processes = 0\nmax_files = 0\n' >"$HOME/.config/libvirt/qemu.conf"
fi

# gateway_off: the Gateway is shut down (its disk and settings can change only then)
gateway_off() {
    [ "$("${VIRSH[@]}" domstate "$GW" 2>/dev/null)" != running ] && return 0
    die "The Gateway is running. Shut it down first (whonix stop), then run this again."
}

if defined "$GW" && defined "$WS"; then
    note "Whonix is already installed."
    install_bin whonix
    # An install from before: the Gateway gets Wren Linux's network card
    if ! gateway_has_wren_net; then
        gateway_off
        say "The Gateway's network"
        note "Its own passt now (bin/whonix): DNS for the bridges that need it, and"
        note "nothing on this computer reachable from the Gateway."
        work=$(mktemp -d)
        "${VIRSH[@]}" dumpxml --inactive "$GW" >"$work/$GW.xml"
        gateway_net_define "$work/$GW.xml"
        rm -rf "$work"
    fi
    # Choosing the Gateway's bridge again (its disk is edited, with the Gateway off)
    if [ "${1:-}" = --bridges ]; then
        gateway_off
        say "Gateway bridges"
        pick_bridges whonix
        webtunnel_note
        work=$(mktemp -d)
        trap 'rm -rf "$work"' EXIT
        gateway_config "$work"
        image_put "$IMAGES/$GW.qcow2" "${GW_FILES[@]}"
        lyrebird_record
        note "The Gateway's bridge: $(bridge_summary). It takes effect at its next start."
    fi
    note "Start it with: whonix   (Tor settings: whonix gateway; another bridge: wrenctl install whonix --bridges)"
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
webtunnel_note
gateway_config "$work"
image_put "$work/gw.qcow2" "${GW_FILES[@]}"
lyrebird_record
if [ "$BRIDGE_TYPE" != none ]; then
    note "The Gateway's first connection goes through a bridge: $(bridge_summary)."
elif $BRIDGE_WANTED; then
    warn "No bridge chosen: Tor on the Gateway stays off until you turn it on with: whonix gateway"
else
    note "No bridge: the Gateway connects to Tor directly at its first boot."
fi

say "Workstation: Tor Browser and the wallets"
ws_files=("$WREN_DIR/data/tor-browser-safest.js" /usr/local/etc/torbrowser.d/user.js "$WREN_DIR/data/whonix-power-button" /etc/acpi/events/wren-power-button)
if workstation_feather "$work"; then
    ws_files+=(--exec "$work/feather.AppImage" /usr/local/lib/feather/feather.AppImage
        --exec "$WREN_DIR/data/whonix-feather" /usr/local/bin/feather
        "$WREN_DIR/data/whonix-feather.desktop" /usr/local/share/applications/feather.desktop)
fi
image_put "$work/ws.qcow2" "${ws_files[@]}"
note "Its Tor Browser starts at the Safest level with JavaScript off, every time."
if [ -n "${FEATHER_VERSION:-}" ]; then
    note "Feather $FEATHER_VERSION (Monero; its signature checked) is in the Workstation's menu, and Electrum (Bitcoin) comes with Whonix."
    note "Both reach the network only through the Gateway's Tor. Feather tells you when a newer version is out."
else
    warn "Whonix is installed without Feather (Electrum, for Bitcoin, comes with Whonix). Feather's guide for Whonix: docs.featherwallet.org"
fi

say "Setting up the VMs"
if ! "${VIRSH[@]}" pool-info default >/dev/null 2>&1; then
    "${VIRSH[@]}" pool-define-as default dir --target "$IMAGES" >/dev/null
fi
"${VIRSH[@]}" pool-autostart default >/dev/null
"${VIRSH[@]}" pool-start default >/dev/null 2>&1 || true
mv "$work/gw.qcow2" "$IMAGES/$GW.qcow2"
mv "$work/ws.qcow2" "$IMAGES/$WS.qcow2"
"${VIRSH[@]}" pool-refresh default >/dev/null
# The Gateway with Wren Linux's network card (gateway_net_define)
gateway_net_define "$work/$GW.xml"
"${VIRSH[@]}" define "$work/$WS.xml" >/dev/null
install_bin whonix

note "Installed. Start Whonix with: whonix   (or Super+d, then whonix)"
note "Change Tor settings with: whonix gateway    Shut down: whonix stop"
