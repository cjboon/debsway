# A disposable practice server (`extras/mockvps-kvm.sh`)

You get a `mockvps-kvm` command that builds a small Debian server inside a virtual machine on your own computer. You log into it with ssh, try things, and delete every trace with one command. It is for practising server setup, testing scripts and running a throwaway website, without a rented server.

## The problem it solves

A "VPS" is a small server you rent online. If you want to learn to set one up, or try a setup script before running it on a real one, mistakes cost time, and sometimes money or a locked-out server. Trying the same things on your own laptop is risky, because a script written for a server can change a lot.

A disposable VM gives you a real Debian server to break. You can save its disk state, go back, or delete it.

## The ideas behind it

**A virtual machine (VM).** A whole computer simulated by a program, with its own disk, memory and operating system (the guest). Your real computer is the host. Programs in the guest cannot see the host's files.

**KVM and QEMU.** KVM is a feature of the Linux kernel, enabled by your processor, that makes a VM run at nearly full speed. QEMU is the program that creates the VM. This extra needs `/dev/kvm`; if it is missing, virtualization (VT-x or AMD-V) may be off in the BIOS.

**ssh.** A way to log into another computer over a network and type commands there. It uses a key pair: a private key that stays on your computer and a public key placed on the server. Only your key opens the door; passwords are not used.

**A snapshot.** A saved copy of the disk's state. You can return to it later, like a save point in a game.

**A port forward.** QEMU makes the VM's ssh door appear on your own computer at `127.0.0.1` (this computer only), port 2232. Nothing on your network can reach it.

**Provisioning.** Running a setup script inside the new server to install and configure what you want.

## How it works, step by step

When you run `bash extras/mockvps-kvm.sh` (as your normal user):

1. It stops if `/dev/kvm` does not exist.
2. It installs `qemu-system-x86`, `qemu-utils`, `wget`, `cpio`, `gzip`, `openssh-client`, `gpgv`, `debian-archive-keyring`, `socat` and `iproute2`.
3. If you are not in the `kvm` group, it adds you (with sudo) and warns you to log out and in once. The command works until then.
4. It makes `~/.local/bin/mockvps-kvm`, a symlink to `vendor/mockvps-kvm/mockvps-kvm.sh`. It will not replace an existing file there that is not debsway's. The script in `vendor/` is the program itself and refuses to run directly until this setup is done (`MOCKVPS_FORCE=1` overrides).

Then, when you run `mockvps-kvm`:

1. It downloads Debian's official network-install kernel and initrd over https and checks them against Debian's checksums. If `gpgv` and the Debian keyring are present, it also checks the checksum file's signature.
2. It makes a random 30-character password for the guest (kept 0600 in `~/vpskvm/credentials/mockvps-kvm.env`, used for `sudo` in the guest only) and a dedicated ssh key, `~/.ssh/mockvps-kvm_id`.
3. It runs an unattended Debian install in QEMU, headless, which typically takes 5 to 15 minutes. Defaults are 2 CPUs, 2 GiB of memory, a 20 GB disk, and a guest user named `vps`.
4. It adds a block to `~/.ssh/config` so `ssh mockvps-kvm` works. In the guest, ssh is key-only and root login is off.
5. After this, the VM runs as one `qemu-system-x86_64` process under your user, with its files in `~/vpskvm/`.

## What it changes on your computer

- The packages listed above.
- Your user is added to the `kvm` group, if needed.
- `~/.local/bin/mockvps-kvm` (a symlink into the repository).
- When you build a VM: `~/vpskvm/` (disk, logs, boot files, credentials), `~/.ssh/mockvps-kvm_id` and its `.pub`, and a marked block in `~/.ssh/config` (a backup is kept).
- Nothing listens on your network. The guest's ssh is on `127.0.0.1` only.

## Using it

- `mockvps-kvm`: build a fresh VM and wait for ssh.
- `ssh mockvps-kvm`: log in. While that session is open, `http://localhost:8080` shows the VM's port 80.
- `mockvps-kvm --status`, `--stop`, `--start`: check, power off gracefully, boot again.
- `mockvps-kvm --snapshot clean` and `--restore clean`: save the disk and go back; `--snapshots` lists them.
- `mockvps-kvm -P nginx --provision setup.sh`: extra packages, then your script as root in the guest.
- `mockvps-kvm --uninstall`: delete the VM and its traces; `--uninstall --dry-run` only lists them.
- `-n NAME` and `-p PORT` let you run several VMs. The full guide is `vendor/mockvps-kvm/README.md`.

## What it protects against

- **Damage to your real system from experiments.** A broken server setup lands in the guest, which you can restore or delete.
- **Network exposure.** The guest's ssh and web tunnels exist only on your computer's loopback. Login is by key only.
- **Tampered installer files.** The kernel and initrd are checked against Debian's checksums, and the checksums against Debian's signature when the tools are present.

## What it doesn't protect against

- **It is not a security sandbox.** The VM can reach the internet and your local network through QEMU's ordinary networking, and nothing here limits it. Do not run software you do not trust in it and expect your computer to be safe. For a limited guest, see `extras/claude-vm.sh`.
- **A VM escape.** A bug in QEMU or the kernel could in theory get out.
- **A kernel bug affecting the host.** Your user runs QEMU, with your permissions, with access to everything you own.
- **Lost work.** Anything inside the VM is gone when you uninstall or restore a snapshot.
- **Plain-text password file.** The guest's sudo password is stored readable by you in `~/vpskvm/credentials/`.
- **Snapshots of memory.** They capture the disk only, and the VM is powered off to take them.

## Removing it

`bash extras/mockvps-kvm.sh --remove` removes the `mockvps-kvm` command (only if it still points at debsway's script) and the packages it installed, unless another extra such as Whonix needs them. VMs you made are not touched, and neither is the `kvm` group membership. Remove a VM first with `mockvps-kvm --uninstall` (add `-n NAME` for others), because after the command is gone it is awkward to find.
