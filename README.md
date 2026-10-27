# debsway

Shell scripts that turn a bare Debian 13 (trixie) install into a
minimal, privacy-minded sway desktop: sound, a launcher, screen lock,
brightness, screenshots, notifications, USB automount, a firewall,
automatic security updates and easy Wi-Fi.
No desktop environment, no display manager, no tray, no settings app:
one compositor and plain text configs.

Everything else is optional, one script per app in `extras/`: Firefox
(hardened, with a throwaway `incognito` mode that plays video and sound),
w3m, Tor Browser with bridges, Whonix, Mullvad VPN and Browser, OnionShare,
wallets (Electrum, Sparrow, Feather), SimpleX Chat, KeePassXC, encrypted
backups and more.

- **Every piece can be undone**: `bash parts/NAME.sh --remove`,
  `bash extras/NAME.sh --remove`. Re-running a script repairs it. Packages
  that another piece still needs are kept ([Removing things](#removing-things)).
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
4. `install-base.sh` ends with a list of optional programs: arrow keys and
   the space bar check the ones you want. Add more later with
   `bash install-extras.sh`, or one directly: `bash extras/keepassxc.sh`.

`bash status.sh` shows what's set up; `bash test.sh` checks that it all
still works.

## Folder layout

```
debsway/
├── README.md, THREAT-MODEL.md, LICENSE (MIT)
├── install-base.sh          the core desktop: explains and asks, packages, sway, bar, every part, then the extras list
├── install-extras.sh        pick optional programs from a list (install-base.sh ends with it)
├── wifi.sh                  get online over Wi-Fi, whatever is installed
├── status.sh                what's installed; warns if the disk isn't encrypted
├── test.sh                  checks scripts, packages, downloads and keys still work
├── packages.sh              the core's package list and the order of the parts
├── pins.sh                  every signing key debsway trusts, with the date it was checked
├── lib.sh, lib/             shared helpers (sourced, not run): apt, sway, network, ...
├── parts/                   one script per core piece; install-base.sh runs them all
├── extras/                  optional apps, one script each (and firefox-profiles/)
├── bin/                     the small commands the scripts install into ~/.local/bin
├── data/                    key cheat sheet, foot and Mousepad settings, Tor Browser and incognito prefs
├── prep/                    intro.sh (what the base install does, and the question);
│                            before a reinstall: fetch-offline-debs.sh, fetch-tor-browser.sh;
│                            setup-sudo.sh (run as root if the installer left sudo out)
├── tools/                   for working on debsway: pack-usb.sh, tests
├── vendor/mockvps-kvm/      the mockvps-kvm project, with its own README and license
├── docs/                    the longer guides
├── hooks/pre-commit         shellcheck before every commit
├── .github/workflows/       shellcheck and test.sh --offline on every push
├── offline/                 saved downloads, not published (in .gitignore)
└── ignore/                  your own setup, never published (in .gitignore)
```

`offline/` holds the large downloads: `debs/` (Wi-Fi packages and their
signed Debian lists), `torbrowser/` and `whonix/`. Run every script with
`bash script.sh`; that works even when a USB stick's filesystem drops the
executable bit.

## Before you reinstall

1. Download the offline Wi-Fi packages, so a fresh install can get
   online without a cable: `bash prep/fetch-offline-debs.sh`. It picks the
   firmware for this machine's network cards, and saves Debian's signed
   package lists next to them, so `wifi.sh` can check every package on the
   stick before installing it. Preparing for a different
   machine? `bash prep/fetch-offline-debs.sh --all` gets the firmware for every
   common Wi-Fi card (larger).
2. Optionally `bash prep/fetch-tor-browser.sh`, so Tor Browser installs
   without contacting torproject.org.
3. **Back up everything you want to keep from `/home`**, above all wallet
   files and password databases: the encrypted install erases the whole
   disk. A plain USB stick isn't encrypted, so delete anything sensitive
   from it once it's restored.
4. Copy debsway to a USB stick: `bash tools/pack-usb.sh /media/you/STICK`
   copies the last commit and `offline/` (not your `ignore/` folder), or
   copy the whole `debsway` folder yourself.

## Installing Debian

In the installer:

- **Root password: leave it empty.** Debian then installs sudo and gives
  it to your user. If you set one, run `prep/setup-sudo.sh` later.
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
su -c "bash $HOME/debsway/prep/setup-sudo.sh $USER"    # then log out and back in

# 4. The core desktop
bash install-base.sh
```

Then log out (`exit`) and log in on tty1: sway starts by itself if you
said yes to that, otherwise type `sway`. The key cheat sheet opens on
your first login; Super+? brings it back.

## More

- [docs/wifi.md](docs/wifi.md): `wifi.sh`, and how the packages on the stick are checked
- [docs/install-base.md](docs/install-base.md): what `install-base.sh` sets up, and every part
- [docs/extras.md](docs/extras.md): the optional apps, Firefox with its hardening and `incognito`, Firefox profiles
- [docs/maintaining.md](docs/maintaining.md): `test.sh`, `pins.sh`, shellcheck, the other scripts
- [THREAT-MODEL.md](THREAT-MODEL.md): what this protects against, and what it doesn't

## Removing things

`bash parts/NAME.sh --remove` and `bash extras/NAME.sh --remove` undo one
piece. Several pieces need the same packages (QEMU for Whonix and
mockvps-kvm, XWayland for every app that only speaks X11), so a script
doesn't install its packages directly. It installs a tiny package of its
own, `debsway-NAME`, that depends on them. `--remove` removes that package
and lets apt autoremove what nothing else needs, so a shared package stays
until the last script that uses it is removed.

- `bash status.sh` lists every script's package list under "Packages
  debsway installed".
- To keep a package after its script is removed: `sudo apt-mark manual PACKAGE`.
- Packages a script installed before this bookkeeping existed have no
  marker; `--remove` then purges the packages it names, but never one that
  another script's marker needs, and shared ones (QEMU, XWayland) are left
  for you: `sudo apt autoremove` collects them once nothing needs them.
- Removing never deletes your data: wallets, chats, keyrings and profiles stay.

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
bash "$DEBSWAY_DIR/extras/firefox-profiles/new-profile.sh" mail https://mail.example --fast-js
```

`put_snippet NAME` writes `~/.config/sway/config.d/NAME.conf`, checks it
with `sway -C` and reloads sway.

## Keys

Super is the Windows / Cmd key. Super+? shows the full list
(`data/keys.txt`); the main ones:

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
  `bash extras/firefox-profiles/new-profile.sh NAME URL --fast-js`.
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
  [docs/install-base.md](docs/install-base.md).
- **USB stick doesn't mount**: `udiskie-info -a`, or mount it by hand
  with `udisksctl mount -b /dev/sdb1`.
- **No sound**: `wpctl status`. If nothing is listed, log out and back in.
- **Brightness keys do nothing**: log out and back in after
  `brightnessctl.sh` added you to the `video` group.
- **`wifi.sh` can't connect with a password**: the password is given to
  NetworkManager on its standard input. If your `nmcli` doesn't take it
  that way, run `DEBSWAY_PASSWORD_ON_COMMAND_LINE=1 bash wifi.sh`.
- **`wifi.sh` says the packages can't be matched to Debian's lists**: the
  stick's `offline/debs` is from an older version of debsway, or a
  package changed. On a machine you trust: `bash prep/fetch-offline-debs.sh`.
- **A program on a USB stick won't run**: drives mount `noexec`. Run it
  with its interpreter, copy it off, or see [docs/install-base.md](docs/install-base.md).
- **Something that used to work doesn't**: `bash test.sh` shows what
  changed outside debsway.

## License

[MIT](LICENSE), for all of debsway (`vendor/mockvps-kvm/` keeps its own
copy of the same license).
