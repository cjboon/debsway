#!/bin/bash
# Checks extras/mousepad.sh: gsettings is installed with Mousepad (without it
# the look was skipped), every setting is set, the black scheme is installed
# and named, they are set again only when debsway's settings change, and the
# mousepad command gets dark menus. Runs the extra with a pretend sudo (only
# logs), dpkg-query (its packages "already installed") and gsettings (logs),
# in a temp home, so nothing on this computer changes. Run by test.sh, or:
#   bash tools/test-mousepad.sh
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

S=$HERE/data/mousepad.settings
setting() { awk -v k="$1" '$2 == k { $1 = $2 = ""; sub(/^ +/, ""); print }' "$S"; }
check "white text on black: debsway's own scheme" test "$(setting color-scheme)" = "'debsway-dark'"
check "...which is the scheme data/mousepad-dark.xml defines" grep -q '<style-scheme id="debsway-dark"' "$HERE/data/mousepad-dark.xml"
check "...black behind white-ish text" grep -qE '<style name="text" +foreground="text" background="black"/>' "$HERE/data/mousepad-dark.xml"
check "the terminal's font, at a readable size" test "$(setting font-name)" = "'DejaVu Sans Mono 14'"
check "...not the default font in its place" test "$(setting use-default-monospace-font)" = false
check "a tab is 4 spaces" bash -c '[ "$1" = 4 ] && [ "$2" = true ]' _ "$(setting tab-width)" "$(setting insert-spaces)"
check "line numbers" test "$(setting show-line-numbers)" = true
check "matching braces highlighted" test "$(setting match-braces)" = true
check "a line down the right side at column 80" bash -c '[ "$1" = true ] && [ "$2" = 80 ]' _ "$(setting show-right-margin)" "$(setting right-margin-position)"
X=/usr/share/glib-2.0/schemas/org.xfce.mousepad.gschema.xml
if [ -f "$X" ]; then
    while read -r _ key _; do
        check "Mousepad has the setting $key" grep -q "<key name=\"$key\"" "$X"
    done < <(grep -v '^#' "$S" | grep .)
fi
R=/usr/share/gtksourceview-4/styles/styles.rng
if command -v xmllint >/dev/null && [ -f "$R" ]; then
    check "the scheme is a valid GtkSourceView 4 scheme" xmllint --noout --relaxng "$R" "$HERE/data/mousepad-dark.xml"
    check "...and its light twin" xmllint --noout --relaxng "$R" "$HERE/data/mousepad-light.xml"
fi

# ---- the extra, with pretend programs ----
mkdir -p "$T/bin" "$T/home"
cat >"$T/bin/sudo" <<EOF
#!/bin/sh
[ "\$1" = -v ] && exit 0
echo "\$*" >>"$T/root-calls"
EOF
cat >"$T/bin/dpkg-query" <<'EOF'
#!/bin/sh
case "$*" in
    *Status*) echo 'install ok installed' ;;
    *Depends*) echo 'mousepad, libglib2.0-bin' ;;
esac
EOF
cat >"$T/bin/gsettings" <<EOF
#!/bin/sh
case "\$1" in
    list-schemas) echo org.xfce.mousepad.preferences.view ;;
    set) shift; echo "\$*" >>"$T/set" ;;
esac
EOF
chmod +x "$T/bin/"*
W=$T/r
mkdir -p "$W/extras" "$W/data" "$W/bin"
sed 's|^export PATH=.*|export PATH="$MOUSEPAD_TEST_PATH"|' "$HERE/lib.sh" >"$W/lib.sh"
grep -q MOUSEPAD_TEST_PATH "$W/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
cp "$HERE/pins.sh" "$HERE/packages.sh" "$W/"
ln -s "$HERE/lib" "$W/lib"
cp "$HERE/extras/mousepad.sh" "$W/extras/"
cp "$HERE/data/mousepad.settings" "$HERE/data/mousepad-dark.xml" "$HERE/data/mousepad-light.xml" "$W/data/"
cp "$HERE/bin/mousepad" "$W/bin/"
export MOUSEPAD_TEST_PATH="$T/bin:$PATH"
run() { : >"$T/set"; HOME=$T/home XDG_DATA_HOME='' XDG_STATE_HOME='' XDG_CONFIG_HOME='' bash "$W/extras/mousepad.sh" "$@" >"$T/out" 2>&1; }

