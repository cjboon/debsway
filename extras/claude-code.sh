#!/bin/bash
# Claude Code (Anthropic's coding assistant for the terminal), from
# Anthropic's signed apt repository. The repository key is only trusted
# if its fingerprint is ANTHROPIC_FPR (pins.sh), as published at
# code.claude.com/docs/en/setup. apt keeps it updated with everything else.
# Usage: bash claude-code.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

KEY=/etc/apt/keyrings/claude-code.asc
LIST=/etc/apt/sources.list.d/claude-code.list

if [ "${1:-}" = --remove ]; then
    apt_purge claude-code
    sudo rm -f "$LIST" "$KEY"
    note "Removed Claude Code and its apt repository. Your settings stay in ~/.claude."
    exit
fi

say "Claude Code apt repository"
if [ ! -s "$KEY" ]; then
    tmp=$(mktemp)
    wget -qO "$tmp" "$ANTHROPIC_KEY_URL" || die "Couldn't download the Claude Code signing key."
    fpr=$(gpg --show-keys --with-colons "$tmp" | awk -F: '/^fpr/ { print $10; exit }')
    if [ "$fpr" != "$ANTHROPIC_FPR" ]; then
        rm -f "$tmp"
        die "Signing key fingerprint is $fpr, expected $ANTHROPIC_FPR. Not trusting it."
    fi
    sudo install -d -m 0755 /etc/apt/keyrings
    sudo install -m 0644 "$tmp" "$KEY"
    rm -f "$tmp"
    note "Key verified: $fpr"
fi
echo "deb [signed-by=$KEY] https://downloads.claude.ai/claude-code/apt/stable stable main" |
    sudo tee "$LIST" >/dev/null
# A fresh update, so apt sees the new repository
unset DEBSWAY_APT_UPDATED

say "Installing Claude Code"
apt_install claude-code
note "Run it in a project folder with: claude"
