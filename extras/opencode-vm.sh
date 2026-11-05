#!/bin/bash
# opencode, the open-source coding agent, inside a disposable virtual machine:
# for people who can't pay for Claude, it works with free models (opencode's
# own, named "... Free"; /models inside it lists them) as well as paid ones. It runs in
# its own throwaway Debian guest (QEMU/KVM), so a kernel bug that would escape
# a user-level sandbox only reaches a VM you can delete. It is self-contained,
# and runs side by side with extras/claude-vm.sh and the other Claude extras.
#
# How it is put together (as extras/claude-vm.sh is):
#  - A locked user, opencode-vm (no password, no login), runs the one
#    qemu-system-x86_64 process. The guest's disk is its own; there is no
#    shared folder with you on purpose. The agent's only way to hand work
#    back is to push to a git host you pull from; the end of this says how.
#  - QEMU's user-mode networking turns the guest's traffic into ordinary
#    host sockets owned by opencode-vm, so a firewall rule on that user
#    (data/opencode-vm-firewall.nft) governs the guest too: internet yes; your
#    router, printers and local services no. The one hole is loopback to the
#    guest's own SSH console (127.0.0.1:2244), which the host needs to log in.
#  - The guest is built unattended with the bundled mockvps-kvm (QEMU, no
#    libvirt), its installer kernel checked against Debian's signed lists,
#    then provisioned (data/opencode-vm-provision.sh) with opencode's newest
#    GitHub release (OPENCODE_REPO in pins.sh). opencode publishes no
#    signatures: the release must be one GitHub marks immutable, and the file
#    must have the SHA-256 GitHub's API gives for it. Weaker than a signature,
#    so it is done inside the VM only. The guest gets its own git identity and
#    ssh key, never yours.
#  - Your user may run exactly one thing as opencode-vm: the opencode-vm-session
#    script (a rule in /etc/sudoers.d). The opencode-vm command calls it.
# Needs KVM (VT-x/AMD-V and /dev/kvm). See THREAT-MODEL.md.
# Usage: bash opencode-vm.sh [--remove | --manual]
# summary: opencode in a disposable VM (no shared folder)
# security: most
# files: bin/no-abstract-sockets bin/sandbox-net-check
# status: bin:opencode-vm file:/usr/local/libexec/opencode-vm-session
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

AGENT=opencode-vm
AGENT_HOME=/home/$AGENT
SESSION=/usr/local/libexec/opencode-vm-session
MOCKVPS=/usr/local/libexec/opencode-vm-mockvps-kvm
SUDOERS=/etc/sudoers.d/wren-opencode-vm
FIREWALL=/etc/wren/opencode-vm.nft
UNIT=/etc/systemd/system/wren-opencode-vm-firewall.service
PROVISION_DST=$AGENT_HOME/.config/opencode-vm/provision.sh
VM_USER=agent

if [ "${1:-}" = --remove ]; then
    remove_bin opencode-vm
    sudo systemctl disable --now wren-opencode-vm-firewall.service >/dev/null 2>&1 || true
    sudo nft delete table inet wren_opencode_vm 2>/dev/null || true
    sudo rm -f "$SUDOERS" "$SESSION" "$MOCKVPS" "$FIREWALL" "$UNIT"
    remove_no_abstract
    remove_net_check
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo rmdir /usr/local/libexec /etc/wren 2>/dev/null || true
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
    note "Removed the opencode-vm sandbox. The Claude extras, if installed, are untouched."
    exit
fi

[ -e /dev/kvm ] || die "No /dev/kvm: turn on virtualization (VT-x / AMD-V) in the firmware settings."

say "Installing what the VM sandbox needs"
# qemu + qemu-utils: the hypervisor. socat: clean power-off. nftables: the
# rule that keeps the guest off your network. openssh-client: logging into the
# guest. cpio/gzip/wget: the unattended installer. gpgv + keyring: verify
# Debian's signature on the installer. The agent itself is installed INSIDE
# the guest, from its GitHub release, by the provisioning step.
apt_install qemu-system-x86 qemu-utils socat nftables openssh-client \
    cpio gzip wget gpgv debian-archive-keyring

say "The $AGENT user"
if ! id "$AGENT" >/dev/null 2>&1; then
    sudo useradd --create-home --home-dir "$AGENT_HOME" --shell /bin/bash --user-group \
        --comment "Wren Linux opencode VM" "$AGENT"
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
sudo install -o root -g root -m 0644 "$WREN_DIR/data/opencode-vm-firewall.nft" "$FIREWALL"
printf '%s\n' '# Written by Wren Linux extras/opencode-vm.sh' '[Unit]' \
    'Description=Keep the opencode-vm user (and its guest) off the local network (Wren Linux)' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' \
    "ExecStart=/usr/sbin/nft -f $FIREWALL" \
    'ExecStop=/usr/sbin/nft delete table inet wren_opencode_vm' '' '[Install]' \
    'WantedBy=multi-user.target' | sudo tee "$UNIT" >/dev/null
