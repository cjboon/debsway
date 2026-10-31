#!/bin/bash
# Claude Code (Anthropic's coding assistant for the terminal), from
# Anthropic's signed apt repository. The repository key is only trusted
# if it is exactly the key with fingerprint ANTHROPIC_FPR (pins.sh), as
# published at code.claude.com/docs/en/setup. unattended-upgrades updates
# it along with Debian's packages.
# The claude command runs it as its own user, claude-agent, not as you:
#  - claude-agent has no password and no login. Its home folder
#    (/home/claude-agent) holds its own Claude login, settings and, if you
#    give it any, its own ssh keys and git settings. It can't read your home
#    folder, your ssh keys, your passwords or your browser profiles.
#  - It works in ~/projects, which you share with it: anything it creates
#    there you can read and change, and the other way round. It may pass
#    through your home folder to get there, but not look inside it.
#  - Your user may run exactly one thing as claude-agent: the small script
#    that starts Claude Code (a rule in /etc/sudoers.d). Run claude from a
#    folder inside ~/projects.
#  - A firewall rule that matches only that user keeps it off your computer
#    and local network (your router, printers, programs on this machine):
#    it can reach the internet, nothing else. It is loaded at every boot.
#  - It gets its own ssh key and git identity (never yours), and the tools
#    a shell-and-git workflow wants (git, ssh, ripgrep, jq, shellcheck, python venv),
#    all from Debian's signed packages. Nothing is downloaded and run as a script.
#  - A short note in its home (CLAUDE.md) tells it how this is set up, including
#    what to tell you about git's "dubious ownership" warning.
#  - It can change any file in ~/projects, .git folders too, so your own git
#    gets a guard there (bin/git): before git runs in a repository under
#    ~/projects it checks .git/config and .git/hooks for anything that could
#    run a program as you, and refuses if it finds some. A repository the agent
#    made is then trusted for that command, so there is no "dubious ownership".
#  - claude-unsandboxed starts Claude Code as you, with all your files.
# This is the lighter of the two Claude Code sandboxes: it shares your
# computer's kernel. If this computer supports KVM, extras/claude-vm.sh puts
# the agent in a VM instead, which is the stronger wall (docs/extras.md).
# Use this one when KVM isn't available, or you want the light setup.
# What it still shares with you: the internet, and anything in ~/projects.
# Treat what it leaves there as untrusted before you run it. See THREAT-MODEL.md.
# Usage: bash claude-code.sh [--remove]
# summary: Claude Code, sandboxed in its own user
# files: bin/no-abstract-sockets
# status: apt:claude-code bin:claude bin:claude-unsandboxed bin:git file:/usr/local/libexec/claude-session
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

AGENT=claude-agent
AGENT_HOME=/home/$AGENT
SESSION=/usr/local/libexec/claude-session
SUDOERS=/etc/sudoers.d/debsway-claude
FIREWALL=/etc/debsway/claude.nft
UNIT=/etc/systemd/system/debsway-claude-firewall.service
PROJECTS=$HOME/projects
KEY=/etc/apt/keyrings/claude-code.asc
LIST=/etc/apt/sources.list.d/claude-code.list

