#!/bin/bash
# GIMP, the image editor, from Debian, run in a sandbox (bin/media-sandbox,
# the one imv, mpv and zathura use): a booby-trapped picture can't read your
# files or reach the network. GIMP sees ~/Pictures (to open and save in),
# ~/Downloads (to open from, read-only), its own settings (~/.config/GIMP),
# the files you name when you start it (read-only), and your screen; nothing
# else, and no network. Its menu entry starts the sandboxed one too.
# Usage: bash gimp.sh [--remove | --manual]
# summary: GIMP image editor, in a sandbox
# security: most
# status: apt:gimp bin:gimp
# files: bin/no-abstract-sockets
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

# Debian's menu entry starts gimp-3.0 itself; this one, of the same name,
# starts the sandboxed gimp (yours win over the system's)
ENTRY="${XDG_DATA_HOME:-$HOME/.local/share}/applications/gimp.desktop"
MARK='# Written by Wren Linux extras/gimp.sh'

if [ "${1:-}" = --remove ]; then
    remove_bin gimp
    if grep -qxF "$MARK" "$ENTRY" 2>/dev/null; then rm -f "$ENTRY"; fi
    # the media and PDF extras, and incognito, use the sandbox too
    if [ ! -f "$BIN/imv" ] && [ ! -f "$BIN/mpv" ] && [ ! -f "$BIN/zathura" ]; then
        remove_bin media-sandbox
    fi
    remove_wayland_restrict
    remove_no_abstract
    apt_purge gimp bubblewrap
    note "Your GIMP settings stay in ~/.config/GIMP, your pictures in ~/Pictures."
    exit
fi

say "Installing GIMP"
# python3: wayland-restrict, the restricted Wayland socket
apt_install gimp bubblewrap python3
install_bin wayland-restrict
install_bin media-sandbox
install_no_abstract
install_bin gimp
mkdir -p "$HOME/Pictures" "$HOME/.config/GIMP"
if [ -f /usr/share/applications/gimp.desktop ]; then
    mkdir -p "${ENTRY%/*}"
    { echo "$MARK"
      sed -e "s|^Exec=gimp-3.0|Exec=$BIN/gimp|" -e "s|^TryExec=.*|TryExec=$BIN/gimp|" /usr/share/applications/gimp.desktop
    } >"$ENTRY"
fi

cat <<'EOF2'

    GIMP runs in a sandbox: no network, and of your files only ~/Pictures
    (open and save there), ~/Downloads (open from) and the files you name.
    Save your work into ~/Pictures: elsewhere, saving fails. Starting it by
    its full path (/usr/bin/gimp-3.0) skips the sandbox; so does
    WREN_NO_SANDBOX=1.

    Run it with: gimp   (or gimp photo.jpg, or Super+d).
EOF2
