#!/bin/bash
# NetworkManager (nmcli, nmtui) for easy switching between networks.
# Moves any Wi-Fi already set up by the Debian installer or wifi.sh
# over to NetworkManager, so it keeps connecting after a reboot.
# Usage: bash network-manager.sh [--remove]
# status: apt:network-manager
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    warn "Removing NetworkManager disconnects you. Run 'bash $DEBSWAY_DIR/wifi.sh' afterwards."
    ask "Continue?" n || exit 0
    # wifi.sh needs these to get you back online
    sudo apt-mark manual wpasupplicant wireless-regdb >/dev/null
    remove_bin nmtui
    apt_purge network-manager
    exit
fi

# polkitd lets your user (not just root) control connections
say "Installing network-manager"
apt_install network-manager wpasupplicant wireless-regdb polkitd
# nmtui in debsway's colors (the Wi-Fi name in the bar opens it)
install_bin nmtui

hex_to_text() { printf '%b' "$(sed 's/../\\x&/g' <<<"$1")"; }

# Prints "ssid<TAB>psk<TAB>hidden" (hidden is 1 or 0) for IF from wifi.sh's
# or the installer's config
existing_wifi() {
    local ifc=$1 conf=/etc/wpa_supplicant/wpa_supplicant-$1.conf ssid psk hidden=0
    if sudo test -f "$conf"; then
        if sudo grep -qE '^[[:space:]]*scan_ssid=1' "$conf"; then hidden=1; fi
        ssid=$(sudo sed -n 's/^[[:space:]]*ssid=//p' "$conf" | head -1)
        psk=$(sudo sed -n 's/^[[:space:]]*psk=//p' "$conf" | head -1)
        case $ssid in
            \"*\") ssid=${ssid:1:-1} ;;
            *) ssid=$(hex_to_text "$ssid") ;;
        esac
        case $psk in \"*\") psk=${psk:1:-1} ;; esac
    else
        ssid=$(sudo awk '$1 == "wpa-ssid" { $1 = ""; sub(/^ /, ""); print; exit }' \
            /etc/network/interfaces 2>/dev/null | tr -d '"')
        psk=$(sudo awk '$1 == "wpa-psk" { print $2; exit }' \
            /etc/network/interfaces 2>/dev/null | tr -d '"')
        if sudo grep -qE '^[[:space:]]*wpa-scan-ssid[[:space:]]+1' /etc/network/interfaces 2>/dev/null; then
            hidden=1
        fi
    fi
    [ -n "$ssid" ] && printf '%s\t%s\t%s\n' "$ssid" "$psk" "$hidden"
}

moved=() moved_psk=()
for ifc in $(wifi_ifaces); do
    creds=$(existing_wifi "$ifc" || true)
    [ -n "$creds" ] || continue
    ssid=${creds%%$'\t'*}
    rest=${creds#*$'\t'}
    psk=${rest%$'\t'*}
    hidden=${rest##*$'\t'}

    say "Moving Wi-Fi \"$ssid\" on $ifc to NetworkManager"
    sudo nmcli connection delete id "$ssid" >/dev/null 2>&1 || true
    # WPA2 first; a WPA3-only network is retried as SAE below. The connection
    # is written to NetworkManager's config folder, so the password never
    # appears in the command line of a running nmcli; nmcli add is the
    # fallback for names and passwords that file format can't hold.
    if ! nm_write_wifi "$ssid" "$psk" "$hidden" "$ifc"; then
        args=(connection add type wifi con-name "$ssid" ifname "$ifc" ssid "$ssid")
        if [ "$hidden" = 1 ]; then args+=(802-11-wireless.hidden yes); fi
        if [ -n "$psk" ]; then args+=(wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$psk"); fi
        sudo nmcli "${args[@]}" >/dev/null
    fi

    # Stop the old setup, then remove its config
    sudo ifdown "$ifc" >/dev/null 2>&1 || true
    sudo systemctl disable --now "wpa_supplicant@$ifc.service" >/dev/null 2>&1 || true
    sudo rm -f "/etc/network/interfaces.d/debsway-wifi-$ifc" \
        "/etc/systemd/network/50-debsway-$ifc.network"
    drop_ifupdown_iface "$ifc"
    moved+=("$ssid")
    if [ -n "$psk" ]; then moved_psk+=(yes); else moved_psk+=(no); fi
done

say "Restarting NetworkManager"
sudo systemctl enable NetworkManager >/dev/null
sudo systemctl restart NetworkManager
for i in "${!moved[@]}"; do
    ssid=${moved[i]}
    if sudo nmcli --wait 30 connection up id "$ssid" >/dev/null 2>&1; then
        note "Connected to \"$ssid\"."
    elif [ "${moved_psk[i]}" = yes ] &&
        sudo nmcli connection modify id "$ssid" wifi-sec.key-mgmt sae &&
        sudo nmcli --wait 30 connection up id "$ssid" >/dev/null 2>&1; then
        note "Connected to \"$ssid\" (WPA3)."
    else
        # Back to WPA2, the usual kind, so nmtui shows what you expect
        if [ "${moved_psk[i]}" = yes ]; then
            sudo nmcli connection modify id "$ssid" wifi-sec.key-mgmt wpa-psk || true
        fi
        warn "Couldn't reconnect to \"$ssid\". Run: nmtui"
    fi
done

note "Pick networks with: nmtui     List them: nmcli device wifi list"
note "Ethernet set up by the installer stays with ifupdown and keeps working."
