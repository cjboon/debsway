# shellcheck shell=bash
# lib/claude-repo.sh: Anthropic's apt repository for Claude Code, shared by
# extras/claude-code.sh (the sandboxed claude) and extras/claude-regular.sh
# (Claude Code as you). Sourced after lib.sh. The repository key is only trusted
# if it is exactly ANTHROPIC_FPR (pins.sh). The repository goes only when
# neither extra is set up any more, so removing one never stops the other's updates.

CLAUDE_KEY=/etc/apt/keyrings/claude-code.asc
CLAUDE_LIST=/etc/apt/sources.list.d/claude-code.list
# What each extra leaves while it is set up
CLAUDE_SANDBOX_MARK=/usr/local/libexec/claude-session
CLAUDE_REGULAR_MARK=$HOME/.local/bin/claude-regular

add_claude_repo() {
    install_apt_key "$ANTHROPIC_FPR" "$ANTHROPIC_KEY_URL" "$CLAUDE_KEY"
    echo "deb [signed-by=$CLAUDE_KEY] https://downloads.claude.ai/claude-code/apt/stable stable main" |
        $SUDO tee "$CLAUDE_LIST" >/dev/null
    allow_unattended_updates claude-code downloads.claude.ai
    # A fresh update, so apt sees the repository
    unset DEBSWAY_APT_UPDATED
}

# remove_claude_repo_if_unused: called by each extra's --remove, after it has
# taken out what marks it as set up
remove_claude_repo_if_unused() {
    [ -e "$CLAUDE_SANDBOX_MARK" ] || [ -e "$CLAUDE_REGULAR_MARK" ] && return 0
    $SUDO rm -f "$CLAUDE_LIST" "$CLAUDE_KEY"
    forget_unattended_updates claude-code
    note "Removed Anthropic's apt repository."
}
