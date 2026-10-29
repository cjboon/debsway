# debsway

A minimal, privacy-minded [sway](https://swaywm.org) desktop for Debian 13
(trixie), installed by plain shell scripts you can read in one sitting.
Start from a bare Debian install; get a launcher, screen lock (with a slow
dimming warning first), notifications, a firewall, kernel hardening and
automatic security updates, plus, where the computer has the hardware,
brightness keys and easy Wi-Fi. Sound, a browser, screenshots and USB
automount are optional extras you pick right after you agree to the install
(nothing is checked for you). No desktop environment, display manager, tray
or settings app: one compositor and plain text configs.

What's different from a dotfiles repo:

- **Hardened Firefox** (an extra you pick): uBlock Origin in medium mode, HTTPS-Only,
  JIT off, DuckDuckGo, and `firefox` runs it as its own locked-down user (shared
  clipboard and `~/Downloads`, nothing else of yours). `incognito` opens a throwaway Firefox as a
  separate locked-down user, in memory, on a restricted Wayland socket,
  with its own firewall rule and audio, that plays video and sound.
- **Sandboxes for the risky things**: images and video open in bubblewrap;
  Claude Code can run as its own user or in a VM; Tor Browser, Whonix,
  wallets and more are one script each in `extras/`.
- **Everything undoable and checked**: every part and extra has `--remove`;
  every download from outside Debian is signature-checked against a key
  pinned in `pins.sh`; `test.sh` checks that it all still works.

Everything beyond the base is optional, one script per app in `extras/`:
Firefox profiles, w3m, Tor Browser with bridges, Whonix, Mullvad VPN and
Browser, OnionShare, wallets (Electrum, Sparrow, Feather), SimpleX Chat,
KeePassXC, encrypted backups and more.

It's a set of scripts, not a distribution: you install Debian yourself,
then run them. Read them first. `THREAT-MODEL.md` says plainly what this
protects against and what it doesn't. It is a personal project tested on
Debian 13 only.

Good to know before you run anything:

- Re-running a script repairs it, and packages that another piece still
  needs are kept when you remove one ([Removing things](#removing-things)).
- The scripts change system files: apt sources, AppArmor, PAM (for one
  extra), Firefox policies, firewall rules.

## Quick start

1. Install Debian 13 with disk encryption and no desktop (details in
   [Installing Debian](#installing-debian)).
2. Log in on the text console, plug in the USB stick (labelled `DEBSWAY`,
   which `tools/pack-usb.sh` does for you) and type one line:

```bash
sudo mount -L DEBSWAY /mnt && bash /mnt/debsway/start.sh
```

   `start.sh` copies debsway to `~/debsway`, unmounts the stick, runs
   `wifi.sh` if you aren't online, and starts `install-base.sh`, which
   explains what it will do and asks before changing anything. (Without
   the stick, see [After the first boot](#after-the-first-boot).)

3. Log out and log in on tty1: sway starts. Super+? shows every key (also
   `keys` in a terminal, or the file `~/KEYS.txt`).
4. `install-base.sh` ends with a list of optional programs: arrow keys and
   the space bar check the ones you want. Add more later with
   `bash install-extras.sh`, or one directly: `bash extras/keepassxc.sh`.

`bash status.sh` shows what's set up; `bash test.sh` checks that it all
still works.

## Folder layout

```
debsway/
├── README.md, THREAT-MODEL.md, LICENSE (MIT)
├── start.sh                 from the stick on a fresh install: copies debsway home, unmounts, wifi.sh if needed, install-base.sh
├── install-base.sh          the core desktop: explains and asks, packages, sway, bar, every part, then the extras list
├── install-extras.sh        pick optional programs from a list (install-base.sh ends with it)
├── wifi.sh                  get online over Wi-Fi, whatever is installed
├── status.sh                what's installed; warns if the disk isn't encrypted
├── update.sh                bring debsway up to date and rerun the scripts whose files changed
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
   copies the last commit and `offline/` (not your `ignore/` folder),
   labels the stick `DEBSWAY` (it asks) and adds a `START-HERE.txt` you can
   read on another computer. The label is what lets one line find the stick
   on the new system. Or copy the whole `debsway` folder yourself and label
   the stick yourself (`fatlabel /dev/sdX1 DEBSWAY` for FAT,
   `e2label /dev/sdX1 DEBSWAY` for ext4).

## Installing Debian

In the installer:

- **Root password: leave it empty, don't set one.** Debian then locks the
  root account (nobody can log in as root, on the console or anywhere
  else) and gives your user sudo. A root password is one more password
  that unlocks the whole system, typed at a login prompt where every
  command runs with full rights and nothing records which user did what;
  with sudo, root is used only for single commands, after your own
  password, and the system logs each one. If you set one anyway, run
  `prep/setup-sudo.sh` later, and lock root afterwards with
  `sudo passwd -l root`.
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

The quick way is the one line in the [Quick start](#quick-start). By hand,
or without the stick:

```bash
# 1. Get the scripts. From the USB stick (labelled DEBSWAY):
sudo mount -L DEBSWAY /mnt
cp -r /mnt/debsway ~ && sudo umount /mnt
#    If it can't find the label, lsblk -f lists the drives and dmesg | tail
#    shows the name the stick got (e.g. sdb1): sudo mount /dev/sdb1 /mnt
#
#    Or, with no stick, if you're already online (a cable, USB tethering from
#    a phone, or Wi-Fi you set up in the installer; wifi.sh is one of the
#    scripts you're downloading, so it can't help yet):
#    wget -qO- https://github.com/cjboon/debsway/archive/refs/heads/main.tar.gz | tar xz
#    mv debsway-main debsway
#    (git isn't part of "standard system utilities", wget is. Read the
#    scripts before you run them: this comes over https from GitHub only.)
cd ~/debsway

# 2. Get online (skip if you already are: a cable, or the installer's Wi-Fi)
bash wifi.sh

# 3. Only if you set a root password in the installer
su -c "bash $HOME/debsway/prep/setup-sudo.sh $USER"    # then log out and back in

# 4. The core desktop
bash install-base.sh
```

Then log out (`exit`) and log in on tty1: sway starts by itself if you
said yes to that, otherwise type `sway`. The key cheat sheet opens on
your first login; Super+? brings it back, and so does typing `keys` or
opening `~/KEYS.txt`. The status bar has a "debsway" at its left: click it for a black-and-gray menu that fills the window area under the bar (arrow keys and Enter, or click; Esc closes every screen) with Help (the sheet), Install apps, Update and Status, and the Wi-Fi name next to it opens nmtui. Scrolling over "vol" or "bright" changes them; clicking "vol" mutes, and clicking "bat" says how long the battery will last.

Click the time (or press Super+t) for timers and alarms: type `10m` or `7:30` and press Enter; Esc closes it. From a terminal: `timer 10m tea`, `timer at 7:30 wake up`, `timer clock` (date in the bar or not). Timers last until you log out; a sleeping laptop does not wake for them.

### Getting updates from GitHub

The copy from the stick has the files but no git history. Once you're
online, this makes it a git checkout of GitHub's debsway, without changing
a file (`git status` then shows anything that differs from GitHub):

```bash
cd ~/debsway && git init -q -b main && git remote add origin https://github.com/cjboon/debsway.git && git fetch -q && git reset origin/main && git branch -u origin/main && git status
```

After that, `claude-pull` shows what's new and asks before bringing it in;
plain `git pull` works too. (`claude-pull` is installed by the Claude Code
sandboxes, `extras/claude-code.sh` and `extras/claude-vm.sh`.) If Claude Code
pushes to the repository, add the ssh key its sandbox prints as a deploy key
on GitHub (with write access), replacing the old install's.

## The `debsway` command

In a terminal, `debsway --help` lists what it does and `man debsway` has the
details. `debsway --update` brings debsway up to date (see below),
`debsway --apps` picks optional programs, `debsway --status` shows what is
set up, `debsway --test` runs the checks, `debsway --welcome` shows the key
cheat sheet again. On a sway screen, `debsway` alone (or a click on
**debsway** in the bar) opens the menu.

## Updating

```bash
bash ~/debsway/update.sh
```

or click **debsway** at the left of the status bar and choose Update. Install apps (`install-extras.sh`) opens in the same window; Esc on its list with nothing picked closes the window at once.

It fetches what's new, shows you every change, and asks before bringing it
in (only a plain fast-forward, so your own edits are never overwritten).
Then it lists the parts and extras you have set up whose files changed and
offers to run them again, one after the other: running a script again is
how a change reaches `/usr/local`, the firewall or Firefox's policy. It
never runs `--remove`. If a script fails it says so and offers it again
next time. A part of the base desktop that is new in an update is offered
too, even though it isn't set up yet.

The first run takes what you have now as already applied. If you updated by
hand earlier, `bash update.sh --since COMMIT` offers what changed after that
commit (`git log` shows it), and `bash update.sh --all` offers everything
that is set up.

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
  `bash parts/NAME.sh` (or `bash extras/NAME.sh`).
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
  stick's `offline/debs` is from an older version of debsway, a
  package changed, or the saved lists are old (Debian's security and
  updates lists are good for a week, the stable list for about 4 months;
  the message names which). On a machine you trust:
  `bash prep/fetch-offline-debs.sh`. To accept old lists on purpose:
  `DEBSWAY_OFFLINE_ALLOW_STALE=1 bash wifi.sh`.
- **A program on a USB stick won't run**: drives mount `noexec`. Run it
  with its interpreter, copy it off, or see [docs/install-base.md](docs/install-base.md).
- **Something that used to work doesn't**: `bash test.sh` shows what
  changed outside debsway.

## License

[MIT](LICENSE), for all of debsway (`vendor/mockvps-kvm/` keeps its own
copy of the same license).
