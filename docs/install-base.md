# What install-base.sh does

0. Starts with `prep/intro.sh`: it explains what is about to happen, shows
   a disclaimer, and asks whether to go on. `bash install-base.sh --yes`
   skips it. Right after you agree, it shows the list of optional extras
   (`install-extras.sh --choose`) so you answer everything up front; nothing
   is checked for you. What you pick is installed once the base is done.
1. Installs the core packages, all with `--no-install-recommends`:
   `sway foot libgl1-mesa-dri gpg age diceware` (`gpg` checks downloads;
   `age` encrypts a file to a password or a key, `age -p file >file.age`, and
   `age -d file.age` decrypts it; `diceware -n 6` makes a passphrase of six random
   words, from the system's secure random source). Every part
   installs its own packages (see the table below). There is no web
   browser until you pick one: Firefox and w3m are in the extras list.
2. Sets up sway (a copy of the stock config plus one `include` line for
   `~/.config/sway/config.d/`), the status bar (see-through black), no window
   borders (`appearance.conf`), and the key cheat sheet: `Super+?`, the `keys` command, `~/KEYS.txt` (a link
   to the one copy; the first time sway starts it asks whether sway's shortcuts use
   Super, the Windows key, or Alt, and `keys --mod alt` / `keys --mod super` switches
   later, with the sheet showing whichever you use), a bar with a clickable "debsway" menu (a gray menu: Help, Terminal, Install apps, Update, Status, and Wi-Fi, Bluetooth (with the Bluetooth extra) and Microphone switches on computers that have them) and Wi-Fi name, a scrollable volume and brightness, and a battery you can click for the time left, and a one-line hint on
   plain text consoles. `display-scale` sets the text size of each screen,
   remembered per screen (`display.conf`), and a watcher started by sway says
   once, in a notification, when a sharp screen is still at scale 1, also when
   you plug one in later. A screen's size comes from its own data in
   `/sys/class/drm`; without it the sharpness is unknown and nothing is said.
   `timer` (Super+t, or a click on the time in the bar) sets timers and alarms
   with systemd user timers and no extra package: `timer 10m tea`,
   `timer at 7:30`, `timer list`, `timer cancel`. The next one shows in the bar.
   `timer lock 10` (or `l` in the timer menu) sets how many minutes idle before the screen locks.
   `timer stop`, clicking the notification or dismissing it ends the ringing (an alarm repeats a gentle bell phrase for up to 5 minutes, to wake you; a timer rings about 20 seconds). `timer clock` chooses whether the bar shows the date (the time is always am/pm)
   (`~/.config/debsway/clock`). Timers last until logout or reboot, and a
   laptop that is asleep does not wake for them.
3. Offers to start sway when you log in on tty1 (a marked block in
   `~/.profile`).
4. Runs every script in the base list (`PARTS` in `packages.sh`). If one
   fails, the rest still run and it tells you which to re-run. A few only
   run where the computer has the hardware: `brightnessctl` needs a screen
   backlight, `power-profiles-daemon` a battery or power profiles,
   `network-manager` and `random-mac` a Wi-Fi adapter. Otherwise they say
   so and are skipped (run by hand, a part always installs).
5. Installs the extras you picked at the start (`install-extras.sh --install`).
   The list is the one from step 0: arrow keys move, the space bar checks a
   box, Tab reaches **Install** or **No extras**. `debsway --apps` shows it
   again whenever you like; `debsway --apps --list` only prints it.

An existing sway config is kept; only the include line is added, and the
bar is only changed if it's still the stock one. Every snippet is
checked with `sway -C` before it's kept.

### parts/

| Script | Installs | Sets up |
|---|---|---|
| `clock.sh` | systemd-timesyncd | The clock is set over the network (NTP, from `debian.pool.ntp.org`) and kept right; Tor needs a right clock. While the time zone is UTC it asks for yours (Enter keeps UTC), so the bar shows your local time; run it again to change it (`timedatectl list-timezones` lists them) |
| `no-live-extras.sh` | (removes) | Takes out what Debian's live image installs and debsway doesn't use; a DVD or netinst install doesn't have it. Always: avahi (announces this computer's name and services on every network), hw-probe (can send your hardware details off), extrepo, the telnet client. Printing (cups) unless you say you print; cups-browsed, which looks for printers on the network, either way. dkms and mdadm only if nothing needs them: no kernel module DKMS builds (some Wi-Fi drivers; `wifi.sh` says when yours is one) and no software RAID. It marks sudo as wanted first, and refuses any removal that would take sudo, the kernel, disk encryption or networking with it. Shows what goes first. To have one back: `sudo apt install NAME` |
| `unattended-upgrades.sh` | unattended-upgrades | Debian's security fixes install themselves daily, with Debian's default rules; the Mullvad and Claude Code repositories debsway adds are included, any repository you add yourself is left to you. Log: `/var/log/unattended-upgrades/` |
| `wmenu.sh` | wmenu | The launcher on Super+d, in the bar's black and white, opaque (the bar is see-through) and with a font a little bigger than the bar's so it covers the bar. If a strip of the bar still shows, raise the `12` in the `set $menu` line of `~/.config/sway/config` |
| `swaylock.sh` | swaylock | Super+Escape locks |
| `swayidle.sh` | swayidle, swaylock | Lock after 30 min idle (`timer lock 10` makes it 10; 1 to 120, kept when the part runs again; `bash status.sh` shows it), screen off 5 min after the lock, lock before sleep. The screen fades down slowly for the 30 seconds before the lock, with a "Locking soon" notification; any key or mouse movement puts it back (`dim-warning`; a monitor with no backlight gets only the notification) |
| `brightnessctl.sh` | brightnessctl | `brightness up\|down [STEP]`, never below 5%; brightness keys and Super+F1/F2 |
| `wl-clipboard.sh` | wl-clipboard | `wl-copy` / `wl-paste` |
| `mako.sh` | mako-notifier | Notifications close after 5 seconds; Super+n / Super+Shift+n dismiss |
| `foot-config.sh` | fonts-dejavu-mono | The terminal's look (`data/foot.ini`): DejaVu Sans Mono at size 14 instead of foot's small default, black background, readable colors. `console-font`, run in a terminal window, picks another size (or bold) for every terminal opened after; foot-config.sh keeps that choice when it writes the file again. Written to `~/.config/foot/foot.ini`; one you wrote yourself is kept as `foot.ini.bak` |
| `wallpaper.sh` | (none) | Your own wallpaper: the newest JPEG or PNG in `~/Pictures/debsway/desktop` goes up at every login and sway reload (Super+Shift+c); with the folder empty, your sway config's own `output * bg` line or sway's plain background stays. Super+] and Super+[ step through `~/Pictures/Wallpapers` as the wallpaper and Super+Shift+w lists it by name, with "0  No wallpaper" first (wmenu; the one chosen is copied into the desktop folder, so it stays), and Super+\ goes back to no wallpaper (the theme's plain background, until you choose one or copy in a newer picture). A JPEG or PNG in `~/Pictures/debsway/firefox` is the sandboxed Firefox's New Tab background instead of the fox (a checked copy is handed over at each start: Firefox never sees the folder). `wallpaper status` says which picture is used and why a file isn't (a file that only says it is a JPEG or PNG, over 50 MB). sway gets a link named with digits, never your file name. `extras/wallpapers.sh` fills `~/Pictures/Wallpapers` with pictures from NASA, ESA's Webb, NASA Earth Observatory and Budgie to choose from, or sets it up for your own |
| `theme.sh` | (none) | Light or dark, from one place (`theme light`, `theme dark`, `theme toggle`, or the debsway menu's Theme line; dark is the default and debsway's look as before). Light has warm light backgrounds (#f2efe9) and dark text: the bar (see-through), the plain background with no wallpaper, foot, the debsway menu and its lists, nmtui, the launcher (Super+d), the power menu, notifications and the lock screen; GTK apps prefer light too (`settings.ini` for GTK 3 and 4, and the color-scheme setting libadwaita apps read, through `gsettings`), and the sandboxed Firefox and incognito take Firefox's light or dark theme at their next start, websites that offer one their light or dark version, and the light or dark fox. The colors are `data/themes/dark` and `light`, read strictly (colors only); only debsway's own foot.ini and mako config are changed. Windows open now keep their colors until they open again; the text console (tmux) stays dark. The lock screen falls back to black if the theme can't say |
| `console-tmux.sh` | tmux | tmux dressed like the desktop, always installed: `~/.config/tmux/tmux.conf` (plain settings) loads `console.conf` (the bar on top: workspace numbers, then debsway, wifi, vol, bright, bat, timer, date, with the same clicks and scrolls; black and gray; Alt+1 … Alt+0 workspaces, Alt+Shift+1 … sends the pane, Alt+m the debsway menu) only on a text console, so a tmux in a foot window under sway stays plain. `console-click` handles the bar clicks. The console-only extra starts it at login |
| `debsway-menu.sh` | wmenu, rfkill | `debsway-menu`: click "debsway" at the left of the bar, or press Super+m (again closes it), for a black-and-gray menu in a floating window over what you were doing (arrows and Enter, or click; Esc closes every screen, the install list and the help page included) with Help (the key cheat sheet, in the menu's own pager, which also opens on Super+?), Terminal (a terminal window, as Super+Enter opens; only inside sway), Web browser (the one links open in, or the first installed), Text editor (Mousepad), File manager (Thunar), Password manager (KeePassXC), Mail (Tuta), Signal, SimpleX, Claude and opencode (opencode-vm) (claude-vm, else the sandboxed claude in `~/projects`, else claude-regular, in a window of its own), each only inside sway and only when installed, Back up now (with the backup extra), Install apps (`install-extras.sh`, its list in grays too, in three groups: most secure, somewhat secure, least secure; a click checks a box, the wheel scrolls, and the arrow keys go round from the last line to the first), Remove apps (`install-extras.sh --remove`: only what is installed; what you check is removed with its own `--remove`, after a question), Update (`update.sh`) and Status (`status.sh`), then the switches with their state: Wi-Fi, Bluetooth (with the Bluetooth extra), Microphone, Webcam and, with the vault extra, Vault (choosing it closes it, or asks for its password and opens it for an hour). What you pick runs in that window, which closes when it ends; the install and update screens wait for Enter first if they did something |
| `power-menu.sh` | wmenu | `powermenu`: lock, suspend, log out, reboot or power off from a small menu on Super+Shift+Escape |
| `needrestart.sh` | needrestart, libnotify-bin | After every update, lists the running programs that still use outdated libraries (list only: it never restarts anything). Check any time: `sudo needrestart` |
| `sysctl-hardening.sh` | (none) | Kernel and network settings in the spirit of Kicksecure (`data/sysctl-hardening.conf`): kernel addresses hidden, only your own child programs can be traced, no kexec, SysRq limited, stricter file and network defaults. Applies now and at every boot. See [Kernel hardening](#kernel-hardening) |
| `module-blacklist.sh` | (none) | Blocks rare network protocols, old filesystems and FireWire from loading (`data/module-blacklist.conf`) |
| `boot-hardening.sh` | (none) | Adds Kicksecure's boot parameters to GRUB (`slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 randomize_kstack_offset=on vsyscall=none debugfs=off`); applies after a reboot |
| `ufw.sh` | ufw | Firewall: blocks everything incoming, allows outgoing |
| `power-profiles-daemon.sh` | power-profiles-daemon | `powerprofilesctl set power-saver \| balanced \| performance` (skips itself if tlp is installed) |
| `network-manager.sh` | network-manager, wpasupplicant, wireless-regdb, polkitd | Moves the Wi-Fi from the installer or wifi.sh into NetworkManager; `nmtui` (in debsway's white-on-black colors, like the install list; your own `NEWT_COLORS` wins) to switch networks |
| `usb.sh` | udisks2, polkitd | The `usb` command: `usb` lists sticks, `usb mount [NAME]` mounts one as you under `/media/$USER/` (`nosuid,nodev,noexec`; FAT, exFAT and NTFS readable by you alone; an encrypted one asks for its passphrase), `usb unmount` unmounts, locks and switches it off. A FAT stick mounted with `sudo mount` is root's, so you can't write to it: `usb mount` offers to mount it again as you. Nothing mounts by itself (that is `extras/udiskie.sh`) |
| `random-mac.sh` | (NetworkManager) | A made-up Wi-Fi MAC address on every connection and while scanning, no computer name sent to the network, temporary IPv6 addresses: networks can't recognise the laptop from place to place |

**USB drives and `noexec`:** a drive can't run programs from itself
(`bash script.sh` and `mpv file` work; `./program` doesn't). Delete
`noexec` in `~/.config/udiskie/config.yml` if you want that.

**Random MAC side effects:** Wi-Fi login pages at cafés and hotels may
ask again after reconnecting, and your home router sees a new device
each time. For one made-up address per network instead, change `random`
to `stable` in `/etc/NetworkManager/conf.d/90-debsway-random-mac.conf`.

## Kernel hardening

Three parts follow Kicksecure's approach, with what it does by default
checked against this Debian:

- **`sysctl-hardening.sh`**: Debian already sets `dmesg_restrict`,
  `unprivileged_bpf_disabled`, `perf_event_paranoid` and
  `protected_symlinks`/`hardlinks`; this adds `kptr_restrict=2`,
  `ptrace_scope=1`, `kexec_load_disabled=1`, `sysrq=4`, a hardened BPF JIT,
  `protected_fifos/regular=2` and stricter network defaults (reverse-path
  filtering in loose mode, so VPNs keep working). Two things it changes:
  `gdb` and `strace` can't attach to a program that is already running
  unless you use `sudo`, and the Magic SysRq REISUB rescue sequence needs
  `kernel.sysrq = 438` back (edit `/etc/sysctl.d/60-debsway-hardening.conf`).
- **`boot-hardening.sh`**: kernel parameters that clear memory when it is
  handed out and freed (`init_on_free` costs a few percent of speed) and
  make the allocator harder to predict. Needs GRUB (other boot loaders are
  skipped with a note) and one reboot. If the system ever doesn't start,
  press `e` on the GRUB entry, delete the parameters from the line that
  starts with `linux`, boot, then run `bash parts/boot-hardening.sh --remove`.
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
   `tor+https://…` (originals saved as `*.debsway-tor.bak`) and runs
   `apt-get update` through Tor; if that fails, the sources are put back.

apt still checks every package's signature as always; this hides who
downloads what from your network and your address from the mirrors. It is
slower, and other repositories you added (Mullvad, Claude Code) are still
fetched directly. `bash parts/apt-tor.sh --remove` puts it all back.

## Bridges

Everything in debsway that connects to Tor (Tor Browser, Whonix, OnionShare,
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
deb.torproject.org, and debsway takes **only lyrebird** from it:

- its signing key must be exactly `TORPROJECT_FPR` in `pins.sh` (checked
  against the key on deb.torproject.org, keys.openpgp.org and
  keyserver.ubuntu.com, and against the repository's signature);
- `/etc/apt/preferences.d/debsway-torproject.pref` gives every other package
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
wget -O /tmp/tpo.asc "$(. ~/debsway/pins.sh; echo "$TORPROJECT_KEY_URL")"
gpg --show-keys /tmp/tpo.asc
sudo install -D -m 0644 /tmp/tpo.asc /usr/share/keyrings/debsway-torproject.asc
# lyrebird only, from that repository
printf '%s\n' 'Package: lyrebird' 'Pin: origin deb.torproject.org' 'Pin-Priority: 500' '' \
    'Package: *' 'Pin: origin deb.torproject.org' 'Pin-Priority: -1' |
    sudo tee /etc/apt/preferences.d/debsway-torproject.pref
echo "deb [signed-by=/usr/share/keyrings/debsway-torproject.asc arch=amd64] https://deb.torproject.org/torproject.org trixie main" |
    sudo tee /etc/apt/sources.list.d/debsway-torproject.list
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

