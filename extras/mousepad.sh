#!/bin/bash
# Mousepad, a simple graphical text editor from Xfce (GTK, so it runs
# natively on Wayland). From Debian. Made the default for text files.
# It also sets Mousepad's look and editing settings (data/mousepad.settings):
# white text on black in the terminal's colors (data/mousepad-dark.xml) with
# dark menus (bin/mousepad), DejaVu Sans Mono 14, tabs of 4 spaces, line
# numbers, matching braces highlighted and a line at column 80. They are set
# again only when Wren Linux's settings change, so running this again doesn't
# undo changes you made in Mousepad.
# Usage: bash mousepad.sh [--remove | --manual]
# summary: Mousepad text editor
# security: some
# status: apt:mousepad
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

APP=org.xfce.mousepad.desktop
SETTINGS="$WREN_DIR/data/mousepad.settings"
SCHEME="$WREN_DIR/data/mousepad-dark.xml"
# its light twin, for Wren Linux's light theme (bin/theme switches between them)
SCHEME_LIGHT="$WREN_DIR/data/mousepad-light.xml"
STYLES="${XDG_DATA_HOME:-$HOME/.local/share}/gtksourceview-4/styles"
APPLIED="${XDG_STATE_HOME:-$HOME/.local/state}/wren/mousepad-settings"

if [ "${1:-}" = --remove ]; then
    apt_purge mousepad libglib2.0-bin
    unset_default_app "$APP"
    remove_bin mousepad
    rm -f "$APPLIED" "$STYLES/wren-dark.xml" "$STYLES/wren-light.xml"
    note "Your Mousepad settings are left as they are (gsettings reset -r org.xfce.mousepad.preferences clears them)."
    exit
fi

# apply_settings FILE: gsettings set for every SCHEMA KEY VALUE line
apply_settings() {
    local schema key value failed=0
    while read -r schema key value; do
        case $schema in '' | '#'*) continue ;; esac
        gsettings set "$schema" "$key" "$value" || failed=1
    done <"$1"
    return "$failed"
}

say "Installing Mousepad"
# libglib2.0-bin: gsettings, which sets its preferences
apt_install mousepad libglib2.0-bin
set_default_app "$APP" text/plain text/markdown text/x-log application/x-shellscript
install_bin mousepad
install -D -m 0644 "$SCHEME" "$STYLES/wren-dark.xml"
install -D -m 0644 "$SCHEME_LIGHT" "$STYLES/wren-light.xml"

# Which settings were set, so a change to them (not a rerun) sets them again
want=$(cat "$SETTINGS" "$SCHEME" "$SCHEME_LIGHT" | sha256sum | cut -d' ' -f1)
if [ "$(cat "$APPLIED" 2>/dev/null)" = "$want" ]; then
    note "Mousepad's settings were set up before; leaving them as they are."
elif ! command -v gsettings >/dev/null || ! gsettings list-schemas | grep -qx org.xfce.mousepad.preferences.view; then
    warn "Couldn't find Mousepad's settings (gsettings or its schema is missing); its look isn't set. Run this again to retry."
elif apply_settings "$SETTINGS"; then
    mkdir -p "${APPLIED%/*}"
    echo "$want" >"$APPLIED"
    note "Set Mousepad's look and editing settings (data/mousepad.settings). Close and reopen Mousepad to see them."
    # in Wren Linux's light theme, its light scheme (data/mousepad.settings says dark)
    if [ "$(head -c 16 "${XDG_CONFIG_HOME:-$HOME/.config}/wren/theme" 2>/dev/null || true)" = light ]; then
        gsettings set org.xfce.mousepad.preferences.view color-scheme wren-light || true
    fi
else
    warn "Some of Mousepad's settings couldn't be set; run this again to retry."
fi
note "Run it with: mousepad   (or Super+d). Text files now open in it."
