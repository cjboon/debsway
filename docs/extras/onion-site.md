# Your own onion site (`extras/onion-site.sh`)

This sets up a website at a `.onion` address, served from your computer, for sites that need more than plain files. The site runs inside a virtual machine (VM) that has no network at all, so nothing the site's software does can give away where your computer is. Only Tor, on your computer, can reach it.

## The problem it solves

The most common way an onion site gives away where it runs is its own software reaching out to the internet: loading an image or font, checking for updates, sending email, looking up a name. Each of those connections can show the real address. By putting the site where it cannot reach any network, these leaks are impossible.

## The ideas behind it

**Tor and an onion service.** Tor is a network of volunteer relays that hides who talks to whom. An onion service is a website reachable only through Tor at a `.onion` address, without anyone learning where it is hosted. A visitor opens it in Tor Browser. See `docs/extras/tor-browser.md`.

**A virtual machine.** A whole pretend computer run by a program (here QEMU with KVM) with its own disk and system. If something goes wrong inside, it stays inside the VM unless the program running the VM has a bug.

**No network, but two small doors.** After its first setup the VM runs with QEMU's `restrict=on`: the guest cannot send a single packet out. Two ports on your computer's own loopback lead in: its SSH console (2243) and its nginx web server (18080).

**nginx and an app server.** nginx serves static files (pages, images) and hands everything else to your own program running on `127.0.0.1:8000` inside the VM. **gunicorn** runs a Python **Flask** app. You choose which one when you set it up.

**Client authorization.** An option for a private site: only visitors who hold a key you gave them can even find it. Tor Browser asks for the key the first time.

**A firewall rule.** A rule that allows or refuses network traffic. Here it applies to the `onion-site` user, who runs the VM.

**A bridge.** A Tor relay not on the public list, for networks that block Tor. See "Bridges" in `docs/install-base.md`; obfs4 and Snowflake are offered here.

## How it works, step by step

1. **Needs `/dev/kvm`.** If missing, it tells you to turn on virtualization in the firmware.
2. **Asks first,** before installing anything: which app (1 `any`, your own server on `127.0.0.1:8000`; 2 `python`, a Flask app), who can reach it (public or private), and about a bridge if the system tor is not yet set up by something else.
3. **Installs** `qemu-system-x86`, `qemu-utils`, `socat`, `nftables`, `openssh-client`, `cpio`, `gzip`, `wget`, `gpgv`, `debian-archive-keyring`, `tor`, `openssl` (and a bridge program). Tor is kept from starting until its settings are in.
4. **Makes the `onion-site` user:** locked (no password, no login), in the `kvm` group.
5. **Loads a firewall rule for that user** (`data/onion-site-firewall.nft`, run at boot by `debsway-onion-site-firewall.service`). It keeps even the QEMU process off your router, printers, other machines and local services, except two loopback doors: the VM's SSH console (2243) and Tor's SOCKS port (9050, used only for updates). DNS is allowed. The internet is allowed because the first setup needs it.
6. **Installs the VM engine and the command:** `mockvps-kvm` from `vendor/` into `/usr/local/libexec/onion-site-mockvps-kvm`, the session script, a one-line sudo rule in `/etc/sudoers.d/debsway-onion-site` (checked with `visudo`) that lets you run only that script as `onion-site`, and `~/.local/bin/onion-site`.
7. **Sets up Tor's onion service** in `/etc/tor/torrc`: port 80 of the onion address leads to `127.0.0.1:18080`, with Tor's defences against floods of visits (and a proof-of-work defence where this Tor has it). The settings are checked before Tor restarts. If private, it makes a client key and shows it once.
8. **Starts Tor** and waits up to 3 minutes. It saves the address to `~/.local/state/debsway/onion-site-address`.
9. **Builds the VM** (asks first): this installs Debian and nginx (and gunicorn with Flask) in the VM, takes 5 to 15 minutes and downloads a few hundred MB, without Tor. The time zone in the VM is UTC; nginx shows no version and keeps no access log. After that the VM has no network.

## What it changes on your computer

- Packages: those listed above.
- The user `onion-site` and its home `/home/onion-site` (the VM and the site's data).
- `/etc/debsway/onion-site.nft`, `/etc/debsway/onion-site.conf`, `/etc/systemd/system/debsway-onion-site-firewall.service` (nft table `inet debsway_onion_site`).
- `/usr/local/libexec/onion-site-session`, `onion-site-mockvps-kvm` and the `no-abstract-sockets` helper; `/etc/sudoers.d/debsway-onion-site`.
- `/etc/tor/torrc` (marked blocks), `/etc/tor/.debsway-onion-site`, `/var/lib/tor/debsway-onion-site/` (the address and keys); `tor@default.service` enabled.
- `~/.local/bin/onion-site` and `~/.local/state/debsway/onion-site-address`.

## Using it

- `onion-site start | stop | status`: the site is up only while its VM runs.
- `onion-site upload static FOLDER`: your files, served as they are. It replaces what was there.
- `onion-site upload app FOLDER`: your app (Flask: `app.py` with `app = Flask(...)`; otherwise run it on `127.0.0.1:8000` through `onion-site shell`).
- `onion-site shell`: a shell in the VM as the user `site`.
- `onion-site update`: the VM's security updates. It lends the VM a relay to your Tor for apt only, upgrades, then takes it away.
- `onion-site address`: the address again. `onion-site rebuild`: a fresh VM (the address stays; the site's files do not).
- Run `bash extras/onion-site.sh` again for a new client key (private sites).
- Back up `/var/lib/tor/debsway-onion-site` as root to keep the address.

## What it protects against

- **The site's software giving away your address,** because the VM can send nothing out (`THREAT-MODEL.md`).
- **A hole in your app reaching your computer.** It gets the VM and the site's data, not your home or files.
- **Floods of visits,** partly, through Tor's defences.
- **The VM reaching your local network,** by the firewall rule on its user.

## What it doesn't protect against

- **When it is up.** The site is only up while your computer is on and the VM runs. That timing can link it to you. A dedicated machine is the right host for anything serious.
- **What you put in the site:** names, metadata in files, writing style.
- **A hole in QEMU or the kernel,** which a VM does not fully stop.
- **It is a service strangers can send requests to** (unless private). Turn it on only if you need it.
- **Your network seeing that you use Tor,** unless you chose a bridge.
- **Fetching anything at run time.** The app cannot reach the internet, ever; this is a limit, not a protection.

## Removing it

`bash extras/onion-site.sh --remove` stops the VM, removes the Tor blocks, the marker, the firewall service and rule, the sudo rule, helper scripts and the command. It asks before deleting the `.onion` address (default: keep) and before deleting the `onion-site` user and its home, which holds the VM and the site's data (default: keep). It uninstalls the packages it added, unless another debsway script needs them.
