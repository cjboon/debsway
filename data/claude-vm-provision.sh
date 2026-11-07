#!/bin/bash
# Runs as root INSIDE the disposable claude-vm guest, once, right after the
# unattended Debian install (mockvps-kvm --provision). extras/claude-vm.sh
# fills in the @...@ placeholders from pins.sh before handing it over, so the
# Anthropic signing key is pinned to the same fingerprint the host trusts.
#
# It installs Claude Code from Anthropic's signed apt repository and the
# tools a shell-and-git workflow wants, then sets up the guest's working
# user: an empty ~/projects, its own git identity and ssh key (never yours),
# and a short CLAUDE.md telling the agent where it is. The guest reaches the
# internet (Claude's servers, git hosts) but nothing on your machine or
# network; it hands work back as commits on a branch claude, which you fetch
# from it with claude-pull. Nothing here runs as you or touches your files.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

FPR='@ANTHROPIC_FPR@'
KEY_URL='@ANTHROPIC_KEY_URL@'
VM_USER='@VM_USER@'
KEY=/etc/apt/keyrings/claude-code.asc
LIST=/etc/apt/sources.list.d/claude-code.list

log() { printf '\n[claude-vm guest] %s\n' "$*"; }
die() { printf '[claude-vm guest] ERROR: %s\n' "$*" >&2; exit 1; }

# key_ok FILE FPR: FILE holds exactly one key, it is FPR, not expired/revoked.
# (Same test as the host's lib/apt.sh, so a file with a second key is refused.)
key_ok() {
    local out
    out=$(gpg --show-keys --with-colons "$1" 2>/dev/null) || return 1
    [ "$(grep -c '^pub:' <<<"$out")" -eq 1 ] || return 1
    [ "$(awk -F: '/^fpr:/ { print $10; exit }' <<<"$out")" = "$2" ] || return 1
    awk -F: '/^pub:/ { exit ($2 ~ /[er]/) }' <<<"$out"
}

# Claude Code's settings in the guest. The VM walls off your computer, but the
# agent is signed in to your Claude account, and that wall doesn't cover it:
# these pass less between the VM and the account. No messages to or from your
# other sessions (isolatePeerMachines, crossSessionInbound), no Remote Control
# at start, no claude.ai connectors, skills or plugins, no Artifact tool, and
# none of Claude Code's own nonessential traffic: telemetry, error reports,
# /feedback (which sends the conversation). The mouse is left to the terminal,
# so selecting text needs no Shift and Page Up scrolls (CLAUDE_CODE_DISABLE_MOUSE).
# They guard against mistakes: root in the guest, which the agent has, can
# change them.
CLAUDE_SETTINGS=$(cat <<'JSON'
{
  "isolatePeerMachines": true,
  "crossSessionInbound": "refuse",
  "remoteControlAtStartup": false,
  "disableClaudeAiConnectors": true,
  "enableArtifact": false,
  "syncClaudeAiSkills": false,
  "syncClaudeAiPlugins": false,
  "env": {
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "DISABLE_FEEDBACK_COMMAND": "1",
    "CLAUDE_CODE_DISABLE_MOUSE": "1"
  }
}
JSON
)

# claude_settings FILE (~/.claude/settings.json): those settings, over what the
# file already says, if anything
claude_settings() {
    local f=$1 tmp
    tmp=$(mktemp)
    if [ -s "$f" ]; then
        jq -s '.[0] * .[1]' "$f" - <<<"$CLAUDE_SETTINGS" >"$tmp" || { rm -f "$tmp"; return 1; }
    else
        printf '%s\n' "$CLAUDE_SETTINGS" >"$tmp"
    fi
    install -D -m 0600 "$tmp" "$f"
    rm -f "$tmp"
}

# grub_no_wait FILE (/etc/default/grub): boot straight into Debian. The
# guest has no screen, so GRUB's 5 s menu only adds to every start; a VM
# that won't boot is rebuilt, not repaired from the menu.
grub_no_wait() {
    local f=$1
    [ -f "$f" ] || return 0
    if grep -q '^GRUB_TIMEOUT=' "$f"; then
        sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' "$f"
    else
        echo 'GRUB_TIMEOUT=0' >>"$f"
    fi
    update-grub
}

log "Installing prerequisites"
apt-get update
apt-get install -y --no-install-recommends ca-certificates gpg wget \
    git openssh-client ripgrep jq shellcheck python3-venv

log "Verifying and installing Anthropic's apt signing key"
tmp=$(mktemp)
wget -qO "$tmp" "$KEY_URL" || die "could not download the signing key from $KEY_URL"
key_ok "$tmp" "$FPR" || die "the key at $KEY_URL is not exactly the pinned key $FPR (or it expired)"
install -D -m 0644 "$tmp" "$KEY"
rm -f "$tmp"
printf 'deb [signed-by=%s] https://downloads.claude.ai/claude-code/apt/stable stable main\n' "$KEY" >"$LIST"

