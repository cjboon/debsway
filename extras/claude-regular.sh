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
# Another account (a second Claude login): --account NAME gives it its own
# settings folder, ~/.claude-NAME (its login, memories and settings; Claude
# Code's CLAUDE_CONFIG_DIR), with the same settings as above; claude-regular
# --account NAME runs it. Its file tools and sandboxed commands are kept from
# ~/.claude, and the first account's from ~/.claude-NAME. Those are Claude
# Code's own rules, not a wall: both run as you, so either could still get at
# the other's folder another way, and two extra accounts aren't kept from each
# other. For accounts that really can't see each other, use the sandboxed
# claude (extras/claude-code.sh --account) or claude-vm (--account).
# --remove-account NAME takes Wren Linux's settings out again (asks before
# deleting its login and memories).
# Usage: bash claude-regular.sh [--remove | --manual | --account NAME | --remove-account NAME]
# summary: Claude Code as you, with its own sandbox on
# security: least
# status: bin:claude-regular
# files: data/claude-regular-settings.json lib/claude-settings.py
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$WREN_DIR/lib/claude-repo.sh"
. "$WREN_DIR/lib/claude-accounts.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

SETTINGS=$HOME/.claude/settings.json
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/wren/claude-regular-settings.json
merge() { python3 -I "$WREN_DIR/lib/claude-settings.py" "$1" "$SETTINGS" "$WREN_DIR/data/claude-regular-settings.json" "$STATE"; }

# account NAME: its folder and the two state files (its own settings, and
# what was added to the first account's to keep it out)
account() {
    [[ $1 =~ ^[a-z][a-z0-9]{0,14}$ ]] || die "An account name is small letters and digits, a letter first, at most 15 (e.g. work)."
    ACCOUNT_DIR=$HOME/.claude-$1
    ACCOUNT_STATE=${STATE%.json}-$1.json
    MAIN_STATE=${STATE%.json}-$1-first.json
}
# keep_out DIR: Claude Code settings that keep file tools and sandboxed
# commands from DIR
keep_out() {
    printf '{ "sandbox": { "filesystem": { "denyRead": ["%s"] } },\n  "permissions": { "deny": ["Read(%s/**)", "Edit(%s/**)"] } }\n' "$1" "$1" "$1"
}
remove_account() {
    account "$1"
    [ ! -f "$MAIN_STATE" ] || python3 -I "$WREN_DIR/lib/claude-settings.py" remove "$SETTINGS" /dev/null "$MAIN_STATE" || true
    [ ! -f "$ACCOUNT_STATE" ] || python3 -I "$WREN_DIR/lib/claude-settings.py" remove "$ACCOUNT_DIR/settings.json" /dev/null "$ACCOUNT_STATE" || true
    rm -f "$MAIN_STATE" "$ACCOUNT_STATE"
    if [ -d "$ACCOUNT_DIR" ] && ask "Delete $ACCOUNT_DIR (that account's Claude login, memories and settings)?" n; then
        rm -rf "${ACCOUNT_DIR:?}"
        note "Deleted $ACCOUNT_DIR."
    elif [ -d "$ACCOUNT_DIR" ]; then
        note "Kept $ACCOUNT_DIR."
    fi
}

if [ "${1:-}" = --account ] || [ "${1:-}" = --remove-account ]; then
    [ -n "${2:-}" ] || die "Usage: bash claude-regular.sh $1 NAME"
    account "$2"
    if [ "$1" = --remove-account ]; then
        remove_account "$2"
        note "The account $2 is gone from Wren Linux's settings."
        exit
    fi
    [ -x "$BIN/claude-regular" ] || die "Set up claude-regular first: bash $WREN_DIR/extras/claude-regular.sh"
    mkdir -p "$ACCOUNT_DIR"
    chmod 700 "$ACCOUNT_DIR"
    ours=$(mktemp)
    # Wren Linux's settings, and ~/.claude kept out
    # shellcheck disable=SC2088  # a literal ~: Claude Code's settings expand it themselves
    python3 -I -c 'import json, sys
a = json.load(open(sys.argv[1])); b = json.loads(sys.argv[2])
a["sandbox"]["filesystem"]["denyRead"] += b["sandbox"]["filesystem"]["denyRead"]
a["permissions"]["deny"] += b["permissions"]["deny"]
json.dump(a, open(sys.argv[3], "w"), indent=2)' "$WREN_DIR/data/claude-regular-settings.json" "$(keep_out "~/.claude")" "$ours" ||
        { rm -f "$ours"; die "Couldn't make the account's settings."; }
    python3 -I "$WREN_DIR/lib/claude-settings.py" add "$ACCOUNT_DIR/settings.json" "$ours" "$ACCOUNT_STATE" ||
        { rm -f "$ours"; die "Couldn't write $ACCOUNT_DIR/settings.json."; }
    # and the first account kept out of this one's folder
    # shellcheck disable=SC2088  # a literal ~: Claude Code's settings expand it themselves
    keep_out "~/.claude-$2" >"$ours"
    python3 -I "$WREN_DIR/lib/claude-settings.py" add "$SETTINGS" "$ours" "$MAIN_STATE" ||
        { rm -f "$ours"; die "Couldn't write $SETTINGS."; }
    rm -f "$ours"
    note "claude-regular --account $2: its own login and memories in ~/.claude-$2."
    note "Both run as you: Claude Code's rules keep them out of each other's folder, not a wall."
    note "The first time, it shows a login link: log in with the other account."
    exit
fi

if [ "${1:-}" = --remove ]; then
    # the other accounts first, each with its own question
    for st in "${STATE%.json}"-*-first.json; do
        [ -f "$st" ] || continue
        n=${st##*/claude-regular-settings-}
        remove_account "${n%-first.json}"
    done
    remove_bin claude-regular
    remove_claude_chooser
    if [ -f "$STATE" ]; then merge remove && note "Took Wren Linux's settings out of $SETTINGS; yours stay."; fi
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
install_bin claude

say "Claude Code's settings"
merge add || die "Couldn't write $SETTINGS; nothing of yours was changed."
note "Its sandbox is on, and it is kept from your keys, passwords and wallets ($SETTINGS)."

if [ -e "$CLAUDE_SANDBOX_MARK" ]; then
    note "Run it with: claude-regular   (claude asks which one, and starts the sandboxed one on Enter)"
else
    note "Run it with: claude   (or claude-regular), in the folder of your project"
fi
note "The first time, it shows sign-in links. The sandboxed Firefox can't finish the one that"
note "comes back to this computer (localhost): if it says it can't connect, open the link"
note "printed in the terminal, and paste the code it gives you."
