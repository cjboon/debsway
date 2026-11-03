#!/bin/bash
# Checks that debsway works from wherever it is, not only from ~/debsway (the
# first step to a package that installs it root-owned in /usr/share/debsway):
# no script assumes ~/debsway, the commands find a root-owned copy before
# yours, and scripts run from a copy in another folder. Changes nothing outside
# a temp folder. Run by test.sh, or:  bash tools/test-location.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}

# 1. No script code (comments aside) names ~/debsway or $HOME/debsway, except
# the commands' last fallback and the two whose job is to copy debsway there
# (start.sh, and the install stick's first-login question); advice to clone a
# new copy there is fine
cd "$HERE" || exit 1
mapfile -t files < <(git ls-files 'bin/*' 'lib/*' 'parts/*' 'extras/*' '*.sh' 'data/*.sh' 'data/*.bash' | grep -vx -e start.sh -e test.sh -e data/install-iso-first-login.sh -e 'tools/.*')
# shellcheck disable=SC2088  # a literal ~, as scripts would write it
found=$(grep -nE '~/debsway|\$HOME/debsway|\$\{HOME\}/debsway' "${files[@]}" | grep -vE '^[^:]+:[0-9]+:\s*#' |
    grep -vxE '[^:]+:[0-9]+:    DIR=\$HOME/debsway' | grep -v 'get it again: git clone')
check "no script assumes ~/debsway${found:+: $(head -3 <<<"$found" | cut -c1-120 | paste -sd'|')}" test -z "$found"
check "...the commands that look for it say where in one way (DEBSWAY_DIR, the root-owned copy, ~/debsway)" bash -c '
    for f in bin/debsway bin/debsway-menu bin/tails-usb; do
        grep -q "elif \[ -f \"\${DEBSWAY_SYSTEM_DIR:-/usr/share/debsway}/lib.sh\" \]; then" "$f" || exit 1
    done'

# 2. Which copy the debsway command uses
mkdir -p "$T/home/debsway" "$T/sys" "$T/mine"
: >"$T/home/debsway/lib.sh"
: >"$T/mine/lib.sh"
dir() { env -u DEBSWAY_DIR HOME="$T/home" DEBSWAY_SYSTEM_DIR="$T/sys" "$@" bash "$HERE/bin/debsway" --dir; }
check "no package installed: your own copy, ~/debsway" test "$(dir)" = "$T/home/debsway"
: >"$T/sys/lib.sh"
check "the package's root-owned copy wins over ~/debsway (programs running as you can't change it)" test "$(dir)" = "$T/sys"
check "DEBSWAY_DIR, set by you, wins over both" test "$(dir DEBSWAY_DIR="$T/mine")" = "$T/mine"
check "the menu looks in the same order" env -u DEBSWAY_DIR HOME="$T/home" DEBSWAY_SYSTEM_DIR="$T/sys" bash -c '
    eval "$(sed -n "/^if \[ -n \"\${DEBSWAY_DIR:-}\" \]; then/,/^fi/p" "$1")"; [ "$DIR" = "$2" ]' _ "$HERE/bin/debsway-menu" "$T/sys" \
    </dev/null
check "...and tails-usb" env -u DEBSWAY_DIR HOME="$T/home" DEBSWAY_SYSTEM_DIR="$T/sys" bash -c '
    eval "$(sed -n "/^if \[ -n \"\${DEBSWAY_DIR:-}\" \]; then/,/^fi/p" "$1")"; [ "$DIR" = "$2" ]' _ "$HERE/bin/tails-usb" "$T/sys"

# 3. Scripts run from a copy in another folder, and say that folder
mkdir -p "$T/elsewhere"
git ls-files -co --exclude-standard | tar -cf - -T - | tar -C "$T/elsewhere" -xf -
C=$T/elsewhere
out=$(HOME="$T/home" bash "$C/install-extras.sh" --list 2>&1)
check "install-extras.sh --list works from there" grep -q 'MOST SECURE' <<<"$out"
out=$(HOME="$T/home" bash "$C/extras/vim.sh" --manual 2>&1)
check "an extra's --manual works from there, with that folder in its steps" grep -q "$C/data/vimrc" <<<"$out"
out=$(HOME="$T/home" DEBSWAY_DIR="$C" bash "$C/bin/debsway" --list 2>&1)
check "debsway list works from there" grep -q 'vim' <<<"$out"
check "a message during an install names that folder, not ~/debsway" bash -c '
    grep -q "bash \$DEBSWAY_DIR/extras/autologin.sh --remove" "$1" && [ "$(bash -c ". \"\$1/lib.sh\"; echo \"\$DEBSWAY_DIR\"" _ "$2")" = "$2" ]' _ "$HERE/extras/autologin.sh" "$C"

# 4. Saved downloads (offline/: Whonix, Tor Browser, the Wi-Fi packages): in the
# folder when it has them or can be written, else in your home
od() { env -u OFFLINE_DIR HOME="$T/home" XDG_DATA_HOME= bash -c '. "$1/lib.sh"; echo "$OFFLINE_DIR"' _ "$1"; }
check "a copy you can write: its own offline/" test "$(od "$C")" = "$C/offline"
mkdir -p "$T/ro"
cp -r "$C" "$T/ro/debsway"
rm -rf "$T/ro/debsway/offline"
chmod a-w "$T/ro/debsway"
check "a read-only copy (the package's): ~/.local/share/debsway/offline" test "$(od "$T/ro/debsway")" = "$T/home/.local/share/debsway/offline"
chmod u+w "$T/ro/debsway"
mkdir "$T/ro/debsway/offline"
chmod a-w "$T/ro/debsway"
check "a read-only stick that has offline/ (mounted by root): that one, so wifi.sh finds its packages" test "$(od "$T/ro/debsway")" = "$T/ro/debsway/offline"
chmod u+w "$T/ro/debsway"
found=$(grep -rnE '\$\{?DEBSWAY_DIR\}?"?/offline' --include='*.sh' lib parts extras prep bin ./*.sh | grep -v '^lib/core.sh:' |
    grep -v '\${OFFLINE_DIR:-\$DEBSWAY_DIR/offline}')
check "every script keeps its saved downloads in OFFLINE_DIR${found:+: $(head -2 <<<"$found" | cut -c1-100 | paste -sd'|')}" test -z "$found"

[ "$fails" -eq 0 ]
