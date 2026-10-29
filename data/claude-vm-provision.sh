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
# network; its only way to hand work back is to push to a git host you pull
# from. Nothing here runs as you or touches your files.
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

# The guest's working user (the Debian installer made it with uid 1000).
home=$(getent passwd "$VM_USER" | cut -d: -f6)
[ -n "$home" ] || die "guest user $VM_USER not found"

log "Setting up $VM_USER (projects folder, git identity, ssh key, CLAUDE.md)"
run() { runuser -u "$VM_USER" -- "$@"; }
run mkdir -p "$home/projects" "$home/.claude"

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
- You have git, ssh, ripgrep, jq, shellcheck and python3 with venv. You may
  install more with `sudo apt-get install` (you have sudo IN THIS VM only).
- Your git identity is Claude <noreply@anthropic.com> and your ssh key is
  `~/.ssh/id_ed25519`, made here, never theirs.
- **How your work reaches them:** commit and push to the git host (run the
  project's tests first). This VM has no shared folder with their machine on
  purpose; pushing to a remote they pull from is the only way out. They
  review your commits before merging. The person adds your ssh public key on
  the host before your first push: ask them.
- The VM can be thrown away and rebuilt at any time, so keep nothing here
  that you have not pushed.
CLAUDEMD
run chmod 600 "$home/.claude/CLAUDE.md" 2>/dev/null || true
chown "$VM_USER:$VM_USER" "$home/.claude/CLAUDE.md"

log "Booting without GRUB's menu wait"
grub_no_wait /etc/default/grub || log "Couldn't update GRUB; the VM still boots, 5 s slower."

log "Claude Code installed. The guest's ssh public key (add it on your git host):"
cat "$home/.ssh/id_ed25519.pub"
log "Provisioning finished."
