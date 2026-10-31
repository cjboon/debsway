#!/bin/bash
# Mousepad, a simple graphical text editor from Xfce (GTK, so it runs
# natively on Wayland). From Debian. Made the default for text files.
# The first time, it also sets Mousepad's look and editing settings
# (data/mousepad.settings: solarized-dark, 16 pt monospace, tabs of 4
# spaces, line numbers, a margin at column 80). They are applied once, so
# running this again doesn't undo changes you made in Mousepad.
# Usage: bash mousepad.sh [--remove]
# summary: Mousepad text editor
# status: apt:mousepad
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

APP=org.xfce.mousepad.desktop
SETTINGS="$DEBSWAY_DIR/data/mousepad.settings"
APPLIED="${XDG_STATE_HOME:-$HOME/.local/state}/debsway/mousepad-settings"

if [ "${1:-}" = --remove ]; then
    apt_purge mousepad
    unset_default_app "$APP"
    rm -f "$APPLIED"
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
apt_install mousepad
set_default_app "$APP" text/plain text/markdown text/x-log application/x-shellscript

if [ -f "$APPLIED" ]; then
    note "Mousepad's settings were set up before; leaving them as they are."
elif ! command -v gsettings >/dev/null || ! gsettings list-schemas | grep -qx org.xfce.mousepad.preferences.view; then
    warn "Couldn't find Mousepad's settings; skipping its look."
elif apply_settings "$SETTINGS"; then
    mkdir -p "${APPLIED%/*}"
    date +%F >"$APPLIED"
    note "Set Mousepad's look and editing settings (data/mousepad.settings)."
else
    warn "Some of Mousepad's settings couldn't be set; run this again to retry."
fi
note "Run it with: mousepad   (or Super+d). Text files now open in it."
