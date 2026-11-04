#!/bin/bash
# The terminal's look: DejaVu Sans Mono at size 14 (foot's own default is
# small), a black background and readable colours (data/foot.ini). It goes
# to ~/.config/foot/foot.ini, which only affects terminals you open after
# this. A foot.ini you wrote yourself is kept as foot.ini.bak.
# (The terminal that opens on workspace 1 at login is a line in
# ~/.config/wren/autostart: parts/autostart.sh.)
# Usage: bash foot-config.sh [--remove]
# status: file:~/.config/foot/foot.ini
# files: lib/sway.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

CONF="$HOME/.config/foot/foot.ini"
MARK='Written by Wren Linux parts/foot-config.sh'

if [ "${1:-}" = --remove ]; then
    if grep -qs "$MARK" "$CONF"; then
        rm -f "$CONF"
        if [ -f "$CONF.bak" ]; then
            mv "$CONF.bak" "$CONF"
            note "Put your earlier foot.ini back."
        fi
    fi
    # (an older version's terminal at login, and today's line in your list)
    remove_snippet terminal-start
    if [ -x "$BIN/wren-autostart" ]; then "$BIN/wren-autostart" remove foot; fi
    apt_purge fonts-dejavu-mono
    exit
fi

say "Installing the terminal font"
apt_install fonts-dejavu-mono

say "foot config"
mkdir -p "${CONF%/*}"
if [ -f "$CONF" ] && ! grep -qs "$MARK" "$CONF" && ! cmp -s "$WREN_DIR/data/foot.ini" "$CONF"; then
    cp "$CONF" "$CONF.bak"
    note "Your foot.ini is kept as $CONF.bak"
fi
cp "$WREN_DIR/data/foot.ini" "$CONF"
# The text size chosen with console-font (in a terminal window) stays
FONT_CHOICE="$HOME/.config/wren/foot-font"
if [ -s "$FONT_CHOICE" ]; then
    font=$(head -n1 "$FONT_CHOICE")
    case $font in
        *'|'* | *\\*) warn "Ignoring $FONT_CHOICE: odd characters in it" ;;
        *) sed -i "s|^font=.*|font=$font|" "$CONF" && note "Your text size: $font (console-font)" ;;
    esac
fi
# The theme chosen (light or dark: parts/theme.sh) keeps its colors here too
if [ -x "$BIN/theme" ]; then "$BIN/theme" apply >/dev/null 2>&1 || warn "Couldn't put the theme's colors in $CONF (theme apply)"; fi
foot -C -c "$CONF" || warn "foot reports a problem in $CONF"
note "Installed $CONF. New terminals use it (Super+Enter)."

# An older version's terminal at login: it is a line in your list now
remove_snippet terminal-start
