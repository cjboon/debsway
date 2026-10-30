#!/bin/bash
# Tries an install image from prep/make-install-iso.sh in a throwaway VM, the
# way a real laptop would start it: UEFI firmware, the image plugged in as a USB
# stick, and an empty 20 GB disk. Nothing on this computer is touched; the VM's
# files are in ~/.cache/debsway/iso-test (left out of backups).
#
#   bash tools/try-install-iso.sh                 install from the newest built image
#   bash tools/try-install-iso.sh --iso FILE      ...from FILE
#   bash tools/try-install-iso.sh --two-disks     with a second empty disk: the
#                                                 installer should then ask which
#   bash tools/try-install-iso.sh --boot          start the installed system again
#   bash tools/try-install-iso.sh --clean         delete the VM's files (and QEMU and
#                                                 the firmware, if this script installed them)
#   bash tools/try-install-iso.sh --print ...     only show the QEMU commands
#
# It needs QEMU (qemu-system-x86, qemu-utils), the UEFI firmware (ovmf) and
# access to /dev/kvm, and offers to install the packages (sudo) if they are
# missing. Run it as your normal user, in your sway session (the VM is a window).
# shellcheck disable=SC2054  # QEMU's options are comma-separated on purpose
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
not_root

DIR=${XDG_CACHE_HOME:-$HOME/.cache}/debsway/iso-test
OVMF=${DEBSWAY_OVMF_DIR:-/usr/share/OVMF}   # (a test points this elsewhere)
CODE=$OVMF/OVMF_CODE_4M.fd
VARS_TEMPLATE=$OVMF/OVMF_VARS_4M.fd
DISK=$DIR/disk.qcow2
DISK2=$DIR/disk2.qcow2
VARS=$DIR/vars.fd

mode=install iso='' two=false print=false
while [ $# -gt 0 ]; do
    case $1 in
        --iso) iso=${2:-}; shift 2 ;;
        --two-disks) two=true; shift ;;
        --boot) mode=boot; shift ;;
        --clean) mode=clean; shift ;;
        --print) print=true; shift ;;
        -h | --help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "Unknown option $1. Try: bash tools/try-install-iso.sh --help" ;;
    esac
done

if [ "$mode" = clean ]; then
    rm -rf "$DIR"
    note "Deleted $DIR."
    if is_installed "$(apt_marker)"; then
        ask "Also remove QEMU and the UEFI firmware, which this script installed?" y && apt_purge
    fi
    exit 0
fi

