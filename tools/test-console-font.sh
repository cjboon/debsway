#!/bin/bash
# Checks bin/console-font in a terminal window (foot): it lists foot's sizes,
# a name or number changes the font= line of foot.ini (nothing else in it) and
# is remembered; a font foot rejects changes nothing; on a text console it is
# still the console's fonts. And that parts/foot-config.sh, writing foot.ini
# again, keeps the size chosen. Runs in a temp home with a pretend foot,
# sudo and dpkg, so nothing on this computer changes.
# Run by test.sh, or:  bash tools/test-console-font.sh
# shellcheck disable=SC2016  # the pretend programs expand their own variables
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

mkdir -p "$T/bin" "$T/home/.config/foot"
# foot -C: fine, unless the file asks for a font named Nope
printf '#!/bin/sh\n[ "$1" = -C ] || exit 0\n! grep -q "^font=Nope" "$3"\n' >"$T/bin/foot"
printf '#!/bin/sh\necho "sudo $*" >>"%s/calls"\n' "$T" >"$T/bin/sudo"
printf '#!/bin/sh\ncase "$*" in *Status*) echo "install ok installed" ;; esac\n' >"$T/bin/dpkg-query"
chmod +x "$T/bin/"*
INI=$T/home/.config/foot/foot.ini
cp "$HERE/data/foot.ini" "$INI"
cf() { env -u TMUX HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" PATH="$T/bin:$PATH" WAYLAND_DISPLAY=wayland-1 TERM=foot bash "$HERE/bin/console-font" "$@" </dev/null; }

out=$(cf list)
check "in a terminal window: foot's sizes, the one in use marked" grep -qE '^ \* +[0-9]+  dejavu-14$' <<<"$out"
check "...not the console's" not grep -q terminus <<<"$out"
cf dejavu-18 >/dev/null
check "a name: foot.ini's font= line changes" grep -qx 'font=DejaVu Sans Mono:size=18' "$INI"
check "...and nothing else in it" bash -c 'diff <(grep -v "^font=" "$1") <(grep -v "^font=" "$2")' _ "$HERE/data/foot.ini" "$INI"
check "...remembered" grep -qx 'DejaVu Sans Mono:size=18' "$T/home/.config/wren/foot-font"
check "...and marked in the list" grep -qE '^ \* +[0-9]+  dejavu-18$' <(cf list)
n=$(cf list | awk '$NF == "dejavu-bold-20" { print $1 }')
cf "$n" >/dev/null
check "a number: that one (bold 20)" grep -qx 'font=DejaVu Sans Mono:style=Bold:size=20' "$INI"
check "a name that isn't one: refused" not cf terminus-24
check "...nothing changed" grep -qx 'font=DejaVu Sans Mono:style=Bold:size=20' "$INI"
# a font foot rejects (a copy of console-font whose list has one)
cp "$HERE/bin/console-font" "$T/cf-bad"
sed -i 's/files+=("DejaVu Sans Mono:size=$s")/files+=("Nope:size=$s")/' "$T/cf-bad"
env -u TMUX HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" PATH="$T/bin:$PATH" WAYLAND_DISPLAY=wayland-1 TERM=foot bash "$T/cf-bad" dejavu-12 >/dev/null 2>&1 </dev/null
check "a font foot rejects: foot.ini and the choice stay as they were" \
    bash -c 'grep -qx "font=DejaVu Sans Mono:style=Bold:size=20" "$1" && grep -qx "DejaVu Sans Mono:style=Bold:size=20" "$2"' _ "$INI" "$T/home/.config/wren/foot-font"
out=$(env -u TMUX -u WAYLAND_DISPLAY HOME="$T/home" TERM=linux PATH="$T/bin:$PATH" bash "$HERE/bin/console-font" --console list </dev/null)
check "--console (or a text console): the console's fonts" bash -c '! grep -q "dejavu-bold-20$" <<<"$1" && grep -q "Console fonts" <<<"$1"' _ "$out"

# parts/foot-config.sh writes foot.ini again, keeping the size
R=$T/r
mkdir -p "$R/parts"
sed 's|^export PATH=.*|export PATH="$FONT_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q FONT_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
for f in packages.sh pins.sh lib data bin docs; do ln -s "$HERE/$f" "$R/$f"; done
cp "$HERE/parts/foot-config.sh" "$R/parts/"
export FONT_TEST_PATH="$T/bin:$PATH"
[ "$(bash -c '. "$1/lib.sh"; command -v sudo' _ "$R")" = "$T/bin/sudo" ] || { echo "  FAIL  the real sudo would run; stopping"; exit 1; }
echo 'font=Old' >"$INI"
HOME=$T/home bash "$R/parts/foot-config.sh" >"$T/out" 2>&1
check "foot-config.sh writes foot.ini again, with the size chosen" \
    bash -c 'grep -qx "font=DejaVu Sans Mono:style=Bold:size=20" "$1" && grep -q "^\[colors\]" "$1"' _ "$INI"
rm "$T/home/.config/wren/foot-font"
HOME=$T/home bash "$R/parts/foot-config.sh" >"$T/out" 2>&1
check "...and Wren Linux's own size without a choice" grep -qx 'font=DejaVu Sans Mono:size=14' "$INI"

[ "$fails" -eq 0 ]
