#!/bin/bash
# For working on Wren Linux itself, on the computer where you build its package:
# lintian, Debian's checker for packages (tools/build-deb.sh runs it on every
# package it builds), and shellcheck, which test.sh runs on every script. Both
# from Debian. Only that computer needs them: they aren't in the base install,
# which keeps every other Wren Linux computer to what it uses.
# Usage: bash wren-dev.sh [--remove | --manual]
# summary: For working on Wren Linux: lintian and shellcheck
# security: some
# status: apt:lintian
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

if [ "${1:-}" = --remove ]; then
    # (the Claude Code sandbox installs shellcheck too: it stays while that does)
    apt_purge lintian shellcheck
    exit
fi

say "Tools for working on Wren Linux"
apt_install lintian shellcheck

cat <<'EOF2'

    How to use them:
      bash test.sh                   every check, shellcheck on every script included
      bash tools/build-deb.sh        build the package; lintian checks it
      lintian FILE.deb               check any package
      shellcheck SCRIPT              check one script
EOF2
