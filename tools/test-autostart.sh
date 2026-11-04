#!/bin/bash
# Checks what opens at login (bin/wren-autostart, parts/autostart.sh, the helpers
# in lib/sway.sh): the one file that says it, what is started on which workspace,
# changing it, and a list that was changed by hand. With a pretend swaymsg and
# home; nothing is started on this computer's sway.
# Run by test.sh, or:  bash tools/test-autostart.sh
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
not() { ! "$@"; }

H=$T/home
F=$H/.config/wren/autostart
mkdir -p "$T/fake" "${F%/*}"
printf '#!/bin/sh\nshift\necho "$*" >>"%s/calls"\n' "$T" >"$T/fake/swaymsg"
chmod +x "$T/fake/swaymsg"
wa() { env -u SWAYSOCK HOME="$H" PATH="$T/fake:$PATH" bash "$HERE/bin/wren-autostart" "$@" 2>&1; }

# ---- the file a new install starts with
check "the file a new install gets opens a terminal on workspace 2, and nothing else" bash -c '
    [ "$(grep -vE "^(#|$)" "$1")" = "2 foot" ]' _ "$HERE/data/autostart"
check "...and says how to change it" grep -q 'System > Startup programs' "$HERE/data/autostart"
cp "$HERE/data/autostart" "$F"
check "list says what opens where" grep -qE '^  workspace 2 +foot$' <<<"$(wa list)"

# ---- at login
printf '# a comment\n\n1 keepassxc\n2 foot\n3   firefox --new-window https://example.org/\n' >"$F"
: >"$T/calls"
wa
check "at login each program starts on its workspace, in the order of the file" test "$(cat "$T/calls")" = \
    'workspace number 1
exec ~/.local/bin/wren-autostart --run 3
workspace number 2
exec ~/.local/bin/wren-autostart --run 4
workspace number 3
exec ~/.local/bin/wren-autostart --run 5
workspace number 1'
run_line() { # N: what --run N would start, with a pretend sh
    printf '#!/bin/bash\nprintf "%%s\\n" "$2"\n' >"$T/fake/sh"
    chmod +x "$T/fake/sh"
    wa --run "$1"
    rm -f "$T/fake/sh"
}
check "...a line's command is the whole of it, its words kept" test "$(run_line 5)" = 'firefox --new-window https://example.org/'
check "...a comment's line runs nothing" test -z "$(run_line 1)"
check "...--run takes only a number" not wa --run 'x; id'

# a command sway could misread: it only ever sees a line number
printf '1 foot; exit\n2 echo "a, b"\n' >"$F"
: >"$T/calls"
wa
check "a ; or a , in a command never reaches sway as a sway command" bash -c '
    ! grep -qE "exit|echo" "$1" && [ "$(grep -c "^exec " "$1")" = 2 ]' _ "$T/calls"

# the one-workspace extra leaves no keys to reach another workspace
mkdir -p "$H/.config/sway/config.d"
: >"$H/.config/sway/config.d/one-workspace.conf"
printf '1 a\n2 b\n' >"$F"
: >"$T/calls"
wa
check "with the one-workspace extra everything opens on the one workspace" bash -c '
    ! grep -q "workspace number 2" "$1" && [ "$(grep -c "^exec " "$1")" = 2 ]' _ "$T/calls"
rm "$H/.config/sway/config.d/one-workspace.conf"

# ---- a file changed by hand
printf '  3   foot  \nfirefox\n11 toolarge\n0 zero\nx y\n\n# fine\n' >"$F"
: >"$T/calls"
wa
check "by hand: spaces around a line are fine" grep -qx 'workspace number 3' "$T/calls"
check "...a line with no workspace, or none from 1 to 10, starts nothing" test "$(grep -c '^exec ' "$T/calls")" = 1
out=$(wa list)
check "...and list says which it didn't understand" bash -c '
    for l in firefox "11 toolarge" "0 zero" "x y"; do grep -qxF "    $l" <<<"$1" || exit 1; done' _ "$out"
check "...a comment or blank line isn't one of them" not grep -q 'fine' <<<"$out"
: >"$F"
: >"$T/calls"
wa
check "an empty file: nothing started, the workspace left alone" test ! -s "$T/calls"
rm -f "$F"
check "no file at all: nothing started, no error" wa
check "...list says so" grep -q 'Nothing opens by itself' <<<"$(wa list)"

# ---- changing it
cp "$HERE/data/autostart" "$F"
wa add 3 firefox >/dev/null
check "add: a line for it" grep -qx '3 firefox' "$F"
check "...the comments stay" grep -q 'Change it here' "$F"
wa add 4 firefox >/dev/null
check "add again: it moves, one line" bash -c '[ "$(grep -c firefox "$1" | head -1)" -ge 1 ] && grep -qx "4 firefox" "$1" && ! grep -qx "3 firefox" "$1"' _ "$F"
check "...a comment that mentions a program is kept" grep -qx '#   3 firefox' "$F"
check "a workspace that isn't 1 to 10 is refused" not wa add 11 foo
check "...and nothing is written" not grep -qE '^11 ' "$F"
check "add with no command is refused" not wa add 3
wa remove firefox
check "remove: its line goes" not grep -qx '4 firefox' "$F"
check "...the others stay" grep -qx '2 foot' "$F"
check "removing what isn't listed is no error" wa remove nothing-here
out=$(wa add 5 no-such-program-here)
check "a program that isn't there yet: added, and it says so" bash -c 'grep -q "no program called" <<<"$1" && grep -qx "5 no-such-program-here" "$2"' _ "$out" "$F"
wa remove no-such-program-here
: >"$T/empty"
rm -f "$F"
wa add 1 foot >/dev/null
check "add with no file yet makes it" grep -qx '1 foot' "$F"

# ---- the edit screen
cp "$HERE/data/autostart" "$F"
printf 'add 3 firefox --private\nmove 1 4\nremove 9\nnonsense\n\n' >"$T/typed"
out=$(wa edit <"$T/typed")
check "the edit screen: add" grep -qx '3 firefox --private' "$F"
check "...move" grep -qx '4 foot' "$F"
check "...a line that isn't listed: says so, nothing lost" bash -c 'grep -q "Which line" <<<"$1"' _ "$out"
check "...what it doesn't understand: says what to type" grep -q 'Type add, move or remove' <<<"$out"
printf 'remove 2\n\n' >"$T/typed"
wa edit <"$T/typed" >/dev/null
check "...remove" not grep -qx '4 foot' "$F"
check "...its text ends the same way (Enter, or no input)" wa edit </dev/null

# ---- the part, on a copy of Wren Linux, with a pretend sudo
R=$T/wren
mkdir -p "$R" "$T/h2/.config/sway/config.d" "$T/bin"
cp -r "$HERE/lib" "$HERE/lib.sh" "$HERE/pins.sh" "$HERE/parts" "$HERE/bin" "$HERE/data" "$R/"
printf '#!/bin/sh\nexit 0\n' >"$T/bin/sudo"
printf '#!/bin/sh\nexit 0\n' >"$T/bin/sway"
chmod +x "$T/bin/"*
: >"$T/h2/.config/sway/config"
sed -i 's|^PATH=.*||; s|^export PATH=.*|export PATH="$WREN_TEST_PATH:$PATH"|' "$R/lib.sh"
part() { env -u SWAYSOCK HOME="$T/h2" XDG_CONFIG_HOME= WREN_ALLOW_OLD_INSTALL=1 WREN_TEST_PATH="$T/bin" bash "$R/parts/autostart.sh" "$@" 2>&1; }
F2=$T/h2/.config/wren/autostart
S2=$T/h2/.config/sway/config.d
printf 'bad line of mine\n' >"$T/mine"
out=$(part)
check "the part: the list with a terminal on workspace 2" grep -qx '2 foot' "$F2"
check "...the command" test -x "$T/h2/.local/bin/wren-autostart"
check "...sway starts it at login" grep -qx 'exec ~/.local/bin/wren-autostart' "$S2/autostart.conf"
echo '5 mine' >>"$F2"
part >/dev/null
check "run again: your list is left as it is" grep -qx '5 mine' "$F2"
printf '# old\nexec sh -c x\n' >"$S2/keepassxc-start.conf"
part >/dev/null
check "KeePassXC's old line at login moves into the list" grep -qx '1 keepassxc' "$F2"
check "...the old line goes" test ! -e "$S2/keepassxc-start.conf"
part --remove >/dev/null
check "--remove: sway no longer starts it" test ! -e "$S2/autostart.conf"
check "...your list stays" test -f "$F2"

# ---- who else knows
check "it is in the base install" grep -qE '(^|[ (])autostart( |$)' "$HERE/packages.sh"
check "the startup watch watches the list: it starts programs at every login" grep -q '".config/wren/autostart"' "$HERE/bin/wren-watch"
check "no terminal is started any other way" not grep -q 'wren-start-terminal' "$HERE/parts/foot-config.sh"
check "KeePassXC offers its line in the list" grep -q 'wren-autostart" add 1 keepassxc' "$HERE/extras/keepassxc.sh"
check "the menu's Startup programs opens the edit screen" grep -q 'edit' <(grep -A4 '^        autostart)' "$HERE/bin/wren-menu")

[ "$fails" -eq 0 ]
