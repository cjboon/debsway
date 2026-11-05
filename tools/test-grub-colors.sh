#!/bin/bash
# Checks parts/grub-colors.sh: it writes its script into grub.d (runnable,
# printing GRUB's four colour settings, valid GRUB script) and runs
# update-grub; if update-grub fails, the script is taken out again; --remove
# takes it out; without GRUB nothing is written. Runs on a copy of Wren Linux
# with a pretend sudo and update-grub, in a temp grub.d, so nothing on this
# computer changes. Run by test.sh, or:  bash tools/test-grub-colors.sh
# shellcheck disable=SC2016  # the pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
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
mkdir -p "$R/parts" "$T/bin" "$T/nogrub" "$T/grub.d" "$T/home"
sed 's|^export PATH=.*|export PATH="$GRUB_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q GRUB_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
for f in packages.sh pins.sh lib data bin docs; do ln -s "$HERE/$f" "$R/$f"; done
cp "$HERE/parts/grub-colors.sh" "$R/parts/"
# sudo runs the command as this user (sudo -v, asking for the password up
# front, just succeeds); update-grub notes it ran, and fails while $T/fail exists
printf '#!/bin/sh\nwhile [ "${1#-}" != "$1" ]; do shift; done\n[ $# -eq 0 ] || exec "$@"\n' >"$T/bin/sudo"
printf '#!/bin/sh\necho ran >>"%s/update-grub.calls"\n[ ! -e "%s/fail" ]\n' "$T" "$T" >"$T/bin/update-grub"
cp "$T/bin/sudo" "$T/nogrub/sudo"
chmod +x "$T/bin/"* "$T/nogrub/"*
export WREN_GRUB_D=$T/grub.d
[ "$(GRUB_TEST_PATH="$T/bin:$PATH" bash -c '. "$1/lib.sh"; command -v sudo' _ "$R")" = "$T/bin/sudo" ] ||
    { echo "  FAIL  the real sudo would run; stopping"; exit 1; }
part() { HOME=$T/home GRUB_TEST_PATH=$1 bash "$R/parts/grub-colors.sh" "${@:2}" >"$T/out" 2>&1; }
S=$T/grub.d/06_wren_colors

part "$T/bin:$PATH"
check "it writes its script after Debian's colours (05_debian_theme), runnable" test -x "$S"
check "...the menu's box red with white text, the chosen entry yellow; black around it and on the loading screen" bash -c '
    [ "$(sh "$1")" = "$(printf "%s\n" "set color_normal=white/black" "set color_highlight=black/white" "set menu_color_normal=white/red" "set menu_color_highlight=yellow/red")" ]' _ "$S"
if command -v grub-script-check >/dev/null; then
    check "...which GRUB accepts (grub-script-check)" bash -c 'sh "$1" | grub-script-check' _ "$S"
fi
check "...and runs update-grub" grep -qx ran "$T/update-grub.calls"

rm -f "$S" "$T/update-grub.calls"
: >"$T/fail"
part "$T/bin:$PATH"
check "update-grub fails: the script is taken out again" test ! -e "$S"
check "...and it says so" grep -q "update-grub failed with the new colours" "$T/out"
rm -f "$T/fail"

part "$T/bin:$PATH"
rm -f "$T/update-grub.calls"
part "$T/bin:$PATH" --remove
check "--remove takes it out" test ! -e "$S"
check "...and builds the menu again" grep -qx ran "$T/update-grub.calls"

part "$T/nogrub:/usr/bin:/bin"
check "without GRUB (no update-grub): nothing is written" test ! -e "$S"
check "...and it says so" grep -q "doesn't boot with GRUB" "$T/out"

check "it is part of the base install, after boot-hardening" bash -c '
    . "$1/packages.sh"; [[ " ${PARTS[*]} " == *" boot-hardening grub-colors "* ]]' _ "$HERE"

[ "$fails" -eq 0 ]
