# shellcheck shell=bash
# Second (third...) accounts of the sandboxed Claude Code (extras/claude-code.sh
# --account NAME): each its own locked user, claude-agent-NAME, with its own
# home (login, settings, memories) and its own folder, ~/projects-NAME, so two
# accounts can't read each other's. Sourced by extras/claude-code.sh, and by
# extras/claude-vm.sh for its own accounts (below).

CLAUDE_ACCOUNT_PREFIX=claude-agent-

# claude_account_valid NAME: a short name (small letters and digits, a letter
# first), so the user name stays within limits and can't be mistaken for
# anything else
claude_account_valid() { [[ $1 =~ ^[a-z][a-z0-9]{0,14}$ ]]; }

# claude_account_users [PREFIX]: the account users on this computer, as
# USER:UID, one per line (WREN_PASSWD: a passwd file to read instead, for tests)
claude_account_users() {
    if [ -n "${WREN_PASSWD:-}" ]; then cat "$WREN_PASSWD"; else getent passwd; fi |
        awk -F: -v p="${1:-$CLAUDE_ACCOUNT_PREFIX}" 'index($1, p) == 1 && substr($1, length(p) + 1) ~ /^[a-z][a-z0-9]*$/ { print $1 ":" $3 }'
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

# ---- Accounts of claude-vm (extras/claude-vm.sh --account NAME): each its own
# locked user, claude-vm-NAME, with its own VM (disk, keys, Claude login) in
# its home, and its own SSH console port on 127.0.0.1, which only that user
# may reach. The ports are kept where only root can write
# (WREN_CLAUDE_VM_PORTS: another file, for tests): one "NAME PORT" a line.

CLAUDE_VM_PREFIX=claude-vm-
CLAUDE_VM_PORTS=${WREN_CLAUDE_VM_PORTS:-/etc/wren/claude-vm-ports}

# claude_vm_port NAME: its port, or nothing
claude_vm_port() {
    awk -v n="$1" '$1 == n && $2 ~ /^[0-9]+$/ && $2 >= 2250 && $2 <= 2299 { print $2; exit }' "$CLAUDE_VM_PORTS" 2>/dev/null
}

# claude_vm_free_port: the lowest of 2250-2299 that no account has and nothing
# listens on (2242 is claude-vm's own, 2244 opencode-vm's)
claude_vm_free_port() {
    local p used
    used=$(awk '{ print $2 }' "$CLAUDE_VM_PORTS" 2>/dev/null; ss -Hltn 2>/dev/null | awk '{ n = split($4, a, ":"); print a[n] }')
    for ((p = 2250; p <= 2299; p++)); do
        grep -qx "$p" <<<"$used" || { echo "$p"; return 0; }
    done
    return 1
}

# claude_vm_firewall_text RULES: data/claude-vm-firewall.nft with, for each
# account user, a line sending it through the same rules and one letting it
# reach its own console port (none without a port: then it reaches none)
claude_vm_firewall_text() {
    local line user uid port
    while IFS= read -r line; do
        printf '%s\n' "$line"
        if [[ $line =~ ^[[:space:]]*meta\ skuid\ \"claude-vm\"\ jump\ claude_vm$ ]]; then
            while IFS=: read -r user uid; do
                [[ $uid =~ ^[0-9]+$ ]] && printf '        meta skuid %s jump claude_vm  # %s\n' "$uid" "$user"
            done < <(claude_account_users "$CLAUDE_VM_PREFIX")
        elif [[ $line =~ ^[[:space:]]*meta\ skuid\ \"claude-vm\"\ ip\ daddr\ 127\.0\.0\.1\ tcp\ dport\ 2242\ accept$ ]]; then
            while IFS=: read -r user uid; do
                port=$(claude_vm_port "${user#"$CLAUDE_VM_PREFIX"}")
                [[ $uid =~ ^[0-9]+$ ]] && [ -n "$port" ] &&
                    printf '        meta skuid %s ip daddr 127.0.0.1 tcp dport %s accept  # %s\n' "$uid" "$port" "$user"
            done < <(claude_account_users "$CLAUDE_VM_PREFIX")
        fi
    done <"$1"
}

# remove_claude_chooser: the claude command goes with the last way it can start
remove_claude_chooser() {
    local c
    for c in claude-vm claude-sandbox claude-regular; do
        [ ! -e "$BIN/$c" ] || return 0
    done
    remove_bin claude
}
