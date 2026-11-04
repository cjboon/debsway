#!/bin/bash
# git, and optionally the GitHub command line tool (gh), from Debian. Your
# name and email on commits, and how git logs in to push, are git-init.sh's:
# it asks when you run it, not during an install.
# Usage: bash git.sh [--remove | --manual]
# summary: git, and optionally GitHub's gh
# security: some
# status: apt:git apt:gh
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

if [ "${1:-}" = --remove ]; then
    apt_purge gh git
    note "Your settings stay in ~/.gitconfig and ~/.config/gh."
    exit
fi

say "Installing git"
pkgs=(git)
if auto_or_ask WREN_SETUP_GH "Also install gh, GitHub's command line tool?" n; then pkgs+=(gh); fi
apt_install "${pkgs[@]}"

git config --global init.defaultBranch main
note "Your name and email on commits, and how git logs in to push (a token, or gh):"
note "  bash $WREN_DIR/git-init.sh        (for any repository of yours: bash $WREN_DIR/git-init.sh DIR)"
