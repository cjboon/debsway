#!/bin/bash
# Checks that dhcpcd and dhclient are told not to send this computer's name, on copies of
# their settings like Debian's: taken out, put back exactly, and nothing else touched. That
# the real clients then send none, and do once it's put back, was seen once in a real
# DHCP server's log, in network namespaces. Changes nothing outside a temp folder.
# Run by test.sh, or:  bash tools/test-dhcp-no-name.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
eval "$(sed -n '/^DHCP_NO_NAME_MARK=/,/^}/p' "$HERE/lib/net.sh")"
SUDO=
export WREN_ETC=$T/etc
mkdir -p "$T/etc/dhcp"
D=$T/etc/dhcpcd.conf C=$T/etc/dhcp/dhclient.conf
cat >"$D" <<'CONF'
# A sample configuration for dhcpcd.
# Inform the DHCP server of our hostname for DDNS.
hostname
# hostname written in a comment stays
option domain_name_servers
CONF
cat >"$C" <<'CONF'
# Configuration file for /sbin/dhclient.
send host-name = gethostname();
#send host-name "andare.fugue.com";
request subnet-mask, routers, domain-name-servers;
CONF
cp "$D" "$T/d.orig"; cp "$C" "$T/c.orig"

dhcp_no_name on
check "dhcpcd: its hostname line is out" not grep -qx 'hostname' "$D"
check "dhclient: its send host-name line is out" not grep -qE '^send host-name' "$C"
check "nothing else changed" bash -c '[ "$(diff "$1" "$2" | grep -c "^[<>]")" = 2 ] && [ "$(diff "$3" "$4" | grep -c "^[<>]")" = 2 ]' _ "$T/d.orig" "$D" "$T/c.orig" "$C"
cp "$D" "$T/d.once"
dhcp_no_name on
check "run again, it's the same" cmp "$D" "$T/d.once"
dhcp_no_name off
check "off puts dhcpcd's back exactly" cmp "$D" "$T/d.orig"
check "...and dhclient's" cmp "$C" "$T/c.orig"
rm -f "$D" "$C"
check "a client that isn't installed: nothing to do, no error" dhcp_no_name on
check "...and no file made" test ! -e "$D"

W=$HERE/wifi.sh
check "wifi.sh: before it gets an address" bash -c 'sed -n "/^dhcp_now() {/,/^}/p" "$1" | grep -q "dhcp_no_name on"' _ "$W"
check "...before a saved Wi-Fi connection comes up (ifup)" bash -c 'grep -B14 "ifup \"\$IF\"" "$1" | grep -q "dhcp_no_name on"' _ "$W"
check "...and a saved cable" bash -c 'sed -n "/^keep_wired() {/,/^}/p" "$1" | grep -q "dhcp_no_name on"' _ "$W"
check "...with systemd-networkd, its own setting" bash -c 'sed -n "/^networkd_dhcp() {/,/^}/p" "$1" | grep -q "SendHostname=no"' _ "$W"
P=$HERE/parts/dhcp-no-name.sh
check "the part is in the base, and --remove puts them back" bash -c '. "$1/packages.sh"; [[ " ${PARTS[*]} " == *" dhcp-no-name "* ]] && grep -q "dhcp_no_name off" "$2"' _ "$HERE" "$P"

[ "$fails" -eq 0 ]
