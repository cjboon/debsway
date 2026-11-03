# mockvps-kvm, a throwaway VPS (`extras/mockvps-kvm.sh`)

## SYNOPSIS

```
wrenctl install mockvps-kvm                     install what it needs and the mockvps-kvm command
wrenctl remove mockvps-kvm                      remove the command (VMs stay: mockvps-kvm --uninstall first)
wrenctl manual mockvps-kvm                      print the manual steps below

mockvps-kvm                    install a fresh Debian VM (5-15 min)
ssh mockvps-kvm                log in to it (key only)
mockvps-kvm --status | --stop | --start
mockvps-kvm --snapshot clean   save the disk; --restore clean goes back
mockvps-kvm -P nginx --provision setup.sh   extra packages, then your script as root
mockvps-kvm --uninstall        delete the VM and every trace of it
http://localhost:8080          the VM's port 80, while "ssh mockvps-kvm" is open
```

mockvps-kvm makes a disposable Debian "VPS" on this computer with QEMU/KVM,
for trying out server setups: you log in with ssh, take snapshots, and throw
it away with one command. It installs Debian from Debian's netboot files,
checked against Debian's signed release file. Nothing in it is reachable from
your network. The program is `vendor/mockvps-kvm/mockvps-kvm.sh` (its
`README.md` is the full guide); this extra installs what it needs and links
`~/.local/bin/mockvps-kvm` to it. It needs KVM (`/dev/kvm`).

## LIMITS

- The VM shares this computer's kernel's KVM: a bug in QEMU or KVM could reach this computer.
- It's for trying things out, not for running a real service.
- The VM can reach the internet.

## MANUAL INSTALL

```
# KVM must be on: this must list /dev/kvm (if not, turn on VT-x / AMD-V in the firmware settings)
ls -l /dev/kvm
# QEMU and what mockvps-kvm uses: gpgv and Debian's keyring check the netboot
# files, socat for clean shutdowns, iproute2 for ss
sudo apt install --no-install-recommends qemu-system-x86 qemu-utils wget cpio gzip openssh-client \
    gpgv debian-archive-keyring socat iproute2
# Your user may use KVM (log out and back in once after this)
sudo adduser "$(id -un)" kvm
# The command: a link to the program in Wren Linux
mkdir -p ~/.local/bin
ln -sfn @WREN_DIR@/vendor/mockvps-kvm/mockvps-kvm.sh ~/.local/bin/mockvps-kvm
chmod +x @WREN_DIR@/vendor/mockvps-kvm/mockvps-kvm.sh
mockvps-kvm
```

To undo:

```
# Delete each VM first (add -n NAME for others)
mockvps-kvm --uninstall
# The command
rm ~/.local/bin/mockvps-kvm
# QEMU and the tools, marked "automatic": autoremove takes them out only if
# nothing (Whonix, claude-vm, the onion site) needs them
sudo apt-mark auto qemu-system-x86 qemu-utils cpio socat
sudo apt autoremove --purge
```