if [ "${1:-}" = --remove ]; then
    remove_bin claude
    remove_bin claude-unsandboxed
    # claude-pull is shared with extras/claude-vm.sh; keep it if that sandbox
    # is still set up (its session wrapper is the tell)
    [ -e /usr/local/libexec/claude-vm-session ] || remove_bin claude-pull
    remove_bin git
    sudo systemctl disable --now debsway-claude-firewall.service >/dev/null 2>&1 || true
    sudo nft delete table inet debsway_claude 2>/dev/null || true
    sudo rm -f "$SUDOERS" "$SESSION" "$FIREWALL" "$UNIT"
    remove_no_abstract
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo rmdir /usr/local/libexec /etc/debsway 2>/dev/null || true
    # take back what it was allowed to reach
    if command -v setfacl >/dev/null; then
        setfacl -x "u:$AGENT" "$HOME" 2>/dev/null || true
        [ -d "$PROJECTS" ] && setfacl -R -x "u:$AGENT,d:u:$AGENT" "$PROJECTS" 2>/dev/null
    fi
    if id "$AGENT" >/dev/null 2>&1; then
        if ask "Delete the user $AGENT and its home folder $AGENT_HOME (its Claude login, ssh keys and settings)?" n; then
            sudo pkill -KILL -u "$AGENT" 2>/dev/null || true
            # whatever it made in ~/projects becomes yours
            [ -d "$PROJECTS" ] && sudo find "$PROJECTS" -user "$AGENT" -exec chown -h "$(id -un):$(id -gn)" {} +
            sudo userdel -r "$AGENT" 2>/dev/null || sudo userdel "$AGENT"
            note "Removed the user $AGENT."
        else
            note "Kept the user $AGENT and $AGENT_HOME."
        fi
    fi
    apt_purge claude-code acl nftables ripgrep jq shellcheck python3-venv
    sudo rm -f "$LIST" "$KEY"
    forget_unattended_updates claude-code
    note "Removed Claude Code and its apt repository. Your own settings stay in ~/.claude, and ~/projects is untouched."
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
# acl: lets claude-agent into ~/projects without opening your home folder
# nftables: the rule that keeps claude-agent off your local network
# the rest: what it uses day to day (it can't install anything itself)
apt_install claude-code acl nftables git openssh-client ripgrep jq shellcheck python3-venv

say "The $AGENT user"
if ! id "$AGENT" >/dev/null 2>&1; then
    sudo useradd --create-home --home-dir "$AGENT_HOME" --shell /bin/bash --user-group \
        --comment "debsway Claude Code" "$AGENT"
fi
# No password, so nobody can log in as it; only the sudo rule below starts anything
sudo usermod --lock "$AGENT"
sudo chmod 700 "$AGENT_HOME"
note "$AGENT: no password, no login, and no group but its own."

# Its own notes and git settings. Git there trusts any folder: the repositories
# it will meet in ~/projects are yours or its own, and the risk git guards
# against (hooks planted by another user) runs the other way, from it to you
agent_file() { # SOURCE DESTINATION [MODE]: as claude-agent, unless you changed it
    if ! sudo test -e "$2" || sudo grep -qis 'written by debsway' "$2"; then
        sudo install -D -o "$AGENT" -g "$AGENT" -m "${3:-0644}" "$1" "$2"
    else
        note "Kept your $2"
    fi
}
sudo install -d -o "$AGENT" -g "$AGENT" -m 0700 "$AGENT_HOME/.claude"
agent_file "$DEBSWAY_DIR/data/claude-agent-CLAUDE.md" "$AGENT_HOME/.claude/CLAUDE.md"
gitconfig=$(mktemp)
printf '# Written by debsway extras/claude-code.sh\n[user]\n\tname = Claude\n\temail = noreply@anthropic.com\n[init]\n\tdefaultBranch = main\n[safe]\n\tdirectory = *\n' >"$gitconfig"
agent_file "$gitconfig" "$AGENT_HOME/.gitconfig"
rm -f "$gitconfig"

say "Its own ssh key"
sudo install -d -o "$AGENT" -g "$AGENT" -m 0700 "$AGENT_HOME/.ssh"
if ! sudo test -e "$AGENT_HOME/.ssh/id_ed25519"; then
    # no passphrase: it has to be able to use the key by itself
    sudo -u "$AGENT" -H bash -c 'cd && ssh-keygen -q -t ed25519 -N "" -C "claude-agent@$(hostname)" -f .ssh/id_ed25519'
    note "Made its ssh key."
else
    note "It already has an ssh key."
fi
# GitHub's own list of its host keys, over https, so the first push doesn't have to guess
if ! sudo test -e "$AGENT_HOME/.ssh/known_hosts"; then
    if command -v python3 >/dev/null &&
        hosts=$(curl -fsS --max-time 20 https://api.github.com/meta 2>/dev/null |
            python3 -c 'import json,sys; [print("github.com " + k) for k in json.load(sys.stdin)["ssh_keys"]]' 2>/dev/null) &&
        [ -n "$hosts" ]; then
        known=$(mktemp)
        printf '%s\n' "$hosts" >"$known"
        sudo install -o "$AGENT" -g "$AGENT" -m 0644 "$known" "$AGENT_HOME/.ssh/known_hosts"
        rm -f "$known"
        note "Wrote GitHub's host keys to its known_hosts."
    else
        warn "Couldn't fetch GitHub's host keys; the first ssh to GitHub will ask about its key."
    fi
