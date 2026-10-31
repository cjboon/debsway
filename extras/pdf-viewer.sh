#!/bin/bash
# zathura, a small keyboard-driven PDF viewer (it also opens PostScript and
# DjVu if you add their plugins), from Debian. A PDF is a program-sized file
# that a viewer has to interpret, and crafted ones are a common way in, so
# zathura starts inside bubblewrap (bin/media-sandbox, the same sandbox as imv
# and mpv): it sees only the files you open, read-only, has no network and an
# empty home. DEBSWAY_NO_SANDBOX=1 runs it without. Made the default for PDFs.
# Usage: bash pdf-viewer.sh [--remove]
# summary: zathura PDF viewer, in a sandbox
# status: apt:zathura apt:zathura-pdf-poppler bin:zathura
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    remove_bin zathura
    unset_default_app org.pwmt.zathura.desktop
    # the media extra and incognito need the sandbox too
    if [ ! -f "$BIN/imv" ] && [ ! -f "$BIN/mpv" ]; then
        remove_bin media-sandbox
        [ -x /usr/local/bin/incognito ] || remove_bin wayland-restrict
    fi
    apt_purge zathura zathura-pdf-poppler bubblewrap
    exit
fi

say "Installing zathura"
apt_install zathura zathura-pdf-poppler bubblewrap python3
install_bin wayland-restrict
install_bin media-sandbox
install_bin zathura
set_default_app org.pwmt.zathura.desktop application/pdf

cat <<'EOF2'

    zathura runs in a sandbox: it sees only the files you name when you
    start it, read-only. Starting it by its full path (/usr/bin/zathura), or
    from a launcher that does, skips the sandbox; so does DEBSWAY_NO_SANDBOX=1.

    How to use zathura:
      zathura paper.pdf              open a PDF
      zathura -P 5 paper.pdf         open at page 5
    Keys: j/k or arrows scroll, Space / b page down / up, J / K next / previous
          page, gg / G first / last page, 5G page 5, + / - zoom, a fit page,
          s fit width, d two pages, / search (n next), Tab table of contents,
          r rotate, F11 fullscreen, q quit
EOF2
