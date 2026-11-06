# What install-base.sh does

`install-base.sh` turns a bare Debian 13 into the Wren Linux desktop, in six steps:

1. **It explains and asks.** Nothing changes until you agree.
2. **You pick your extras.** They install at the end, so you answer everything up front.
3. **It installs the core packages:** sway, a terminal, and a few tools.
4. **It sets up the desktop:** sway, the bar and the key cheat sheet.
5. **It runs every base part:** the firewall, the screen lock, kernel hardening and the rest.
6. **It installs the extras you picked.**

The rest of this page goes through each step, then each part, one at a time.

## 1. It explains and asks

`prep/intro.sh` says what is about to happen, shows a disclaimer, and asks whether to go on.
`bash install-base.sh --yes` skips it.

## 2. You pick your extras

Right after you agree, it shows the list of optional extras (`install-extras.sh --choose`).
Nothing is checked for you. What you pick is installed once the base is done.

- Arrow keys move, and the space bar checks a box.
- `/` or Tab searches.
- Enter goes on.

`wrenctl --apps` shows the list again whenever you like, and `wrenctl --apps --list` only prints it.

There is no web browser until you pick one: Firefox and w3m are in the list.

## 3. It installs the core packages

All with `--no-install-recommends`: `sway foot libgl1-mesa-dri gpg age diceware`.
Every part then installs its own packages, listed [below](#the-parts).

| Tool | What it's for |
|---|---|
| `gpg` | Checks downloads |
| `age` | Encrypts a file to a password or a key: `age -p file >file.age`, and `age -d file.age` decrypts it |
| `diceware` | `diceware -n 6` makes a passphrase of six random words, from the system's secure random source |

## 4. It sets up the desktop

**sway:** a copy of the stock config, plus one `include` line for `~/.config/sway/config.d/`.
An existing sway config is kept: only the include line is added. Every snippet is checked with
`sway -C` before it's kept. Windows have no borders (`appearance.conf`).

**Starting it:** sway starts when you log in on tty1, from a marked block in `~/.profile`.

**The login:** at its first run on an encrypted disk, it also sets up the login without your password
on tty1 (`extras/autologin.sh --encrypted-only`). The disk passphrase at boot is the lock then, and
the screen lock and sudo still ask for yours. On a disk that isn't encrypted it doesn't.
`wrenctl remove autologin` takes it out, and later runs leave that alone.

**The bar** is see-through black, and it's only changed if it's still the stock one. It has:

- a clickable **Wren Menu**: a gray menu with your browser, password manager and terminal, then
  Apps, Wi-Fi, Settings, System and Power, and Help
- your Wi-Fi name
- volume and brightness, which you can scroll
- a battery you can click for the time left

**The key cheat sheet:** `Super+?`, the `keys` command, or `~/KEYS.txt` (a link to the one copy).
The first time sway starts, it asks whether sway's shortcuts use Super, the Windows key, or Alt.
`keys --mod alt` and `keys --mod super` switch later, and the sheet shows whichever you use.
Plain text consoles get a one-line hint.

**Screens:** `display-scale` sets the text size of each screen, remembered per screen
(`display.conf`). A watcher started by sway says once, in a notification, when a sharp screen is
still at scale 1, also when you plug one in later. A screen's size comes from its own data in
`/sys/class/drm`. Without it, the sharpness is unknown and nothing is said.

### Timers and alarms

`timer` (Super+t, or a click on the time in the bar) uses systemd user timers and no extra package.
The next one shows in the bar.

| Command | What it does |
|---|---|
| `timer 10m tea` | A timer |
| `timer at 7:30` | An alarm |
| `timer list` | What is running |
| `timer cancel` | Cancels one |
| `timer stop` | Ends the ringing. Clicking the notification or dismissing it does too |
| `timer lock 10` | Minutes idle before the screen turns off (or `l` in the timer menu). It locks a minute later |
| `timer sound` | Hear and choose what it rings with (or `a` in the timer menu): the wren, unless you choose another. The sounds are made on your computer by `lib/alarm-sounds.py` |
| `timer clock` | Whether the bar shows the date (`~/.config/wren/clock`). The time is always am/pm |

An alarm repeats its sound for up to 5 minutes, to wake you, and a timer rings for about 20 seconds.
Timers last until logout or reboot, and a laptop that is asleep does not wake for them.

## 5. It runs every base part

It runs every script in the base list (`PARTS` in `packages.sh`). If one fails, the rest still run,
and it tells you which to re-run.

A few only run where the computer has the hardware, and otherwise say so and are skipped. Run by
hand, a part always installs.

| Part | Needs |
|---|---|
| `brightnessctl` | A screen backlight |
| `power-profiles-daemon` | A battery or power profiles |
| `network-manager`, `random-mac` | A Wi-Fi adapter |

## 6. It installs the extras you picked

`install-extras.sh --install` installs what you chose in step 2.

## The parts

Each is one script in `parts/`, and its `--remove` undoes it.

### Updates

**`unattended-upgrades.sh`** installs unattended-upgrades.

- Debian's security fixes install themselves daily, with Debian's default rules.
- The Mullvad and Claude Code repositories Wren Linux adds are included. Any repository you add
  yourself is left to you.
- The bar says so if updates stop arriving while you're online.
- Log: `/var/log/unattended-upgrades/`

**`needrestart.sh`** installs needrestart and libnotify-bin. After every update, it lists the running
programs that still use outdated libraries. It only lists: it never restarts anything. Check any time
with `sudo needrestart`.

### Networks and DNS

**`ufw.sh`** installs ufw, the firewall. It blocks everything incoming and allows outgoing.

**`secure-dns.sh`** installs unbound, dns-root-data and nftables. Unbound on this computer checks every
answer with DNSSEC and asks the resolver you pick (Enter: Quad9) over DNS over TLS. A firewall rule
lets only Unbound send DNS out. There's a switch for Wi-Fi sign-in pages: the Wren menu's Secure DNS
line, or `secure-dns on`/`off`. See [Encrypted DNS](#encrypted-dns-with-a-switch-partssecure-dnssh).

**`sandbox-dns.sh`** sends DNS from Wren Linux's sandbox users only to the resolver this computer uses,
not to any address. That covers the sandboxed Firefox, incognito, the Wi-Fi sign-in window, yt-dlp,
Claude's own user and the VMs.

- Their firewall rules take port 53 only to a set that a root helper fills from `/etc/resolv.conf`:
  Unbound with secure DNS on, the network's resolver while it is off.
- It's filled at boot, whenever that file changes, and after each sandbox's firewall loads.
- It keeps a hacked sandbox off what else listens on port 53 nearby. It can still send data out.

**`network-manager.sh`** installs network-manager, wpasupplicant, wireless-regdb and polkitd. It moves
the Wi-Fi from the installer or wifi.sh into NetworkManager. `nmtui` switches networks, in Wren Linux's
white-on-black colors, like the install list. Your own `NEWT_COLORS` wins.

**`random-mac.sh`** (with NetworkManager) means a made-up Wi-Fi MAC address on every connection and
while scanning, no computer name sent to the network, and temporary IPv6 addresses. Networks can't
recognise the laptop from place to place.

- Wi-Fi login pages at cafés and hotels may ask again after reconnecting, and your home router sees a
  new device each time.
- For one made-up address per network instead, change `random` to `stable` in
  `/etc/NetworkManager/conf.d/90-wren-random-mac.conf`.

**`dhcp-no-name.sh`** stops dhcpcd and dhclient sending this computer's name to each network, on a cable
or through `wifi.sh`.

**`tether.sh`** adds `tether`: a phone's mobile data through its USB cable, with or without NetworkManager.
While you are offline, a window asks when a phone appears, and it connects only if you say so. See
[phone tethering](extras/phone-tethering.md).

**`no-live-extras.sh`** takes out what Debian's live image installs and Wren Linux doesn't use. A DVD or
netinst install doesn't have it. It shows what goes first.

- **Always:** avahi (announces this computer's name and services on every network), hw-probe (can send
  your hardware details off), extrepo, and the telnet client.
- **Unless you say you print:** printing (cups). cups-browsed, which looks for printers on the network,
  goes either way.
- **Only if nothing needs them:** dkms, if no kernel module needs building (some Wi-Fi drivers: `wifi.sh`
  says when yours is one), and mdadm, if there's no software RAID.
- It marks sudo as wanted first, and refuses any removal that would take sudo, the kernel, disk
  encryption or networking with it.
- To have one back: `sudo apt install NAME`

### Kernel and boot

**`sysctl-hardening.sh`** applies kernel and network settings in the spirit of Kicksecure
(`data/sysctl-hardening.conf`), now and at every boot: kernel addresses hidden, only your own child
programs can be traced, no kexec, SysRq limited, no io_uring, and stricter file and network defaults.
See [Kernel hardening](#kernel-hardening).

**`module-blacklist.sh`** blocks rare network protocols, old filesystems and FireWire from loading
(`data/module-blacklist.conf`).

**`boot-hardening.sh`** adds Kicksecure's boot parameters to GRUB, and they apply after a reboot:
`slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 randomize_kstack_offset=on vsyscall=none debugfs=off intel_iommu=on iommu.passthrough=0 iommu.strict=1`

**`grub-colors.sh`** changes GRUB's boot menu to a red box with white text, the chosen entry yellow, and
black around it (`/etc/grub.d/06_wren_colors`). Colours only.

### Your account

**`sudo-timeout.sh`** makes sudo remember your password for 60 seconds, in the terminal it was typed in,
instead of Debian's 15 minutes (`timestamp_timeout=1`). A program waiting for you to use sudo gets a
minute, not a quarter of an hour. Wren Linux's scripts refresh it every 50 seconds while they run, so a
long install still asks once.

**`home-private.sh`** keeps your home private to you, also from Wren Linux's sandbox users. The sandboxed
Firefox and Claude pass through your home to their shared folder, and could otherwise open any
world-readable file in it by name.

- Others lose access to what is directly in your home.
- Folders shared through an ACL keep their user.
- New files start private (`umask 077`, at the top of `~/.profile`).
- A sudo rule keeps Debian's usual umask for commands run through sudo.

**`clock.sh`** installs systemd-timesyncd. The clock is set over the network (NTP, from
`debian.pool.ntp.org`) and kept right, which Tor needs. While the time zone is UTC it asks for yours
(Enter keeps UTC), so the bar shows your local time. Run it again to change it:
`timedatectl list-timezones` lists them.

### Locking the screen, and power

**`swaylock.sh`** installs swaylock. Super+Escape locks.

**`swayidle.sh`** installs swayidle and swaylock.

- The screen turns off after 5 minutes idle. `timer lock 10` makes it 10 (1 to 120, kept when the part
  runs again), and `bash status.sh` shows it.
- It locks a minute later, with the vault and KeePassXC. Back within that minute, any key brings it
  back without a password.
- It locks at once before sleep.
- The screen fades down slowly for the 30 seconds before it turns off, with a "Screen going dark"
  notification. Any key or mouse movement puts it back (`dim-warning`). A monitor with no backlight
  gets only the notification.

**`power-menu.sh`** installs wmenu. `powermenu` locks, suspends, logs out, reboots or powers off, from a
small menu on Super+Shift+Escape.

**`power-profiles-daemon.sh`** installs power-profiles-daemon:
`powerprofilesctl set power-saver | balanced | performance`. It skips itself if tlp is installed.

**`brightnessctl.sh`** installs brightnessctl: `brightness up|down [STEP]`, never below 5%, on the
brightness keys and Super+F1/F2.

### USB

**`usb.sh`** installs udisks2 and polkitd, for the `usb` command. Nothing mounts by itself: that is
`extras/udiskie.sh`.

| Command | What it does |
|---|---|
| `usb` | Lists sticks |
| `usb mount [NAME]` | Mounts one as you, under `/media/$USER/`, with `nosuid,nodev,noexec`. FAT, exFAT and NTFS are readable by you alone. An encrypted one asks for its passphrase |
| `usb unmount` | Unmounts, locks and switches it off |

A FAT stick mounted with `sudo mount` is root's, so you can't write to it: `usb mount` offers to mount it
again as you.

**USB drives and `noexec`:** a drive can't run programs from itself (`bash script.sh` and `mpv file` work;
`./program` doesn't). Delete `noexec` in `~/.config/udiskie/config.yml` if you want that.

### The Wren menu

**`wren-menu.sh`** installs wmenu and rfkill, for `wren-menu`. Click "wren" at the left of the bar, or press
Super+m (again closes it), for a black-and-gray menu in a floating window over what you were doing.

- **Keys:** arrows and Enter, or click. Space flips a switch. Esc goes back from a list, and closes the
  rest, the install list and the help page included.
- **What you pick** runs in that window, which closes when it ends. The install and update screens wait
  for Enter first if they did something.

Its first screen stays nearly the same whatever is installed:

- Web browser (the one links open in, or the first installed; with none, no line: a host may do without one)
- Password manager (KeePassXC; with none, it offers to install one)
- Terminal (as Super+Enter opens; only inside sway)
- Apps, Wi-Fi, Settings, System and Power, the lists below
- Help (the key cheat sheet, in the menu's own pager, which also opens on Super+?)

The Settings line shows the microphone, webcam and secure DNS at a glance.

The lists, each with only what is here:

- **Apps:**
  - Install apps (`install-extras.sh`, in three groups: most secure, somewhat secure, least secure)
  - What you have (only inside sway): Tor Browser, Whonix, Text editor, File manager, GIMP, Signal, SimpleX,
    the wallets, Claude, opencode
  - Remove apps (`install-extras.sh --remove`)
- **Wi-Fi:** Choose a network (`nmtui`, or `wifi.sh` without NetworkManager), Wi-Fi on or off, Sign-in page
- **Settings** (choosing one flips it): Theme, Bluetooth, Microphone, Webcam, the Vault, Secure DNS, and
  Font size on a text console
- **System:** Update (`update.sh`), Status (`status.sh`), Back up now, Startup programs (`wren-autostart edit`)
- **Power:** Lock, Suspend, Log out, Reboot, Shut down

### The desktop

**`core-commands.sh`** installs ncal, and puts the base desktop's own commands in `~/.local/bin` (`keys`,
`wren-welcome`, `timer`, `display-scale`, `sway-status`), with the key cheat sheet and the alarm sound.
`install-base.sh` puts them in place too. This part does it again so that `wrenctl --update` brings them up
to date when they change.

**`wmenu.sh`** installs wmenu, the launcher on Super+d, in the bar's black and white. It's opaque (the bar is
see-through), with a font a little bigger than the bar's, so it covers the bar. If a strip of the bar still
shows, raise the `12` in the `set $menu` line of `~/.config/sway/config`.

**`autostart.sh`** sets what opens when you log in, and on which workspace, in one file:
`~/.config/wren/autostart`, a workspace and a command on each line. It starts with a terminal on workspace 1.
Change it there, with the Wren menu's System > Startup programs, or with `wren-autostart edit`. Yours is never
replaced.

**`mako.sh`** installs mako-notifier. Notifications close after 5 seconds, and Super+n and Super+Shift+n dismiss.

**`wl-clipboard.sh`** installs wl-clipboard: `wl-copy` and `wl-paste`.

**`command-hints.sh`** helps when you type a Wren Linux extra's command that isn't installed (`claude-vm`,
`gimp`...): the terminal says which script installs it. It only prints, and bash asks it only when no program of
that name exists. It's a root-owned file (`data/command-hints.bash`), loaded by one marked block in `~/.bashrc`.

**`foot-config.sh`** installs fonts-dejavu-mono, and sets the terminal's look (`data/foot.ini`): DejaVu Sans Mono
at size 14 instead of foot's small default, a black background and readable colors.

- `console-font`, run in a terminal window, picks another size (or bold) for every terminal opened after.
  foot-config.sh keeps that choice when it writes the file again.
- It's written to `~/.config/foot/foot.ini`. One you wrote yourself is kept as `foot.ini.bak`.

**`console-tmux.sh`** installs tmux, dressed like the desktop, always. `~/.config/tmux/tmux.conf` (plain settings)
loads `console.conf` only on a text console, so a tmux in a foot window under sway stays plain.
`console-click` handles the bar clicks, and the console-only extra starts it at login.

- The bar is on top, in black and gray: workspace numbers, then Wren Linux, wifi, vol, bright, bat, timer and
  date, with the same clicks and scrolls.
- Alt+1 … Alt+0 go to workspaces, Alt+Shift+1 … sends the pane there, and Alt+m opens the Wren menu.

### Wallpaper and theme

**`wallpaper.sh`** is your own wallpaper: the newest JPEG or PNG in `~/Pictures/wren/desktop` goes up at every
login and sway reload (Super+Shift+c). With the folder empty you get the default, a wren for the theme in use,
which swaps when the theme does. Your sway config's own `output * bg` line stays instead, if it has one.

| Key or command | What it does |
|---|---|
| Super+] and Super+[ | Step through `~/Pictures/Wallpapers` as the wallpaper |
| Super+Shift+w | Lists it by name, with "0  No wallpaper" first (wmenu). The one chosen is copied into the desktop folder, so it stays |
| Super+\ | No wallpaper, not even a wren: the theme's plain background, until you choose one or copy in a newer picture |
| `wallpaper status` | Which picture is used, and why a file isn't (a file that only says it is a JPEG or PNG, over 50 MB) |

- A JPEG or PNG in `~/Pictures/wren/firefox` is the sandboxed Firefox's New Tab background instead of the fox. A
  checked copy is handed over at each start: Firefox never sees the folder.
- sway gets a link named with digits, never your file name.
- `extras/wallpapers.sh` fills `~/Pictures/Wallpapers` with pictures that come with Wren Linux: wrens, art,
  Earth and space. Stronger ones are there only if you tick them.

**`theme.sh`** is light or dark, from one place: `theme light`, `theme dark`, `theme toggle`, or the Wren menu's
Theme line. Dark is the default, and Wren Linux's look as before. Light has warm light backgrounds (#f2efe9) and dark
text.

- **It changes:** the bar (see-through), the plain background with no wallpaper, foot, the Wren menu and its lists,
  nmtui, the launcher (Super+d), the power menu, notifications and the lock screen.
- **GTK apps** prefer light too: `settings.ini` for GTK 3 and 4, and the color-scheme setting libadwaita apps read,
  through `gsettings`.
- **The sandboxed Firefox and incognito** take Firefox's light or dark theme at their next start, websites that offer
  one their light or dark version, and the light or dark fox.
- **The colors** are `data/themes/dark` and `light`, read strictly (colors only). Only Wren Linux's own foot.ini and
  mako config are changed.
- **Windows open now** keep their colors until they open again, and the text console (tmux) stays dark.
- **The lock screen** falls back to black if the theme can't say.

## Encrypted DNS, with a switch (`parts/secure-dns.sh`)

Without it, every name the computer looks up goes unencrypted to the DNS server
the network hands out (usually the router): the network and your ISP see each
one and anyone on the way can answer falsely. With it:

- **Unbound** runs on this computer, answering only `127.0.0.1`, and
  `/etc/resolv.conf` points at it. It checks every answer with **DNSSEC**
  (Debian's own root key, `dns-root-data`): an answer proven false is refused.
- It asks **one resolver you choose**, over **DNS over TLS** (port 853), and
  only if that resolver's certificate is for its name. The choices are in
  `pins.sh` (`DOT_*`), each checked against its own site:

  | Resolver | Where, who | Notes |
  |---|---|---|
  | `dns.quad9.net` | Switzerland, the Quad9 Foundation | also blocks known malware sites |
  | `dns.digitale-gesellschaft.ch` | Switzerland, an association | no filtering; says it logs no queries |
  | `dot1.applied-privacy.net` | Austria, the Foundation for Applied Privacy | no filtering; one server |

  The resolver sees the names you look up; your network and ISP no longer
  do. Enter picks Quad9, the one Firefox uses for its own when this is
  switched off. (Mullvad's public DNS isn't offered: it
  shuts down on 2 November 2026. Mullvad VPN's own DNS, inside the tunnel,
  is a different thing and keeps working.)
- **It fails closed.** A firewall rule (`data/secure-dns-firewall.nft`) lets
  only Unbound send DNS out (ports 53 and 853), so a program that asks another
  DNS server itself is refused, and if the resolver can't be reached names stop
  resolving rather than going out unencrypted. That holds for the sandboxes
  too: the sandboxed Claude's users and the VMs (claude-vm, the retired opencode-vm, and
  their accounts) can only ask Unbound while it is on.
- NetworkManager (`dns=none`), dhclient, dhcpcd and `wifi.sh` stop rewriting
  `/etc/resolv.conf`. The old one is kept as `/etc/resolv.conf.wren-secure-dns.bak`.
- **A VPN:** Mullvad VPN points `/etc/resolv.conf` at its own DNS server inside
  its tunnel while connected, and the firewall rule lets tunnels (`wg*`,
  `tun*`) through; when it disconnects, Unbound takes over again.
- **The switch.** Wi-Fi sign-in pages (cafés, hotels, trains) need the
  network's own DNS, so they don't work while it's on: switch it off in the
  Wren menu (the Secure DNS line: Space or Enter) or with `secure-dns off`,
  sign in, and switch it on again (`secure-dns on`); the Wi-Fi sign-in window
  below does all of that for you. Switching on checks that
  names resolve first and stays off if they don't. Your user may switch it
  without a password: a sudo rule allows exactly `on` and `off` of the switch
  script (`bin/secure-dns-switch`), so a program running as you could switch
  it off too (Status then says so).
- **While it is off**, other programs use the network's DNS, unencrypted.
  Wren Linux's Firefox encrypts its own instead (DNS over HTTPS to Quad9, set
  at each start, so it follows the switch at its next start): strict by
  default, so a hostile network can't push it back to plain DNS by blocking
  the encrypted kind.
- **The Wi-Fi sign-in window** (the Wren menu's Wi-Fi > Sign-in page, or
  `wifi-signin`) is the easy way through a sign-in page: it switches secure
  DNS off, opens a throwaway incognito window (in memory, gone when it
  closes; as its own user, `wifi-signin`, which may reach the local network
  where sign-in pages often are, but not this computer) that alone uses the
  network's own DNS and allows plain http,
  opening Mozilla's test page so the network can show its sign-in page, and
  switches secure DNS on again when you close it. Every other Firefox keeps
  its encrypted DNS meanwhile; only programs that look names up during that
  minute use the network's. uBlock's medium mode can block a sign-in page's
  scripts from other sites: allow them with uBlock's button in that window.
  If you log out while it is open, secure DNS stays off; at your next login
  (a notification in sway, a line in a text console's shell) you are told,
  until it is on again. Switched off by you, it says nothing.
- **DNS over HTTPS** looks like any web traffic, so no firewall can stop it.
  Firefox's own is off while this is on; Mullvad Browser keeps its own.

It is part of the base install and switches on the first time. Something
else running DNS here (systemd-resolved, resolvconf, another server on port
53) makes it skip itself with a note. Run it again to pick another resolver;
a re-run keeps the switch where you left it. `bash status.sh` shows whether
it is on and which resolver is in use. `--remove` takes it out.

LIMITS: the resolver you choose sees every name you look up, from your
address; the sites you then connect to are still seen by your network (by
address, and usually by name in the TLS handshake); a computer whose clock is
far off can't check DNSSEC, so names stop resolving until the clock is right.

## Kernel hardening

Three parts follow Kicksecure's approach, with what it does by default
checked against this Debian:

- **`sysctl-hardening.sh`**: Debian already sets `dmesg_restrict`,
  `unprivileged_bpf_disabled`, `perf_event_paranoid` and
  `protected_symlinks`/`hardlinks`; this adds `kptr_restrict=2`,
  `ptrace_scope=1`, `kexec_load_disabled=1`, `sysrq=4`, `io_uring_disabled=2`
  (io_uring, a frequent source of kernel exploits, off for everyone; a
  program that wants it, such as QEMU, falls back), a hardened BPF JIT,
  `protected_fifos/regular=2` and stricter network defaults (reverse-path
  filtering in loose mode, so VPNs keep working). Two things it changes:
  `gdb` and `strace` can't attach to a program that is already running
  unless you use `sudo`, and the Magic SysRq REISUB rescue sequence needs
  `kernel.sysrq = 438` back (edit `/etc/sysctl.d/60-wren-hardening.conf`).
- **`boot-hardening.sh`**: kernel parameters that clear memory when it is
  handed out and freed (`init_on_free` costs a few percent of speed) and
  make the allocator harder to predict, and the IOMMU on and strict, so a
  device (Thunderbolt, USB4, a Wi-Fi card) reaches only the memory its driver
  gave it (with VT-d or AMD-Vi on in the firmware, see `docs/bios.md`). Needs GRUB (other boot loaders are
  skipped with a note) and one reboot. If the system ever doesn't start,
  press `e` on the GRUB entry, delete the parameters from the line that
  starts with `linux`, boot, then run `bash parts/boot-hardening.sh --remove`.
- **`grub-colors.sh`**: only the boot menu's colours; what boots doesn't
  change. If `update-grub` can't build the menu with them, they are taken
  out again. Undo with `bash parts/grub-colors.sh --remove`.
- **`module-blacklist.sh`**: `dccp`, `sctp`, `rds`, `tipc`, `ax25`, `netrom`,
  `rose`; the old filesystems `cramfs`, `freevxfs`, `jffs2`, `hfs`, `affs`,
  `bfs`, `befs`, `efs`, `qnx4`, `qnx6`, `sysv`, `minix`, `omfs`, `hpfs`,
  `ufs`; and FireWire (`firewire-core`, `firewire-ohci`, `firewire-sbp2`),
  which can read memory directly. A stick with one of those filesystems
  won't mount. HFS+ (Mac sticks), UDF, exFAT and NTFS are not on the list.

Not taken from Kicksecure: `security-misc`, `hardened-malloc` and `kloak`
are not in Debian, and using them means trusting another apt repository.

## apt through Tor

`install-base.sh` asks first, before anything is downloaded, whether apt
should fetch Debian's packages through Tor (the default is no). Say yes, or
run `bash parts/apt-tor.sh` any time, and it:

1. asks whether you need a bridge to reach Tor (see [Bridges](#bridges));
   obfs4 or webtunnel lines, or Snowflake, are offered here (there is no
   client program for meek); the choice goes into `/etc/tor/torrc`;
2. installs `tor`, `apt-transport-tor` and the bridge's program in the
   normal way (once), with Tor kept from starting until your bridges are in
   place;
3. starts Tor and waits for it to connect; if it doesn't in 3 minutes,
   apt is left alone;
4. changes `deb.debian.org` and `security.debian.org` (and
   `deb.torproject.org`, for webtunnel) in your apt sources to
   `tor+https://…` (originals saved as `*.wren-tor.bak`) and runs
   `apt-get update` through Tor; if that fails, the sources are put back.

apt still checks every package's signature as always; this hides who
downloads what from your network and your address from the mirrors. It is
slower, and other repositories you added (Mullvad, Claude Code) are still
fetched directly. `bash parts/apt-tor.sh --remove` puts it all back.

## Bridges

Everything in Wren Linux that connects to Tor (Tor Browser, Whonix, OnionShare,
and the system Tor that apt over Tor, remote access and the onion site
share) asks the same way. First: **do you need a bridge to reach the
Tor network?** A bridge is a relay that isn't listed publicly; you need one if
your network blocks Tor or you don't want it to see that you use Tor. The
default is no. If you say yes, you get the kinds that work in that place:

| Kind | What it is | Tor Browser | Whonix Gateway | OnionShare | system Tor |
|---|---|---|---|---|---|
| obfs4, built-in | Tor's own public list; nothing to fetch; often blocked where Tor is | yes | no | yes | no |
| obfs4, your lines | Makes Tor look like random data; fast | yes | yes | yes | yes |
| webtunnel | Looks like a visit to a website; good against blocking | yes | no | no | yes |
| Snowflake | No lines needed; borrows volunteers' browsers; slower | yes | yes | yes | yes |
| meek (Azure) | Looks like a visit to Microsoft's cloud; slowest, a last resort | yes | no | no | no |

The "no" entries are real limits: the Whonix Gateway ships only the obfs4 and
Snowflake programs (I checked its package list), there is no client for meek
outside Tor Browser, and OnionShare can't use webtunnel or meek. The menu says
what is left out, and why. The system Tor is shared, so its bridge is asked
for once, by whichever of apt over Tor, remote access and the onion site comes
first.

### webtunnel for the system Tor

Debian has no webtunnel client. The Tor Project's own bridge program,
**lyrebird** (the one Tor Browser carries; it speaks obfs4, webtunnel,
Snowflake and meek), comes from the Tor Project's apt repository,
deb.torproject.org, and Wren Linux takes **only lyrebird** from it:

- its signing key must be exactly `TORPROJECT_FPR` in `pins.sh` (checked
  against the key on deb.torproject.org, keys.openpgp.org and
  keyserver.ubuntu.com, and against the repository's signature);
- `/etc/apt/preferences.d/wren-torproject.pref` gives every other package
  there priority -1, so it can't replace Debian's `tor` or add anything else
  (tested with real apt: lyrebird installable, the repository's newer `tor`
  and its keyring package not);
- the package is one program and a man page, with no install scripts;
  unattended-upgrades keeps it up to date;
- Debian's AppArmor profile for tor already allows `/usr/bin/lyrebird`, so
  nothing in AppArmor is changed; the torrc gets
  `ClientTransportPlugin webtunnel exec /usr/bin/lyrebird`.

When the last script using it is removed, lyrebird and the repository go too.
Building webtunnel from its git source as root, and editing the
`system_tor` AppArmor profile by hand, as some guides say, is not done: its
releases aren't signed, and Debian's profile is overwritten by updates.

By hand:

```
# the key: check gpg prints exactly the TORPROJECT_FPR of pins.sh
wget -O /tmp/tpo.asc "$(. ~/wren/pins.sh; echo "$TORPROJECT_KEY_URL")"
gpg --show-keys /tmp/tpo.asc
sudo install -D -m 0644 /tmp/tpo.asc /usr/share/keyrings/wren-torproject.asc
# lyrebird only, from that repository
printf '%s\n' 'Package: lyrebird' 'Pin: origin deb.torproject.org' 'Pin-Priority: 500' '' \
    'Package: *' 'Pin: origin deb.torproject.org' 'Pin-Priority: -1' |
    sudo tee /etc/apt/preferences.d/wren-torproject.pref
echo "deb [signed-by=/usr/share/keyrings/wren-torproject.asc arch=amd64] https://deb.torproject.org/torproject.org trixie main" |
    sudo tee /etc/apt/sources.list.d/wren-torproject.list
sudo apt update
# tor's Candidate must be Debian's version (not one ending in ~d13.trixie+1),
# and the deb.torproject.org lines under tor must show -1
apt-cache policy tor lyrebird
sudo apt install lyrebird
# at the end of /etc/tor/torrc:
#   UseBridges 1
#   ClientTransportPlugin webtunnel exec /usr/bin/lyrebird
#   Bridge webtunnel [ADDRESS]:443 FINGERPRINT url=https://... ver=0.0.3
```

For **obfs4** and **webtunnel** lines you get yourself, from Tor's BridgeDB:

- the website https://bridges.torproject.org/options (choose the kind; for
  obfs4 you solve a captcha);
- email to bridges@torproject.org from a Gmail or Riseup address (for
  webtunnel put `get transport webtunnel` in the message; if it only
  answers with obfs4, use the website);
- the Telegram bot @GetBridgesBot;
- or a friend outside the network that blocks Tor.

Snowflake needs nothing from you. Tor Browser has it built in; for the others
`data/snowflake-bridges.txt` has Tor Browser's own Snowflake lines, adjusted
for Debian's `snowflake-client` (one `front=` instead of `fronts=`). I have
not connected through these Snowflake lines from Debian's client, so if one
fails, try another kind.

