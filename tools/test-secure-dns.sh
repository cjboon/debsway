#!/bin/bash
# Checks parts/secure-dns.sh's pieces: the resolvers pinned in pins.sh, the
# Unbound settings made from them (lib/secure-dns.sh), the firewall rule that
# keeps DNS from going around Unbound, that wifi.sh and wifi.sh --remove
# leave /etc/resolv.conf alone while it is on (on a pretend /etc), and the
# switch (bin/secure-dns-switch, on a copy whose /etc is a temp folder, with
# pretend systemctl, nmcli, nft and getent; and bin/secure-dns with a pretend
# sudo). Nothing is installed and nothing outside a temp folder is changed.
# Run by test.sh, or:
#   bash tools/test-secure-dns.sh
# shellcheck disable=SC2016  # the inner bash expands its own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh"
. "$HERE/lib/secure-dns.sh"
set +e +o pipefail

T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
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
# A first run has no settings file yet: asking which resolver is in use must
# not end the script (it did, silently, right after "Which resolver")
check "first run, no settings yet: dns_current gives nothing and the script goes on" \
    env WREN_ETC="$T/no-etc" bash -c 'set -euo pipefail; . "$1/lib.sh"; . "$1/lib/secure-dns.sh"; c=$(dns_current); [ -z "$c" ] && echo on' _ "$HERE"
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
export WREN_ETC=$T/etc
mkdir -p "$T/etc/unbound/unbound.conf.d"
if secure_dns_on; then off=false; else off=true; fi
check "with no settings it is off" $off
check "status.sh says DNS is unencrypted" grep -q "DNS: unencrypted" <<<"$(dns_status)"
dns_unbound_conf digiges >"$T/etc/unbound/unbound.conf.d/wren-secure-dns.conf"
check "with its settings but switched off: still off (on means switched on)" bash -c '! secure_dns_on'
check "...status.sh says it is switched off" grep -q "secure DNS is switched off" <<<"$(dns_status)"
printf '%s\n' '# Written by Wren Linux parts/secure-dns.sh. Every name goes to Unbound on this' 'nameserver 127.0.0.1' >"$T/etc/resolv.conf"
check "switched on (resolv.conf says so in its first line): on" secure_dns_on
check "the resolver in use is read back" test "$(dns_current)" = digiges
check "status.sh names it" grep -q "DNS: encrypted to dns.digitale-gesellschaft.ch" <<<"$(dns_status)"
printf '%s\n' '# Written by Wren Linux extras/secure-dns.sh. Every name goes to Unbound on this' 'nameserver 127.0.0.1' >"$T/etc/resolv.conf"
check "...an older Wren Linux's mark (extras/) counts as on too" secure_dns_on

# ---- wifi.sh leaves resolv.conf alone while it is on ----
# set_dns from wifi.sh, writing into the pretend /etc; resolvconf only writes down that it ran
printf '%s\n' '# Written by Wren Linux parts/secure-dns.sh. Every name goes to Unbound on this' 'nameserver 127.0.0.1' >"$T/etc/resolv.conf"
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
    grep -qF "! grep -qE '^# Written by Wren Linux (parts|extras)/secure-dns\.sh' /etc/resolv.conf" "$HERE/wifi.sh"
echo "nameserver 192.168.1.1" >"$T/etc/resolv.conf.wren.bak"
remove_wifi_config >/dev/null 2>&1
check "wifi.sh --remove doesn't put its old copy back over it" grep -qx "nameserver 127.0.0.1" "$T/etc/resolv.conf"
echo "nameserver 10.0.0.1" >"$T/etc/resolv.conf"
remove_wifi_config >/dev/null 2>&1
check "...but does once secure DNS is switched off" grep -qx "nameserver 192.168.1.1" "$T/etc/resolv.conf"
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
    bash -c 'grep -qx "delete table inet wren_secure_dns" "$1" && grep -qx "table inet wren_secure_dns {" "$1"' _ "$FW"
# nft reads user names as it loads, so "unbound" becomes root for the check here
if command -v nft >/dev/null && unshare -rn true 2>/dev/null; then
    sed 's/skuid "unbound"/skuid "root"/' "$FW" >"$T/fw.nft"
    check "nft accepts the rule" unshare -rn nft -c -f "$T/fw.nft"
else
    echo "  skip  nft isn't installed (or no user namespaces), so its syntax isn't checked"
fi

