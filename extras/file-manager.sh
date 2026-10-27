#!/bin/bash
# Thunar, a light graphical file manager from Xfce (GTK, so it runs
# natively on Wayland), from Debian. gvfs gives it the Trash, tumbler
# draws thumbnails. USB drives are already mounted by udiskie
# (parts/udiskie.sh), so Thunar's own volume manager isn't needed.
# Made the default for folders, e.g. "open containing folder" in Firefox.
# Usage: bash file-manager.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

APP=thunar.desktop

if [ "${1:-}" = --remove ]; then
    apt_purge thunar tumbler
    unset_default_app "$APP"
    note "gvfs is kept, since other apps may use it."
    exit
fi

say "Installing Thunar"
apt_install thunar gvfs tumbler
set_default_app "$APP" inode/directory
cat <<'TIPS'

    How to use Thunar:
      thunar                 open your home folder (or Super+d, thunar)
      thunar ~/Downloads     open a folder
    Keys: Ctrl+L type a path, Ctrl+H show hidden files, Ctrl+T new tab,
          F2 rename, Delete move to Trash, Shift+Delete delete for good,
          Alt+Up parent folder, Ctrl+1/2/3 icon/list/compact view
TIPS
