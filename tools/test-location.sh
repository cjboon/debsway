#!/bin/bash
# Checks that Wren Linux works from wherever it is, not only from ~/wren (the
# first step to a package that installs it root-owned in /usr/share/wren):
# no script assumes ~/wren, the commands find a root-owned copy before
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

# 1. No script code (comments aside) names ~/wren or $HOME/wren, except
# the commands' last fallback and the two whose job is to copy Wren Linux there
# (start.sh, and the install stick's first-login question); advice to clone a
# new copy there is fine
cd "$HERE" || exit 1
mapfile -t files < <(git ls-files 'bin/*' 'lib/*' 'parts/*' 'extras/*' '*.sh' 'data/*.sh' 'data/*.bash' | grep -vx -e start.sh -e test.sh -e data/install-iso-first-login.sh -e 'tools/.*')
# shellcheck disable=SC2088  # a literal ~, as scripts would write it
found=$(grep -nE '~/wren|\$HOME/wren|\$\{HOME\}/wren' "${files[@]}" | grep -vE '^[^:]+:[0-9]+:\s*#' |
    grep -vxE '[^:]+:[0-9]+:    DIR=\$HOME/wren' | grep -v 'get it again: git clone')
check "no script assumes ~/wren${found:+: $(head -3 <<<"$found" | cut -c1-120 | paste -sd'|')}" test -z "$found"
check "...the commands that look for it say where in one way (WREN_DIR, the root-owned copy, ~/wren)" bash -c '
    for f in bin/wrenctl bin/wren-menu bin/tails-usb; do
        grep -q "elif \[ -f \"\${WREN_SYSTEM_DIR:-/usr/share/wren}/lib.sh\" \]; then" "$f" || exit 1
    done'

# 2. Which copy the Wren Linux command uses
mkdir -p "$T/home/wren" "$T/sys" "$T/mine"
: >"$T/home/wren/lib.sh"
: >"$T/mine/lib.sh"
dir() { env -u WREN_DIR HOME="$T/home" WREN_SYSTEM_DIR="$T/sys" "$@" bash "$HERE/bin/wrenctl" --dir; }
check "no package installed: your own copy, ~/wren" test "$(dir)" = "$T/home/wren"
: >"$T/sys/lib.sh"
check "the package's root-owned copy wins over ~/wren (programs running as you can't change it)" test "$(dir)" = "$T/sys"
check "WREN_DIR, set by you, wins over both" test "$(dir WREN_DIR="$T/mine")" = "$T/mine"
check "the menu looks in the same order" env -u WREN_DIR HOME="$T/home" WREN_SYSTEM_DIR="$T/sys" bash -c '
    eval "$(sed -n "/^if \[ -n \"\${WREN_DIR:-}\" \]; then/,/^fi/p" "$1")"; [ "$DIR" = "$2" ]' _ "$HERE/bin/wren-menu" "$T/sys" \
    </dev/null
check "...and tails-usb" env -u WREN_DIR HOME="$T/home" WREN_SYSTEM_DIR="$T/sys" bash -c '
    eval "$(sed -n "/^if \[ -n \"\${WREN_DIR:-}\" \]; then/,/^fi/p" "$1")"; [ "$DIR" = "$2" ]' _ "$HERE/bin/tails-usb" "$T/sys"

# 3. Scripts run from a copy in another folder, and say that folder
mkdir -p "$T/elsewhere"
git ls-files -co --exclude-standard | tar -cf - -T - | tar -C "$T/elsewhere" -xf -
C=$T/elsewhere
out=$(HOME="$T/home" bash "$C/install-extras.sh" --list 2>&1)
check "install-extras.sh --list works from there" grep -q 'MOST SECURE' <<<"$out"
out=$(HOME="$T/home" bash "$C/extras/vim.sh" --manual 2>&1)
check "an extra's --manual works from there, with that folder in its steps" grep -q "$C/data/vimrc" <<<"$out"
out=$(HOME="$T/home" WREN_DIR="$C" bash "$C/bin/wrenctl" --list 2>&1)
check "wrenctl list works from there" grep -q 'vim' <<<"$out"
check "a message during an install names that folder, not ~/wren" bash -c '
    grep -q "bash \$WREN_DIR/extras/autologin.sh --remove" "$1" && [ "$(bash -c ". \"\$1/lib.sh\"; echo \"\$WREN_DIR\"" _ "$2")" = "$2" ]' _ "$HERE/extras/autologin.sh" "$C"

