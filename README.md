# debsway

Shell scripts that turn a bare Debian 13 (trixie) install into a
minimal, privacy-minded sway desktop: Firefox with sensible hardening,
sound, a launcher, screen lock, brightness, screenshots, notifications,
USB automount, a firewall, automatic security updates and easy Wi-Fi.
No desktop environment, no display manager, no tray, no settings app:
one compositor and plain text configs.

Everything else is optional, one script per app in `extras/`: Tor
Browser with bridges, Whonix, Mullvad VPN and Browser, OnionShare,
wallets (Electrum, Sparrow, Feather), SimpleX Chat, KeePassXC, encrypted
backups and more.

- **Every piece can be undone**: `bash parts/NAME.sh --remove`,
  `bash extras/NAME.sh --remove`. Re-running a script repairs it.
- **Everything downloaded from outside Debian is signature-checked**
  against a key pinned by fingerprint in `pins.sh`, and `test.sh` checks
  that those keys, downloads and packages still work.
- **Read the scripts before you run them.** They change system files
  (apt sources, AppArmor, PAM for one extra, Firefox policies) and are
  written to be readable. `THREAT-MODEL.md` says what this protects
  against and what it doesn't.

It's a set of scripts, not a distribution: you install Debian yourself,
then run them.

## Quick start

