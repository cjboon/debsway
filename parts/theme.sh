#!/bin/bash
# Light or dark: Wren Linux's colors from one place (bin/theme). Dark is the
# default and looks as Wren Linux always has; "theme light" (or the Wren Linux
# menu's Theme line) switches to warm light backgrounds and dark text: the
# bar, the plain background with no wallpaper, foot, the Wren menu and its
# lists, nmtui, the launcher, the power menu, notifications, the lock
# screen, GTK apps (Mousepad, Thunar...), and the sandboxed Firefox and
# incognito at their next start: their own look, and websites that offer a
# dark or light version. The text console (tmux) stays dark. The colors are
# data/themes/dark and data/themes/light.
# Usage: bash theme.sh [--remove]
# status: bin:theme
# files: data/themes/dark data/themes/light
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

THEMES="$HOME/.local/share/wren/themes"

if [ "${1:-}" = --remove ]; then
    # back to dark first, so nothing stays light without a way to switch it
    if [ -x "$BIN/theme" ]; then "$BIN/theme" dark >/dev/null 2>&1 || true; fi
    remove_snippet theme
    remove_bin theme
    rm -rf "$THEMES"
    apt_purge
    note "Wren Linux's colors are dark again; your choice in ~/.config/wren/theme stays."
    exit
fi

say "Light or dark (theme)"
# gsettings: tells libadwaita apps light or dark (GTK 3 ones read settings.ini)
apt_install libglib2.0-bin
install_bin theme
mkdir -p "$THEMES"
install -m 0644 "$WREN_DIR/data/themes/dark" "$WREN_DIR/data/themes/light" "$THEMES/"
ensure_sway_config
# the colors of the theme chosen (dark if none), written again, and checked
"$BIN/theme" apply
check_sway_config || {
    remove_snippet theme
    die "sway rejected the theme's colors, so they were taken out."
}
note "$("$BIN/theme"). Switch: theme light, theme dark, or the Wren menu's Theme line."
