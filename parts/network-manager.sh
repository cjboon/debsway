#!/bin/bash
# NetworkManager (nmcli, nmtui) for easy switching between networks.
# Moves any Wi-Fi already set up by the Debian installer or wifi.sh
# over to NetworkManager, so it keeps connecting after a reboot.
# Usage: bash network-manager.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    warn "Removing NetworkManager disconnects you. Run 'bash $DEBSWAY_DIR/wifi.sh' afterwards."
    ask "Continue?" n || exit 0
    apt_purge network-manager
    exit
fi

# polkitd lets your user (not just root) control connections
say "Installing network-manager"
apt_install network-manager wpasupplicant wireless-regdb polkitd

hex_to_text() { printf '%b' "$(sed 's/../\\x&/g' <<<"$1")"; }

# Prints "ssid<TAB>psk" for IF from wifi.sh's or the installer's config
existing_wifi() {
    local ifc=$1 conf=/etc/wpa_supplicant/wpa_supplicant-$1.conf ssid psk
    if sudo test -f "$conf"; then
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
    fi
    [ -n "$ssid" ] && printf '%s\t%s\n' "$ssid" "$psk"
}

moved=()
for ifc in $(wifi_ifaces); do
    creds=$(existing_wifi "$ifc" || true)
    [ -n "$creds" ] || continue
    ssid=${creds%%$'\t'*}
    psk=${creds#*$'\t'}

    say "Moving Wi-Fi \"$ssid\" on $ifc to NetworkManager"
    sudo nmcli connection delete id "$ssid" >/dev/null 2>&1 || true
    if [ -n "$psk" ]; then
        sudo nmcli connection add type wifi con-name "$ssid" ifname "$ifc" ssid "$ssid" \
            wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$psk" >/dev/null
    else
        sudo nmcli connection add type wifi con-name "$ssid" ifname "$ifc" ssid "$ssid" >/dev/null
    fi

    # Stop the old setup, then remove its config
    sudo ifdown "$ifc" >/dev/null 2>&1 || true
    sudo systemctl disable --now "wpa_supplicant@$ifc.service" >/dev/null 2>&1 || true
    sudo rm -f "/etc/network/interfaces.d/debsway-wifi-$ifc" \
        "/etc/systemd/network/50-debsway-$ifc.network"
    drop_ifupdown_iface "$ifc"
    moved+=("$ssid")
done

say "Restarting NetworkManager"
sudo systemctl enable NetworkManager >/dev/null
sudo systemctl restart NetworkManager
for ssid in "${moved[@]}"; do
    if sudo nmcli --wait 30 connection up id "$ssid" >/dev/null 2>&1; then
        note "Connected to \"$ssid\"."
    else
        warn "Couldn't reconnect to \"$ssid\". Run: nmtui"
    fi
done

note "Pick networks with: nmtui     List them: nmcli device wifi list"
note "Ethernet set up by the installer stays with ifupdown and keeps working."
