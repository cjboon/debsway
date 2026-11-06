#!/bin/bash
# tether: a phone's mobile data through its USB cable, for anyone, with or without
# NetworkManager and without knowing what DHCP is (bin/tether). While you are offline, a
# phone appearing opens a window that asks; it connects only if you say so.
# NetworkManager would otherwise connect any new wired device by itself, and any USB
# device can claim to be a network card, so it is told not to for the drivers phones
# use: tether asks instead. The computer's own Ethernet still connects by itself. A
# device with another driver still does too: this narrows the risk, not more.
# Usage: bash tether.sh [--remove]
# status: bin:tether
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

CONF=/etc/NetworkManager/conf.d/90-wren-tether.conf

reload_nm() {
    if systemctl is-active --quiet NetworkManager; then sudo nmcli general reload conf; fi
}

if [ "${1:-}" = --remove ]; then
    remove_snippet tether
    remove_bin tether
    sudo rm -f "$CONF"
    reload_nm
    note "A phone's connection is NetworkManager's alone again, or: sudo dhcpcd NAME"
    exit
fi

say "Phone tethering"
install_bin tether
sudo install -d -o root -g root -m 0755 "${CONF%/*}"
printf '%s\n' '# Written by Wren Linux parts/tether.sh: these connect only when you say so (tether)' \
    '[main]' 'no-auto-default=driver:rndis_host,driver:cdc_ether,driver:cdc_ncm,driver:ipheth' |
    sudo tee "$CONF" >/dev/null
reload_nm
put_snippet tether <<'SNIPPET'
# A phone tethering over USB, while offline: a window asks (Wren Linux parts/tether.sh)
exec ~/.local/bin/tether --watch
SNIPPET
note "While you are offline, plug a phone in and turn on USB tethering: a window asks. Or type: tether"
