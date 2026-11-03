#!/bin/bash
# Takes out what Debian's live image installs that Wren Linux doesn't use (a
# DVD or netinst install doesn't have it): avahi, which announces this
# computer's name and services on every network it joins; hw-probe, which can
# send your hardware details off; extrepo and the telnet client; and the
# printing system, unless you say you print (cups-browsed, which looks for
# printers on the network, goes either way). dkms and mdadm go only if nothing
# here needs them: no kernel module DKMS builds (some Wi-Fi drivers) and no
# software RAID. sudo is marked as wanted first: on a live install nothing but
# hw-probe kept it, so removing that would let apt take sudo too.
# Nothing is reinstalled by --remove: install one again with: sudo apt install NAME
# Usage: bash no-live-extras.sh [--remove]
# status: gone:avahi-daemon gone:hw-probe
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$WREN_DIR/lib/live-extras.sh"
need_user

if [ "${1:-}" = --remove ]; then
    note "Nothing to undo. To have one back: sudo apt install NAME (e.g. cups for printing)."
    exit
fi

# Kept whatever apt thinks: sudo is how you run everything as root
if is_installed sudo && apt-mark showauto sudo 2>/dev/null | grep -qx sudo; then
    sudo apt-mark manual sudo >/dev/null
    note "Marked sudo as wanted, so removing other packages can't take it out."
fi

go=()
for p in "${LIVE_EXTRAS[@]}"; do is_installed "$p" && go+=("$p"); done
printing=()
for p in "${LIVE_PRINTING[@]}"; do is_installed "$p" && printing+=("$p"); done
if [ ${#printing[@]} -gt 0 ]; then
    if ask "Do you print from this computer?" n; then
        if is_installed cups-browsed; then go+=(cups-browsed); fi
        note "Printing stays (cups). Add a printer by its address; it isn't looked for on the network."
    else
        go+=("${printing[@]}")
    fi
fi
for p in dkms mdadm; do
    is_installed "$p" || continue
    if why=$("${p}_needed"); then
        note "Keeping $p: $why."
    else
        go+=("$p")
    fi
done

if [ ${#go[@]} -eq 0 ]; then
    note "None of the live image's extras are installed."
    exit
fi

say "Removing what the live image installed and Wren Linux doesn't use"
# What apt would take out with them, before anything is done
mapfile -t gone < <(apt-get -s purge --autoremove "${go[@]}" 2>/dev/null | awk '/^(Purg|Remv) / { print $2 }')
[ ${#gone[@]} -gt 0 ] || die "apt couldn't work out what removing ${go[*]} would take. Nothing was removed."
keep=$(printf '%s\n' "${gone[@]}" | grep -xE "$LIVE_KEEP" | paste -sd' ' || true)
[ -z "$keep" ] ||
    die "Removing ${go[*]} would also take out $keep, which this system needs. Nothing was removed."
note "Going: ${gone[*]}"
sudo apt-get purge --autoremove -y "${go[@]}"
note "Removed. To have one back: sudo apt install NAME"
