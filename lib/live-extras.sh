# shellcheck shell=bash
# lib/live-extras.sh: what Debian's live image installs that debsway doesn't
# use (parts/no-live-extras.sh takes it out), and whether this computer needs
# dkms or mdadm after all (wifi.sh says so for a Wi-Fi driver too).

# Taken out wherever they are installed: network discovery that announces this
# computer's name on every network (avahi), a tool that can send your hardware
# details off (hw-probe), a helper for adding outside apt repositories
# (extrepo) and the unencrypted telnet client
LIVE_EXTRAS=(avahi-daemon libnss-mdns hw-probe extrepo inetutils-telnet)
# Printing, unless you print from this computer. cups-browsed (finding
# printers on the network) goes either way.
LIVE_PRINTING=(cups cups-daemon cups-core-drivers cups-browsed)
# A removal that would take any of these with it is refused
LIVE_KEEP='sudo|apt|dpkg|systemd|systemd-sysv|udev|cryptsetup|cryptsetup-initramfs|lvm2|initramfs-tools|grub-.*|shim-.*|linux-image-.*|firmware-.*|network-manager|wpasupplicant|iw|sway|foot|tor|nftables|ufw|debsway-.*'

DKMS_DIR=${DEBSWAY_DKMS_DIR:-/var/lib/dkms}
MDSTAT=${DEBSWAY_MDSTAT:-/proc/mdstat}

# dkms_needed: why dkms must stay (a module it builds, or a package that
# needs it), or nothing and false
dkms_needed() {
    local d deps
    for d in "$DKMS_DIR"/*/; do
        [ -d "$d" ] || continue
        echo "it builds the kernel module $(basename "$d")"
        return 0
    done
    deps=$(apt-cache rdepends --installed --no-recommends --no-suggests --no-conflicts \
        --no-breaks --no-replaces --no-enhances dkms 2>/dev/null | tail -n +3 | sed 's/^ *//' | grep -vx dkms | sort -u | paste -sd' ')
    if [ -n "$deps" ]; then
        echo "$deps needs it"
        return 0
    fi
    return 1
}

# mdadm_needed: why mdadm must stay (a software RAID array, running or on a
# disk, or one named in its settings), or nothing and false
mdadm_needed() {
    if grep -qE '^md[0-9a-z_]* *:' "$MDSTAT" 2>/dev/null; then
        echo "a software RAID array is running"
        return 0
    fi
    if lsblk -rno FSTYPE 2>/dev/null | grep -qx linux_raid_member; then
        echo "a disk is part of a software RAID array"
        return 0
    fi
    if grep -qs '^ARRAY' "${DEBSWAY_ETC:-/etc}/mdadm/mdadm.conf"; then
        echo "${DEBSWAY_ETC:-/etc}/mdadm/mdadm.conf names a RAID array"
        return 0
    fi
    return 1
}

# dkms_wifi_driver IFACE: the name of IFACE's driver if DKMS built it, else false
dkms_wifi_driver() {
    local mod path
    [ -e "$SYS/class/net/$1/device/driver/module" ] || return 1
    mod=$(basename "$(readlink -f "$SYS/class/net/$1/device/driver/module")")
    path=$(modinfo -n "$mod" 2>/dev/null) || return 1
    case $path in */dkms/*) echo "$mod" ;; *) return 1 ;; esac
}
