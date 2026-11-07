# What Wren Linux adds to Debian

Debian 13 is a careful system already, and Wren Linux is built on it, not around it. This page
lists what Wren Linux changes or adds for security and privacy, what Debian does there by
itself, and how to check each one on your own computer. It says what's different, not how
safe you are: for that, read [what Wren Linux protects against, and what it doesn't](../THREAT-MODEL.md).

Debian's side was measured on Debian 13 (kernel 6.12): a plain install's settings, its kernel's
build options, and its live "standard" image's package list. A row isn't a promise that a setting
stops an attack. Most of them make one harder, and many are small on their own.

## What Debian already gives you

Wren Linux relies on these, and doesn't take credit for them:

- **Signed packages:** apt checks every package against Debian's signing keys.
- **Security fixes,** from Debian's security team, for its whole archive.
- **AppArmor,** on by default, confining the programs that ship a profile.
- **Private home folders** for new users (`HOME_MODE 0700`).
- **Kernel defaults:** memory cleared when handed out (`init_on_alloc`), a random kernel stack
  offset, no legacy `vsyscall`, kernel log hidden from users (`dmesg_restrict`), and `protected_regular`.
- **Disk encryption,** when you choose it in the installer. Wren Linux's guide and install image choose it.

## In the base install

Everyone who installs Wren Linux gets these. The script named in each row does it, and its `--remove` undoes it.

### Updates and what you run

| Debian 13 by itself | Wren Linux | Script | Check |
|---|---|---|---|
| Automatic updates are a choice, and not on the live image | On, every day | `parts/unattended-upgrades.sh` | `systemctl status apt-daily.timer` |
| A daily update that can't reach any server still counts as done, and says nothing | The bar says so at once, if you're online | `parts/unattended-upgrades.sh` | `cat /run/wren-updates/state` |
| Nothing lists programs still running old, unfixed libraries | They're listed after every apt run | `parts/needrestart.sh` | `sudo needrestart` |
| Updates to scripts come from wherever you got them | `update.sh` takes only what Wren Linux's key signed, checked with the pin you already have | `update.sh` | `grep WREN_SIGNING_FPR ~/wren/pins.sh` |
| Anything you download by hand is on you | Programs the extras download from outside Debian are checked against a signing key pinned in `pins.sh` | `lib/appimage.sh` | `less ~/wren/pins.sh` |

### Network

| Debian 13 by itself | Wren Linux | Script | Check |
|---|---|---|---|
| No firewall set up | Nothing comes in unless you allow it | `parts/ufw.sh` | `sudo ufw status` |
| DNS goes to the network's server, unencrypted | Unbound checks answers with DNSSEC, and asks a resolver you pick, over TLS. It fails closed, with a switch for sign-in pages | `parts/secure-dns.sh` | `cat /etc/resolv.conf` |
| dhcpcd and dhclient send this computer's name to each network | They don't | `parts/dhcp-no-name.sh` | `grep 'no name sent' /etc/dhcpcd.conf` |
| Wi-Fi uses the card's real hardware address, with NetworkManager's defaults | A made-up address at each connection, no name sent, temporary IPv6 addresses | `parts/random-mac.sh` | `ip link` |
| The live image installs avahi, which announces this computer's name on every network, and hw-probe | Taken out, with printing unless you print | `parts/no-live-extras.sh` | `systemctl status avahi-daemon` |
| Has no sandbox users like these | DNS from its sandbox users goes only to the resolver this computer uses, so a hacked sandbox can't reach what else listens on port 53 nearby. It can still send data out | `parts/sandbox-dns.sh` | `sudo nft list ruleset \| grep -A3 resolvers` |
| NetworkManager connects a new USB network device by itself | It asks first, for the drivers phones use | `parts/tether.sh` | `cat /etc/NetworkManager/conf.d/90-wren-tether.conf` |

### The kernel

| Setting | Debian 13 | Wren Linux | What it's for |
|---|---|---|---|
| `kernel.kptr_restrict` | 0 | 2 | Hides kernel addresses, which exploits use |
| `kernel.yama.ptrace_scope` | 0 | 1 | A program can only trace its own children |
| `kernel.kexec_load_disabled` | 0 | 1 | No swapping in another kernel while running |
| `kernel.sysrq` | 438 | 0 | Turns the magic keys off: from the keyboard, they could end a locked desktop |
| `kernel.io_uring_disabled` | 0 | 2 | Off: where many recent kernel exploits came from |
| `dev.tty.ldisc_autoload` | 1 | 0 | Users can't load terminal line disciplines |
| `fs.protected_fifos` | 1 | 2 | Stricter about pipes in shared folders |
| `net.ipv4.conf.default.accept_redirects` | 1 | 0 | The network can't re-route you by message |
| `net.ipv6.conf.all.accept_redirects` | 1 | 0 | The same, for IPv6 |
| `net.ipv4.conf.all.secure_redirects` | 1 | 0 | The same, even from your router |
| `net.ipv4.conf.all.send_redirects` | 1 | 0 | This computer isn't a router |
| `net.ipv4.tcp_rfc1337` | 0 | 1 | A small fix for a rare TCP attack |

Check one with `sysctl kernel.kptr_restrict`. All of them, with a few more where Debian already agrees: `parts/sysctl-hardening.sh` and `data/sysctl-hardening.conf`.

| At boot | Debian 13 | Wren Linux (`parts/boot-hardening.sh`) |
|---|---|---|
| `init_on_free=1` | Off | Memory is cleared when freed too, at a few percent of speed |
| `slab_nomerge` | Merging on | Kernel memory kinds are kept apart |
| `page_alloc.shuffle=1` | Built in, off | Memory layout is harder to predict |
| `debugfs=off` | On | A large part of the kernel's surface is gone |
| `intel_iommu=on` | Off unless the firmware asks | Devices reach only the memory their driver gave them |
| `iommu.strict=1` | Lazy | ...and lose it as soon as the driver is done |

Check with `cat /proc/cmdline`, after a reboot. Its line also repeats three Debian already defaults to.

Rare network protocols and old filesystems (`dccp`, `sctp`, `rds`, `tipc`, `cramfs`, `jffs2`, `hfs` and more), and FireWire, which can read memory directly, can't be loaded: `parts/module-blacklist.sh`. Check with `cat /etc/modprobe.d/60-wren-blacklist.conf`.

### At the computer

| Debian 13 by itself | Wren Linux | Script | Check |
|---|---|---|---|
| sudo remembers your password for 15 minutes | For 1 minute, in that terminal only | `parts/sudo-timeout.sh` | `sudo -l` |
| New users' home folders are private, but new files can be read by others, so a folder opened to a sandbox would show them | New files are private (`umask 077`), and everything directly in your home is closed to others | `parts/home-private.sh` | `umask` |
| A screen lock is up to your desktop, and a bare install has none | Locks when idle, and before suspend | `parts/swayidle.sh`, `parts/swaylock.sh` | `timer lock` |
| USB sticks are mounted as root if you `sudo mount` them | Mounted as you, with `nosuid,nodev,noexec` | `parts/usb.sh` | `usb` |
| Shutting down takes a command, or a desktop's menu | A power menu on a key combination: shutting down is the safe state for a laptop you're leaving | `parts/power-menu.sh` | Super+Shift+Escape |

## Only if you choose them

These are extras (`wrenctl --apps`). `wrenctl manual NAME` shows each step by hand, and [docs/extras/](extras/README.md) has a page for each, with its limits.

| Extra | What it adds |
|---|---|
| `firefox-sandbox` | Firefox as its own locked-down user, with uBlock Origin, HTTPS-Only Mode, no JavaScript JIT, and `incognito`, a throwaway one |
| `claude-vm` | A coding agent in a disposable VM, walled off from your files |
| `media`, `pdf-viewer`, `gimp` | Opening pictures, video and PDFs in a sandbox |
| `yt-dlp` | A video downloader as its own locked user |
| `tor-browser`, `whonix`, `onionshare`, `onion-site` | Tor, with bridges, checked downloads, and Tor Browser at Safest |
| `mullvad-vpn` | A VPN, from Mullvad's signed repository |
| `backup`, `vault` | Encrypted backups, and an encrypted folder that locks itself |
| `keepassxc` | A password manager, locked at every screen lock |
| `security-key`, `hardware-wallet` | Hardware keys for SSH, the web and sudo, and hardware wallets |
| `startup-watch` | Notices changes to what starts at your login, and shows it in the bar |
| `metadata-cleaner` | Takes hidden data out of files you share |
| `tails-usb`, `get-iso` | Other systems' images, checked against pinned keys, onto a stick |
| `webcam`, `bluetooth` | Off at start, with a switch in the menu |

## What this costs

Most of these have a price: JavaScript is slower without the JIT, `init_on_free` takes a little speed, `gdb` and `strace` can't attach without sudo, some sticks won't mount, and Wi-Fi sign-in pages may ask again. [THREAT-MODEL.md](../THREAT-MODEL.md), under "Trade-offs", has more.

And a setting list isn't the whole picture: a hardened desktop can still run something bad that you start yourself.
