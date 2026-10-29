#!/bin/bash
# Checks remove_wifi_config (lib/net.sh, behind wifi.sh --remove) on a pretend
# /etc, with pretend systemctl and ifdown. Changes nothing outside a temp
# folder. Run by test.sh, or:  bash tools/test-wifi-remove.sh
# shellcheck disable=SC2016  # the inner bash expands its own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

mkdir -p "$T/fake" "$T/etc/wpa_supplicant" "$T/etc/network/interfaces.d" "$T/etc/systemd/network"
for c in systemctl ifdown; do
    # shellcheck disable=SC2016  # written into the pretend programs, expanded when they run
    printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\n' "$c" "$T" >"$T/fake/$c"
done
chmod +x "$T/fake/"*

# what wifi.sh wrote, and some things that are not its
printf '# Written by debsway wifi.sh\nnetwork={\n}\n' >"$T/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
printf 'ctrl_interface=x\nnetwork={ ssid="mine" }\n' >"$T/etc/wpa_supplicant/wpa_supplicant-wlan1.conf"
printf '# Written by debsway wifi.sh\nallow-hotplug wlan0\n' >"$T/etc/network/interfaces.d/debsway-wifi-wlan0"
printf 'auto eth0\n' >"$T/etc/network/interfaces.d/eth0"
printf '[Match]\nName=wlan0\n' >"$T/etc/systemd/network/50-debsway-wlan0.network"
printf '[Match]\nName=eth0\n' >"$T/etc/systemd/network/10-mine.network"
echo "nameserver 192.168.1.1" >"$T/etc/resolv.conf.debsway.bak"
echo "nameserver 9.9.9.9" >"$T/etc/resolv.conf"

out=$(env PATH="$T/fake:$PATH" DEBSWAY_ETC="$T/etc" bash -c '. "$1/lib.sh"; PATH="$2:$PATH"; remove_wifi_config' _ "$HERE" "$T/fake" 2>&1)
check "wifi.sh's wpa_supplicant file is removed" test ! -e "$T/etc/wpa_supplicant/wpa_supplicant-wlan0.conf"
check "...and its service for that interface is switched off" grep -q 'systemctl disable --now wpa_supplicant@wlan0.service' "$T/calls"
check "a wpa_supplicant file that is yours is left alone" test -f "$T/etc/wpa_supplicant/wpa_supplicant-wlan1.conf"
check "the ifupdown stanza wifi.sh wrote is removed, the interface taken down" test ! -e "$T/etc/network/interfaces.d/debsway-wifi-wlan0" -a -n "$(grep 'ifdown wlan0' "$T/calls")"
check "other ifupdown files are left alone" test -f "$T/etc/network/interfaces.d/eth0"
check "the systemd-networkd file wifi.sh wrote is removed, networkd restarted" test ! -e "$T/etc/systemd/network/50-debsway-wlan0.network" -a -n "$(grep 'restart systemd-networkd' "$T/calls")"
check "your own networkd files are left alone" test -f "$T/etc/systemd/network/10-mine.network"
check "the saved DNS file is put back" grep -q 192.168.1.1 "$T/etc/resolv.conf"
check "...and the backup is gone" test ! -e "$T/etc/resolv.conf.debsway.bak"
check "it says what it removed" grep -q 'Removed .*wpa_supplicant-wlan0.conf' <<<"$out"

# nothing to remove: quiet, and nothing breaks
: >"$T/calls"
out=$(env PATH="$T/fake:$PATH" DEBSWAY_ETC="$T/etc" bash -c '. "$1/lib.sh"; PATH="$2:$PATH"; remove_wifi_config' _ "$HERE" "$T/fake" 2>&1)
check "running it again removes nothing and says nothing" test -z "$out"
check "...and starts no services" test ! -s "$T/calls"

# a DNS file that is a link (systemd-resolved) is not replaced
echo "nameserver 1.1.1.1" >"$T/etc/resolv.conf.debsway.bak"
rm -f "$T/etc/resolv.conf"; ln -s /run/systemd/resolve/stub-resolv.conf "$T/etc/resolv.conf"
env PATH="$T/fake:$PATH" DEBSWAY_ETC="$T/etc" bash -c '. "$1/lib.sh"; PATH="$2:$PATH"; remove_wifi_config' _ "$HERE" "$T/fake" >/dev/null 2>&1
check "a resolv.conf that is a link is left alone" test -L "$T/etc/resolv.conf"

# wifi.sh --remove is wired up and does not need a network
check "wifi.sh --remove is documented in its header" grep -q 'wifi.sh --remove' "$HERE/wifi.sh"
check "wifi.sh --remove calls it, before anything asks for a network" python3 -I -c '
import sys
s = open(sys.argv[1]).read()
assert s.index("remove_wifi_config") < s.index("\nfind_iface\n")
' "$HERE/wifi.sh"

[ "$fails" -eq 0 ]