# ---- the switch: on, off, and on where names don't resolve ----
W=$T/sw
mkdir -p "$W/etc/unbound/unbound.conf.d" "$W/etc/NetworkManager/conf.d" "$W/bin" "$W/usr/local/bin"
sed -e "s|/etc/|$W/etc/|g" -e "s|/usr/local/bin/ublock-allow|$W/usr/local/bin/ublock-allow|g" \
    -e "s|^export PATH=.*|export PATH=$W/bin:\$PATH|" "$HERE/bin/secure-dns-switch" >"$W/switch"
grep -q "$W/etc/resolv.conf" "$W/switch" || { echo "  FAIL  the switch's /etc paths weren't found"; exit 1; }
# root, a running NetworkManager, systemctl/nmcli/nft writing down what they did,
# names resolving unless $W/no-dns exists, no waiting
printf '#!/bin/sh\n[ "$1" = -u ] && echo 0 || exec /usr/bin/id "$@"\n' >"$W/bin/id"
printf '#!/bin/sh\necho "systemctl $*" >>"%s/calls"\n[ "$1" != is-active ] || [ "$3" = NetworkManager ] || [ "$3" = unbound ]\n' "$W" >"$W/bin/systemctl"
printf '#!/bin/sh\necho "nmcli $*" >>"%s/calls"\n' "$W" >"$W/bin/nmcli"
printf '#!/bin/sh\necho "nft $*" >>"%s/calls"\n' "$W" >"$W/bin/nft"
printf '#!/bin/sh\n[ ! -e "%s/no-dns" ]\n' "$W" >"$W/bin/getent"
printf '#!/bin/sh\n' >"$W/bin/sleep"
printf '#!/bin/sh\necho "ublock-allow $*" >>"%s/calls"\n' "$W" >"$W/usr/local/bin/ublock-allow"
chmod +x "$W/bin/"* "$W/usr/local/bin/ublock-allow"
chmod +x "$W/switch"
sw() { bash "$W/switch" "$@"; }
export W
export -f sw
: >"$W/etc/unbound/unbound.conf.d/wren-secure-dns.conf"
echo "nameserver 192.168.1.1" >"$W/etc/resolv.conf"
: >"$W/calls"

check "switch: off to start with" test "$(sw status)" = off
sw on >/dev/null 2>&1
check "on: resolv.conf points at Unbound, and says so" bash -c '
    head -1 "$1" | grep -q "^# Written by Wren Linux parts/secure-dns.sh" && grep -qx "nameserver 127.0.0.1" "$1"' _ "$W/etc/resolv.conf"
check "...the network's copy kept, to put back" grep -qx "nameserver 192.168.1.1" "$W/etc/resolv.conf.wren-secure-dns.bak"
check "...NetworkManager told to leave resolv.conf alone" grep -qx "dns=none" "$W/etc/NetworkManager/conf.d/90-wren-secure-dns.conf"
check "...its firewall rule enabled and loaded" bash -c '
    grep -qx "systemctl enable wren-secure-dns-firewall.service" "$1" && grep -qx "systemctl restart wren-secure-dns-firewall.service" "$1"' _ "$W/calls"
check "...status: on" test "$(sw status)" = on
: >"$W/calls"
sw off >/dev/null 2>&1
check "off: the network's DNS server back" grep -qx "nameserver 192.168.1.1" "$W/etc/resolv.conf"
check "...and NetworkManager writes it again now: the copy is from where it was switched on, maybe another network" \
    grep -qx "nmcli general reload dns-full" "$W/calls"
check "...NetworkManager may write it again" test ! -e "$W/etc/NetworkManager/conf.d/90-wren-secure-dns.conf"
check "...the firewall rule off, also at boot" grep -qx "systemctl disable --now wren-secure-dns-firewall.service" "$W/calls"
: >"$W/no-dns"; : >"$W/calls"
check "on where names don't resolve (a sign-in page): it says so, and fails" bash -c '! sw on'
check "...and stays off: the network's DNS server, no firewall rule" bash -c '
    grep -qx "nameserver 192.168.1.1" "$1" && [ "$(sw status)" = off ] && ! grep -q "systemctl enable" "$2"' _ "$W/etc/resolv.conf" "$W/calls"
rm -f "$W/no-dns"
rm "$W/etc/unbound/unbound.conf.d/wren-secure-dns.conf"
check "on without Unbound's settings: refused" bash -c '! sw on'
check "anything but on, off or status: refused" bash -c '! sw "on; id" && ! sw && ! sw on off'
check "not as root: refused" bash -c '! bash "$1" status' _ "$HERE/bin/secure-dns-switch"