# 4. Saved downloads (offline/: Whonix, Tor Browser, the Wi-Fi packages): in the
# folder when it has them or can be written, else in your home
od() { env -u OFFLINE_DIR HOME="$T/home" XDG_DATA_HOME= bash -c '. "$1/lib.sh"; echo "$OFFLINE_DIR"' _ "$1"; }
check "a copy you can write: its own offline/" test "$(od "$C")" = "$C/offline"
mkdir -p "$T/ro"
cp -r "$C" "$T/ro/wren"
rm -rf "$T/ro/wren/offline"
chmod a-w "$T/ro/wren"
check "a read-only copy (the package's): ~/.local/share/wren/offline" test "$(od "$T/ro/wren")" = "$T/home/.local/share/wren/offline"
chmod u+w "$T/ro/wren"
mkdir "$T/ro/wren/offline"
chmod a-w "$T/ro/wren"
check "a read-only stick that has offline/ (mounted by root): that one, so wifi.sh finds its packages" test "$(od "$T/ro/wren")" = "$T/ro/wren/offline"
chmod u+w "$T/ro/wren"
found=$(grep -rnE '\$\{?WREN_DIR\}?"?/offline' --include='*.sh' lib parts extras prep bin ./*.sh | grep -v '^lib/core.sh:' |
    grep -v '\${OFFLINE_DIR:-\$WREN_DIR/offline}')
check "every script keeps its saved downloads in OFFLINE_DIR${found:+: $(head -2 <<<"$found" | cut -c1-100 | paste -sd'|')}" test -z "$found"

# 5. A computer set up as debsway, before the name: the scripts that change the
# system stop and say to reinstall; the install stick can still be made
mkdir -p "$T/old/.config/debsway"
nu() { env -u WREN_ALLOW_OLD_INSTALL HOME="$T/old" WREN_SUDO=true "$@" bash -c '. "$1/lib.sh"; need_user && echo passed' _ "$HERE" 2>&1; }
check "set up as debsway: a script that changes the system stops, and says to reinstall" \
    bash -c '! grep -q passed <<<"$1" && grep -q "make-install-iso.sh" <<<"$1"' _ "$(nu)"
check "...unless asked to anyway (WREN_ALLOW_OLD_INSTALL=1)" grep -q passed <<<"$(nu WREN_ALLOW_OLD_INSTALL=1)"
check "...the install stick is still made there (make-install-iso.sh doesn't ask need_user)" \
    bash -c '! grep -q "^need_user" "$1" && grep -q "^not_root" "$1"' _ "$HERE/prep/make-install-iso.sh"
check "a computer set up as Wren Linux: no stop" grep -q passed <<<"$(env HOME="$T/home" WREN_SUDO=true bash -c '. "$1/lib.sh"; need_user && echo passed' _ "$HERE" 2>&1)"

# 6. The documentation in ~/Documents/wren-docs, links into the copy in use
dl() { env HOME="$1" WREN_DIR="$2" bash -c 'note() { :; }; eval "$(sed -n "/^DOCS=/p; /^docs_links() {/,/^}/p" "$3")"; docs_links' _ "$1" "$2" "$HERE/parts/core-commands.sh"; }
mkdir -p "$T/dh"
dl "$T/dh" "$C"
check "Documents/wren-docs in your home links to the README, the threat model and the guides of the copy in use" bash -c '
    [ "$(readlink "$1/README.md")" = "$2/README.md" ] && [ "$(readlink "$1/THREAT-MODEL.md")" = "$2/THREAT-MODEL.md" ] &&
    [ "$(readlink "$1/guides")" = "$2/docs" ] && [ -f "$1/guides/install-base.md" ]' _ "$T/dh/Documents/wren-docs" "$C"
dl "$T/dh" "$T/sys"
check "...and follows when the copy in use changes (the package's, after it is installed)" test "$(readlink "$T/dh/Documents/wren-docs/guides")" = "$T/sys/docs"
mkdir -p "$T/mine/Documents/wren-docs"
echo "my notes" >"$T/mine/Documents/wren-docs/notes.txt"
dl "$T/mine" "$C"
check "a ~/Documents/wren-docs of your own is left alone" bash -c '[ ! -e "$1/README.md" ] && [ "$(ls "$1")" = notes.txt ]' _ "$T/mine/Documents/wren-docs"
check "--remove takes the links out, only if Wren Linux made them" bash -c '
    s=$(sed -n "/^if \[ \"\${1:-}\" = --remove \]; then/,/^fi/p" "$1"); grep -q "DOCS/.wren-docs" <<<"$s" && grep -q "rmdir" <<<"$s"' _ "$HERE/parts/core-commands.sh"

[ "$fails" -eq 0 ]
