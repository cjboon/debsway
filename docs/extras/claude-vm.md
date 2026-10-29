# Claude Code inside a disposable virtual machine (`extras/claude-vm.sh`)

You get a `claude-vm` command that runs Claude Code inside a small Debian virtual machine, a computer simulated inside your computer, with no shared folder. The assistant hands work back only by pushing to a git host (GitHub, for example), and you bring it in with `claude-pull` after reading it. This is the stronger of debsway's two Claude Code sandboxes and needs KVM.

## The problem it solves

A coding assistant reads and writes files and runs commands. Even run as a separate user (`extras/claude-code.sh`), it shares your computer's kernel, the core of the operating system. A bug in the kernel could in principle let a program step out of its user.

A virtual machine puts a much thicker wall in the way. The assistant runs on a different kernel, in a different filesystem, and if it makes a mess you delete the machine.

## The ideas behind it

**A virtual machine (VM).** A whole computer simulated by a program. It has its own disk (a file on your real disk), its own memory and its own operating system, called the guest. Your real computer is the host. Programs in the guest cannot see the host's files.

**KVM and QEMU.** KVM is a feature of the Linux kernel, switched on by your processor, that lets a VM run at nearly full speed. QEMU is the program that creates the VM. To check this computer, both of these should succeed:

```
grep -cE 'vmx|svm' /proc/cpuinfo
ls -l /dev/kvm
```

A number above 0 means the processor can do it, and `/dev/kvm` means the kernel can too. If not, virtualization may be off in the BIOS, the CPU may be too old, or you may already be inside a VM.

**A separate Linux user.** Each account has its own files. The VM runs as a locked user, `claude-vm`, with no password and no login. QEMU is the one process it runs.

**sudo and a sudoers rule.** `sudo` runs a command as another user. A sudoers rule, in `/etc/sudoers.d/debsway-claude-vm`, lets your user run exactly one script as `claude-vm`, without a password.

**A firewall rule.** An instruction to the network layer to allow or refuse certain connections. QEMU's simple networking turns the guest's traffic into ordinary connections owned by `claude-vm`, so a rule on that user governs the guest too.

**git push.** Git sends a copy of your work to a server with `git push`. With no shared folder, this is the only way work leaves the VM, and you review it before you take it.

## How it works, step by step

When you run `bash extras/claude-vm.sh`:

