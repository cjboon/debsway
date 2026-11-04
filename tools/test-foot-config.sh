#!/bin/bash
# Checks parts/foot-config.sh with a pretend sudo and apt, in a temp home: the
# terminal on workspace 2 at login (only that one, by its own app id), sway
# taking it, and --remove taking it out. Nothing outside a temp folder changes.
# Run by test.sh, or:  bash tools/test-foot-config.sh
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
not() { ! "$@"; }
mkdir -p "$T/bin" "$T/home"
printf '#!/bin/sh\n[ "$1" = -v ] && exit 0\necho "sudo $*" >>"%s/calls"\n' "$T" >"$T/bin/sudo"
printf '#!/bin/sh\ncase "$*" in *Status*) echo "install ok installed" ;; *Depends*) echo fonts-dejavu-mono ;; esac\n' >"$T/bin/dpkg-query"
chmod +x "$T/bin/"*
R=$T/r
mkdir -p "$R/parts" "$R/lib"
sed 's|^export PATH=.*|export PATH="$FC_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q FC_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
for f in pins.sh packages.sh data bin docs; do ln -s "$HERE/$f" "$R/$f"; done
for f in "$HERE"/lib/*; do ln -s "$f" "$R/lib/${f##*/}"; done
cp "$HERE/parts/foot-config.sh" "$R/parts/"
export FC_TEST_PATH="$T/bin:$PATH"
fc() { env -u SWAYSOCK HOME="$T/home" XDG_CONFIG_HOME= bash "$R/parts/foot-config.sh" "$@" 2>&1; }
S=$T/home/.config/sway/config.d/terminal-start.conf

out=$(fc)
check "a terminal on workspace 2 at login, sent there by its own app id" bash -c '
    grep -qx "assign \[app_id=\"wren-start-terminal\"\] workspace number 2" "$1" && grep -qx "exec foot --app-id=wren-start-terminal" "$1"' _ "$S"
check "...only that one: no rule for foot's own app id" not grep -q 'app_id="foot"' "$S"
if command -v sway >/dev/null; then
    check "...and sway takes it" bash -c '! grep -q "rejected" <<<"$1"' _ "$out"
fi
fc --remove >/dev/null
check "--remove takes it out" test ! -e "$S"

[ "$fails" -eq 0 ]
