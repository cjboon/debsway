#!/bin/bash
# Claude Code (Anthropic's coding assistant for the terminal), from
# Anthropic's signed apt repository. The repository key is only trusted
# if it is exactly the key with fingerprint ANTHROPIC_FPR (pins.sh), as
# published at code.claude.com/docs/en/setup. unattended-upgrades updates
# it along with Debian's packages.
# Usage: bash claude-code.sh [--remove]
# summary: Claude Code, Anthropic's coding assistant
# status: apt:claude-code
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

KEY=/etc/apt/keyrings/claude-code.asc
LIST=/etc/apt/sources.list.d/claude-code.list

if [ "${1:-}" = --remove ]; then
    apt_purge claude-code
    sudo rm -f "$LIST" "$KEY"
    forget_unattended_updates claude-code
    note "Removed Claude Code and its apt repository. Your settings stay in ~/.claude."
    exit
fi

say "Claude Code apt repository"
install_apt_key "$ANTHROPIC_FPR" "$ANTHROPIC_KEY_URL" "$KEY"
echo "deb [signed-by=$KEY] https://downloads.claude.ai/claude-code/apt/stable stable main" |
    sudo tee "$LIST" >/dev/null
allow_unattended_updates claude-code downloads.claude.ai
# A fresh update, so apt sees the new repository
unset DEBSWAY_APT_UPDATED

say "Installing Claude Code"
apt_install claude-code
note "Run it in a project folder with: claude"
