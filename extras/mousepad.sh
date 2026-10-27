#!/bin/bash
# Mousepad, a simple graphical text editor from Xfce (GTK, so it runs
# natively on Wayland). From Debian. Made the default for text files.
# Usage: bash mousepad.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

APP=org.xfce.mousepad.desktop

if [ "${1:-}" = --remove ]; then
    apt_purge mousepad
    unset_default_app "$APP"
    exit
fi

say "Installing Mousepad"
apt_install mousepad
set_default_app "$APP" text/plain text/markdown text/x-log application/x-shellscript
note "Run it with: mousepad   (or Super+d). Text files now open in it."