1. It stops if `/dev/kvm` does not exist.
2. It installs `qemu-system-x86`, `qemu-utils`, `socat`, `nftables`, `openssh-client`, `cpio`, `gzip`, `wget`, `gpgv` and `debian-archive-keyring`.
3. It creates the user `claude-vm` (home `/home/claude-vm`, mode 700, locked) and adds it to the `kvm` group, its only extra group.
4. It installs the firewall rule `/etc/debsway/claude-vm.nft` and the service `debsway-claude-vm-firewall`, loaded at every boot. For `claude-vm` it accepts DNS and the internet, and rejects connections to this computer and to private address ranges, with one exception: loopback TCP to port 2242, the guest's own ssh console, which the host needs to log in.
5. It installs the bundled VM tool `vendor/mockvps-kvm/mockvps-kvm.sh` as `/usr/local/libexec/claude-vm-mockvps-kvm`, the session script `/usr/local/libexec/claude-vm-session`, `debsway-no-abstract-sockets`, and a copy of `data/claude-vm-provision.sh` (with Anthropic's pinned key fingerprint filled in) in `/home/claude-vm/.config/claude-vm/`.
6. It writes the sudoers rule (checked with `visudo`) and installs `claude-vm` and `claude-pull` into `~/.local/bin`.
7. It offers to build the VM now. If one already exists, it is kept as it is. Building takes 5 to 15 minutes and downloads a few hundred MB: an unattended Debian install (the installer's kernel is checked against Debian's signed lists), then the provision script runs inside the guest as root. It installs a few tools (`git`, `openssh-client`, `ripgrep`, `jq`, `shellcheck`, `python3-venv`), checks Anthropic's apt key against the same pinned fingerprint, installs `claude-code`, creates `~/projects` in the guest, gives the agent its own git identity (Claude, noreply@anthropic.com) and its own ssh key, and writes a short `CLAUDE.md` note telling the agent where it is. It then prints the guest's public ssh key; add it on your git host.

When you run `claude-vm` (in a terminal, or in wmenu with Super+d, which opens its own foot window):

1. The session script runs as `claude-vm`, through `debsway-no-abstract-sockets` (Landlock stops it connecting to X11's abstract sockets).
2. If the VM is off, it starts it ("about a minute"), with QEMU on KVM. Once running, connecting is quick.
3. It logs into the guest over ssh with a key kept by `claude-vm`, to `127.0.0.1:2242`, and runs `claude` in the guest's `~/projects`.

The guest's `CLAUDE.md` tells the agent it can use `sudo` in the guest, and that nothing in the VM is kept unless pushed.

## What it changes on your computer

- Packages: `qemu-system-x86`, `qemu-utils`, `socat`, `nftables`, `openssh-client`, `cpio`, `gzip`, `wget`, `gpgv`, `debian-archive-keyring`.
- The user `claude-vm`, in the `kvm` group, and its home `/home/claude-vm`: the VM disk (`vm/claude-vm.qcow2`), logs, its ssh key and the provision script.
- `/etc/sudoers.d/debsway-claude-vm`.
- `/usr/local/libexec/claude-vm-session`, `claude-vm-mockvps-kvm`, `debsway-no-abstract-sockets`.
- `/etc/debsway/claude-vm.nft` and `/etc/systemd/system/debsway-claude-vm-firewall.service`.
- Commands `claude-vm` and `claude-pull` in `~/.local/bin`.
- While the VM runs: one `qemu-system-x86_64` process as `claude-vm`.

It does not touch `extras/claude-code.sh`, and they can be installed together.

## Using it

- `claude-vm`: start Claude Code in the VM (booting it first if needed).
- `claude-vm shell`: a plain shell in the VM.
- `claude-vm status`: is it running?
- `claude-vm stop`: power it off.
- `claude-vm pubkey`: the VM's public ssh key, to add on your git host (a deploy key on one repository is narrowest).
- `claude-vm rebuild`: throw the VM away, with anything not pushed, and build a fresh one.
- `claude-pull`: in your own clone, fetch what the agent pushed, show the commits, and ask before merging (fast-forward only).

Running `claude-vm.sh` again keeps an already-built VM and what is unpushed in it.

## What it protects against

- **A kernel bug reaching your computer through the assistant.** The guest has its own kernel. Escape would need a flaw in QEMU or the hypervisor, a smaller surface than the shared kernel.
- **Reading your files, ssh keys, passwords.** There is no shared folder, and the guest holds none of them.
- **Reaching your network and local services.** The firewall rule on `claude-vm` rejects your router, printers and local programs; only the guest's own ssh console is allowed on loopback.
- **Using your ssh identity.** The guest has its own key and git identity.
- **X11 snooping** through the abstract socket, for the host-side processes.
- **Surprise changes in your repository.** The only way out is a push you review before merging.

## What it doesn't protect against

- **The internet.** The agent can send anything it can read to anywhere online, including your repository contents if you push them.
- **What you pull in.** Work it pushes is still untrusted until you have read it.
- **A VM escape.** Rare, but QEMU is not a perfect wall.
- **Losing unpushed work.** If you rebuild or remove the VM, anything not pushed is gone.
- **Something you tell it.** It can use any secret you paste into the guest.
- **Sudo inside the guest.** The agent may use it there; that only affects the VM.

## Removing it

`bash extras/claude-vm.sh --remove` removes the `claude-vm` command, the firewall service and rule, the sudoers rule, the session script and VM tool, and then asks whether to delete the user `claude-vm` and its home (the VM disk, its ssh key and settings). The default is no: they are kept. Then it purges the QEMU packages unless another extra needs them. `claude-pull` stays if `claude-code.sh` is still set up. `extras/claude-code.sh`, if installed, is untouched.