fi

say "Keeping $AGENT off your network"
sudo install -d -o root -g root -m 0755 "${FIREWALL%/*}"
sudo install -o root -g root -m 0644 "$DEBSWAY_DIR/data/claude-firewall.nft" "$FIREWALL"
# Loaded before the network comes up, at every boot
printf '%s\n' '# Written by debsway extras/claude-code.sh' '[Unit]' \
    'Description=Keep the claude-agent user off the local network (debsway)' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' \
    "ExecStart=/usr/sbin/nft -f $FIREWALL" \
    'ExecStop=/usr/sbin/nft delete table inet debsway_claude' '' '[Install]' \
    'WantedBy=multi-user.target' | sudo tee "$UNIT" >/dev/null
sudo systemctl daemon-reload
# Restart, not just enable --now: the unit stays "active" after it first ran,
# so a rule file changed by an update would otherwise not be loaded
sudo systemctl enable debsway-claude-firewall.service >/dev/null &&
    sudo systemctl restart debsway-claude-firewall.service ||
    warn "Couldn't load the firewall rule; check: systemctl status debsway-claude-firewall"
note "$AGENT can reach the internet, not your router, printers or your own local services."

say "The projects folder"
mkdir -p "$PROJECTS"
# It may walk through your home folder to ~/projects (not list or read it),
# and read and write in ~/projects; new files there are open to both of you
if ! { setfacl -m "u:$AGENT:--x" "$HOME" &&
    setfacl -R -m "u:$AGENT:rwX,u:$(id -un):rwX" "$PROJECTS" &&
    setfacl -R -d -m "u:$AGENT:rwX,u:$(id -un):rwX,m::rwX" "$PROJECTS"; }; then
    die "Couldn't set access on $PROJECTS (does this file system support ACLs?)."
fi
note "$PROJECTS is shared with $AGENT."

say "The claude command"
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 "$DEBSWAY_DIR/bin/claude-session" "$SESSION"
install_no_abstract
rule=$(mktemp)
printf '# Written by debsway extras/claude-code.sh. %s may run the claude-session script,\n# and nothing else, as the user %s.\n%s ALL=(%s) NOPASSWD: %s\n' \
    "$(id -un)" "$AGENT" "$(id -un)" "$AGENT" "$SESSION" >"$rule"
# A broken sudoers file locks you out of sudo, so it is checked first
if ! sudo visudo -cf "$rule" >/dev/null; then
    rm -f "$rule"
    die "The sudoers rule didn't pass visudo's check, so it wasn't installed."
fi
sudo install -o root -g root -m 0440 "$rule" "$SUDOERS"
rm -f "$rule"
note "Wrote $SUDOERS"
install_bin claude
install_bin claude-unsandboxed
install_bin claude-pull
install_bin git

cat <<EOF

    claude                 Claude Code as $AGENT. Run it from a folder in
                           ~/projects: cd ~/projects/NAME   (mkdir for a new one)
    claude-unsandboxed     Claude Code as you, with all your files
    claude-pull            in your own copy of a repository: shows what
                           Claude pushed to GitHub, brings it in if you say y

    The first time, claude shows a login link: open it in your browser. Its
    login and settings live in $AGENT_HOME, apart from your own ~/.claude.
    It has its own ssh key and git identity (Claude, noreply@anthropic.com),
    none of yours. Its tools: git, ssh, ripgrep, jq, shellcheck, python venv;
    it can't install more (Node, Rust or Go: add them yourself with apt).
    Your git has a guard inside ~/projects (git is now ~/.local/bin/git): it
    looks at a repository's .git/config and .git/hooks before every command,
    and refuses if something there could run a program as you, such as a
    hook or core.fsmonitor. Repositories it made work without any "dubious
    ownership" warning. /usr/bin/git skips the guard.
    It can't reach servers on this machine, its own dev servers included; the
    note at the top of $FIREWALL says how to allow that.

    Its ssh public key, to add on GitHub (a deploy key on one repository is
    the narrowest; a key on your account lets it push to all of them):

EOF
sudo cat "$AGENT_HOME/.ssh/id_ed25519.pub" | sed 's/^/        /'
echo
