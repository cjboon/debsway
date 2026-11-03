# shellcheck shell=bash
# Second (third...) accounts of the sandboxed Claude Code (extras/claude-code.sh
# --account NAME): each its own locked user, claude-agent-NAME, with its own
# home (login, settings, memories) and its own folder, ~/projects-NAME, so two
# accounts can't read each other's. Sourced by extras/claude-code.sh.

CLAUDE_ACCOUNT_PREFIX=claude-agent-

# claude_account_valid NAME: a short name (small letters and digits, a letter
# first), so the user name stays within limits and can't be mistaken for
# anything else
claude_account_valid() { [[ $1 =~ ^[a-z][a-z0-9]{0,14}$ ]]; }

# claude_account_users: the account users on this computer, one per line
# (DEBSWAY_PASSWD: a passwd file to read instead, for tests)
claude_account_users() {
    if [ -n "${DEBSWAY_PASSWD:-}" ]; then cat "$DEBSWAY_PASSWD"; else getent passwd; fi |
        awk -F: -v p="$CLAUDE_ACCOUNT_PREFIX" 'index($1, p) == 1 && substr($1, length(p) + 1) ~ /^[a-z][a-z0-9]*$/ { print $1 ":" $3 }'
}

# claude_firewall_text RULES: the firewall rules (data/claude-firewall.nft)
# with a line for each account user after claude-agent's. By number, not name:
# nft refuses the whole file over a user that doesn't exist (one deleted by
# hand), and claude-agent would then be left without its rule at boot. A
# number never fails; if it is given to a new user later, that user is
# kept off the network too until the accounts change again.
claude_firewall_text() {
    local line user uid
    while IFS= read -r line; do
        printf '%s\n' "$line"
        if [[ $line =~ ^[[:space:]]*meta\ skuid\ \"claude-agent\"\ jump\ claude$ ]]; then
            while IFS=: read -r user uid; do
                [[ $uid =~ ^[0-9]+$ ]] || continue
                printf '        meta skuid %s jump claude  # %s\n' "$uid" "$user"
            done < <(claude_account_users)
        fi
    done <"$1"
}
