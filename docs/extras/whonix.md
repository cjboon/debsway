# Whonix, Tor in a virtual machine (`extras/whonix.sh`)

Whonix is a pair of virtual computers that run inside your computer. One of them (the Gateway) runs Tor. The other (the Workstation) is where you browse, and it can reach the internet only through the Gateway. This extra downloads Whonix, checks it, installs the tools to run it, and sets it up so you can start it with one command.

## The problem it solves

Tor Browser hides your real internet address, but it runs as an ordinary program on your computer. If someone broke into the browser, the program could look at your real network connection and tell the attacker your real address.

Whonix puts the browser in a separate box that has no way out except through Tor. Even a hacked browser inside that box has no real address to find, because the box has never been given one.

## The ideas behind it

**Tor.** A network of volunteer relays that passes your traffic through three hops so that no single relay knows both who you are and where you are going. `extras/tor-browser.md` explains it in more detail.

**A virtual machine (VM).** A VM is a whole computer simulated by a program. It has its own disk, its own system and its own network card, all pretend. Whatever happens inside stays inside unless the program running it has a bug. It is like a room with its own door and no windows: the outside only sees what you let through.

**KVM and QEMU.** KVM is a feature of Linux (and of your processor) that lets VMs run at nearly full speed. QEMU is the program that builds the pretend computer. `libvirt` and `virt-manager` are the tools that define VMs and show their screens.

**Gateway and Workstation.** The Gateway has two network connections: one to the real internet, over which it speaks only Tor, and one private link to the Workstation. The Workstation has only the private link. Everything it sends leaves via Tor, or does not leave.

**Bridges.** A bridge is a Tor relay that is not on the public list, for networks that block Tor. See "Bridges" in `docs/install-base.md`. The Whonix Gateway can use obfs4 and Snowflake. It cannot use webtunnel or meek, because it has no program for them.

**A signature check.** A signature is a mathematical stamp made with a secret key that anyone can check with the public key. If a single byte of the download changed, the check fails.

## How it works, step by step

1. **Needs `/dev/kvm`.** If it is missing, the script stops and tells you to turn on virtualization (VT-x or AMD-V) in the firmware settings.
2. **Installs the tools:** QEMU, libvirt, `virt-manager`, SPICE, `passt`, `ovmf`, `swtpm`, `qemu-utils`, `xz-utils`, `e2fsprogs` and `fdisk` (the list follows Whonix's own KVM instructions for Debian trixie). It adds you to the `kvm` and `libvirt` groups if you are not in them; log out and back in once for that to apply. It writes `~/.config/libvirt/qemu.conf` (no core dumps, no limits that a normal user cannot set), unless that file exists.
3. **Downloads Whonix** (about 1.9 GB, the LXQt edition). It reads the newest version number from whonix.org's KVM page, downloads the image and its signature, and checks the signature against Whonix's signing key, whose fingerprint is pinned in `pins.sh`. If the check fails, the download is deleted. The file is kept in `offline/whonix/`, so a reinstall does not fetch it again. `bash extras/whonix.sh --fetch` does only this step.
4. **Unpacks it** and shows you where Whonix's license and disclaimer are. You have to confirm that you read and accept them.
5. **Asks about a bridge** for the Gateway. If you give one, the script writes it into the Gateway's disk image as `/usr/local/etc/torrc.d/50_user.conf`, so its first connection uses it. If you say you need a bridge but have none yet, it writes `DisableNetwork 1` so Tor stays off until you turn it on in the Gateway (`whonix gateway`). If you say no bridge, nothing is written and the Gateway connects directly at its first boot.
6. **Sets the Workstation's browser** to Safest with JavaScript off, by writing `data/tor-browser-safest.js` into the Workstation image as `/usr/local/etc/torbrowser.d/user.js`.
7. **Edits the images without mounting them,** using `qemu-img` and `debugfs`. The script reads every written file back to make sure it is correct and checks the filesystem afterwards.
8. **Defines the VMs** (`Whonix-Gateway` and `Whonix-Workstation`) with libvirt, in a disk pool called `default` pointing at `~/.local/share/libvirt/images`, and installs the `whonix` command.

Everything runs as your user, through `qemu:///session`. There is no root service and no network setup on the host.

## What it changes on your computer

- Packages: the KVM and libvirt tools listed above.
- You are added to the groups `kvm` and `libvirt`.
- `~/.config/libvirt/qemu.conf` (if it did not exist).
- `offline/whonix/` in the debsway folder: the downloaded archive, its signature and the signing key.
- `~/.local/share/libvirt/images/Whonix-Gateway.qcow2` and `Whonix-Workstation.qcow2`: the VMs' disks.
- Two libvirt VM definitions and a libvirt storage pool called `default` (set to start automatically).
- `~/.local/bin/whonix`.
- No firewall rules and no services of its own.

## Using it

- `whonix` starts both VMs and opens the Workstation's screen.
- `whonix gateway` starts the Gateway and opens it, for the Tor settings.
- `whonix stop` shuts both down.
- `bash extras/whonix.sh` again: repair, or notes "already installed".

## What it protects against

- **A hacked browser revealing your real address.** The Workstation's only network is the Gateway. This is the main point of the extra and is stated in `THREAT-MODEL.md`.
- **Your network seeing that you use Tor,** if you chose a bridge. It is set before the first connection.
- **A tampered download,** thanks to the signature check against a pinned key.
- **Browser exploits reaching your files,** at least in the usual case: the browser sits in a VM, apart from your home folder.

## What it doesn't protect against

- **A bug in QEMU or the kernel.** The VM is a wall, not a vault. A serious bug could let an attacker out of the VM.
- **Telling a site who you are.** If you log in, the site knows. Tor hides your address, not your identity.
- **Habits and mistakes,** such as moving files between the VM and your computer, or using your name.
- **Your network seeing the first connection to Whonix's website** to fetch the download, as no Tor is available yet.
- **Whonix's own limits.** This script installs Whonix; it does not change what Whonix does inside.
- **A laptop that is on or asleep** (`THREAT-MODEL.md`).
- **A determined, well-funded attacker** who targets you.

## Removing it

`bash extras/whonix.sh --remove` first asks whether to delete the disks (`Whonix-*.qcow2`), which hold everything you saved inside the VMs; the default is no. Then it stops and removes both VM definitions. If you keep the disks, installing Whonix again asks before it puts fresh disks in their place. It removes the `whonix` command and uninstalls the KVM and virt-manager packages, unless another debsway script still needs them. It keeps the downloaded archive in `offline/whonix/` and tells you to delete it yourself if you like. It does not remove `~/.config/libvirt/qemu.conf` or take you out of the `kvm` and `libvirt` groups.
