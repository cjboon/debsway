#!/bin/bash
# vim with colors for every programming language it knows (shell, Python, C,
# JavaScript, HTML, Markdown...): Debian's full vim, instead of the vim-tiny
# that comes with Debian, which has no colors at all. It writes ~/.vimrc
# (data/vimrc) unless you have one of your own: colors and indenting by file
# type, light or dark as debsway's theme is, search highlighting, line
# numbers, and modelines off (settings hidden in a file you open, which
# crafted files have used to run commands).
# Usage: bash vim.sh [--remove | --manual]
# summary: vim, with colors for each programming language
# security: most
# status: apt:vim
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

VIMRC=$HOME/.vimrc
MARK='" Written by debsway extras/vim.sh'
# ours: the vimrc's first line still says debsway wrote it
ours() { head -1 "$VIMRC" 2>/dev/null | grep -qF "$MARK"; }

if [ "${1:-}" = --remove ]; then
    if ours; then rm -f "$VIMRC"; fi
    apt_purge vim
    note "vim-tiny, Debian's own small vim, stays: vi and vim still start it (without colors)."
    exit
fi

say "Installing vim"
apt_install vim
if [ ! -e "$VIMRC" ] || ours; then
    install -m 0644 "$DEBSWAY_DIR/data/vimrc" "$VIMRC"
    note "Wrote $VIMRC: colors by language, light or dark with the theme, modelines off."
else
    note "Keeping your own $VIMRC. For the colors, it needs: syntax on"
    note "and: filetype plugin indent on  ($DEBSWAY_DIR/data/vimrc has debsway's whole set)."
fi
note "Run it with: vim FILE   (vi does the same). :q quits, :wq saves and quits."
