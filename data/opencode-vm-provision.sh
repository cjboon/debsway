#!/bin/bash
# Runs as root INSIDE the disposable opencode-vm guest, once, right after the
# unattended Debian install (mockvps-kvm --provision). extras/opencode-vm.sh
# fills in the @...@ placeholders before handing it over.
#
# It installs opencode, the open-source coding agent, from its newest GitHub
# release, and the tools a shell-and-git workflow wants, then sets up the
# guest's working user: an empty ~/projects, its own git identity and ssh key
# (never yours), and an AGENTS.md telling the agent where it is. The guest
# reaches the internet (model providers, git hosts) but nothing on your machine
# or network; its only way to hand work back is to push to a git host you pull
# from. Nothing here runs as you or touches your files.
#
# How the download is checked: opencode's releases carry no signature of their
# own. The release must be one GitHub marks immutable (its files can't be
# replaced once it is published), and the file must have the SHA-256 GitHub's
# API gives for it, over HTTPS. That stops a download changed on the way, not a
# release a hijacked maintainer account made; this VM is what limits that.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

REPO='@OPENCODE_REPO@'
VM_USER='@VM_USER@'
# The build without the newest CPU instructions: it runs on any amd64 CPU
ASSET=opencode-linux-x64-baseline.tar.gz

log() { printf '\n[opencode-vm guest] %s\n' "$*"; }
die() { printf '[opencode-vm guest] ERROR: %s\n' "$*" >&2; exit 1; }

# grub_no_wait FILE (/etc/default/grub): boot straight into Debian (the guest
# has no screen, so GRUB's 5 s menu only adds to every start)
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
apt-get install -y --no-install-recommends ca-certificates wget jq \
    git openssh-client ripgrep shellcheck python3 python3-venv

# release_field FIELD: tag_name, immutable, or url / digest of $ASSET, from the
# release list (read with python3)
release_field() {
    python3 -I - "$work/release.json" "$1" "$ASSET" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
field, name = sys.argv[2], sys.argv[3]
if field in ("tag_name", "immutable"):
    v = r.get(field)
    print("true" if v is True else "false" if v is False else v)
else:
    key = {"url": "browser_download_url", "digest": "digest"}[field]
    print(next((a.get(key) or "" for a in r.get("assets", []) if a.get("name") == name), ""))
PY
}

log "Security updates install themselves, in the guest too"
apt-get -y upgrade
apt-get install -y --no-install-recommends unattended-upgrades
printf '%s\n' 'APT::Periodic::Update-Package-Lists "1";' 'APT::Periodic::Unattended-Upgrade "1";' >/etc/apt/apt.conf.d/20auto-upgrades

log "The newest opencode release"
work=$(mktemp -d)
wget -qO "$work/release.json" "https://api.github.com/repos/$REPO/releases/latest" ||
    die "could not read the newest release of $REPO from GitHub"
tag=$(release_field tag_name)
[[ $tag =~ ^v[0-9]+(\.[0-9]+)+$ ]] || die "the newest release's tag ($tag) doesn't look like a version"
[ "$(release_field immutable)" = true ] ||
    die "release $tag isn't marked immutable by GitHub, so its files could have been replaced; not installing"
url=$(release_field url)
digest=$(release_field digest)
[ "$url" = "https://github.com/$REPO/releases/download/$tag/$ASSET" ] ||
    die "release $tag has no $ASSET where it should be ($url)"
[[ $digest =~ ^sha256:[0-9a-f]{64}$ ]] || die "GitHub gives no SHA-256 for $ASSET ($digest)"

log "Downloading opencode $tag and checking it"
wget -qO "$work/$ASSET" "$url" || die "could not download $url"
echo "${digest#sha256:}  $work/$ASSET" | sha256sum -c --quiet - ||
    die "$ASSET doesn't have the SHA-256 GitHub gives for it; not installing"
# The archive holds the one program, opencode
[ "$(tar -tzf "$work/$ASSET")" = opencode ] || die "$ASSET doesn't hold just the opencode program"
tar -xzf "$work/$ASSET" -C "$work" opencode
install -o root -g root -m 0755 "$work/opencode" /usr/local/bin/opencode
echo "$tag" >/usr/local/share/opencode-version
rm -rf "$work"

# The guest's working user (the Debian installer made it with uid 1000).
home=$(getent passwd "$VM_USER" | cut -d: -f6)
[ -n "$home" ] || die "guest user $VM_USER not found"

log "Setting up $VM_USER (projects folder, git identity, ssh key, AGENTS.md)"
run() { runuser -u "$VM_USER" -- "$@"; }
run mkdir -p "$home/projects" "$home/.config/opencode"

if [ ! -e "$home/.gitconfig" ]; then
    run git config --global user.name "opencode agent"
    run git config --global user.email "opencode@vm.invalid"
    run git config --global init.defaultBranch main
fi

if [ ! -e "$home/.ssh/id_ed25519" ]; then
    run mkdir -p "$home/.ssh"
    run chmod 700 "$home/.ssh"
    run ssh-keygen -q -t ed25519 -N "" -C "opencode-vm@guest" -f "$home/.ssh/id_ed25519"
fi

cat >"$home/.config/opencode/AGENTS.md" <<'AGENTSMD'
# How this machine is set up

You are running inside a disposable virtual machine, as the only working
user. This whole VM exists to give you a place to work that is sealed off
from the person's real computer.

- You can read and write anywhere you have permission here; this is not
  their machine and holds none of their files, keys or passwords. Work in
  `~/projects`.
- You can reach the internet (model providers, git hosts, package mirrors)
  but nothing on their computer or local network: no localhost services of
  theirs, no router, no printers. A refused connection to a `192.168.x.x` or
  `localhost` address of theirs is that boundary, not a bug.
- You have git, ssh, ripgrep, jq, shellcheck and python3 with venv. You may
  install more with `sudo apt-get install` (you have sudo IN THIS VM only).
- Your git identity is "opencode agent" <opencode@vm.invalid> and your ssh key
  is `~/.ssh/id_ed25519`, made here, never theirs.
- **How your work reaches them:** commit and push to the git host (run the
  project's tests first), to a branch of its own, not to main. This VM has no
  shared folder with their machine on purpose; pushing to a remote they pull
  from is the only way out. They review your commits before merging. The
  person adds your ssh public key on the host before your first push: ask them.
- The VM can be thrown away and rebuilt at any time, so keep nothing here
  that you have not pushed.
AGENTSMD
chown -R "$VM_USER:$VM_USER" "$home/.config/opencode"
chmod 600 "$home/.config/opencode/AGENTS.md"

log "Booting without GRUB's menu wait"
grub_no_wait /etc/default/grub || log "Couldn't update GRUB; the VM still boots, 5 s slower."

log "opencode $tag installed. The guest's ssh public key (add it on your git host):"
cat "$home/.ssh/id_ed25519.pub"
log "Provisioning finished."
