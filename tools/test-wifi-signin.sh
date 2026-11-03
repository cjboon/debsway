#!/bin/bash
# Checks Firefox's own DNS, set at every start (doh_prefs in bin/firefox-session
# and bin/incognito-session): the system's while secure DNS is on, its own
# encrypted DNS to Quad9 while it is off (strict, or fallback as chosen), and
# the network's own in the Wi-Fi sign-in window only. And bin/wifi-signin:
# secure DNS off while the window is open, on again after (with a pretend
# incognito and secure-dns). On a temp /etc; nothing of this computer is used.
# Run by test.sh, or:  bash tools/test-wifi-signin.sh
# shellcheck disable=SC2016  # the inner shells and pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}

fn() { sed -n '/^doh_prefs() {/,/^}/p' "$1"; }
check "the same DNS function in firefox-session and incognito-session" \
    bash -c '[ -n "$1" ] && [ "$1" = "$2" ]' _ "$(fn "$HERE/bin/firefox-session")" "$(fn "$HERE/bin/incognito-session")"
mkdir -p "$T/etc/wren"
fn "$HERE/bin/firefox-session" | sed "s|/etc/|$T/etc/|g" >"$T/fn"
prefs() { bash -c '. "$1"; doh_prefs "$2"' _ "$T/fn" "$1"; }
mode() { prefs "$1" | sed -n 's/^user_pref("network.trr.mode", \([0-9]\));$/\1/p'; }
on() { printf '%s\n' '# Written by Wren Linux parts/secure-dns.sh. Every name goes to Unbound on this' 'nameserver 127.0.0.1' >"$T/etc/resolv.conf"; }
off() { echo "nameserver 192.168.1.1" >"$T/etc/resolv.conf"; }

on
check "secure DNS on: Firefox uses the system's DNS (mode 5)" test "$(mode normal)" = 5
off
check "secure DNS off: its own encrypted DNS, strict (mode 3, never plain DNS)" test "$(mode normal)" = 3
check "...to Quad9" bash -c 'grep -qx "user_pref(\"network.trr.uri\", \"https://dns.quad9.net/dns-query\");" <<<"$1"' _ "$(prefs normal)"
echo dns=fallback >"$T/etc/wren/firefox.conf"
check "...with fallback when that was chosen (mode 2)" test "$(mode normal)" = 2
rm "$T/etc/wren/firefox.conf"
check "the Wi-Fi sign-in window: the network's own DNS (mode 5), whatever else" test "$(mode signin)" = 5
check "firefox-session sets it at every start, never the sign-in kind" bash -c '
    grep -qx "doh_prefs normal >>\"\$profile/user.js\"" "$1" && ! grep -q "doh_prefs signin" "$1"' _ "$HERE/bin/firefox-session"
check "incognito-session sets the kind it was given, checked: normal or signin only" bash -c '
    grep -qx "doh_prefs \"\$kind\" >>\"\$base/profile/user.js\"" "$1" &&
    grep -qx "\[\[ \$kind == normal || \$kind == signin \]\] || die \"unexpected window kind.\"" "$1"' _ "$HERE/bin/incognito-session"
check "...and HTTPS-Only off in the sign-in window only (sign-in pages are plain http)" bash -c '
    s=$(sed -n "/^if \[ \"\$kind\" = signin \]; then/,/^fi/p" "$1"); [[ $s == *"https_only_mode\", false"* ]]' _ "$HERE/bin/incognito-session"
check "incognito --signin passes signin, anything else normal" bash -c '
    grep -q "if \[ \"\${1:-}\" = --signin \]; then kind=signin; shift; fi" "$1" &&
    grep -q "\"\$theme\" \"\$kind\" \"\$@\"" "$1"' _ "$HERE/bin/incognito"

# ---- wifi-signin: off while the window is open, on again after
mkdir -p "$T/home/.local/bin" "$T/usr"
printf '#!/bin/sh\necho "secure-dns $*" >>"%s/calls"\ncase "$1" in status) cat "%s/state" ;; on) [ ! -e "%s/no-dns" ] && echo on >"%s/state" ;; off) echo off >"%s/state" ;; esac\n' \
    "$T" "$T" "$T" "$T" "$T" >"$T/home/.local/bin/secure-dns"
