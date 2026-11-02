# opencode in a VM (`extras/opencode-vm.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/opencode-vm.sh            set it up and build the VM (keeps a VM already built)
bash ~/debsway/extras/opencode-vm.sh --remove   remove it (asks before deleting the user and its VM)
bash ~/debsway/extras/opencode-vm.sh --manual   print the manual steps below

opencode-vm              opencode inside the VM (boots it; powers it off when you exit)
opencode-vm shell        a plain shell in the VM
opencode-vm status | stop
opencode-vm pubkey       the VM's ssh public key (add it on your git host)
opencode-vm rebuild      throw the VM away and build a fresh one
  inside opencode: /connect logs in to a provider (choose opencode for its own
  models; ones named "... Free" cost nothing), /models picks the model

Its work, by git (the VM has no shared folder with you):
  1. a repository on your git host, with the VM's key as a deploy key with write access
  2. in the VM: git clone it into ~/projects, run opencode there, have it push a branch
  3. here: git fetch origin
           git log --oneline main..origin/BRANCH      what it did
           git diff main...origin/BRANCH              every change: read it first
           git merge origin/BRANCH                    once you have
```

opencode is an open-source coding agent that works with many model providers,
free models among them, for people who can't pay for Claude. Here it runs in
a disposable Debian virtual machine (QEMU/KVM), built and run as claude-vm is:
a locked user, `opencode-vm`, runs the one QEMU process; the guest has its own
disk and no shared folder with you; and a firewall rule on that user
(`data/opencode-vm-firewall.nft`) lets the guest reach the internet but not
your router, printers or this computer's services, except its own ssh console
on 127.0.0.1:2244. Your user may run exactly one thing as `opencode-vm`, the
`opencode-vm-session` script, through a rule in `/etc/sudoers.d`. Inside, opencode
comes from its newest GitHub release (`OPENCODE_REPO` in `pins.sh`).
opencode publishes no signatures, so the guest takes only a release GitHub
marks immutable (its files can't be replaced once published) and only a file
with the SHA-256 GitHub's API gives for it: weaker than the signed checks
elsewhere in debsway, which is why it happens only inside the VM. The agent
has its own git identity and ssh key, never yours, and hands work back only
by pushing to a git host you pull from, after you have read it. It needs KVM.

## LIMITS

- opencode's download is checked against GitHub's own SHA-256, not a signature: a hijacked maintainer account could publish a bad release. The VM is what limits that.
- What it writes is code from a program you don't control: read the diff before you merge it, and run nothing it wrote before you have.
- It reaches the internet, and the model provider you choose sees your prompts and the code it reads.
- Its key on your git host can push wherever you allow: a deploy key on one repository is the narrowest.
- A bug in QEMU or KVM could reach this computer.

## MANUAL INSTALL

```
# KVM must be on: this must list /dev/kvm (if not, turn on VT-x / AMD-V in the firmware settings)
ls -l /dev/kvm
# QEMU, socat for a clean power-off, nftables for the firewall rule, ssh into
# the guest, and the installer's tools (gpgv and Debian's keyring check it)
sudo apt install --no-install-recommends qemu-system-x86 qemu-utils socat nftables openssh-client \
    cpio gzip wget gpgv debian-archive-keyring

# The opencode-vm user, locked, with /dev/kvm as its only extra group
sudo useradd --create-home --home-dir /home/opencode-vm --shell /bin/bash --user-group --comment "debsway opencode VM" opencode-vm
sudo usermod --lock opencode-vm
sudo chmod 700 /home/opencode-vm
sudo usermod -aG kvm opencode-vm

