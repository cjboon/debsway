#!/bin/bash
# Checks that every sandbox stays off this computer and your network, or doesn't
# run: bin/sandbox-net-check (for real, with nft in a network namespace, against
# each sandbox's own rule), its --watch (a copy that writes down instead of
# ending anything), the rules (this computer refused so the check can see it, and
# no answers out but from a VM's own forwarded ports), each session script
# (checked before it starts, watched while it runs), each installer, and
# status.sh's line on the loaded firewalls (pretend sudo, nft and systemd).
# Nothing outside temp folders changes. Run by test.sh, or:  bash tools/test-sandbox-net.sh
# shellcheck disable=SC2016  # the inner shells and pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"; kill $(jobs -p) 2>/dev/null' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
NC=$HERE/bin/sandbox-net-check
# The sandboxes this covers: rule, session script, installer, firewall service
SANDBOXES="firefox:firefox-session:extras/firefox-sandbox.sh:wren-firefox-firewall
incognito:incognito-session:parts/incognito.sh:wren-incognito-firewall
wifi-signin:incognito-session:parts/incognito.sh:wren-incognito-firewall
yt-dlp:yt-dlp-session:extras/yt-dlp.sh:wren-ytdlp-firewall
claude:claude-session:extras/claude-code.sh:wren-claude-firewall
claude-vm:claude-vm-session:extras/claude-vm.sh:wren-claude-vm-firewall
opencode-vm:opencode-vm-session:extras/opencode-vm.sh:wren-opencode-vm-firewall
onion-site:onion-site-session:extras/onion-site.sh:wren-onion-site-firewall"

# ---- the rules
while IFS=: read -r rule _ _ _; do
    f=$HERE/data/$rule-firewall.nft
    check "$rule: this computer refused with admin-prohibited (how the check sees the rule)" \
        grep -qx '        oifname "lo" reject with icmpx admin-prohibited' "$f"
    check "...and no answers out to just anyone (it can't stand in for Tor's port, or another service here)" \
        not grep -qE '^[^#]*(established|related)' "$f"
