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

echo "Parts packages:"
for p in "${PARTS_PKGS[@]}"; do show "$p"; done

echo "Extras (optional):"
for p in git gh keepassxc-minimal claude-code torbrowser-launcher seahorse electrum \
    sparrowwallet onionshare-cli mullvad-vpn mullvad-browser mat2 restic imv mpv mousepad thunar; do
    show "$p"
done
for app in feather simplex; do
    v=$(cat "$HOME/.local/opt/$app/.debsway-version" 2>/dev/null || true)
    if [ -n "$v" ]; then printf '  [x] %s %s\n' "$app" "$v"; else printf '  [ ] %s\n' "$app"; fi
done
if [ -L "$HOME/.local/bin/mockvps-kvm" ]; then
    printf '  [x] mockvps-kvm\n'
else
    printf '  [ ] mockvps-kvm\n'
fi
if virsh -c qemu:///session dominfo Whonix-Gateway >/dev/null 2>&1; then
    printf '  [x] whonix\n'
else
    printf '  [ ] whonix\n'
fi
for f in "$DEBSWAY_DIR"/torbrowser/tor-browser-linux-*.tar.xz "$DEBSWAY_DIR"/whonix/Whonix-*.libvirt.xz; do
    [ -f "$f" ] && printf '      saved: %s\n' "${f#"$DEBSWAY_DIR"/}"
done

echo "Firefox hardening (parts/firefox-hardening.sh):"
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

echo "Firefox profile commands (firefox-profiles/new-profile.sh):"
found=false
for c in "$HOME"/.local/bin/firefox-*; do
    if grep -qs 'debsway firefox-profiles/' "$c"; then
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
if [ -f /etc/NetworkManager/conf.d/90-debsway-random-mac.conf ]; then
    echo "  random Wi-Fi MAC address: on"
else
    echo "  random Wi-Fi MAC address: off"
fi
if have_internet; then echo "  online"; else echo "  offline"; fi
