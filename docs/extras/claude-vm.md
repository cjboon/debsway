# Claude Code in a VM (`extras/claude-vm.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/claude-vm.sh            set it up and build the VM (keeps a VM already built)
bash ~/debsway/extras/claude-vm.sh --remove   remove it (asks before deleting the user and its VM)
bash ~/debsway/extras/claude-vm.sh --manual   print the manual steps below

claude-vm              Claude Code inside the VM (boots it; powers it off when you exit)
claude-vm shell        a plain shell in the VM
claude-vm status | stop
claude-vm pubkey       the VM's ssh public key (add it on your git host)
claude-vm rebuild      throw the VM away and build a fresh one
claude-pull            in your copy of a repository: shows what the agent pushed, brings it in on y
```

Claude Code inside a disposable Debian virtual machine (QEMU/KVM), so a
kernel bug that would get out of a user-level sandbox only reaches a VM you
can delete. A locked user, `claude-vm` (no password, no login), runs the one
QEMU process; the guest's disk is its own and there is no shared folder: the
agent hands work back only by pushing to a git host, which you bring into your
own copy with `claude-pull`. QEMU's user-mode networking turns the guest's
traffic into ordinary sockets owned by `claude-vm`, so a firewall rule on that
user (`data/claude-vm-firewall.nft`) governs the guest: the internet yes, your
router, printers and local services no, except the guest's own ssh console on
127.0.0.1:2242. The guest is built unattended with the bundled mockvps-kvm,
its installer checked against Debian's signed lists, then provisioned
(`data/claude-vm-provision.sh`) with Claude Code from Anthropic's apt
repository, checked against the same pinned key (`ANTHROPIC_FPR`), and its
own git identity and ssh key. Your user may run exactly one thing as
`claude-vm`, the `claude-vm-session` script, through a rule in
`/etc/sudoers.d`. It needs KVM.

## LIMITS

- A bug in QEMU or KVM could reach this computer; a VM is a stronger wall than a user, not a perfect one.
- It reaches the internet, so what it reads can leave the VM.
- Treat what it pushes as untrusted until you have read it (`claude-pull` shows it first).
- Its ssh key on your git host can push wherever you allow: a deploy key on one repository is the narrowest.

## MANUAL INSTALL

```
# KVM must be on: this must list /dev/kvm (if not, turn on VT-x / AMD-V in the firmware settings)
ls -l /dev/kvm
# QEMU, socat for a clean power-off, nftables for the firewall rule, ssh into
# the guest, and the installer's tools (gpgv and Debian's keyring check it)
sudo apt install --no-install-recommends qemu-system-x86 qemu-utils socat nftables openssh-client \
    cpio gzip wget gpgv debian-archive-keyring

# The claude-vm user, locked, with /dev/kvm as its only extra group
sudo useradd --create-home --home-dir /home/claude-vm --shell /bin/bash --user-group --comment "debsway Claude Code VM" claude-vm
sudo usermod --lock claude-vm
sudo chmod 700 /home/claude-vm
sudo usermod -aG kvm claude-vm

# The firewall rule on that user (and so the guest), loaded at every boot
sudo install -D -o root -g root -m 0644 @DEBSWAY_DIR@/data/claude-vm-firewall.nft /etc/debsway/claude-vm.nft
printf '%s\n' '[Unit]' 'Description=Keep the claude-vm user (and its guest) off the local network' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' 'ExecStart=/usr/sbin/nft -f /etc/debsway/claude-vm.nft' \
    'ExecStop=/usr/sbin/nft delete table inet debsway_claude_vm' '' '[Install]' 'WantedBy=multi-user.target' |
    sudo tee /etc/systemd/system/debsway-claude-vm-firewall.service
sudo systemctl daemon-reload
sudo systemctl enable --now debsway-claude-vm-firewall.service

# The VM engine, the session script, and the no-abstract-sockets wrapper, as root's files
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 @DEBSWAY_DIR@/vendor/mockvps-kvm/mockvps-kvm.sh /usr/local/libexec/claude-vm-mockvps-kvm
sudo install -o root -g root -m 0755 @DEBSWAY_DIR@/bin/claude-vm-session /usr/local/libexec/claude-vm-session
sudo install -o root -g root -m 0755 @DEBSWAY_DIR@/bin/no-abstract-sockets /usr/local/libexec/debsway-no-abstract-sockets

# The provisioning script, with Anthropic's pinned key filled in, readable only by claude-vm
sudo install -d -o claude-vm -g claude-vm -m 0700 /home/claude-vm/.config /home/claude-vm/.config/claude-vm
sed -e 's|[@]ANTHROPIC_FPR@|@ANTHROPIC_FPR@|g' -e 's|[@]ANTHROPIC_KEY_URL@|@ANTHROPIC_KEY_URL@|g' -e 's|[@]VM_USER@|agent|g' \
    @DEBSWAY_DIR@/data/claude-vm-provision.sh |
    sudo install -o claude-vm -g claude-vm -m 0600 /dev/stdin /home/claude-vm/.config/claude-vm/provision.sh

# Your user may run the session script, and nothing else, as claude-vm. visudo
# checks the rule first: never put a rule in /etc/sudoers.d it hasn't passed.
printf '%s ALL=(claude-vm) NOPASSWD: /usr/local/libexec/claude-vm-session\n' "$(id -un)" >/tmp/debsway-claude-vm
sudo visudo -cf /tmp/debsway-claude-vm
sudo install -o root -g root -m 0440 /tmp/debsway-claude-vm /etc/sudoers.d/debsway-claude-vm
rm /tmp/debsway-claude-vm

# The commands
install -D -m 0755 @DEBSWAY_DIR@/bin/claude-vm ~/.local/bin/claude-vm
install -D -m 0755 @DEBSWAY_DIR@/bin/claude-pull ~/.local/bin/claude-pull

# Build the VM (unattended, 10-20 minutes), then show its ssh key for your git host
sudo -u claude-vm /usr/local/libexec/claude-vm-session install
sudo -u claude-vm /usr/local/libexec/claude-vm-session pubkey
claude-vm
```

The `sed` line fills the placeholders in `data/claude-vm-provision.sh` with
the pinned key; `--manual` prints it with the pinned values in place.

To undo:

```
# The commands (keep claude-pull if claude-code is set up)
rm ~/.local/bin/claude-vm ~/.local/bin/claude-pull
# The firewall rule
sudo systemctl disable --now debsway-claude-vm-firewall.service
sudo rm /etc/systemd/system/debsway-claude-vm-firewall.service /etc/debsway/claude-vm.nft
sudo systemctl daemon-reload
# The sudo rule and root's scripts (the no-abstract-sockets wrapper only if
# incognito, claude-code and the Firefox sandbox don't use it)
sudo rm /etc/sudoers.d/debsway-claude-vm /usr/local/libexec/claude-vm-session /usr/local/libexec/claude-vm-mockvps-kvm
sudo rm /usr/local/libexec/debsway-no-abstract-sockets
# The user, its home and the VM in it
sudo pkill -KILL -u claude-vm
sudo userdel -r claude-vm
# QEMU and the tools, marked "automatic": autoremove takes them out only if
# nothing (Whonix, mockvps-kvm, the onion site) needs them
sudo apt-mark auto qemu-system-x86 qemu-utils socat nftables cpio
sudo apt autoremove --purge
```
