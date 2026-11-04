#!/bin/bash
# Checks parts/foot-config.sh with a pretend sudo and apt, in a temp home: the
# an older version's terminal at login going (it is a line in your list now:
# tools/test-autostart.sh), and --remove taking your list's line out. Nothing
# outside a temp folder changes.
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
check "no terminal at login of its own: that is a line in your list" test ! -e "$S"
if command -v sway >/dev/null; then
    check "...and sway takes the rest" bash -c '! grep -q "rejected" <<<"$1"' _ "$out"
fi
mkdir -p "${S%/*}"
echo '# old' >"$S"
fc >/dev/null
check "an older version's terminal at login goes" test ! -e "$S"
mkdir -p "$T/home/.local/bin" "$T/home/.config/wren"
cp "$HERE/bin/wren-autostart" "$T/home/.local/bin/"
printf '2 foot\n5 other\n' >"$T/home/.config/wren/autostart"
fc --remove >/dev/null
check "--remove takes the terminal out of your list" bash -c '! grep -qx "2 foot" "$1" && grep -qx "5 other" "$1"' _ "$T/home/.config/wren/autostart"

[ "$fails" -eq 0 ]
