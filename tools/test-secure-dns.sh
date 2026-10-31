#!/bin/bash
# Checks extras/secure-dns.sh's pieces: the resolvers pinned in pins.sh, the
# Unbound settings made from them (lib/secure-dns.sh), the firewall rule that
# keeps DNS from going around Unbound, and that wifi.sh and wifi.sh --remove
# leave /etc/resolv.conf alone while it is on (on a pretend /etc). Nothing is
# installed and nothing outside a temp folder is changed. Run by test.sh, or:
#   bash tools/test-secure-dns.sh
# shellcheck disable=SC2016  # the inner bash expands its own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh"
. "$HERE/lib/secure-dns.sh"
set +e +o pipefail

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
ip_ok() { [[ $1 =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || $1 =~ ^[0-9a-f:]+:[0-9a-f:]*$ ]]; }

# ---- the resolvers ----
for name in "${DNS_PROVIDERS[@]}"; do
    pin=$(dns_pin "$name")
    tls=$(dns_tls_name "$name")
    addrs=${pin#* }
    check "$name: pinned with a certificate name ($tls)" bash -c "[[ \$1 =~ ^[a-z0-9.-]+\.[a-z]+\$ ]]" _ "$tls"
    good=true
    for a in $addrs; do ip_ok "$a" || good=false; done
    check "$name: every pinned address is an IP address" $good
    check "$name: has a description" test -n "$(dns_describe "$name")"

    conf=$(dns_unbound_conf "$name")
    n=0
    for a in $addrs; do
        grep -qxF "    forward-addr: $a@853#$tls" <<<"$conf" && n=$((n + 1))
    done
    check "$name: Unbound asks each address on port 853 and checks it is $tls" test "$n" -eq "$(wc -w <<<"$addrs")"
    check "$name: only over TLS, never unencrypted" bash -c 'grep -qx "    forward-tls-upstream: yes" <<<"$1" && grep -qx "    forward-first: no" <<<"$1" && ! grep -E "forward-addr: [^ ]*$" <<<"$1" | grep -v "@853#"' _ "$conf"
    check "$name: certificates checked against the system's CA list" grep -qx "    tls-cert-bundle: /etc/ssl/certs/ca-certificates.crt" <<<"$conf"
    check "$name: listens on 127.0.0.1 only" bash -c '[ "$(grep -c "^ *interface:" <<<"$1")" = 1 ] && grep -qx "    interface: 127.0.0.1" <<<"$1"' _ "$conf"
    check "$name: no failing open on a bad DNSSEC signature" grep -qx "    val-permissive-mode: no" <<<"$conf"
done
if dns_unbound_conf nobody >/dev/null 2>&1; then unknown=false; else unknown=true; fi
check "an unknown resolver gives no settings" $unknown
check "Mullvad's public DNS (gone 2026-11-02) isn't offered" bash -c '! grep -qi mullvad <<<"$1"' _ "$(for n in "${DNS_PROVIDERS[@]}"; do dns_pin "$n"; done)"
if command -v unbound-checkconf >/dev/null; then
    dns_unbound_conf quad9 >"$T/unbound.conf"
    check "unbound-checkconf accepts the settings" unbound-checkconf "$T/unbound.conf"
else
    echo "  skip  unbound-checkconf isn't installed"
fi

# ---- which resolver is in use, and status.sh's line ----
export DEBSWAY_ETC=$T/etc
mkdir -p "$T/etc/unbound/unbound.conf.d"
if secure_dns_on; then off=false; else off=true; fi
check "with no settings it is off" $off
check "status.sh says DNS is unencrypted" grep -q "DNS: unencrypted" <<<"$(dns_status)"
dns_unbound_conf digiges >"$T/etc/unbound/unbound.conf.d/debsway-secure-dns.conf"
check "with its settings it is on" secure_dns_on
check "the resolver in use is read back" test "$(dns_current)" = digiges
check "status.sh names it" grep -q "DNS: encrypted to dns.digitale-gesellschaft.ch" <<<"$(dns_status)"

# ---- wifi.sh leaves resolv.conf alone while it is on ----
# set_dns from wifi.sh, writing into the pretend /etc; resolvconf only writes down that it ran
echo "nameserver 127.0.0.1" >"$T/etc/resolv.conf"
# shellcheck disable=SC2016
out=$(bash -c '
    . "$1/lib.sh"; set +e
    log=$2/log; resolvconf() { echo "resolvconf ran" >>"$log"; }
    eval "$(sed -n "/^set_dns() {/,/^}/p" "$1/wifi.sh" | sed "s|/etc/resolv.conf|$2/etc/resolv.conf|g")"
    IF=wlan0
    set_dns 192.168.1.1' _ "$HERE" "$T" 2>&1)
check "wifi.sh doesn't put the network's DNS server back" grep -qx "nameserver 127.0.0.1" "$T/etc/resolv.conf"
check "nor hand it to resolvconf" test ! -e "$T/log"
check "its busybox DHCP script leaves it alone too" \
    grep -q 'resolv.conf \] && \[ ! -e /etc/unbound/unbound.conf.d/debsway-secure-dns.conf \]' "$HERE/wifi.sh"
echo "nameserver 192.168.1.1" >"$T/etc/resolv.conf.debsway.bak"
remove_wifi_config >/dev/null 2>&1
check "wifi.sh --remove doesn't put its old copy back over it" grep -qx "nameserver 127.0.0.1" "$T/etc/resolv.conf"
rm -f "$T/etc/unbound/unbound.conf.d/debsway-secure-dns.conf"
remove_wifi_config >/dev/null 2>&1
check "...but does once secure DNS is off" grep -qx "nameserver 192.168.1.1" "$T/etc/resolv.conf"
: "$out"

# ---- the firewall rule ----
FW=$HERE/data/secure-dns-firewall.nft
rules=$(sed -n '/chain output {/,/^    }/p' "$FW" | grep -v '^ *#')
pos() { grep -n -- "$1" <<<"$rules" | head -1 | cut -d: -f1; }
check "the rule refuses DNS (53) and DNS over TLS (853), UDP and TCP" \
    bash -c 'grep -q "udp dport { 53, 853 } reject" <<<"$1" && grep -q "tcp dport { 53, 853 } reject" <<<"$1"' _ "$rules"
check "questions to Unbound on this computer pass first" test "$(pos 'oifname "lo" accept')" -lt "$(pos 'udp dport')"
check "Unbound itself may ask its resolver" test "$(pos 'meta skuid "unbound" accept')" -lt "$(pos 'udp dport')"
check "a VPN tunnel's own DNS passes (Mullvad points resolv.conf into it)" \
    bash -c '[ "$1" -lt "$3" ] && [ "$2" -lt "$3" ]' _ "$(pos 'oifname "wg\*" accept')" "$(pos 'oifname "tun\*" accept')" "$(pos 'udp dport')"
check "nobody else is let through" test "$(grep -c ' accept$' <<<"$rules")" -eq 4
check "it replaces its own table when loaded again" \
    bash -c 'grep -qx "delete table inet debsway_secure_dns" "$1" && grep -qx "table inet debsway_secure_dns {" "$1"' _ "$FW"
# nft reads user names as it loads, so "unbound" becomes root for the check here
if command -v nft >/dev/null && unshare -rn true 2>/dev/null; then
    sed 's/skuid "unbound"/skuid "root"/' "$FW" >"$T/fw.nft"
    check "nft accepts the rule" unshare -rn nft -c -f "$T/fw.nft"
else
    echo "  skip  nft isn't installed (or no user namespaces), so its syntax isn't checked"
fi

[ "$fails" -eq 0 ]
