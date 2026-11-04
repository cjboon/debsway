#!/bin/bash
# For working on Wren Linux itself, on the computer where you build its package:
# lintian, Debian's checker for packages (tools/build-deb.sh runs it on every
# package it builds), and shellcheck, which test.sh runs on every script. Both
# from Debian. Only that computer needs them: they aren't in the base install,
# which keeps every other Wren Linux computer to what it uses. And a git copy of
# Wren Linux in ~/wren-linux, if you have none: the package leaves out the tests,
# the build tools, the plans and the signing key's tools, and they are in it.
# Usage: bash wren-dev.sh [--remove | --manual]
# summary: For working on Wren Linux: tools, a git copy
# security: some
# status: apt:lintian
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$WREN_DIR/lib/appimage.sh"
. "$WREN_DIR/lib/update.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

DEV=$HOME/wren-linux

if [ "${1:-}" = --remove ]; then
    # (the Claude Code sandbox installs shellcheck too: it stays while that does)
    apt_purge lintian shellcheck git
    if [ -d "$DEV/.git" ]; then note "Your copy in $DEV stays: it may hold work of yours."; fi
    exit
fi

say "Tools for working on Wren Linux"
apt_install lintian shellcheck git

say "A copy of Wren Linux to work on"
if git -C "$WREN_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    DEV=$WREN_DIR
    note "This is one: $DEV"
elif [ -d "$DEV/.git" ]; then
    note "You have one: $DEV"
elif [ -e "$DEV" ]; then
    warn "$DEV is there and isn't a git copy, so it was left alone and nothing was fetched."
else
    tmp=$(mktemp -d "$HOME/.wren-linux.XXXXXX")
    trap 'rm -rf "$tmp"' EXIT
    git clone --quiet "$WREN_GIT_URL" "$tmp/copy" || die "Couldn't fetch $WREN_GIT_URL; nothing was left behind."
    # Before it is there to run: only what Wren Linux's own key signed, once one is pinned
    if [ -n "${WREN_SIGNING_FPR:-}" ]; then
        # (the key comes from this copy, never from what was fetched)
        GIT_DIR=$tmp/copy/.git update_signed HEAD ||
            die "What $WREN_GIT_URL gives isn't signed by Wren Linux's key ($WREN_SIGNING_FPR); nothing was left behind."
        note "Its newest commit is signed by Wren Linux's key."
    else
        note "(Its signature is not checked: no signing key is pinned in pins.sh yet. Read before you run.)"
    fi
    mv "$tmp/copy" "$DEV"
    note "Fetched it into $DEV."
fi

cat <<EOF2

    How to use them, in $DEV:
      bash test.sh                   every check, shellcheck on every script included
      bash extras/signing-key.sh     the key to sign Wren Linux with, if you publish it
      bash tools/git-push.sh         publish: signs, checks, asks, pushes
      bash tools/build-deb.sh        build the package; lintian checks it
      lintian FILE.deb               check any package
      shellcheck SCRIPT              check one script
EOF2