done <<<"$SANDBOXES"
check "the VMs answer only from their own forwarded ports" bash -c '
    grep -qx "        meta skuid \"claude-vm\" ip saddr 127.0.0.1 tcp sport 2242 accept" "$1/claude-vm-firewall.nft" &&
    grep -qx "        ip saddr 127.0.0.1 tcp sport 2244 accept" "$1/opencode-vm-firewall.nft" &&
    grep -qx "        ip saddr 127.0.0.1 tcp sport { 2243, 18080 } accept" "$1/onion-site-firewall.nft" &&
    [ "$(grep -h "^[^#]*sport" "$1"/{claude,firefox,incognito,wifi-signin,yt-dlp}-firewall.nft | wc -l)" = 0 ]' _ "$HERE/data"

# ---- the check, for real: each rule in a network namespace of its own, where
# root stands in for the sandbox's user
NS_PATH=/usr/sbin:/sbin:/usr/bin:/bin
if PATH=$NS_PATH command -v nft >/dev/null && unshare -rn true 2>/dev/null; then
    cat >"$T/in-ns.sh" <<'EOF'
ip link set lo up && ip link add d0 type dummy && ip link set d0 up &&
ip addr add 192.168.5.2/24 dev d0 && ip route add default dev d0 || exit 9
[ "$FW" = none ] || nft -f "$FW" || exit 8
"$@"
EOF
    ns() { local f=$1; shift; FW=$f PATH=$NS_PATH unshare -rn bash "$T/in-ns.sh" "$@"; }
    while IFS=: read -r rule _ _ _; do
        sed -E 's/meta (skuid|skgid) "[a-z-]+"/meta \1 0/g' "$HERE/data/$rule-firewall.nft" >"$T/$rule.nft"
        check "$rule: with its rule, the check passes" ns "$T/$rule.nft" bash "$NC"
    done <<<"$SANDBOXES"
    check "...and with no rule (flushed), it fails" not ns none bash "$NC"
    # The replies: a VM's QEMU may answer its own console's login, and nothing else
    cat >"$T/answer.py" <<'EOF'
import socket, sys
srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(("127.0.0.1", int(sys.argv[1]))); srv.listen()
c = socket.socket(); c.settimeout(1)
# (the connecting side is the same user here: let its own packets to the port out)
print("answered" if c.connect_ex(("127.0.0.1", int(sys.argv[1]))) == 0 else "no answer")
EOF
    sed 's/^\( *\)ip saddr 127.0.0.1 tcp sport 2244 accept$/&\n\1ip daddr 127.0.0.1 tcp dport 9050 accept/' "$T/opencode-vm.nft" >"$T/oc-9050.nft"
    check "opencode-vm's QEMU answers on its console port (2244)" test "$(ns "$T/opencode-vm.nft" python3 -I "$T/answer.py" 2244)" = answered
    check "...but a listener of that user on Tor's port gets no answer out" test "$(ns "$T/oc-9050.nft" python3 -I "$T/answer.py" 9050)" = "no answer"
else
    echo "  ok    skipped the checks in a network namespace: no nft or no user namespaces here"
fi

# ---- --watch, on a copy that writes down what it would end, and checks often
sed -e 's|exec pkill -KILL -u "$(id -u)"|echo "ended $(id -u)" >>"$WATCH_LOG"; exit 0|' \
    -e 's|/bin/sleep "${WREN_NET_WATCH_EVERY:-5}"|/bin/sleep 0.1|' -e 's|logger |: |' "$NC" >"$T/watch"
grep -q 'WATCH_LOG' "$T/watch" || { echo "  FAIL  the watch's end line wasn't found"; exit 1; }
sed 's|^check() {|check() { [ -e "$WATCH_DOWN" ] \&\& return 1; return 0; }\ncheck_real() {|' "$T/watch" >"$T/watch2"
/bin/sleep 5 &
p=$!
WATCH_LOG=$T/log WATCH_DOWN=$T/down timeout 3 bash "$T/watch2" --watch "$p" &
w=$!
/bin/sleep 0.5
check "--watch: while the rule holds, nothing is ended" test ! -e "$T/log"
: >"$T/down"
wait "$w"
check "...the moment it is gone, every process of the user is ended" grep -qx "ended $(id -u)" "$T/log"
kill "$p" 2>/dev/null
rm -f "$T/log" "$T/down"
(/bin/sleep 0.3) &
p=$!
WATCH_LOG=$T/log WATCH_DOWN=$T/down timeout 3 bash "$T/watch2" --watch "$p"
check "...and when the program ends by itself, so does the watch (ending nothing)" bash -c '[ $? -ne 124 ] && [ ! -e "$1" ]' _ "$T/log"
check "...a pid that isn't a number is refused" not bash "$NC" --watch 'x; id'

# ---- each session script: the check before it starts, the watch while it runs
while IFS=: read -r rule session installer unit; do
    s=$HERE/bin/$session
    check "$session ($rule): checked before it starts, with how to put the rule back" bash -c '
        grep -q "wren-sandbox-net-check" "$1" && grep -q "sudo systemctl restart $2" "$1"' _ "$s" "$unit"
    check "...and watched while it runs" grep -qE -- '--watch ("\$pid"|\$\$)' "$s"
    check "$installer: installs the check, takes it out with the last sandbox, and its update notices" bash -c '
        grep -qx "[[:space:]]*install_net_check" "$1" && grep -qx "[[:space:]]*remove_net_check" "$1" &&
        grep -q "^# files:.*bin/sandbox-net-check" "$1"' _ "$HERE/$installer"
done <<<"$SANDBOXES"
check "firefox-session: the check runs at start, before anything" grep -qx 'start) need_net ;;' "$HERE/bin/firefox-session"
check "the VMs: any start (the install too) goes through the check" bash -c '
    for s in claude-vm onion-site opencode-vm; do
        f=$1/bin/$s-session
        sed -n "/^mockvps() {/,/^}/p" "$f" | grep -q "then net_ok" || exit 1
    done
    # (the site starts QEMU itself in two places)
    [ "$(grep -c "^ *net_ok$" "$1/bin/onion-site-session")" = 2 ]' _ "$HERE"
check "the shared check goes only when no sandbox session is left" bash -c '
    f=$(sed -n "/^remove_net_check() {/,/^}/p" "$1/lib/core.sh")
    for s in incognito claude claude-vm opencode-vm firefox onion-site yt-dlp; do grep -q " $s-session" <<<"$f" || exit 1; done' _ "$HERE"

# ---- status.sh: which sandbox firewalls are loaded (pretend systemd, sudo and nft)
R=$T/r
mkdir -p "$R" "$T/home" "$T/etc/systemd/system" "$T/bin" "$T/etc/wren"
for f in "$HERE"/*; do [ "${f##*/}" = lib.sh ] || ln -s "$f" "$R/${f##*/}"; done
sed 's|^export PATH=.*|export PATH="$STATUS_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
for n in firefox incognito; do
    printf '[Service]\nExecStart=/usr/sbin/nft -f %s\n' "$T/etc/wren/$n.nft" >"$T/etc/systemd/system/wren-$n-firewall.service"
    printf 'table inet wren_%s\ndelete table inet wren_%s\n\ntable inet wren_%s {\n}\n' "$n" "$n" "$n" >"$T/etc/wren/$n.nft"
done
# (the incognito service loads the sign-in window's rule too)
printf 'ExecStart=/usr/sbin/nft -f %s\n' "$T/etc/wren/wifi-signin.nft" >>"$T/etc/systemd/system/wren-incognito-firewall.service"
printf 'table inet wren_wifi_signin {\n}\n' >"$T/etc/wren/wifi-signin.nft"
printf '#!/bin/sh\ncase "$*" in *is-enabled*nftables*) [ -e "%s/nftables-on" ] ;; *is-enabled*) exit 0 ;; *) exit 1 ;; esac\n' "$T" >"$T/bin/systemctl"
printf '#!/bin/sh\n[ "$1" = -n ] && [ -e "%s/sudo-locked" ] && exit 1\n[ "$1" = -n ] && shift\nexec "$@"\n' "$T" >"$T/bin/sudo"
printf '#!/bin/sh\ncat "%s/tables"\n' "$T" >"$T/bin/nft"
chmod +x "$T/bin/"*
glance() { HOME=$T/home WREN_ETC=$T/etc STATUS_TEST_PATH="$T/bin:$PATH" bash "$R/status.sh" 2>/dev/null | sed -n '/^Security at a glance:/,/^$/p'; }
printf 'table inet wren_firefox\ntable inet wren_incognito\ntable inet wren_wifi_signin\n' >"$T/tables"
out=$(glance)
check "status.sh: all loaded, it says so (three tables, from two services)" grep -qF "[x] The sandboxes' firewalls are loaded (3)" <<<"$out"
check "...and says nothing of Debian's nftables service while it is off" not grep -q 'nftables service' <<<"$out"
printf 'table inet wren_firefox\ntable inet wren_incognito\n' >"$T/tables"
out=$(glance)
check "...one table gone: it names the service to restart" grep -qF "[ ] Sandbox firewall NOT loaded, so that sandbox won't start: sudo systemctl restart wren-incognito-firewall.service" <<<"$out"
: >"$T/sudo-locked"
out=$(glance)
check "...without sudo unlocked, it says so instead of asking for a password" grep -qF "weren't checked (that needs sudo)" <<<"$out"
rm -f "$T/sudo-locked"
: >"$T/nftables-on"
check "...Debian's nftables service on: it warns" grep -qF "Debian's nftables service is on" <<<"$(glance)"

[ "$fails" -eq 0 ]
