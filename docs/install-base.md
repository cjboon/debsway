# What install-base.sh does

0. Starts with `prep/intro.sh`: it explains what is about to happen, shows
   a disclaimer, and asks whether to go on. `bash install-base.sh --yes`
   skips it. Right after you agree, it shows the list of optional extras
   (`install-extras.sh --choose`) so you answer everything up front; nothing
   is checked for you. What you pick is installed once the base is done.
1. Installs the core packages, all with `--no-install-recommends`:
   `sway foot libgl1-mesa-dri gpg` (`gpg` checks downloads). Every part
   installs its own packages (see the table below). There is no web
   browser until you pick one: Firefox and w3m are in the extras list.
2. Sets up sway (a copy of the stock config plus one `include` line for
   `~/.config/sway/config.d/`), the status bar (see-through black), no window
   borders (`appearance.conf`), and the key cheat sheet: `Super+?`, the `keys` command, `~/KEYS.txt` (a link
   to the one copy; the first time sway starts it asks whether sway's shortcuts use
   Super, the Windows key, or Alt, and `keys --mod alt` / `keys --mod super` switches
   later, with the sheet showing whichever you use), a bar with a clickable "debsway" menu (a gray menu: Help, Install apps, Update, Status, and Wi-Fi, Bluetooth and Microphone switches on computers that have them) and Wi-Fi name, a scrollable volume and brightness, and a battery you can click for the time left, and a one-line hint on
   plain text consoles. `display-scale` sets the text size of each screen,
   remembered per screen (`display.conf`), and a watcher started by sway says
   once, in a notification, when a sharp screen is still at scale 1, also when
   you plug one in later. A screen's size comes from its own data in
   `/sys/class/drm`; without it the sharpness is unknown and nothing is said.
   `timer` (Super+t, or a click on the time in the bar) sets timers and alarms
   with systemd user timers and no extra package: `timer 10m tea`,
   `timer at 7:30`, `timer list`, `timer cancel`. The next one shows in the bar.
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
| `unattended-upgrades.sh` | unattended-upgrades | Debian's security fixes install themselves daily, with Debian's default rules; the Mullvad and Claude Code repositories debsway adds are included, any repository you add yourself is left to you. Log: `/var/log/unattended-upgrades/` |
| `wmenu.sh` | wmenu | The launcher on Super+d, in the bar's black and white, opaque (the bar is see-through) and with a font a little bigger than the bar's so it covers the bar. If a strip of the bar still shows, raise the `12` in the `set $menu` line of `~/.config/sway/config` |
| `swaylock.sh` | swaylock | Super+Escape locks |
| `swayidle.sh` | swayidle, swaylock | Lock after 5 min, screen off after 10, lock before sleep. The screen fades down slowly for the 30 seconds before the lock, with a "Locking soon" notification; any key or mouse movement puts it back (`dim-warning`; a monitor with no backlight gets only the notification) |
| `brightnessctl.sh` | brightnessctl | `brightness up\|down [STEP]`, never below 5%; brightness keys and Super+F1/F2 |
| `wl-clipboard.sh` | wl-clipboard | `wl-copy` / `wl-paste` |
| `mako.sh` | mako-notifier | Notifications close after 5 seconds; Super+n / Super+Shift+n dismiss |
| `foot-config.sh` | fonts-dejavu-mono | The terminal's look (`data/foot.ini`): DejaVu Sans Mono at size 14 instead of foot's small default, black background, readable colors. Written to `~/.config/foot/foot.ini`; one you wrote yourself is kept as `foot.ini.bak` |
| `debsway-menu.sh` | wmenu, rfkill | `debsway-menu`: click "debsway" at the left of the bar for a black-and-gray menu that fills the area under the bar (arrows and Enter, or click; Esc closes every screen, the install list and the help page included) with Help (the key cheat sheet, in the menu's own pager, which also opens on Super+?), Install apps (`install-extras.sh`, its list in grays too), Update (`update.sh`) and Status (`status.sh`). What you pick runs in that window, which closes when it ends; the install and update screens wait for Enter first if they did something |
| `power-menu.sh` | wmenu | `powermenu`: lock, suspend, log out, reboot or power off from a small menu on Super+Shift+Escape |
| `needrestart.sh` | needrestart, libnotify-bin | After every update, lists the running programs that still use outdated libraries (list only: it never restarts anything). Check any time: `sudo needrestart` |
| `sysctl-hardening.sh` | (none) | Kernel and network settings in the spirit of Kicksecure (`data/sysctl-hardening.conf`): kernel addresses hidden, only your own child programs can be traced, no kexec, SysRq limited, stricter file and network defaults. Applies now and at every boot. See [Kernel hardening](#kernel-hardening) |
| `module-blacklist.sh` | (none) | Blocks rare network protocols, old filesystems and FireWire from loading (`data/module-blacklist.conf`) |
| `boot-hardening.sh` | (none) | Adds Kicksecure's boot parameters to GRUB (`slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 randomize_kstack_offset=on vsyscall=none debugfs=off`); applies after a reboot |
| `ufw.sh` | ufw | Firewall: blocks everything incoming, allows outgoing |
| `power-profiles-daemon.sh` | power-profiles-daemon | `powerprofilesctl set power-saver \| balanced \| performance` (skips itself if tlp is installed) |
| `network-manager.sh` | network-manager, wpasupplicant, wireless-regdb, polkitd | Moves the Wi-Fi from the installer or wifi.sh into NetworkManager; `nmtui` (in debsway's white-on-black colors, like the install list; your own `NEWT_COLORS` wins) to switch networks |
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

1. installs `tor`, `obfs4proxy` and `apt-transport-tor` in the normal way
   (once), with Tor kept from starting until your bridges are in place;
2. asks whether you need a bridge to reach Tor (see [Bridges](#bridges));
   obfs4 lines or Snowflake are offered here, since Debian has no client
   program for webtunnel or meek; the choice goes into `/etc/tor/torrc`;
3. starts Tor and waits for it to connect; if it doesn't in 3 minutes,
   apt is left alone;
4. changes `deb.debian.org` and `security.debian.org` in your apt sources to
   `tor+https://…` (originals saved as `*.debsway-tor.bak`) and runs
   `apt-get update` through Tor; if that fails, the sources are put back.

apt still checks every package's signature as always; this hides who
downloads what from your network and your address from the mirrors. It is
slower, and other repositories you added (Mullvad, Claude Code) are still
fetched directly. `bash parts/apt-tor.sh --remove` puts it all back.

## Bridges

Everything in debsway that connects to Tor (Tor Browser, Whonix, OnionShare,
apt over Tor) asks the same way. First: **do you need a bridge to reach the
Tor network?** A bridge is a relay that isn't listed publicly; you need one if
your network blocks Tor or you don't want it to see that you use Tor. The
default is no. If you say yes, you get the kinds that work in that place:

| Kind | What it is | Tor Browser | Whonix Gateway | OnionShare | apt over Tor |
|---|---|---|---|---|---|
| obfs4, built-in | Tor's own public list; nothing to fetch; often blocked where Tor is | yes | no | yes | no |
| obfs4, your lines | Makes Tor look like random data; fast | yes | yes | yes | yes |
| webtunnel | Looks like a visit to a website; good against blocking | yes | no | no | no |
| Snowflake | No lines needed; borrows volunteers' browsers; slower | yes | yes | yes | yes |
| meek (Azure) | Looks like a visit to Microsoft's cloud; slowest, a last resort | yes | no | no | no |

The "no" entries are real limits: the Whonix Gateway ships only the obfs4 and
Snowflake programs (I checked its package list), Debian has no client for
webtunnel or meek, and OnionShare can't use them. The menu says what is left
out, and why.

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

