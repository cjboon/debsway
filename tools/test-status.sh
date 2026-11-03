#!/bin/bash
# Checks status.sh's Screen lock line: it says the screen never locks when
# swaylock isn't installed, whatever the idle settings say; and its "Security
# at a glance" lines, all done and none done, with pretend disks, firewall,
# packages and Firefox. status.sh only
# reads; it runs here in a temp home, once with swaylock, once with a PATH
# that has everything else. Run by test.sh, or:  bash tools/test-status.sh
# shellcheck disable=SC2016  # sed expands its own variables
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

# A copy of Wren Linux whose lib.sh keeps the test's PATH
R=$T/r
mkdir -p "$R" "$T/home/.config/sway/config.d" "$T/home/.local/bin" "$T/bin" "$T/nolock"
for f in "$HERE"/*; do [ "${f##*/}" = lib.sh ] || ln -s "$f" "$R/${f##*/}"; done
sed 's|^export PATH=.*|export PATH="$STATUS_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q STATUS_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
# The idle lock is set up, for 30 minutes
: >"$T/home/.config/sway/config.d/idle.conf"
printf '#!/bin/sh\necho 30\n' >"$T/home/.local/bin/wren-idle"
printf '#!/bin/sh\nexit 0\n' >"$T/bin/swaylock"
chmod +x "$T/home/.local/bin/wren-idle" "$T/bin/swaylock"
# Every program of /usr/bin and /usr/sbin but swaylock
for d in /usr/bin /usr/sbin; do
    for f in "$d"/*; do [ "${f##*/}" = swaylock ] || [ -e "$T/nolock/${f##*/}" ] || ln -s "$f" "$T/nolock/${f##*/}"; done
done
lockline() { HOME=$T/home STATUS_TEST_PATH=$1 bash "$R/status.sh" 2>/dev/null | sed -n '/^Screen lock:/{n;p}'; }

check "with swaylock: it locks after the idle minutes" grep -q 'after 30 minutes idle' <<<"$(lockline "$T/bin:$T/nolock")"
check "without swaylock: it says the screen never locks" grep -q "swaylock isn't installed, so the screen never locks" <<<"$(lockline "$T/nolock")"

# ---- Security at a glance
G=$T/g
mkdir -p "$G/bin" "$G/etc/apt/apt.conf.d" "$G/etc/unbound/unbound.conf.d" "$G/dist" "$T/home/.config"
# a root on encryption, the firewall up, unattended-upgrades installed
printf '#!/bin/sh\necho /dev/mapper/root\n' >"$G/bin/findmnt"
printf '#!/bin/sh\n[ -e %s/plain ] && echo part || { echo crypt; echo part; }\n' "$G" >"$G/bin/lsblk"
printf '#!/bin/sh\n[ "$1 $2 $3" = "is-active --quiet ufw" ] && [ ! -e %s/fw-off ]\n' "$G" >"$G/bin/systemctl"
printf '#!/bin/sh\necho "install ok installed"\n' >"$G/bin/dpkg-query"
printf '#!/bin/sh\n' >"$G/firefox"
chmod +x "$G/bin/"* "$G/firefox"
printf 'APT::Periodic::Unattended-Upgrade "1";\n' >"$G/etc/apt/apt.conf.d/20auto-upgrades"
printf '[Default Applications]\nx-scheme-handler/https=wren-firefox.desktop\n' >"$T/home/.config/mimeapps.list"
: >"$G/etc/unbound/unbound.conf.d/wren-secure-dns.conf"
printf '%s\n' '# Written by Wren Linux parts/secure-dns.sh. Every name goes to Unbound on this' 'nameserver 127.0.0.1' >"$G/etc/resolv.conf"
glance() { HOME=$T/home WREN_ETC=$G/etc WREN_FX_CLIENT=$1 WREN_FIREFOX_DIST=$G/dist STATUS_TEST_PATH="$G/bin:$T/bin:$T/nolock" bash "$R/status.sh" 2>/dev/null | sed -n '/^Security at a glance:/,/^$/p'; }
out=$(glance "$G/firefox")
check "at a glance, all done: six [x] lines, first in the screen" bash -c '[ "$(grep -c "^  \[x\]" <<<"$1")" = 6 ] && [ "$(head -1 <<<"$1")" = "Security at a glance:" ]' _ "$out"
first=$(HOME=$T/home WREN_ETC=$G/etc WREN_FX_CLIENT=$G/firefox WREN_FIREFOX_DIST=$G/dist STATUS_TEST_PATH="$G/bin:$T/bin:$T/nolock" bash "$R/status.sh" 2>/dev/null | head -1)
check "...and it is the first thing Status shows" test "$first" = "Security at a glance:"
# nothing done: a plain disk, no firewall, no automatic updates, no sandboxed Firefox, plain DNS
: >"$G/plain"; : >"$G/fw-off"
rm -f "$G/etc/apt/apt.conf.d/20auto-upgrades" "$G/etc/unbound/unbound.conf.d/wren-secure-dns.conf" "$G/etc/resolv.conf" "$T/home/.config/sway/config.d/idle.conf"
out=$(glance "$G/none")
check "...none done: each says so, with what to run" bash -c '
    grep -q "\[ \] Disk NOT encrypted" <<<"$1" && grep -q "\[~\] Screen locks only when you lock it" <<<"$1" &&
    grep -q "\[ \] Firewall off: bash parts/ufw.sh" <<<"$1" && grep -q "\[ \] Security updates don.t install by themselves" <<<"$1" &&
    grep -q "\[ \] No sandboxed browser" <<<"$1" && grep -q "\[ \] DNS not encrypted" <<<"$1"' _ "$out"
# the sandboxed Firefox (it encrypts its own DNS while secure DNS is off), no secure DNS
out=$(glance "$G/firefox")
check "...Firefox's own encrypted DNS without secure DNS: partly ([~])" grep -q '\[~\] DNS encrypted for Firefox only' <<<"$out"

: >"$G/etc/unbound/unbound.conf.d/wren-secure-dns.conf"
out=$(glance "$G/firefox")
check "...secure DNS set up but switched off: partly ([~]), and it says so" grep -q '\[~\] Secure DNS switched off' <<<"$out"

[ "$fails" -eq 0 ]