log "Installing Claude Code"
apt-get update
apt-get install -y --no-install-recommends claude-code

log "Security updates install themselves, in the guest too"
apt-get -y upgrade
apt-get install -y --no-install-recommends unattended-upgrades
printf '%s\n' 'APT::Periodic::Update-Package-Lists "1";' 'APT::Periodic::Unattended-Upgrade "1";' >/etc/apt/apt.conf.d/20auto-upgrades
# ...and Claude Code's, from Anthropic's repository
printf '%s\n' 'Unattended-Upgrade::Origins-Pattern:: "site=downloads.claude.ai";' >/etc/apt/apt.conf.d/52wren-claude-code

# The guest's working user (the Debian installer made it with uid 1000).
home=$(getent passwd "$VM_USER" | cut -d: -f6)
[ -n "$home" ] || die "guest user $VM_USER not found"
# Claude Code's theme follows the terminal's
if [ ! -e "$home/.claude.json" ]; then
    printf '{\n  "theme": "auto"\n}\n' >"$home/.claude.json"
    chown "$VM_USER:$VM_USER" "$home/.claude.json"
    chmod 600 "$home/.claude.json"
fi

# sudo without a password, in this guest only. That is safe because of where it
# is: nothing of yours is in here, and the wall is the VM, not this rule.
log "sudo without a password for $VM_USER, in this VM"
printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$VM_USER" >/etc/sudoers.d/90-wren-agent
chmod 0440 /etc/sudoers.d/90-wren-agent
visudo -cf /etc/sudoers.d/90-wren-agent >/dev/null || { rm -f /etc/sudoers.d/90-wren-agent; echo "the sudo rule didn't pass visudo" >&2; exit 1; }

log "Setting up $VM_USER (projects folder, git identity, ssh key, CLAUDE.md)"
run() { runuser -u "$VM_USER" -- "$@"; }
run mkdir -p "$home/projects" "$home/.claude"
claude_settings "$home/.claude/settings.json" || die "couldn't write Claude Code's settings"
chown "$VM_USER:$VM_USER" "$home/.claude/settings.json"

if [ ! -e "$home/.gitconfig" ]; then
    run git config --global user.name Claude
    run git config --global user.email noreply@anthropic.com
    run git config --global init.defaultBranch main
fi

if [ ! -e "$home/.ssh/id_ed25519" ]; then
    run mkdir -p "$home/.ssh"
    run chmod 700 "$home/.ssh"
    run ssh-keygen -q -t ed25519 -N "" -C "claude-vm@guest" -f "$home/.ssh/id_ed25519"
fi

cat >"$home/.claude/CLAUDE.md" <<'CLAUDEMD'
# How this machine is set up

You are running inside a disposable virtual machine, as the only working
user. This whole VM exists to give you a place to work that is sealed off
from the person's real computer.

- You can read and write anywhere you have permission here; this is not
  their machine and holds none of their files, keys or passwords. Work in
  `~/projects`.
- You can reach the internet (Claude's servers, git hosts, package mirrors)
  but nothing on their computer or local network: no localhost services of
  theirs, no router, no printers. A refused connection to a `192.168.x.x` or
  `localhost` address of theirs is that boundary, not a bug.
- You have git, ssh, ripgrep, jq, shellcheck and python3 with venv. You have
  sudo without a password, IN THIS VM only: install what you need, and test
  real installs here. The person can put the VM back to its clean state.
- Your git identity is Claude <noreply@anthropic.com> and your ssh key is
  `~/.ssh/id_ed25519`, made here, never theirs.
- **How your work reaches them:** commit to a branch named `claude` in the
  repository's folder in `~/projects` (run the project's tests first). They
  run `claude-pull` in their copy of it (a folder of the same name), which
  fetches that branch from this VM over its ssh login, shows them every
  commit, and brings it in only if they say yes. This VM has no shared folder
  with their machine on purpose; that is the only way out. You need no push
  access to any git host for it: fetch from the public address, never push.
- The VM can be thrown away and rebuilt at any time, so keep nothing here
  that they have not brought in.
CLAUDEMD
run chmod 600 "$home/.claude/CLAUDE.md" 2>/dev/null || true
chown "$VM_USER:$VM_USER" "$home/.claude/CLAUDE.md"

log "Booting without GRUB's menu wait"
grub_no_wait /etc/default/grub || log "Couldn't update GRUB; the VM still boots, 5 s slower."

log "Claude Code installed. The guest's ssh public key (only if it is to push to a git host itself):"
cat "$home/.ssh/id_ed25519.pub"
log "Provisioning finished."