# The firewall rule on that user (and so the guest), loaded at every boot
sudo install -D -o root -g root -m 0644 @DEBSWAY_DIR@/data/opencode-vm-firewall.nft /etc/debsway/opencode-vm.nft
printf '%s\n' '[Unit]' 'Description=Keep the opencode-vm user (and its guest) off the local network' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' 'ExecStart=/usr/sbin/nft -f /etc/debsway/opencode-vm.nft' \
    'ExecStop=/usr/sbin/nft delete table inet debsway_opencode_vm' '' '[Install]' 'WantedBy=multi-user.target' |
    sudo tee /etc/systemd/system/debsway-opencode-vm-firewall.service
sudo systemctl daemon-reload
sudo systemctl enable --now debsway-opencode-vm-firewall.service

# The VM engine, the session script, and the no-abstract-sockets wrapper, as root's files
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 @DEBSWAY_DIR@/vendor/mockvps-kvm/mockvps-kvm.sh /usr/local/libexec/opencode-vm-mockvps-kvm
sudo install -o root -g root -m 0755 @DEBSWAY_DIR@/bin/opencode-vm-session /usr/local/libexec/opencode-vm-session
sudo install -o root -g root -m 0755 @DEBSWAY_DIR@/bin/no-abstract-sockets /usr/local/libexec/debsway-no-abstract-sockets

# The provisioning script, with the repository it installs from filled in, readable only by opencode-vm
sudo install -d -o opencode-vm -g opencode-vm -m 0700 /home/opencode-vm/.config /home/opencode-vm/.config/opencode-vm
sed -e 's|[@]OPENCODE_REPO@|@OPENCODE_REPO@|g' -e 's|[@]VM_USER@|agent|g' \
    @DEBSWAY_DIR@/data/opencode-vm-provision.sh |
    sudo install -o opencode-vm -g opencode-vm -m 0600 /dev/stdin /home/opencode-vm/.config/opencode-vm/provision.sh

# Your user may run the session script, and nothing else, as opencode-vm. visudo
# checks the rule first: never put a rule in /etc/sudoers.d it hasn't passed.
printf '%s ALL=(opencode-vm) NOPASSWD: /usr/local/libexec/opencode-vm-session\n' "$(id -un)" >/tmp/debsway-opencode-vm
sudo visudo -cf /tmp/debsway-opencode-vm
sudo install -o root -g root -m 0440 /tmp/debsway-opencode-vm /etc/sudoers.d/debsway-opencode-vm
rm /tmp/debsway-opencode-vm

# The commands
install -D -m 0755 @DEBSWAY_DIR@/bin/opencode-vm ~/.local/bin/opencode-vm

# Build the VM (unattended, 10-20 minutes), then show its ssh key for your git host
sudo -u opencode-vm /usr/local/libexec/opencode-vm-session install
sudo -u opencode-vm /usr/local/libexec/opencode-vm-session pubkey
opencode-vm
```

The `sed` line fills the placeholders in `data/opencode-vm-provision.sh` with
the repository and the VM's user; `--manual` prints it with the pinned values in place.

To undo:

```
# The command
rm ~/.local/bin/opencode-vm
# The firewall rule
sudo systemctl disable --now debsway-opencode-vm-firewall.service
sudo rm /etc/systemd/system/debsway-opencode-vm-firewall.service /etc/debsway/opencode-vm.nft
sudo systemctl daemon-reload
# The sudo rule and root's scripts (the no-abstract-sockets wrapper only if
# incognito, the Claude extras and the Firefox sandbox don't use it)
sudo rm /etc/sudoers.d/debsway-opencode-vm /usr/local/libexec/opencode-vm-session /usr/local/libexec/opencode-vm-mockvps-kvm
sudo rm /usr/local/libexec/debsway-no-abstract-sockets
# The user, its home and the VM in it
sudo pkill -KILL -u opencode-vm
sudo userdel -r opencode-vm
# QEMU and the tools, marked "automatic": autoremove takes them out only if
# nothing (Whonix, mockvps-kvm, the onion site) needs them
sudo apt-mark auto qemu-system-x86 qemu-utils socat nftables cpio
sudo apt autoremove --purge
```