printf '#!/bin/sh\necho "incognito $* (secure DNS $(cat %s/state))" >>"%s/calls"\n' "$T" "$T" >"$T/usr/incognito"
chmod +x "$T/home/.local/bin/secure-dns" "$T/usr/incognito"
sed "s|/usr/local/bin/incognito|$T/usr/incognito|" "$HERE/bin/wifi-signin" >"$T/wifi-signin"
# (a pretend notify-send: nothing reaches this computer's desktop)
mkdir -p "$T/fake"
printf '#!/bin/sh\necho "notify $*" >>"%s/said"\n' "$T" >"$T/fake/notify-send"
chmod +x "$T/fake/notify-send"
ws() { : >"$T/said"; HOME=$T/home XDG_STATE_HOME=$T/xstate PATH=$T/fake:/usr/bin:/bin bash "$T/wifi-signin" 2>>"$T/said"; }
echo on >"$T/state"; : >"$T/calls"
ws
check "...the mark for the next login is left while it is off" test -e "$T/xstate/wren/secure-dns-left-off"
check "secure DNS on: off while the sign-in window is open" grep -qx "incognito --no-audio --signin http://detectportal.firefox.com/canonical.html (secure DNS off)" "$T/calls"
check "...on again when it closes" bash -c '[ "$(tail -1 "$1")" = "secure-dns on" ] && [ "$(cat "$2")" = on ]' _ "$T/calls" "$T/state"
echo off >"$T/state"; : >"$T/calls"
ws
check "secure DNS off to start with: left off (it isn't switched on behind your back)" bash -c '
    ! grep -qE "secure-dns (on|off)" "$1" && grep -q "incognito --no-audio --signin" "$1"' _ "$T/calls"
echo on >"$T/state"; : >"$T/calls"; : >"$T/no-dns"
ws
check "it can't switch on again (not signed in yet): it says how to, later" grep -q "secure-dns on" "$T/said"
rm -f "$T/no-dns"
check "the menu's Wi-Fi sign-in line runs it" grep -q '/usr/local/bin/wifi-signin}' "$HERE/bin/wren-menu"
check "parts/incognito.sh installs it, root-owned, next to incognito (and removes it)" bash -c '
    grep -q "install -o root -g root -m 0755 \"\$WREN_DIR/bin/wifi-signin\" /usr/local/bin/wifi-signin" "$1" &&
    grep -q "sudo rm -f .*/usr/local/bin/wifi-signin" "$1"' _ "$HERE/parts/incognito.sh"

# ---- the sign-in window's own user: the local network, not this computer
# The user bin/incognito picks for each kind of window (incognito when it
# doesn't choose: that is who every window ran as before)
user_for() { bash -c 'kind=$1 audio=true; eval "$(sed -n "/^user=incognito$/,/^if \[ \"\$kind\" = signin \]/p" "$2")"; echo "${user:-incognito}"' _ "$1" "$HERE/bin/incognito"; }
check "a normal window runs as incognito" test "$(user_for normal)" = incognito
check "the sign-in window runs as wifi-signin, without sound" bash -c '
    [ "$1" = wifi-signin ] && grep -qx "if \[ \"\$kind\" = signin \]; then user=wifi-signin audio=false; fi" "$2"' _ "$(user_for signin)" "$HERE/bin/incognito"
check "...each with its own lock, so the two can be open together" \
    bash -c 'grep -qx "exec 9>\"\$rt/\$user.lock\"" "$1" && grep -qx "sock=\$rt/\$user-wayland" "$1" && ! grep -q "u:incognito:--x" "$1"' _ "$HERE/bin/incognito"
# incognito-session: each user runs only its own kind
line=$(sed -n '/^{ \[ "\$me" = incognito \]/,/die "the user/p' "$HERE/bin/incognito-session")
runs() { bash -c 'die() { exit 1; }; me=$1 kind=$2; eval "$3"' _ "$1" "$2" "$line"; }
check "incognito-session: incognito runs the normal window, wifi-signin the sign-in one" bash -c '[ -n "$1" ]' _ "$line"
check "...incognito normal, wifi-signin signin: yes" bash -c "$(declare -f runs); line=\$1; runs incognito normal && runs wifi-signin signin" _ "$line"
check "...incognito signin, wifi-signin normal: no" bash -c "$(declare -f runs); line=\$1; ! runs incognito signin && ! runs wifi-signin normal" _ "$line"
check "...and any other user: no" grep -qx '\[ "\$me" = incognito \] || \[ "\$me" = wifi-signin \] || die .*' "$HERE/bin/incognito-session"
P=$HERE/parts/incognito.sh
check "parts/incognito.sh makes the wifi-signin user like incognito, and --remove deletes it" bash -c '
    grep -qx "sandbox_user \"\$SIGNIN\" \"Wren Linux Wi-Fi sign-in window\"" "$1" && grep -q "for u in \"\$NAME\" \"\$SIGNIN\"; do" "$1"' _ "$P"