1. Install Debian 13 with disk encryption and no desktop (details in
   [Installing Debian](#installing-debian)).
2. Log in on the text console, copy this folder over, then:

```bash
cd ~/debsway
bash wifi.sh             # get online (skip if you already are)
bash install-base.sh     # the core desktop
```

3. Log out and log in on tty1: sway starts. Super+? shows every key.
4. Add what you want: `bash extras/keepassxc.sh`, `bash extras/tor-browser.sh`, ...

`bash status.sh` shows what's set up; `bash test.sh` checks that it all
still works.

## Folder layout

```
debsway/
├── README.md, THREAT-MODEL.md, LICENSE (MIT)
├── install-base.sh          the core desktop: packages, sway, bar, then every part
├── packages.sh              the core's package lists
├── pins.sh                  every signing key debsway trusts, with the date it was checked
├── test.sh                  checks scripts, packages, downloads and keys still work
├── status.sh                what's installed; warns if the disk isn't encrypted
├── wifi.sh                  get online over Wi-Fi, whatever is installed
├── setup-sudo.sh            install sudo + add your user (run as root)
├── fetch-offline-debs.sh    Wi-Fi packages and firmware into debs/, ahead of time
├── fetch-tor-browser.sh     a verified Tor Browser into torbrowser/, ahead of time
├── lib.sh                   shared helpers (sourced, not run)
├── config/
│   ├── sway-status          status bar: wifi | volume | brightness | battery | date
│   ├── keys.txt             the key cheat sheet behind Super+?
│   ├── tor-browser-safest.js  Tor Browser prefs: Safest, JavaScript off
│   └── ublock-allow         the command that lets a site load other sites' scripts
├── parts/                   one script per core piece; install-base.sh runs them all
├── extras/                  optional apps, one script each
├── firefox-profiles/        give a website its own Firefox profile
├── hooks/pre-commit         shellcheck before every commit
├── .github/workflows/       shellcheck and test.sh --offline on every push
└── ignore/                  your own setup, never published (in .gitignore)
```

`debs/`, `torbrowser/` and `whonix/` hold large downloads and are in
`.gitignore` too. Run every script with `bash script.sh`; that works
even when a USB stick's filesystem drops the executable bit.

## Before you reinstall

1. Download the offline Wi-Fi packages, so a fresh install can get
   online without a cable: `bash fetch-offline-debs.sh`. It picks the
   firmware for this machine's network cards. Preparing for a different
   machine? `bash fetch-offline-debs.sh --all` gets the firmware for every
   common Wi-Fi card (larger).
2. Optionally `bash fetch-tor-browser.sh`, so Tor Browser installs
   without contacting torproject.org.
3. **Back up everything you want to keep from `/home`**, above all wallet
   files and password databases: the encrypted install erases the whole
   disk. A plain USB stick isn't encrypted, so delete anything sensitive
   from it once it's restored.
4. Copy the whole `debsway` folder to a USB stick.

## Installing Debian

In the installer:

- **Root password: leave it empty.** Debian then installs sudo and gives
  it to your user. If you set one, run `setup-sudo.sh` later.
- **Software selection: only "standard system utilities".** Untick
  "Debian desktop environment" and every desktop listed under it.
- **Partitioning: "Guided - use entire disk and set up encrypted LVM".**
  This encrypts everything, swap included, with one passphrase you type
  at every boot. Without it, anyone who gets the laptop can read your
  files, wallets and browser logins, and it can't be added later without
  reinstalling.
  - Use a long passphrase, e.g. five or six random words, in plain
    letters (it's typed before any keyboard layout is set up).
  - The installer then fills the disk with random data, which takes a
    while. Cancelling it is safe.
  - Encryption protects the laptop while it's **off**; shut down before
    leaving it somewhere or crossing a border.
- Wi-Fi during install is optional. If you skip it, `wifi.sh` handles it.

## After the first boot

```bash
# 1. Copy the scripts off the USB stick (lsblk shows its name, e.g. sdb1)
lsblk
sudo mount /dev/sdb1 /mnt
cp -r /mnt/debsway ~ && sudo umount /mnt
cd ~/debsway

# 2. Get online (skip if the installer already connected you)
bash wifi.sh

# 3. Only if you set a root password in the installer
su -c "bash $HOME/debsway/setup-sudo.sh $USER"    # then log out and back in

# 4. The core desktop
bash install-base.sh
```

Then log out (`exit`) and log in on tty1: sway starts by itself if you
said yes to that, otherwise type `sway`. The key cheat sheet opens on
your first login; Super+? brings it back.

## wifi.sh

It finds your Wi-Fi card, turns it on if it's blocked in software, shows
nearby networks, asks for the name and password, connects, and saves the
network so it reconnects at boot. Wrong passwords are caught and you get
three tries. Once `install-base.sh` has run, NetworkManager takes over
and `nmtui` is the everyday tool; wifi.sh is for getting online the
first time, or rescuing a broken setup.

It uses the first of these that works:

| What's installed | How it connects | Saved for boot by |
|---|---|---|
| NetworkManager (running) | `nmcli` | NetworkManager |
| iwd | `iwctl` | iwd (it also enables iwd's own DHCP) |
| wpa_supplicant + ifupdown + dhcpcd/dhclient | checks the password, then `ifup` | `/etc/network/interfaces.d/debsway-wifi-<dev>` |
| wpa_supplicant without a DHCP client | `wpa_supplicant@<dev>` service | that service + systemd-networkd |
| nothing | installs wpasupplicant from `debs/`, then as above | |
| nothing, and no `debs/` | asks for Ethernet or USB tethering, installs wpasupplicant with apt | |

It also handles a missing firmware (installs it from `debs/` and reloads
the driver), Wi-Fi switched off in hardware, hidden and open networks,
an installer that already set up Wi-Fi (asks first, keeps a backup of
`/etc/network/interfaces`), and getting an address without any DHCP
client (systemd-networkd, or busybox). USB tethering from a phone shows
up as a wired network, so it works with no Wi-Fi software at all.

## What install-base.sh does

1. Installs the core packages in one apt run, all with
   `--no-install-recommends`: `sway foot libgl1-mesa-dri firefox-esr
   libavcodec61 webext-ublock-origin-firefox gpg`, plus each part's.
   `libavcodec61` gives Firefox its video codecs; uBlock Origin comes
   from Debian and is on in every Firefox profile; `gpg` checks
   downloads.
2. Sets up sway (a copy of the stock config plus one `include` line for
   `~/.config/sway/config.d/`), the status bar, and the key cheat sheet.
3. Offers to start sway when you log in on tty1 (a marked block in
   `~/.profile`).
4. Runs every script in `parts/`. If one fails, the rest still run and
   it tells you which to re-run.

An existing sway config is kept; only the include line is added, and the
bar is only changed if it's still the stock one. Every snippet is
checked with `sway -C` before it's kept.

### parts/

| Script | Installs | Sets up |
|---|---|---|
| `unattended-upgrades.sh` | unattended-upgrades | Debian's security fixes install themselves daily, with Debian's default rules (other repos are left to you). Log: `/var/log/unattended-upgrades/` |
| `pipewire-audio.sh` | pipewire-audio | Sound; volume and mute keys use `wpctl` |
| `wmenu.sh` | wmenu | The launcher on Super+d |
| `swaylock.sh` | swaylock | Super+Escape locks |
| `swayidle.sh` | swayidle, swaylock | Lock after 5 min, screen off after 10, lock before sleep |
| `brightnessctl.sh` | brightnessctl | `brightness up\|down [STEP]`, never below 5%; brightness keys and Super+F1/F2 |
| `grim-slurp.sh` | grim, slurp | `screenshot` and its keys |
| `wl-clipboard.sh` | wl-clipboard | `wl-copy` / `wl-paste` |
| `mako.sh` | mako-notifier | Notifications close after 5 seconds; Super+n / Super+Shift+n dismiss |
| `udiskie.sh` | udiskie, udisks2, cryptsetup, polkitd | USB drives mount under `/media/$USER/`; encrypted (LUKS) sticks ask for their passphrase |
| `emoji-font.sh` | fonts-noto-color-emoji | Color emoji |
| `ufw.sh` | ufw | Firewall: blocks everything incoming, allows outgoing |
| `power-profiles-daemon.sh` | power-profiles-daemon | `powerprofilesctl set power-saver \| balanced \| performance` (skips itself if tlp is installed) |
| `firefox-hardening.sh` | libnotify-bin | See [Firefox hardening](#firefox-hardening) |
| `network-manager.sh` | network-manager, wpasupplicant, wireless-regdb, polkitd | Moves the Wi-Fi from the installer or wifi.sh into NetworkManager; `nmtui` to switch networks |
| `random-mac.sh` | (NetworkManager) | A made-up Wi-Fi MAC address on every connection and while scanning, so networks can't recognise the laptop from place to place |

**Random MAC side effects:** Wi-Fi login pages at cafés and hotels may
ask again after reconnecting, and your home router sees a new device
each time. For one made-up address per network instead, change `random`
to `stable` in `/etc/NetworkManager/conf.d/90-debsway-random-mac.conf`.

## Firefox hardening

`parts/firefox-hardening.sh` sets these for every Firefox profile:

- **uBlock Origin in "medium mode"**: scripts and frames from other
  sites are blocked everywhere. That's where most malicious ads and
  drive-by attacks come from, and most trackers. Some sites break: allow
  one with `ublock-allow example.com` (then restart Firefox).
  `ublock-allow --list` and `ublock-allow --remove example.com` manage
  the list. Changes made by clicking in uBlock's popup work too, but
  only until Firefox restarts, because uBlock re-reads debsway's rules at
  every start.
- **The JavaScript JIT is off.** Most serious Firefox exploits target the
  JIT, the part that turns JavaScript into fast machine code. JavaScript
  still works, just slower; heavy web apps can feel sluggish. Turn it back
  on for one site by giving it its own profile with fast JavaScript
  (`firefox-profiles/new-profile.sh`).
- **HTTPS-Only Mode**: Firefox won't load an unencrypted page without
  asking first, so nobody on café or hotel Wi-Fi can tamper with it.
- **A notice when Firefox needs a restart**: after an update, the running
  browser keeps the old, unfixed version until you restart it. A check
  every 10 minutes shows a notification when that's the case.

How: default prefs in `/etc/firefox-esr/debsway-hardening.js` (any
profile can change them at `about:config`), a uBlock policy in
`/etc/firefox-esr/policies/policies.json` (only written if no other
policies file exists), and a systemd user timer.
`bash parts/firefox-hardening.sh --remove` undoes all of it.

## extras/

Run one with `bash extras/NAME.sh`; run it again to repair it or, for
downloaded apps, update to the newest release; undo it with `--remove`.
Removing an app never deletes its data: wallets, chats and keyrings stay.

| Script | What you get |
|---|---|
| `keepassxc.sh` | KeePassXC password manager, from Debian |
| `git.sh` | git, and optionally GitHub's `gh`; sets your commit name and email |
| `claude-code.sh` | Claude Code, from Anthropic's signed apt repo |
| `tor-browser.sh` | Tor Browser (Safest, JavaScript off, your webtunnel bridges before its first connection). See below |
| `whonix.sh` | Whonix Gateway + Workstation VMs on KVM. See below |
| `onionshare.sh` | Share files, receive files, host a site or a chat over Tor, with your obfs4 bridges. Prints `onionshare-cli` examples |
| `mullvad-vpn.sh` | Mullvad VPN (app and `mullvad` command), from Mullvad's signed apt repo. Prints `mullvad` examples |
| `mullvad-browser.sh` | Mullvad Browser: Tor Browser's anti-tracking without Tor, for use with a VPN |
| `sparrow-wallet.sh` | Sparrow Bitcoin wallet, the signed official .deb. Command: `sparrow` |
| `electrum.sh` | Electrum Bitcoin wallet, from Debian |
| `feather-wallet.sh` | Feather Monero wallet, the signed official AppImage. Command: `feather` |
| `simplex-chat.sh` | SimpleX Chat desktop, the signed official AppImage. Command: `simplex` |
| `seahorse.sh` | Seahorse and the GNOME keyring, unlocked by your login password (edits `/etc/pam.d/login`; `--remove` takes the lines out) |
| `backup.sh` | Encrypted backups of your home folder with restic, and a `backup` command. Prints examples |
| `mat2.sh` | Removes hidden metadata from photos, PDFs and documents. Prints examples |
| `media.sh` | imv (images) and mpv (video, music). Prints examples and keys |
| `mockvps-kvm.sh` | `mockvps-kvm`: a disposable Debian "VPS" in a local QEMU/KVM VM for trying out server setups, with snapshots and one-command removal. See `extras/mockvps-kvm/README.md` |
| `mousepad.sh` | Mousepad, a simple graphical text editor (made the default for text files) |
| `file-manager.sh` | Thunar, a light graphical file manager, with Trash and thumbnails (made the default for folders). Prints its keys |

Downloads from outside Debian are checked against the keys in
`pins.sh`: the key is fetched into a throwaway keyring and refused
unless its fingerprint matches, then the release's signed checksum list
is checked, then the download against that list. AppImages are unpacked
into `~/.local/opt/NAME/`, so no FUSE is needed.

Apps that only run on X11 (Tor Browser, Mullvad Browser, Sparrow,
Feather, SimpleX) install XWayland; log out and back in once after the
first one, because sway only notices XWayland when it starts.

**Tor Browser.** Debian's `torbrowser-launcher` is in the **contrib**
section, so the script turns contrib on (and `--remove` turns it off, if
the script turned it on). Before Tor Browser's first start it writes a
`user.js` into its profile: the Safest security level, JavaScript off,
and the webtunnel bridge lines you paste in, so its very first
connection goes through a bridge. These are reapplied at every start;
run the script again to change them. It also fixes Tor's AppArmor
profile so webtunnel bridges can look up their host names. If
`fetch-tor-browser.sh` saved a copy, that's installed instead of
downloading one, so torproject.org is never contacted.

**Whonix.** Tor runs in the Gateway VM and your apps in the Workstation
VM, whose only network is the Gateway, so even a hacked browser can't
learn your real IP address. Everything runs as your user
(`qemu:///session`). The download (about 1.9 GB) is kept in `whonix/`;
`--fetch` only downloads it. Before the first boot the script writes into
the disk images (with `qemu-img` and `debugfs`; nothing is mounted): your
obfs4 bridges for the Gateway (Whonix 18 connects at first boot; without
bridges, Tor is kept off until you turn it on), and Safest with
JavaScript off for the Workstation's Tor Browser. Whonix can't use
webtunnel bridges. Then `whonix` starts both, `whonix gateway` opens the
Gateway's Tor settings, `whonix stop` shuts both down.

**OnionShare.** Debian's package pulls in the system tor service, which
would connect to Tor directly the moment it's installed, so the script
masks it first; OnionShare starts its own private tor, with your bridges.

**Backups.** `backup.sh` asks where backups go (a folder on a USB drive
is best) and creates an encrypted restic repository there. The password
is asked for every time and stored nowhere: keep it somewhere safe
outside the laptop. Then `backup` backs up your home folder (caches,
trash, VM disks and big downloads are left out; see
`~/.config/debsway/backup-excludes`), and `backup snapshots`,
`backup restore latest --target ~/restored` and the like work on it.

**Not included: yt-dlp.** It has to run YouTube's own JavaScript, and
the one runtime that sandboxes that code (deno) isn't in Debian;
Debian's yt-dlp is also too old to keep working.

## firefox-profiles/

`bash firefox-profiles/new-profile.sh` gives a website you stay logged
into (a bank, email, shopping, a work account) its own Firefox profile
and a `firefox-NAME` command. See `firefox-profiles/README.md` for why
that's useful.

## Your own setup: ignore/

Keep your personal choices out of the shared scripts: put them in
`ignore/`, which is in `.gitignore`. A `personal.sh` there can run the
extras you use and add your own look, keys and configs, e.g.:

```bash
#!/bin/bash
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user
for x in keepassxc git; do bash "$DEBSWAY_DIR/extras/$x.sh"; done
put_snippet look <<'EOF'
default_border none
output eDP-1 scale 1.25
EOF
bash "$DEBSWAY_DIR/firefox-profiles/new-profile.sh" mail https://mail.example --fast-js
```

`put_snippet NAME` writes `~/.config/sway/config.d/NAME.conf`, checks it
with `sway -C` and reloads sway.

## Keeping it working

Things outside debsway change: download pages move, signing keys are
replaced, packages get renamed, and new Whonix or Tor Browser versions
can change what the scripts rely on.

- **`bash test.sh`** checks it all without installing anything: every
  script parses and passes shellcheck; every Debian package still
  exists; every pinned signing key is still published, still has that
  fingerprint and isn't expiring; the newest release of each downloaded
  app can still be found and its signature verifies; the Debian and
  Firefox features the hardening relies on are still there; and the saved
  downloads still verify. `bash test.sh --offline` skips the network.
  Run it now and then, and before a reinstall.
- **`pins.sh`** holds every fingerprint and the outside versions the
  scripts were written against, each with the date it was last checked
  by hand (`# checked: YYYY-MM-DD`). `test.sh` warns when one is over a
  year old, and when Tor Browser or Whonix reach a new major version.
- **shellcheck on every change:** `git config core.hooksPath hooks` runs
  it before each commit (`hooks/pre-commit`; needs
  `sudo apt install shellcheck`), and the GitHub workflow in
  `.github/workflows/` runs it and `test.sh --offline` on every push.
  Settings are in `.shellcheckrc`.

## Other scripts

- `setup-sudo.sh USER` (as root): installs sudo and adds USER to the
  sudo group.
- `status.sh`: what's installed, the Firefox hardening, sway snippets,
  how each Wi-Fi device is set up, and a warning if `/`, `/home` or swap
  isn't encrypted.

## Keys

Super is the Windows / Cmd key. Super+? shows the full list
(`config/keys.txt`); the main ones:

| Key | Action |
|---|---|
| Super+Enter | terminal (foot) |
| Super+d | launcher (type e.g. `firefox`) |
| Super+Shift+q | close window |
| Super+1 … 0, Super+Shift+1 … 0 | go to / send window to workspace |
| Super+h/j/k/l or arrows | move focus |
| Super+f | fullscreen |
| Super+Escape | lock |
| Brightness keys, Super+F1 / F2 | brightness down / up |
| Print, Super+Shift+p | screenshot of the whole screen to ~/Pictures |
| Shift+Print, Super+Shift+s | screenshot of a region |
| Ctrl+Print, Super+Shift+x | region to the clipboard |
| Super+n / Super+Shift+n | dismiss one / all notifications |
| Super+Shift+c | reload config |
| Super+Shift+e | exit sway |

## Troubleshooting

- **A site doesn't work in Firefox**: uBlock's medium mode is probably
  blocking a script it needs. `ublock-allow thatsite.com`, then restart
  Firefox. To try it first: in uBlock's popup, make the red box next to
  "3rd-party scripts" grey and reload the page (that lasts until Firefox
  restarts).
- **A web app is slow**: give it its own profile with fast JavaScript:
  `bash firefox-profiles/new-profile.sh NAME URL --fast-js`.
- **sway won't start**: switch to another console with Ctrl+Alt+F2, log
  in, and run `sway -d 2>~/sway.log` from tty1 to see why. Missing GPU
  drivers (`libgl1-mesa-dri`) is the usual cause.
- **You want a plain shell on tty1**: use Ctrl+Alt+F2. To stop the
  autostart, delete the `debsway autostart` block in `~/.profile`.
- **A part failed during install-base.sh**: re-run just that one, e.g.
  `bash parts/pipewire-audio.sh`.
- **Wi-Fi gone after install-base.sh**: NetworkManager took it over. Run
  `nmtui` to pick the network, or `bash wifi.sh` to rescue it.
- **A Wi-Fi login page keeps asking again**: that's the random MAC; see
  [parts/](#parts).
- **USB stick doesn't mount**: `udiskie-info -a`, or mount it by hand
  with `udisksctl mount -b /dev/sdb1`.
- **No sound**: `wpctl status`. If nothing is listed, log out and back in.
- **Brightness keys do nothing**: log out and back in after
  `brightnessctl.sh` added you to the `video` group.
- **Something that used to work doesn't**: `bash test.sh` shows what
  changed outside debsway.

## License

[MIT](LICENSE), for all of debsway (`extras/mockvps-kvm/` keeps its own
copy of the same license).
