#!/bin/bash
# Random Wi-Fi MAC address: NetworkManager makes up a new hardware
# address every time it connects, and another while scanning, so networks
# (and whoever runs them) can't recognise this laptop from place to place.
# It also stops sending this computer's name to the network's DHCP server,
# and uses temporary IPv6 addresses instead of ones built from the hardware.
# Side effects: Wi-Fi login pages at cafés and hotels may ask again after
# reconnecting, and your home router sees a "new" device each time. For
# one made-up address per network instead, change "random" to "stable"
# in the file below.
# Runs after parts/network-manager.sh.
# Usage: bash random-mac.sh [--remove]
# status: file:/etc/NetworkManager/conf.d/90-debsway-random-mac.conf
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

CONF=/etc/NetworkManager/conf.d/90-debsway-random-mac.conf

reload_nm() {
    if systemctl is-active --quiet NetworkManager; then sudo nmcli general reload conf; fi
}

if [ "${1:-}" = --remove ]; then
    sudo rm -f "$CONF"
    reload_nm
    note "Wi-Fi uses the real MAC address from the next connection on."
    exit
fi

skip_unless has_wifi "no Wi-Fi adapter found, so there is no Wi-Fi address to randomize."
is_installed network-manager ||
    die "NetworkManager isn't installed. Run parts/network-manager.sh first."

say "Random Wi-Fi MAC address"
printf '%s\n' "# Written by debsway parts/random-mac.sh" \
    '[device]' 'wifi.scan-rand-mac-address=yes' '' \
    '[connection]' 'wifi.cloned-mac-address=random' \
    'ipv4.dhcp-send-hostname=false' 'ipv6.dhcp-send-hostname=false' \
    'ipv6.ip6-privacy=2' | sudo tee "$CONF" >/dev/null
reload_nm

# A connection with its own setting ignores the default above
while IFS=: read -r name type; do
    [ "$type" = 802-11-wireless ] || continue
    mac=$(nmcli -g 802-11-wireless.cloned-mac-address connection show "$name" 2>/dev/null || true)
    if [ -n "$mac" ] && [ "$mac" != random ]; then
        warn "\"$name\" has its own MAC setting ($mac). For it too: nmcli connection modify \"$name\" 802-11-wireless.cloned-mac-address \"\""
    fi
done < <(nmcli -t -f NAME,TYPE connection show 2>/dev/null)

note "Applies from the next Wi-Fi connection (now: nmcli device connect $(wifi_ifaces | head -1))."
note "Check it: ip link show $(wifi_ifaces | head -1)   (the address after link/ether)"