# ---- the secure-dns command and the sudo rule ----
mkdir -p "$W/fake"
printf '#!/bin/sh\necho "sudo $*" >>"%s/calls"\n' "$W" >"$W/fake/sudo"
chmod +x "$W/fake/sudo"
sed "s|/usr/local/libexec/wren-secure-dns|$W/switch|" "$HERE/bin/secure-dns" >"$W/secure-dns"
sdc() { WREN_RESOLV_CONF=$W/etc/resolv.conf PATH="$W/fake:$PATH" bash "$W/secure-dns" "$@"; }
export -f sdc
: >"$W/calls"
sdc toggle
check "secure-dns toggle while off: the switch's on, through sudo without a password" grep -qx "sudo -n $W/switch on" "$W/calls"
check "secure-dns status needs no sudo" bash -c '[ "$(sdc status)" = off ] && [ "$(grep -c . "$1")" = 1 ]' _ "$W/calls"
check "the sudo rule allows exactly on and off" grep -qF 'NOPASSWD: %s on, %s off\n' "$HERE/parts/secure-dns.sh"
check "...checked by visudo before it is installed" grep -q 'sudo visudo -cf "$rule"' "$HERE/parts/secure-dns.sh"
check "...or, if you chose so, on alone without a password (off then asks for it)" bash -c '
    grep -qF "NOPASSWD: %s on\\n" "$1" && grep -q "Switching secure DNS off: ask for your password?" "$1"' _ "$HERE/parts/secure-dns.sh"
# The question's default: yes the first time; your earlier no stays your default
sd_default() { # STRICT-FILE-THERE? RULE-THERE? -> the default given
    bash -c 'STRICT=$1/strict SUDOERS=$1/rule
        rm -f "$STRICT" "$SUDOERS"; [ "$2" = y ] && : >"$STRICT"; [ "$3" = y ] && : >"$SUDOERS"
        sudo() { "$@"; }
        eval "$(sed -n "/^strict_default=y$/,/^if \[ ! -e \"\$STRICT\" \]/p" "$4")"; echo "$strict_default"' _ "$T" "$1" "$2" "$HERE/parts/secure-dns.sh"
}
check "asking for a password to switch it off: yes by default the first time" test "$(sd_default n n)" = y
check "...yes again after a yes" test "$(sd_default y y)" = y
check "...no after your no (a run again keeps your answer)" test "$(sd_default n y)" = n
# off when only on is allowed without a password: it asks, in a terminal; never
# without one. This sudo does as the real one does for someone in the sudo group:
# -l lists the command (it may run, with a password), -n refuses to run it
cat >"$W/fake/sudo" <<FAKE
#!/bin/sh
echo "sudo \$*" >>"$W/calls"
case "\$*" in
    "-n -l "*) exit 0 ;;
    "-n $W/switch off") echo "sudo: a password is required" >&2; exit 1 ;;
esac
FAKE
: >"$W/calls"
out=$(sdc off </dev/null 2>&1) && rc=0 || rc=$?
check "strict: off with no terminal to ask on: refused, it says why, nothing switched" bash -c '
    [ "$1" != 0 ] && grep -q "asks for your password" <<<"$2" && ! grep -qx "sudo $3 off" "$4"' _ "$rc" "$out" "$W/switch" "$W/calls"
: >"$W/calls"
script -qec "bash -c 'WREN_RESOLV_CONF=$W/etc/resolv.conf PATH=$W/fake:\$PATH bash $W/secure-dns off'" "$W/typescript" >/dev/null 2>&1
check "...in a terminal: off through sudo, asking for the password" grep -qx "sudo $W/switch off" "$W/calls"
check "...and sudo's refusal isn't what you see" bash -c '! grep -q "a password is required" "$1"' _ "$W/typescript"
# what goes wrong in the switch itself is shown, and doesn't ask for a password
cat >"$W/fake/sudo" <<FAKE
#!/bin/sh
echo "sudo \$*" >>"$W/calls"
echo "secure-dns: Unbound didn't start" >&2
exit 1
FAKE
: >"$W/calls"
out=$(sdc on </dev/null 2>&1) && rc=0 || rc=$?
check "the switch fails: its own message, and its status, no password asked" bash -c '
    [ "$1" = 1 ] && grep -q "Unbound didn.t start" <<<"$2" && [ "$(grep -c . "$3")" = 1 ]' _ "$rc" "$out" "$W/calls"
