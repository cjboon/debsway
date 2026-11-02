#!/bin/bash
# w3m, a web browser that runs inside the terminal. No JavaScript, no
# plugins, no images in foot: good for reading pages, documentation and
# search results, and a way to get a page when nothing else is installed.
# Cookies last only while it is open: the w3m command debsway puts in
# ~/.local/bin (bin/w3m) deletes the ones w3m keeps (~/.w3m/cookie) when it
# starts and when it ends, so no site recognises you the next time.
# Usage: bash w3m.sh [--remove | --manual]
# summary: w3m, a text-mode web browser for the terminal
# security: some
# status: apt:w3m bin:w3m
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

if [ "${1:-}" = --remove ]; then
    remove_bin w3m
    apt_purge w3m
    note "Your w3m settings stay in ~/.w3m."
    exit
fi

say "Installing w3m"
apt_install w3m
# cookies only while it is open
install_bin w3m

cat <<'EOF'

    How to use w3m:
      w3m https://example.org        open a page
      w3m duckduckgo.com             addresses without https:// work too
    Keys: arrows or j/k scroll, Space/b page down/up, Tab next link,
          Enter follow the link, B back, U type an address, / search,
          T new tab, q quit.
    It runs no JavaScript, so most of what makes pages dangerous or
    tracking-heavy isn't there; sites that need JavaScript won't work.
    Cookies last only while it is open: none are kept for next time
    (w3m -no-cookie: none at all, for one run).
EOF
