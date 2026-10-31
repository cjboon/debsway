#!/bin/bash
# git, and optionally the GitHub command line tool (gh), from Debian.
# Asks for the name and email to put on your commits, and offers to log
# in to GitHub.
# Usage: bash git.sh [--remove]
# summary: git, and optionally GitHub's gh
# status: apt:git apt:gh
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    apt_purge gh git
    note "Your settings stay in ~/.gitconfig and ~/.config/gh."
    exit
fi

say "Installing git"
pkgs=(git)
if auto_or_ask DEBSWAY_SETUP_GH "Also install gh, GitHub's command line tool?" n; then pkgs+=(gh); fi
apt_install "${pkgs[@]}"

if [ -z "$(git config --global user.name || true)" ]; then
    tty_read name "Your name for git commits (Enter to skip): "
    [ -z "$name" ] || git config --global user.name "$name"
fi
if [ -z "$(git config --global user.email || true)" ]; then
    tty_read email "Your email for git commits (Enter to skip): "
    [ -z "$email" ] || git config --global user.email "$email"
fi
git config --global init.defaultBranch main

if command -v gh >/dev/null; then
    if gh auth status >/dev/null 2>&1; then
        note "Already logged in to GitHub."
    elif auto_or_ask DEBSWAY_GH_LOGIN "Log in to GitHub now? (shows a code to enter at github.com/login/device)" n; then
        gh auth login --hostname github.com --git-protocol https
        gh auth setup-git
    else
        note "Later: gh auth login && gh auth setup-git"
    fi
fi
