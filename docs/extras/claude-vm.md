# Claude Code in a VM (`extras/claude-vm.sh`)

## SYNOPSIS

```
wrenctl install claude-vm                         set it up and build the VM (keeps a VM already built)
wrenctl remove claude-vm                          remove it (asks before deleting the user and its VM)
wrenctl manual claude-vm                          print the manual steps below
wrenctl install claude-vm --account NAME          another account, in a VM of its own
wrenctl install claude-vm --remove-account NAME   remove it (asks before deleting its user and VM)
wrenctl install claude-vm --memory MB --disk MB   the VM's size (also with --account NAME)

claude                 Claude Code; asks which if you set up more than one (Enter: the VM)
claude-vm              Claude Code inside the VM (boots it; powers it off when you exit)
claude-vm shell        a plain shell in the VM
claude-vm status | stop
claude-vm pubkey       the VM's ssh public key (add it on your git host; wrenctl gh deploy-key does it for GitHub)
claude-vm rebuild      throw the VM away and build a fresh one (asks first; offers its new key to GitHub)
claude-vm reset        back to how it was built (faster than rebuild; asks first)
claude-pull            in your copy of a repository: shows what the agent pushed, brings it in on y
claude-vm --account NAME [shell|status|stop|pubkey|rebuild]   the same, for that account's VM
```

Claude Code inside a disposable Debian virtual machine (QEMU/KVM), so a
kernel bug that would get out of a user-level sandbox only reaches a VM you
can delete. A locked user, `claude-vm` (no password, no login), runs the one
QEMU process; the guest's disk is its own and there is no shared folder: the
agent hands work back only by pushing to a git host (to a branch `claude`, so your own
branch stays yours), which you bring into your own copy with `claude-pull`. QEMU's user-mode networking turns the guest's
traffic into ordinary sockets owned by `claude-vm`, so a firewall rule on that
user (`data/claude-vm-firewall.nft`) governs the guest: the internet yes, your
router, printers and local services no, except the guest's own ssh console on
127.0.0.1:2242. The guest is built unattended with the bundled mockvps-kvm,
its installer checked against Debian's signed lists, then provisioned
(`data/claude-vm-provision.sh`) with Claude Code from Anthropic's apt
repository, checked against the same pinned key (`ANTHROPIC_FPR`), and its
own git identity and ssh key. Your user may run exactly one thing as
`claude-vm`, the `claude-vm-session` script, through a rule in
`/etc/sudoers.d`. It needs KVM. Another account (a second Claude login)
gets a VM of its own, run by its own locked user, `claude-vm-NAME`: its own
disk, keys and login, its own console port (2250-2299, written by root in
`/etc/wren/claude-vm-ports`), a sudo rule, and firewall lines that let
that user reach its own port and nobody else's. Each VM takes its own disk
space (several GB) and memory while it runs. How much (`lib/vm-size.sh`): the
first time, it shows this computer's memory and free disk and suggests a size
(a third of the memory, 2 to 8 GB; a 40 GB disk), Enter taking the suggestion;
it refuses more than this computer can spare (at most half the memory, always
4 GB left for the computer; at most the free disk less 20 GB, since the VM's
disk file grows as it fills), and builds no VM at all on a computer with less
than 4 GB of memory or 25 GB of free disk. `--memory` and `--disk` change it later: memory
from the VM's next start, the disk from its next build (`claude-vm rebuild`).
The choice is kept in `/etc/wren/claude-vm-size`, which only root can change.

## LIMITS

- Updates install themselves in a VM built since this was added: Debian's and Claude Code's. An older VM needs `claude-vm rebuild`, or `sudo apt update && sudo apt upgrade` in `claude-vm shell`.
- The agent has sudo without a password in the VM, so treat everything in it as under its control, including what the VM tells you. A VM built before this has no such rule and no clean snapshot: `claude-vm rebuild` adds both, and deletes what isn't pushed.
- QEMU runs under its own syscall filter, and the VM won't start unless the firewall is active, and an ssh login that forwards nothing. Its terminal output still reaches your terminal.
- A bug in QEMU or KVM could reach this computer; a VM is a stronger wall than a user, not a perfect one.
- It reaches the internet, so what it reads can leave the VM.
- Treat what it pushes as untrusted until you have read it (`claude-pull` shows it first).
- Its ssh key on your git host can push wherever you allow: a deploy key on one repository is the narrowest, and a rule on the host that only your signed commits go into your main branch keeps it to its `claude` branch.
- Two accounts' VMs are as far apart as two VMs on one computer: a bug in QEMU or KVM is the way between them too.