check "gsettings, which sets its preferences, is installed with it" grep -q '^apt_install mousepad libglib2.0-bin$' "$HERE/extras/mousepad.sh"
run
check "every setting is set" test "$(wc -l <"$T/set")" -eq "$(grep -v '^#' "$S" | grep -c .)"
check "...as written" grep -qx "org.xfce.mousepad.preferences.view color-scheme 'debsway-dark'" "$T/set"
check "the scheme is installed where Mousepad looks" cmp "$HERE/data/mousepad-dark.xml" "$T/home/.local/share/gtksourceview-4/styles/debsway-dark.xml"
check "...its light twin too, for the light theme (the same styles, other colors)" bash -c '
    cmp -s "$1" "$3/debsway-light.xml" && grep -q "<style-scheme id=\"debsway-light\"" "$1" &&
    [ "$(grep -c "<style " "$1")" = "$(grep -c "<style " "$2")" ]' _ "$HERE/data/mousepad-light.xml" "$HERE/data/mousepad-dark.xml" "$T/home/.local/share/gtksourceview-4/styles"
check "mousepad gets dark menus" grep -q 'GTK_THEME=Adwaita:dark /usr/bin/mousepad' "$T/home/.local/bin/mousepad"
# the command, run with a stand-in for /usr/bin/mousepad that says its GTK theme
mp() { sed 's|/usr/bin/mousepad|env|' "$HERE/bin/mousepad" | HOME=$T/home XDG_CONFIG_HOME='' sh -s | grep '^GTK_THEME='; }
check "...in the dark theme: Adwaita's dark variant" test "$(mp)" = GTK_THEME=Adwaita:dark
mkdir -p "$T/home/.config/debsway"; echo light >"$T/home/.config/debsway/theme"
check "...in the light theme: light menus" test "$(mp)" = GTK_THEME=Adwaita
rm -f "$T/home/.config/debsway/theme"
check "...and is the default for text files" grep -q 'text/plain=org.xfce.mousepad.desktop' "$T/home/.config/mimeapps.list"
run
check "run again, your own changes are left alone" test ! -s "$T/set"
echo "org.xfce.mousepad.preferences.view highlight-current-line true" >>"$W/data/mousepad.settings"
run
check "when debsway's settings change, they are set again" grep -q highlight-current-line "$T/set"
echo 2026-01-01 >"$T/home/.local/state/debsway/mousepad-settings"
run
check "...also over the old marker (a date), which never set them on a computer without gsettings" test -s "$T/set"
# (a pretend one that knows no Mousepad, not none: a real gsettings further
# down PATH would change your own settings)
printf '#!/bin/sh\n[ "$1" = set ] && echo "$*" >>"%s/set"\nexit 0\n' "$T" >"$T/bin/gsettings"
rm -f "$T/home/.local/state/debsway/mousepad-settings"
run
check "without Mousepad's settings in gsettings it says so" grep -q "Couldn't find Mousepad's settings" "$T/out"
check "...sets nothing" test ! -s "$T/set"
check "...and tries again next time (no marker)" test ! -e "$T/home/.local/state/debsway/mousepad-settings"
# debsway's light theme (bin/theme): Mousepad starts on the light scheme
rm -f "$T/home/.local/state/debsway/mousepad-settings"
mkdir -p "$T/home/.config/debsway"
echo light >"$T/home/.config/debsway/theme"
cat >"$T/bin/gsettings" <<EOF
#!/bin/sh
case "\$1" in
    list-schemas) echo org.xfce.mousepad.preferences.view ;;
    set) shift; echo "\$*" >>"$T/set" ;;
esac
EOF
run
check "in the light theme it starts on its light scheme" bash -c '[ "$(grep "color-scheme" "$1" | tail -1)" = "org.xfce.mousepad.preferences.view color-scheme debsway-light" ]' _ "$T/set"
rm -f "$T/home/.config/debsway/theme"
run --remove
check "--remove takes out the schemes" bash -c '[ ! -e "$1/debsway-dark.xml" ] && [ ! -e "$1/debsway-light.xml" ]' _ "$T/home/.local/share/gtksourceview-4/styles"
check "...and the mousepad command" test ! -e "$T/home/.local/bin/mousepad"

[ "$fails" -eq 0 ]
