#!/bin/bash
# git, from Debian. Your name and email on commits, and how git logs in to
# push, are wrenctl git's (git-helper.sh): it asks when you run it, not during
# an install. It offers GitHub's gh, from Debian: installed only, never logged in
# here (git needs no more than a token to push; gh's login is wrenctl gh's).
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
if ask "Also install gh, GitHub's command line tool? It stays logged out until you run wrenctl gh." y; then
    apt_install gh
    note "gh is installed, and not logged in. When you want it: wrenctl gh"
else
    note "No gh. Later: wrenctl gh installs it when you want it."
fi

git config --global init.defaultBranch main
note "Your name and email on commits, and how git logs in to push (a token):"
note "  wrenctl git        (in a repository of yours, or: wrenctl git DIR)"