if [ -z "$iso" ]; then
    iso=$(find "$DEBSWAY_DIR/offline/install-iso" -maxdepth 1 -name '*-debsway.iso' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
    [ -n "$iso" ] || $print || [ "$mode" = boot ] ||
        die "No built image in $DEBSWAY_DIR/offline/install-iso. Make one: bash prep/make-install-iso.sh"
fi
[ "$mode" = boot ] || [ -f "$iso" ] || $print || die "No image $iso."

# The machine: KVM, UEFI (its settings in a copy of its own), virtio network
base=(qemu-system-x86_64 -enable-kvm -cpu host -machine q35 -m 2048
    -drive "if=pflash,format=raw,readonly=on,file=$CODE"
    -drive "if=pflash,format=raw,file=$VARS"
    -nic user,model=virtio-net-pci)
install_cmd=("${base[@]}"
    -drive "if=none,id=disk,file=$DISK" -device virtio-blk-pci,drive=disk,bootindex=1)
$two && install_cmd+=(-drive "if=none,id=disk2,file=$DISK2" -device virtio-blk-pci,drive=disk2)
# the image as a USB stick, read-only, booted first; when the installer
# restarts at the end, QEMU stops instead (else the stick starts it again)
install_cmd+=(-drive "if=none,id=stick,format=raw,readonly=on,file=$iso"
    -device qemu-xhci -device usb-storage,drive=stick,bootindex=0 -no-reboot)
boot_cmd=("${base[@]}" -drive "if=none,id=disk,file=$DISK" -device virtio-blk-pci,drive=disk,bootindex=1)
$two && boot_cmd+=(-drive "if=none,id=disk2,file=$DISK2" -device virtio-blk-pci,drive=disk2)

if $print; then
    [ "$mode" = boot ] || { echo "# the installer:"; printf '%q ' "${install_cmd[@]}" | sed 's/\\,/,/g'; echo; }
    echo "# the installed system:"
    printf '%q ' "${boot_cmd[@]}" | sed 's/\\,/,/g'
    echo
    exit 0
fi

# ---- what it needs ----
need=()
command -v qemu-system-x86_64 >/dev/null || need+=(qemu-system-x86)
command -v qemu-img >/dev/null || need+=(qemu-utils)
[ -f "$CODE" ] && [ -f "$VARS_TEMPLATE" ] || need+=(ovmf)
if [ ${#need[@]} -gt 0 ]; then
    note "Missing: ${need[*]}."
    ask "Install them (needs your sudo password)? bash tools/try-install-iso.sh --clean removes them again." y ||
        die "Nothing was started. Install them yourself: sudo apt install ${need[*]}"
    apt_install "${need[@]}"
fi
[ -r /dev/kvm ] && [ -w /dev/kvm ] ||
    die "No access to /dev/kvm. Add yourself to the kvm group (sudo adduser $(id -un) kvm), log out and back in, and run this again. (No KVM in the firmware settings? Turn on VT-x / AMD-V.)"
[ -n "${WAYLAND_DISPLAY:-}${DISPLAY:-}" ] || warn "No graphical session: QEMU's window needs one (run this inside sway)."

mkdir -p "$DIR"
if [ "$mode" = boot ]; then
    [ -s "$DISK" ] || die "Nothing installed yet. Run: bash tools/try-install-iso.sh"
else
    if [ -s "$DISK" ]; then
        ask "A test disk from before is there. Start over with an empty one?" y || die "Kept it. Start the installed system with: bash tools/try-install-iso.sh --boot"
        rm -f "$DISK" "$DISK2"
    fi
    qemu-img create -q -f qcow2 "$DISK" 20G
    $two && qemu-img create -q -f qcow2 "$DISK2" 20G
    # the firmware's settings start fresh with the disk
    cp "$VARS_TEMPLATE" "$VARS"
    chmod u+w "$VARS"
fi
[ -f "$VARS" ] || { cp "$VARS_TEMPLATE" "$VARS"; chmod u+w "$VARS"; }

if [ "$mode" = install ]; then
    say "The installer, from $(basename -- "$iso") as a USB stick"
    cat <<EOF
    What to check in the window:
      1. The menu's first entry, highlighted: "Automatic install with debsway".
         Press Enter.
      2. It asks only for the disk encryption passphrase (twice) and your
         user's password (twice). Use throwaway ones.
EOF
    if $two; then
        echo "      3. With two disks it should ASK which disk (vda or vdb), never the stick."
    else
        echo "      3. \"Write the changes to disks?\" names /dev/vda (the 20 GB disk), not the stick."
    fi
    cat <<EOF
         If it names anything else, choose No.
      4. "Erasing data" fills the disk with random data: a few minutes.
      5. When it is done it restarts: the window closes by itself, and this
         script goes on to the installed system.

EOF
    "${install_cmd[@]}" || warn "QEMU ended with an error (see above)."
    ask "Start the installed system now?" y || { note "Later: bash tools/try-install-iso.sh --boot"; exit 0; }
fi

say "The installed system"
cat <<'EOF'
    What to check:
      - It asks for the disk passphrase at start, then shows a login.
      - You can log in with your user; sudo true works with your password.
      - ls ~/debsway shows debsway (bash ~/debsway/start.sh sets the rest up).
    Close the window to stop it. Delete everything: bash tools/try-install-iso.sh --clean

EOF
"${boot_cmd[@]}" || warn "QEMU ended with an error (see above)."
