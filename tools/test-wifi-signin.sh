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
mkdir -p "$T/etc/debsway"
fn "$HERE/bin/firefox-session" | sed "s|/etc/|$T/etc/|g" >"$T/fn"
prefs() { bash -c '. "$1"; doh_prefs "$2"' _ "$T/fn" "$1"; }
mode() { prefs "$1" | sed -n 's/^user_pref("network.trr.mode", \([0-9]\));$/\1/p'; }
on() { printf '%s\n' '# Written by debsway parts/secure-dns.sh. Every name goes to Unbound on this' 'nameserver 127.0.0.1' >"$T/etc/resolv.conf"; }
off() { echo "nameserver 192.168.1.1" >"$T/etc/resolv.conf"; }

on
check "secure DNS on: Firefox uses the system's DNS (mode 5)" test "$(mode normal)" = 5
off
check "secure DNS off: its own encrypted DNS, strict (mode 3, never plain DNS)" test "$(mode normal)" = 3
check "...to Quad9" bash -c 'grep -qx "user_pref(\"network.trr.uri\", \"https://dns.quad9.net/dns-query\");" <<<"$1"' _ "$(prefs normal)"
echo dns=fallback >"$T/etc/debsway/firefox.conf"
check "...with fallback when that was chosen (mode 2)" test "$(mode normal)" = 2
rm "$T/etc/debsway/firefox.conf"
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
check "...the mark for the next login is left while it is off" test -e "$T/xstate/debsway/secure-dns-left-off"
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
check "the menu's Wi-Fi sign-in line runs it" grep -q '/usr/local/bin/wifi-signin}' "$HERE/bin/debsway-menu"
check "parts/incognito.sh installs it, root-owned, next to incognito (and removes it)" bash -c '
    grep -q "install -o root -g root -m 0755 \"\$DEBSWAY_DIR/bin/wifi-signin\" /usr/local/bin/wifi-signin" "$1" &&
    grep -q "sudo rm -f .*/usr/local/bin/wifi-signin" "$1"' _ "$HERE/parts/incognito.sh"

[ "$fails" -eq 0 ]
