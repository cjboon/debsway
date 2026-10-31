#!/bin/bash
# w3m, a web browser that runs inside the terminal. No JavaScript, no
# plugins, no images in foot: good for reading pages, documentation and
# search results, and a way to get a page when nothing else is installed.
# Usage: bash w3m.sh [--remove]
# summary: w3m, a text-mode web browser for the terminal
# status: apt:w3m
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    apt_purge w3m
    note "Your w3m settings and cookies stay in ~/.w3m."
    exit
fi

say "Installing w3m"
apt_install w3m

cat <<'EOF'

    How to use w3m:
      w3m https://example.org        open a page
      w3m duckduckgo.com             addresses without https:// work too
    Keys: arrows or j/k scroll, Space/b page down/up, Tab next link,
          Enter follow the link, B back, U type an address, / search,
          T new tab, q quit.
    It runs no JavaScript, so most of what makes pages dangerous or
    tracking-heavy isn't there; sites that need JavaScript won't work.
EOF
