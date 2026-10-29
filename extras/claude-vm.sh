#!/bin/bash
# Claude Code inside a disposable virtual machine. Instead of running the
# agent as another user on this computer, this runs it in its own throwaway
# Debian guest (QEMU/KVM), so a kernel bug that would escape a user-level
# sandbox only reaches a VM you can delete. It is self-contained: it needs
# nothing else installed. (It can also run side by side with the lighter
# extras/claude-code.sh, which it leaves untouched.)
#
# How it is put together:
#  - A locked user, claude-vm (no password, no login), runs the one
#    qemu-system-x86_64 process. The guest's disk is its own; there is no
#    shared folder with you on purpose. The agent's only way to hand work
#    back is to push to a git host you pull from with claude-pull (this
#    script installs that command too, so the VM stands on its own).
#  - QEMU's user-mode networking turns the guest's traffic into ordinary
#    host sockets owned by claude-vm, so a firewall rule on that user
#    (data/claude-vm-firewall.nft) governs the guest too: internet yes; your
#    router, printers and local services no. The one hole is loopback to the
#    guest's own SSH console (127.0.0.1:2242), which the host needs to log in.
#  - The guest is built unattended with the bundled mockvps-kvm (QEMU, no
#    libvirt), its installer kernel checked against Debian's signed lists,
#    then provisioned to install Claude Code from Anthropic's apt repository
#    (the same key fingerprint pinned in pins.sh). The guest gets its own git
#    identity and ssh key, never yours.
#  - Your user may run exactly one thing as claude-vm: the claude-vm-session
#    script (a rule in /etc/sudoers.d). The claude-vm command calls it.
# Needs KVM (VT-x/AMD-V and /dev/kvm). Without it, extras/claude-code.sh
# runs Claude Code as its own user instead: lighter, but it shares your
# kernel, so a kernel bug could get out (docs/extras.md compares the two).
# See THREAT-MODEL.md.
# Usage: bash claude-vm.sh [--remove]
# summary: Claude Code in a disposable VM (no shared folder)
# status: bin:claude-vm file:/usr/local/libexec/claude-vm-session
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

AGENT=claude-vm
AGENT_HOME=/home/$AGENT
SESSION=/usr/local/libexec/claude-vm-session
MOCKVPS=/usr/local/libexec/claude-vm-mockvps-kvm
SUDOERS=/etc/sudoers.d/debsway-claude-vm
FIREWALL=/etc/debsway/claude-vm.nft
UNIT=/etc/systemd/system/debsway-claude-vm-firewall.service
PROVISION_DST=$AGENT_HOME/.config/claude-vm/provision.sh
VM_USER=agent

if [ "${1:-}" = --remove ]; then
    remove_bin claude-vm
    # claude-pull is shared with extras/claude-code.sh; keep it if that
    # sandbox is still set up (its session wrapper is the tell)
    [ -e /usr/local/libexec/claude-session ] || remove_bin claude-pull
    sudo systemctl disable --now debsway-claude-vm-firewall.service >/dev/null 2>&1 || true
    sudo nft delete table inet debsway_claude_vm 2>/dev/null || true
    sudo rm -f "$SUDOERS" "$SESSION" "$MOCKVPS" "$FIREWALL" "$UNIT"
    remove_no_abstract
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo rmdir /usr/local/libexec /etc/debsway 2>/dev/null || true
    if id "$AGENT" >/dev/null 2>&1; then
        if ask "Delete the user $AGENT and its home folder $AGENT_HOME (the VM disk, its ssh key and settings)?" n; then
            sudo pkill -KILL -u "$AGENT" 2>/dev/null || true
            sudo userdel -r "$AGENT" 2>/dev/null || sudo userdel "$AGENT"
            note "Removed the user $AGENT and its VM."
        else
            note "Kept the user $AGENT and $AGENT_HOME (the VM is still there)."
        fi
    fi
    # QEMU and friends go unless another script's marker still needs them
    apt_purge qemu-system-x86 qemu-utils socat nftables
    note "Removed the claude-vm sandbox. extras/claude-code.sh, if installed, is untouched."
    exit
fi

[ -e /dev/kvm ] || die "No /dev/kvm: turn on virtualization (VT-x / AMD-V) in the firmware settings."

say "Installing what the VM sandbox needs"
# qemu + qemu-utils: the hypervisor. socat: clean power-off. nftables: the
# rule that keeps the guest off your network. openssh-client: logging into the
# guest. cpio/gzip/wget: the unattended installer. gpgv + keyring: verify
# Debian's signature on the installer. The agent itself is installed INSIDE
# the guest, from Anthropic's signed repo, by the provisioning step.
apt_install qemu-system-x86 qemu-utils socat nftables openssh-client \
    cpio gzip wget gpgv debian-archive-keyring

say "The $AGENT user"
if ! id "$AGENT" >/dev/null 2>&1; then
    sudo useradd --create-home --home-dir "$AGENT_HOME" --shell /bin/bash --user-group \
        --comment "debsway Claude Code VM" "$AGENT"
