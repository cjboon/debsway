#!/bin/bash
# Claude Code as your own user, set up to be easy and still careful: in any
# folder you start it from, with your tools, and none of the sandboxed claude's
# walls (extras/claude-code.sh puts it in a user of its own; claude-vm.sh in a VM).
#  - From Anthropic's signed apt repository (the key must be ANTHROPIC_FPR in
#    pins.sh), shared with extras/claude-code.sh (lib/claude-repo.sh): removing
#    one keeps the other's updates. unattended-upgrades updates it.
#  - Claude Code's own sandbox is on: the shell commands it runs are inside
#    bubblewrap, may write only in the folder you started it in (and a temp
#    folder), and can't read your ssh and gpg keys, passwords, browser profiles
#    or wallets. Sandboxed commands run without asking each time.
#  - Its file tools are kept from the same files, and from changing what runs
#    at login (~/.profile, sway, systemd, ~/.local/bin); it may not run sudo.
#  - These go into your ~/.claude/settings.json next to your own settings
#    (data/claude-regular-settings.json); --remove takes out only what it added.
# claude-regular runs it; so does claude, unless extras/claude-code.sh is set up
# (then claude is the sandboxed one).
# Usage: bash claude-regular.sh [--remove | --manual]
# summary: Claude Code as you, with its own sandbox on
# security: least
# status: bin:claude-regular
# files: data/claude-regular-settings.json lib/claude-settings.py
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$DEBSWAY_DIR/lib/claude-repo.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

SETTINGS=$HOME/.claude/settings.json
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/debsway/claude-regular-settings.json
merge() { python3 -I "$DEBSWAY_DIR/lib/claude-settings.py" "$1" "$SETTINGS" "$DEBSWAY_DIR/data/claude-regular-settings.json" "$STATE"; }

if [ "${1:-}" = --remove ]; then
    remove_bin claude-regular
    if [ -f "$STATE" ]; then merge remove && note "Took debsway's settings out of $SETTINGS; yours stay."; fi
    # claude-code itself stays while the sandboxed claude needs it
    apt_purge claude-code
    remove_claude_repo_if_unused
    note "Your Claude login and settings stay in ~/.claude."
    exit
fi

say "Claude Code apt repository"
add_claude_repo
say "Installing Claude Code"
# bubblewrap and socat: Claude Code's sandbox for the commands it runs;
# git and ripgrep: what it uses day to day; python3: the settings merge
apt_install claude-code bubblewrap socat git ripgrep python3
install_bin claude-regular

say "Claude Code's settings"
merge add || die "Couldn't write $SETTINGS; nothing of yours was changed."
note "Its sandbox is on, and it is kept from your keys, passwords and wallets ($SETTINGS)."

if [ -e "$CLAUDE_SANDBOX_MARK" ]; then
    note "Run it with: claude-regular   (claude is the sandboxed one, as its own user)"
else
    note "Run it with: claude   (or claude-regular), in the folder of your project"
fi
note "The first time, it shows a login link: open it in your browser."
