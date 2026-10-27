#!/bin/bash
# Shows what debsway has set up on this machine.
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
. "$DEBSWAY_DIR/packages.sh"

show() {
    if is_installed "$1"; then printf '  [x] %s\n' "$1"; else printf '  [ ] %s\n' "$1"; fi
}

# Encrypted if any layer under the device is dm-crypt (LUKS)
on_crypt() { lsblk -s -no TYPE "$1" 2>/dev/null | grep -qx crypt; }

echo "Disk encryption:"
plain=()
for m in / /home; do
    src=$(findmnt -no SOURCE "$m" 2>/dev/null | sed 's/\[.*//') || continue
    [ -n "$src" ] || continue
    [ "$m" = / ] || [ "$src" != "$(findmnt -no SOURCE / | sed 's/\[.*//')" ] || continue
    if on_crypt "$src"; then printf '  [x] %s\n' "$m"; else printf '  [ ] %s (%s)\n' "$m" "$src"; plain+=("$m"); fi
done
while read -r name type; do
    case $name in /dev/zram*) continue ;; esac
    dev=$name
    [ "$type" = file ] && dev=$(findmnt -no SOURCE -T "$name" | sed 's/\[.*//')
    if on_crypt "$dev"; then printf '  [x] swap %s\n' "$name"; else printf '  [ ] swap %s\n' "$name"; plain+=("swap"); fi
done < <(swapon --show=NAME,TYPE --noheadings 2>/dev/null)
if [ ${#plain[@]} -gt 0 ]; then
    warn "Not encrypted: ${plain[*]}. Anyone with the laptop can read your files,"
    warn "wallets and passwords. Reinstall with encrypted LVM (see README, Installing Debian)."
fi

echo "Base packages:"
for p in "${PKGS[@]}"; do show "$p"; done

# status_of SCRIPT: "[x] name (what)" from the script's "# status:" line
status_of() {
    local name have=()
    name=$(basename -- "$1" .sh)
    mapfile -t have < <(script_found "$1")
    if [ ${#have[@]} -eq 1 ] && [ "${have[0]}" = "$name" ]; then
        printf '  [x] %s\n' "$name"
    elif [ ${#have[@]} -gt 0 ]; then
        printf '  [x] %s (%s)\n' "$name" "$(IFS=,; echo "${have[*]}" | sed 's/,/, /g')"
    else
        printf '  [ ] %s\n' "$name"
    fi
}

echo "Parts (parts/):"
for part in "${PARTS[@]}"; do status_of "$DEBSWAY_DIR/parts/$part.sh"; done

echo "Extras (optional, extras/):"
for f in "$DEBSWAY_DIR"/extras/*.sh; do status_of "$f"; done
for f in "$DEBSWAY_DIR"/offline/torbrowser/tor-browser-linux-*.tar.xz "$DEBSWAY_DIR"/offline/whonix/Whonix-*.libvirt.xz; do
    [ -f "$f" ] && printf '      saved: %s\n' "${f#"$DEBSWAY_DIR"/}"
done

echo "Packages debsway installed (one marker per script; apt purge debsway-NAME removes it):"
markers=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'debsway-*' 2>/dev/null | awk '$1 == "ii" { print $2 }')
if [ -n "$markers" ]; then
    for m in $markers; do
        printf '  %s: %s\n' "${m#debsway-}" "$(marker_depends "$m" | paste -sd' ')"
    done
else
    echo "  (none recorded yet)"
fi

echo "Firefox (extras/firefox.sh):"
if [ -x /usr/local/bin/incognito ]; then
    echo "  [x] incognito command (throwaway Firefox as the locked-down user)"
else
    echo "  [ ] incognito command (throwaway Firefox as the locked-down user)"
fi
if [ -f /etc/firefox-esr/debsway-hardening.js ]; then
    echo "  [x] HTTPS-Only Mode, JavaScript JIT off"
else
    echo "  [ ] HTTPS-Only Mode, JavaScript JIT off"
fi
if [ -f /etc/firefox-esr/policies/.debsway-written ]; then
    n=$(grep -cv '^#' /etc/firefox-esr/debsway-ublock-allow 2>/dev/null || true)
    echo "  [x] uBlock Origin medium mode (${n:-0} sites allowed: ublock-allow --list)"
else
    echo "  [ ] uBlock Origin medium mode"
fi
if systemctl --user is-enabled --quiet firefox-restart-check.timer 2>/dev/null; then
    echo "  [x] notice when Firefox needs a restart after an update"
else
    echo "  [ ] notice when Firefox needs a restart after an update"
fi

echo "Firefox profile commands (extras/firefox-profiles/new-profile.sh):"
found=false
for c in "$HOME"/.local/bin/firefox-*; do
    if grep -qsE 'debsway (extras/)?firefox-profiles/' "$c"; then
        printf '  %s\n' "${c##*/}"
        found=true
    fi
done
$found || echo "  (none)"

echo "sway snippets in $SWAY_SNIPPETS:"
shopt -s nullglob
snippets=("$SWAY_SNIPPETS"/*.conf)
if [ ${#snippets[@]} -gt 0 ]; then printf '  %s\n' "${snippets[@]##*/}"; else echo "  (none)"; fi

echo "Network:"
for ifc in $(wifi_ifaces); do
    how="not set up"
    if systemctl is-active --quiet NetworkManager &&
        nmcli -t -f DEVICE,STATE device 2>/dev/null | grep -q "^$ifc:connected"; then
        how="NetworkManager"
    elif [ -f "/etc/network/interfaces.d/debsway-wifi-$ifc" ]; then
        how="ifupdown + wpa_supplicant (wifi.sh)"
    elif systemctl is-enabled --quiet "wpa_supplicant@$ifc.service" 2>/dev/null; then
        how="wpa_supplicant@$ifc + systemd-networkd (wifi.sh)"
    elif grep -qs "iface $ifc" /etc/network/interfaces; then
        how="ifupdown (Debian installer)"
    fi
    printf '  %s: %s\n' "$ifc" "$how"
done
if [ -e /etc/tor/.debsway-apt-tor ]; then
    echo "  apt downloads through Tor (parts/apt-tor.sh)"
else
    echo "  apt downloads directly"
fi
if [ -f /etc/NetworkManager/conf.d/90-debsway-random-mac.conf ]; then
    echo "  random Wi-Fi MAC address: on"
else
    echo "  random Wi-Fi MAC address: off"
fi
if have_internet; then echo "  online"; else echo "  offline"; fi