fi
sudo usermod --lock "$AGENT"
sudo chmod 700 "$AGENT_HOME"
# It needs /dev/kvm; the kvm group is the only group it gets
if ! id -nG "$AGENT" | grep -qw kvm; then
    sudo usermod -aG kvm "$AGENT"
fi
note "$AGENT: no password, no login, in the kvm group only."

say "Keeping $AGENT (and so the guest) off your network"
sudo install -d -o root -g root -m 0755 "${FIREWALL%/*}"
sudo install -o root -g root -m 0644 "$DEBSWAY_DIR/data/claude-vm-firewall.nft" "$FIREWALL"
printf '%s\n' '# Written by debsway extras/claude-vm.sh' '[Unit]' \
    'Description=Keep the claude-vm user (and its guest) off the local network (debsway)' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' \
    "ExecStart=/usr/sbin/nft -f $FIREWALL" \
    'ExecStop=/usr/sbin/nft delete table inet debsway_claude_vm' '' '[Install]' \
    'WantedBy=multi-user.target' | sudo tee "$UNIT" >/dev/null
sudo systemctl daemon-reload
# Restart, not just enable --now: the unit stays "active" after it first ran,
# so a rule file changed by an update would otherwise not be loaded
sudo systemctl enable debsway-claude-vm-firewall.service >/dev/null &&
    sudo systemctl restart debsway-claude-vm-firewall.service ||
    warn "Couldn't load the firewall rule; check: systemctl status debsway-claude-vm-firewall"
note "$AGENT can reach the internet and the guest's console, nothing else."

say "The VM engine and the claude-vm command"
sudo install -d -o root -g root -m 0755 /usr/local/libexec
# The bundled mockvps-kvm, where claude-vm (which has no access to your home)
# can run it. It looks at its own location, so the debsway-only reminder in it
# stays quiet here.
sudo install -o root -g root -m 0755 "$DEBSWAY_DIR/vendor/mockvps-kvm/mockvps-kvm.sh" "$MOCKVPS"
sudo install -o root -g root -m 0755 "$DEBSWAY_DIR/bin/claude-vm-session" "$SESSION"
install_no_abstract

# The provisioning script, with Anthropic's pinned key filled in, where only
# claude-vm can read it.
sudo install -d -o "$AGENT" -g "$AGENT" -m 0700 "$AGENT_HOME/.config" "$AGENT_HOME/.config/claude-vm"
prov=$(mktemp)
sed -e "s|@ANTHROPIC_FPR@|$ANTHROPIC_FPR|g" \
    -e "s|@ANTHROPIC_KEY_URL@|$ANTHROPIC_KEY_URL|g" \
    -e "s|@VM_USER@|$VM_USER|g" \
    "$DEBSWAY_DIR/data/claude-vm-provision.sh" >"$prov"
sudo install -o "$AGENT" -g "$AGENT" -m 0600 "$prov" "$PROVISION_DST"
rm -f "$prov"

rule=$(mktemp)
printf '# Written by debsway extras/claude-vm.sh. %s may run the claude-vm-session script,\n# and nothing else, as the user %s.\n%s ALL=(%s) NOPASSWD: %s\n' \
    "$(id -un)" "$AGENT" "$(id -un)" "$AGENT" "$SESSION" >"$rule"
if ! sudo visudo -cf "$rule" >/dev/null; then
    rm -f "$rule"
    die "The sudoers rule didn't pass visudo's check, so it wasn't installed."
fi
sudo install -o root -g root -m 0440 "$rule" "$SUDOERS"
rm -f "$rule"
note "Wrote $SUDOERS"
install_bin claude-vm
# How you bring the agent's pushed work into your own copy, after reviewing
# it. Shared with extras/claude-code.sh, which installs the same command.
install_bin claude-pull

say "Building the VM"
note "This installs Debian and Claude Code inside the guest; it takes 5-15 minutes"
note "and downloads a few hundred MB. You can do it later with: claude-vm rebuild"
if ask "Build the VM now?" y; then
    if sudo -u "$AGENT" "$SESSION" install; then
        say "The VM is ready"
        note "Its ssh public key (add it on your git host so the agent can push):"
        sudo -u "$AGENT" "$SESSION" pubkey 2>/dev/null | sed 's/^/        /' || true
    else
        warn "The build didn't finish. Try again with: claude-vm rebuild"
    fi
else
    note "Skipped. Build it when you're ready with: claude-vm rebuild"
fi

cat <<EOF

    claude-vm              Claude Code inside the disposable VM
    claude-vm shell        a plain shell in the VM
    claude-vm status       is the VM running?
    claude-vm stop         power the VM off
    claude-vm pubkey       the VM's ssh public key (add it on your git host)
    claude-vm rebuild      throw the VM away and build a fresh one

    The agent works in ~/projects INSIDE the VM. There is no shared folder:
    it hands work back only by pushing to a git host, which you bring into
    your own copy with claude-pull (installed above; it shows what's new and
    asks before merging). The VM reaches the internet but nothing on your
    machine or local network.
EOF