## MANUAL INSTALL

```
# KVM must be on: this must list /dev/kvm (if not, turn on VT-x / AMD-V in the firmware settings)
ls -l /dev/kvm
# QEMU, socat for a clean power-off, nftables for the firewall rule, ssh into
# the guest, and the installer's tools (gpgv and Debian's keyring check it)
sudo apt install --no-install-recommends qemu-system-x86 qemu-utils socat nftables openssh-client \
    cpio gzip wget gpgv debian-archive-keyring

# The claude-vm user, locked, with /dev/kvm as its only extra group
sudo useradd --create-home --home-dir /home/claude-vm --shell /bin/bash --user-group --comment "Wren Linux Claude Code VM" claude-vm
sudo usermod --lock claude-vm
sudo chmod 700 /home/claude-vm
sudo usermod -aG kvm claude-vm

# The firewall rule on that user (and so the guest), loaded at every boot
sudo install -D -o root -g root -m 0644 @WREN_DIR@/data/claude-vm-firewall.nft /etc/wren/claude-vm.nft
printf '%s\n' '[Unit]' 'Description=Keep the claude-vm user (and its guest) off the local network' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' 'ExecStart=/usr/sbin/nft -f /etc/wren/claude-vm.nft' \
    'ExecStop=/usr/sbin/nft delete table inet wren_claude_vm' '' '[Install]' 'WantedBy=multi-user.target' |
    sudo tee /etc/systemd/system/wren-claude-vm-firewall.service
sudo systemctl daemon-reload
sudo systemctl enable --now wren-claude-vm-firewall.service

# The VM engine, the session script, and the no-abstract-sockets wrapper, as root's files
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 @WREN_DIR@/vendor/mockvps-kvm/mockvps-kvm.sh /usr/local/libexec/claude-vm-mockvps-kvm
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/claude-vm-net-check /usr/local/libexec/claude-vm-net-check
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/claude-vm-session /usr/local/libexec/claude-vm-session
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/no-abstract-sockets /usr/local/libexec/wren-no-abstract-sockets
# The check that its firewall really holds: it won't start without it, and ends if it goes
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/sandbox-net-check /usr/local/libexec/wren-sandbox-net-check

# The provisioning script, with Anthropic's pinned key filled in, readable only by claude-vm
sudo install -d -o claude-vm -g claude-vm -m 0700 /home/claude-vm/.config /home/claude-vm/.config/claude-vm
sed -e 's|[@]ANTHROPIC_FPR@|@ANTHROPIC_FPR@|g' -e 's|[@]ANTHROPIC_KEY_URL@|@ANTHROPIC_KEY_URL@|g' -e 's|[@]VM_USER@|agent|g' \
    @WREN_DIR@/data/claude-vm-provision.sh |
    sudo install -o claude-vm -g claude-vm -m 0600 /dev/stdin /home/claude-vm/.config/claude-vm/provision.sh

# Your user may run the session script, and nothing else, as claude-vm. visudo
# checks the rule first: never put a rule in /etc/sudoers.d it hasn't passed.
printf '%s ALL=(claude-vm) NOPASSWD: /usr/local/libexec/claude-vm-session\n' "$(id -un)" >/tmp/wren-claude-vm
sudo visudo -cf /tmp/wren-claude-vm
sudo install -o root -g root -m 0440 /tmp/wren-claude-vm /etc/sudoers.d/wren-claude-vm
rm /tmp/wren-claude-vm

# The commands
install -D -m 0755 @WREN_DIR@/bin/claude-vm ~/.local/bin/claude-vm
install -D -m 0755 @WREN_DIR@/bin/claude ~/.local/bin/claude
install -D -m 0755 @WREN_DIR@/bin/claude-pull ~/.local/bin/claude-pull

# Build the VM (unattended, 10-20 minutes), then show its ssh key for your git host
# Its size in MiB (memory, disk), if not the engine's 2048 and 20000; leave
# this computer at least 4 GB of memory and 20 GB of disk
echo "claude-vm 4096 40000" | sudo tee /etc/wren/claude-vm-size
sudo -u claude-vm /usr/local/libexec/claude-vm-session install
sudo -u claude-vm /usr/local/libexec/claude-vm-session pubkey
claude-vm
```