sudo systemctl daemon-reload
# Restart, not just enable --now: the unit stays "active" after it first ran,
# so a rule file changed by an update would otherwise not be loaded
sudo systemctl enable wren-opencode-vm-firewall.service >/dev/null &&
    sudo systemctl restart wren-opencode-vm-firewall.service ||
    warn "Couldn't load the firewall rule; check: systemctl status wren-opencode-vm-firewall"
note "$AGENT can reach the internet and the guest's console, nothing else."

say "The VM engine and the opencode-vm command"
sudo install -d -o root -g root -m 0755 /usr/local/libexec
# The bundled mockvps-kvm, where opencode-vm (which has no access to your home)
# can run it. It looks at its own location, so the wren-only reminder in it
# stays quiet here.
sudo install -o root -g root -m 0755 "$WREN_DIR/vendor/mockvps-kvm/mockvps-kvm.sh" "$MOCKVPS"
sudo install -o root -g root -m 0755 "$WREN_DIR/bin/opencode-vm-session" "$SESSION"
install_no_abstract
install_net_check

# The provisioning script, with the repository filled in, where only
# opencode-vm can read it.
sudo install -d -o "$AGENT" -g "$AGENT" -m 0700 "$AGENT_HOME/.config" "$AGENT_HOME/.config/opencode-vm"
prov=$(mktemp)
sed -e "s|@OPENCODE_REPO@|$OPENCODE_REPO|g" \
    -e "s|@VM_USER@|$VM_USER|g" \
    "$WREN_DIR/data/opencode-vm-provision.sh" >"$prov"
sudo install -o "$AGENT" -g "$AGENT" -m 0600 "$prov" "$PROVISION_DST"
rm -f "$prov"

rule=$(mktemp)
printf '# Written by Wren Linux extras/opencode-vm.sh. %s may run the opencode-vm-session script,\n# and nothing else, as the user %s.\n%s ALL=(%s) NOPASSWD: %s\n' \
    "$(id -un)" "$AGENT" "$(id -un)" "$AGENT" "$SESSION" >"$rule"
if ! sudo visudo -cf "$rule" >/dev/null; then
    rm -f "$rule"
    die "The sudoers rule didn't pass visudo's check, so it wasn't installed."
fi
sudo install -o root -g root -m 0440 "$rule" "$SUDOERS"
rm -f "$rule"
note "Wrote $SUDOERS"
install_bin opencode-vm

say "Building the VM"
if sudo test -s "$AGENT_HOME/vm/$AGENT.qcow2"; then
    # Run again (by update.sh, say): keep the VM and what's unpushed in it
    note "The VM is already built; kept as it is. For a fresh one: opencode-vm rebuild"
else
    note "This installs Debian and opencode inside the guest; it takes 5-15 minutes"
    note "and downloads a few hundred MB."
    if sudo -u "$AGENT" "$SESSION" install; then
        say "The VM is ready"
        note "Its ssh public key (add it on your git host so the agent can push):"
        sudo -u "$AGENT" "$SESSION" pubkey 2>/dev/null | sed 's/^/        /' || true
    else
        warn "The build didn't finish. Try again with: opencode-vm rebuild"
    fi
fi

cat <<'EOF'

    opencode-vm              opencode inside the disposable VM (boots it; powers it off when you exit)
    opencode-vm shell        a plain shell in the VM
    opencode-vm status       is the VM running?
    opencode-vm stop         power the VM off
    opencode-vm pubkey       the VM's ssh public key (add it on your git host)
    opencode-vm rebuild      throw the VM away and build a fresh one
    The first time, inside opencode: /connect logs in to a provider (choose
    opencode for its own models; ones whose name ends in "Free" cost nothing),
    then /models lists the models to pick from.

    How its work gets to you (git; the VM has no shared folder with you):
      1. On your git host (GitHub, Codeberg...), make a repository for the
         project, and add the VM's key to it: opencode-vm pubkey, then the
         repository's Settings > Deploy keys > Add, "Allow write access".
         (A deploy key reaches only that repository.)
      2. In the VM (opencode-vm shell):
           cd ~/projects && git clone git@github.com:YOU/PROJECT.git && cd PROJECT
         then start opencode there (opencode), and ask it to work on a branch
         of its own and push it: git push -u origin BRANCH
      3. On this computer, in your own copy of the project:
           git fetch origin
           git log --oneline main..origin/BRANCH     what it did
           git diff main...origin/BRANCH             every change, to read first
           git merge origin/BRANCH                   only once you've read it
         Run nothing it wrote (tests, scripts, a Makefile) before you've read it:
         it comes from a program you don't control.
    The VM reaches the internet but nothing on your machine or local network.
EOF