printf '#!/bin/sh\necho "sudo $*" >>"%s/calls"\n' "$W" >"$W/fake/sudo"
# the bar: "dns OFF" while it is set up and off, nothing while on or not set up
: >"$W/switch-exe" && chmod +x "$W/switch-exe"
bar() { WREN_RESOLV_CONF=$1 WREN_SECDNS_SWITCH=$2 sh "$HERE/bin/sway-status" --dns; }
echo "nameserver 192.168.1.1" >"$W/off.conf"
printf '# Written by Wren Linux parts/secure-dns.sh\nnameserver 127.0.0.1\n' >"$W/on.conf"
check "the bar: \"dns OFF\" while secure DNS is set up but off" test "$(bar "$W/off.conf" "$W/switch-exe")" = "dns OFF"
check "...nothing while it is on, or isn't set up" bash -c '[ -z "$(bar "$1" "$2")" ] && [ -z "$(bar "$3" "$4/none")" ]' _ "$W/on.conf" "$W/switch-exe" "$W/off.conf" "$W"
check "...a notification when it goes off, and a click on it switches it on" bash -c '
    grep -q "notify-send -a wren -u critical \"Secure DNS is off\"" "$1" && grep -q "secure-dns\" on" "$1"' _ "$HERE/bin/sway-status"
check "secure DNS is part of the base, after NetworkManager" bash -c '
    . "$1/packages.sh"; [[ " ${PARTS[*]} " == *" network-manager secure-dns "* ]]' _ "$HERE"
check "a re-run keeps the switch where it was (on only at first, or if it was on)" grep -qF 'if $first || [ "$("$BIN/secure-dns" status)" = on ]; then' "$HERE/parts/secure-dns.sh"

# ---- login-check: a word at login if the Wi-Fi sign-in window left it off
mkdir -p "$W/state/wren" "$W/nfake"
printf '#!/bin/sh\necho "notify $*" >>"%s/notified"\n' "$W" >"$W/nfake/notify-send"
printf '#!/bin/sh\necho "sudo $*" >>"%s/sudo-calls"\n[ -e "%s/switch-works" ]\n' "$W" "$W" >"$W/nfake/sudo"
chmod +x "$W/nfake/notify-send" "$W/nfake/sudo"
lc() { WREN_SECDNS_RETRY=0 XDG_STATE_HOME=$W/state WREN_RESOLV_CONF=$W/etc/resolv.conf PATH="$W/nfake:$PATH" bash "$HERE/bin/secure-dns" login-check 2>&1; }
echo "nameserver 192.168.1.1" >"$W/etc/resolv.conf"
rm -f "$W/notified"
check "login-check: off, but not left off by the sign-in window (you chose it): nothing said, and it stays off" bash -c '[ -z "$(WAYLAND_DISPLAY=wayland-1 lc)" ] && [ ! -e "$1" ] && [ ! -e "$2" ]' _ "$W/notified" "$W/sudo-calls"
export -f lc; export HERE
: >"$W/state/wren/secure-dns-left-off"
WAYLAND_DISPLAY=wayland-1 lc >/dev/null
check "...left off by it, and it can't come back, in sway: a notification" grep -q "notify .*Secure DNS is off" "$W/notified"
check "...after a few tries, for a network still coming up" test "$(grep -c ' on$' "$W/sudo-calls")" = 3
check "...never asking a password, at login" bash -c '! grep -qv "^sudo -n " "$1"' _ "$W/sudo-calls"
rm -f "$W/notified"; touch "$W/switch-works"
WAYLAND_DISPLAY=wayland-1 lc >/dev/null
check "a power cut in the sign-in: on again by itself, without a word" bash -c '[ ! -e "$1" ] && [ ! -e "$2" ]' _ "$W/notified" "$W/state/wren/secure-dns-left-off"
rm "$W/switch-works"; : >"$W/state/wren/secure-dns-left-off"
check "...on a text console: a line in the terminal" bash -c 'out=$(WAYLAND_DISPLAY= lc); [[ $out == *"secure-dns on"* ]]'
printf '%s\n' '# Written by Wren Linux parts/secure-dns.sh. Every name goes to Unbound on this' 'nameserver 127.0.0.1' >"$W/etc/resolv.conf"
check "...on again by then: nothing said, and the mark goes" bash -c '[ -z "$(WAYLAND_DISPLAY= lc)" ] && [ ! -e "$1" ]' _ "$W/state/wren/secure-dns-left-off"
check "secure-dns on removes the mark once it worked" grep -qF 'if [ "$cmd" = on ] && [ "$rc" = 0 ]; then rm -f "$LEFT_OFF"; fi' "$HERE/bin/secure-dns"
check "the part runs login-check at sway's start, and from ~/.bashrc outside sway" bash -c '
    grep -qx "exec ~/.local/bin/secure-dns login-check" "$1" && grep -qF "[ -n \"\${WAYLAND_DISPLAY:-}\" ] || [ ! -x ~/.local/bin/secure-dns ] || ~/.local/bin/secure-dns login-check" "$1" &&
    grep -q "remove_snippet secure-dns" "$1"' _ "$HERE/parts/secure-dns.sh"

[ "$fails" -eq 0 ]