check "...your user may run the wrapper as either, and nothing else" grep -q 'ALL=(%s, %s) NOPASSWD: %s' "$P"
check "...its firewall rule is loaded at boot with incognito's, and taken out by --remove" bash -c '
    grep -q "\"ExecStart=/usr/sbin/nft -f \$SIGNIN_FIREWALL\"" "$1" && grep -q "nft delete table inet wren_wifi_signin" "$1" &&
    grep -q "\"\$WREN_DIR/data/wifi-signin-firewall.nft\" \"\$SIGNIN_FIREWALL\"" "$1"' _ "$P"

# The rules themselves, in a network namespace of their own (nothing on this
# computer is touched): a dummy network 192.168.5.0/24 and 10.9.0.0/16, with
# this "computer" at 192.168.5.2. A counter on each reject says whether the
# rule turned a connection away.
fw_for() { grep -lF "meta skuid \"$1\" jump" "$HERE"/data/*-firewall.nft | head -1; }
NS_PATH=/usr/sbin:/sbin:/usr/bin:/bin
if PATH=$NS_PATH command -v nft >/dev/null && unshare -rn true 2>/dev/null; then
    # reach RULE-FILE USER HOST PORT: refused (by the rule), or out
    reach() {
        [ -f "$1" ] || { echo "no rule for $2"; return; }
        sed -e "s/meta skuid \"$2\"/meta skuid 0/" -e 's/ reject$/ counter reject/' "$1" >"$T/fw.nft"
        PATH=$NS_PATH unshare -rn bash -c '
            ip link set lo up && ip link add d0 type dummy && ip link set d0 up &&
            ip addr add 192.168.5.2/24 dev d0 && ip route add 10.9.0.0/16 dev d0 || exit 9
            nft -f "$1" || exit 8
            timeout 0.2 bash -c "exec 3<>/dev/tcp/$2/$3" 2>/dev/null
            if nft list ruleset | grep -qE "counter packets [1-9]"; then echo refused; else echo out; fi' _ "$T/fw.nft" "$3" "$4"
    }
    SIGNIN_USER=$(user_for signin)
    SIGNIN_FW=$(fw_for "$SIGNIN_USER")
    INCOG_FW=$(fw_for incognito)
    check "nft accepts the sign-in window's rule" bash -c 'sed "s/skuid \"wifi-signin\"/skuid 0/" "$1" >"$2/c.nft" && PATH=$3 unshare -rn nft -c -f "$2/c.nft"' _ "$HERE/data/wifi-signin-firewall.nft" "$T" "$NS_PATH"
    check "the sign-in window reaches a sign-in page on the local network (192.168.5.1)" test "$(reach "$SIGNIN_FW" "$SIGNIN_USER" 192.168.5.1 80)" = out
    check "...and one at 10.9.0.1" test "$(reach "$SIGNIN_FW" "$SIGNIN_USER" 10.9.0.1 80)" = out
    check "...and the network's DNS server" test "$(reach "$SIGNIN_FW" "$SIGNIN_USER" 192.168.5.1 53)" = out
    check "...but not this computer (its own address)" test "$(reach "$SIGNIN_FW" "$SIGNIN_USER" 192.168.5.2 8080)" = refused
    check "...nor 127.0.0.1" test "$(reach "$SIGNIN_FW" "$SIGNIN_USER" 127.0.0.1 8080)" = refused
    check "incognito still doesn't reach the local network" test "$(reach "$INCOG_FW" incognito 192.168.5.1 80)" = refused
    check "...nor this computer" test "$(reach "$INCOG_FW" incognito 192.168.5.2 8080)" = refused
else
    echo "  skip  the firewall rules in a network namespace (needs nft and unshare -rn)"
fi

[ "$fails" -eq 0 ]
