#!/bin/bash
# git, from Debian. Your name and email on commits, and pushing to GitHub over
# ssh with a key of your own, are wrenctl git's (git-helper.sh): it asks when
# you run it, not during an install. No token, and no GitHub tool: git and ssh
# do it all.
# Usage: bash git.sh [--remove | --manual]
# summary: git, the version control system
# security: some
# status: apt:git
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

if [ "${1:-}" = --remove ]; then
    apt_purge git
    note "Your settings stay in ~/.gitconfig."
    exit
fi

say "Installing git"
apt_install git

git config --global init.defaultBranch main
note "Your name and email on commits, and pushing to GitHub over ssh with a key of your own:"
note "  wrenctl git        (in a repository of yours, or: wrenctl git DIR)"
