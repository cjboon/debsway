#!/bin/bash
# Stops kernel modules nobody on a laptop needs from loading: rare network
# protocols (dccp, sctp, rds, tipc, ...), old filesystems (cramfs, jffs2,
# hfs, ...) and FireWire, which can read memory directly. A USB stick with
# one of those filesystems then simply won't mount. The list is
# data/module-blacklist.conf; HFS+ (Mac sticks), UDF, exFAT and NTFS are
# deliberately not on it.
# Usage: bash module-blacklist.sh [--remove]
# status: file:/etc/modprobe.d/60-debsway-blacklist.conf
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

CONF=/etc/modprobe.d/60-debsway-blacklist.conf

if [ "${1:-}" = --remove ]; then
    sudo rm -f "$CONF"
    note "Those modules can load again."
    exit
fi

say "Blocking unused kernel modules"
tmp=$(mktemp)
{
    echo "# Written by debsway parts/module-blacklist.sh (data/module-blacklist.conf)"
    grep -vE '^[[:space:]]*(#|$)' "$DEBSWAY_DIR/data/module-blacklist.conf" | while read -r mod; do
        echo "blacklist $mod"
        echo "install $mod /bin/false"
    done
} >"$tmp"
sudo install -o root -g root -m 0644 "$tmp" "$CONF"
rm -f "$tmp"
# A module already loaded stays until the next boot
loaded=$(awk '{ print $1 }' /proc/modules)
while read -r mod; do
    if grep -qx "${mod//-/_}" <<<"$loaded"; then warn "$mod is loaded now; it is blocked from the next boot."; fi
done < <(grep -vE '^[[:space:]]*(#|$)' "$DEBSWAY_DIR/data/module-blacklist.conf")
note "Wrote $CONF ($(grep -c '^install' "$CONF") modules)."