The `sed` line fills the placeholders in `data/claude-vm-provision.sh` with
the pinned key; `--manual` prints it with the pinned values in place.

Another account, NAME (small letters and digits), after the steps above:

```
# Its user, locked, in the kvm group only
sudo useradd --create-home --home-dir /home/claude-vm-NAME --shell /bin/bash --user-group --comment "Wren Linux Claude Code VM" claude-vm-NAME
sudo usermod --lock claude-vm-NAME && sudo chmod 700 /home/claude-vm-NAME && sudo usermod -aG kvm claude-vm-NAME
# Its console port: one of 2250-2299 that nothing uses (ss -ltn shows those in use)
echo "NAME 2250" | sudo tee -a /etc/wren/claude-vm-ports
# Its firewall lines, by number (nft refuses the whole file over a user name
# that doesn't exist), with the number from: id -u claude-vm-NAME
# below the line  meta skuid "claude-vm" jump claude_vm  in /etc/wren/claude-vm.nft:
#         meta skuid NUMBER jump claude_vm  # claude-vm-NAME
# and below the line  meta skuid "claude-vm" ip daddr 127.0.0.1 tcp dport 2242 accept:
#         meta skuid NUMBER ip daddr 127.0.0.1 tcp dport 2250 accept  # claude-vm-NAME
sudo nft -c -f /etc/wren/claude-vm.nft && sudo systemctl restart wren-claude-vm-firewall
# Its provisioning script: as above, into /home/claude-vm-NAME/.config/claude-vm/provision.sh, owned by claude-vm-NAME
# Your user may run the session script, and nothing else, as it (checked first)
printf '%s ALL=(claude-vm-NAME) NOPASSWD: /usr/local/libexec/claude-vm-session\n' "$(id -un)" >/tmp/wren-claude-vm-NAME
sudo visudo -cf /tmp/wren-claude-vm-NAME && sudo install -o root -g root -m 0440 /tmp/wren-claude-vm-NAME /etc/sudoers.d/wren-claude-vm-NAME
rm /tmp/wren-claude-vm-NAME
sudo -u claude-vm-NAME /usr/local/libexec/claude-vm-session install
claude-vm --account NAME
```

To undo an account: `sudo rm /etc/sudoers.d/wren-claude-vm-NAME`,
`sudo pkill -KILL -u claude-vm-NAME`, `sudo userdel -r claude-vm-NAME` (its
VM goes with it), its line out of `/etc/wren/claude-vm-ports` and its two
lines out of `/etc/wren/claude-vm.nft`, then
`sudo systemctl restart wren-claude-vm-firewall`.

To undo:

```
# The commands (keep claude-pull if claude-code is set up)
rm ~/.local/bin/claude-vm ~/.local/bin/claude-pull
# (the claude command only if no other Claude Code is set up)
rm ~/.local/bin/claude
# The firewall rule
sudo systemctl disable --now wren-claude-vm-firewall.service
sudo rm /etc/systemd/system/wren-claude-vm-firewall.service /etc/wren/claude-vm.nft
sudo systemctl daemon-reload
# The sudo rule and root's scripts (the no-abstract-sockets wrapper and the firewall check only if
# incognito, claude-code and the Firefox sandbox don't use it)
sudo rm /etc/sudoers.d/wren-claude-vm /usr/local/libexec/claude-vm-session /usr/local/libexec/claude-vm-net-check /usr/local/libexec/claude-vm-mockvps-kvm
sudo rm /usr/local/libexec/wren-no-abstract-sockets
sudo rm /usr/local/libexec/wren-sandbox-net-check
# The user, its home and the VM in it
sudo pkill -KILL -u claude-vm
sudo userdel -r claude-vm
# QEMU and the tools, marked "automatic": autoremove takes them out only if
# nothing (Whonix, mockvps-kvm, the onion site) needs them
sudo apt-mark auto qemu-system-x86 qemu-utils socat nftables cpio
sudo apt autoremove --purge
```
