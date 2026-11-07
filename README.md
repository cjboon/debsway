# Wren Linux

A minimal, privacy-minded [sway](https://swaywm.org) desktop for Debian 13 (trixie), installed by
plain shell scripts you can read in one sitting.

Start from a bare Debian install, and you get:

- a launcher and notifications
- a screen lock, with a slow dimming warning first
- a firewall, kernel hardening and automatic security updates
- brightness keys and easy Wi-Fi, where the computer has the hardware

Sound, a browser, screenshots and USB automount are optional extras you pick right after you agree
to the install. Nothing is checked for you.

No desktop environment, display manager, tray or settings app: one compositor and plain text configs.

**New here? Start with the [first-time guide](docs/first-time.md).**

- To report a security problem, or check Wren Linux's signing key: [SECURITY.md](SECURITY.md)
- To help: [CONTRIBUTING.md](CONTRIBUTING.md) and [how Wren Linux fits together](docs/architecture.md)
- To see each change from plain Debian, and how to check it:
  [what Wren Linux adds to Debian](docs/what-wren-adds.md)

To learn:

- [What Debian is, and why Wren Linux is based on it](docs/what-is-debian.md), and [its history](docs/history-of-debian.md)
- [What free and open source software is, and what it has built](docs/what-is-foss.md)
- [GPG in plain words](docs/gpg.md)
- [What an onion site is](docs/what-is-an-onion-site.md), and [a short history of Tor](docs/history-of-tor.md)
- [What Monero is](docs/what-is-monero.md)
- [A practical opsec guide](docs/opsec.md)
- [Good passwords, and how to keep them](docs/passwords.md)
- [A VPN before Tor: keeping your records away from your ISP](docs/vpn-before-tor.md)

Wren Linux is based on Debian; it is not affiliated with or endorsed by the Debian project. (It was
called debsway until November 2026.)

## What's different from a dotfiles repo

**Hardened Firefox** (an extra you pick):

- uBlock Origin (standard or medium mode, your choice), HTTPS-Only, JIT off and DuckDuckGo.
- No password-saving prompts (KeePassXC keeps them), and a folder of learning bookmarks.
- `firefox` runs it as its own locked-down user: shared clipboard and `~/Downloads`, nothing else of yours.
- `incognito` opens a throwaway Firefox as a separate locked-down user, in memory, on a restricted
  Wayland socket, with its own firewall rule and audio. It plays video and sound.
- "Wi-Fi sign-in" in the Wren menu opens one for a café's sign-in page, the only window that uses the
  network's DNS.

**Sandboxes for the risky things:** images and video open in bubblewrap, and Claude Code can run as its
own user or in a VM. Tor Browser, Whonix, wallets and more are one script each in `extras/`.

**Everything undoable and checked:**

- Every part and extra has `--remove`.
- Every program downloaded from outside Debian is signature-checked against a key pinned in `pins.sh`.
- `test.sh` checks that it all still works.

Everything beyond the base is optional, one script per app in `extras/`: Firefox profiles, w3m, Tor
Browser with bridges, Whonix, Mullvad VPN and Browser, encrypted DNS (Unbound, DNSSEC, DNS over TLS),
OnionShare, your own onion site in an offline VM, wallets (Electrum, Sparrow, Feather), SimpleX Chat,
KeePassXC, encrypted backups and more.

It's a set of scripts, not a distribution: you install Debian yourself, then run them. Read them first.
`THREAT-MODEL.md` says plainly what this protects against and what it doesn't. It is a personal project
tested on Debian 13 only.

Good to know before you run anything:

- Re-running a script repairs it, and packages that another piece still needs are kept when you remove
  one ([Removing things](#removing-things)).
- The scripts change system files: apt sources, AppArmor, PAM (for one extra), Firefox policies, firewall
  rules.

## Quick start

1. Install Debian 13 with disk encryption and no desktop (details in
   [Installing Debian](#installing-debian)).
2. Log in on the text console, plug in the USB stick (labelled `WREN`,
   which `tools/pack-usb.sh` does for you) and type one line:

```bash
sudo mount -L WREN /mnt && bash /mnt/wren/start.sh
```

   `start.sh` copies Wren Linux to `~/wren`, unmounts the stick, runs
   `wifi.sh` if you aren't online, and starts `install-base.sh`, which
   explains what it will do and asks before changing anything. (Without
   the stick, see [After the first boot](#after-the-first-boot).)

3. Log out and log in on tty1: sway starts. Super+? shows every key (also
   `keys` in a terminal, or the file `~/KEYS.txt`).
4. `install-base.sh` starts with a list of optional programs, and installs them
   at its end: arrow keys and the space bar check the ones you want, and `/` searches. Add more later with
   `bash install-extras.sh`, or one directly: `wrenctl install keepassxc`.

`bash status.sh` (Status in the Wren menu) shows what's set up. It starts
with "Security at a glance": disk encryption, screen lock, firewall, automatic
updates, the sandboxed browser and encrypted DNS, each [x] done, [~] partly or
[ ] not, with what to run. `bash test.sh` checks that it all still works.

## Folder layout

```
wren/
├── README.md, THREAT-MODEL.md, SECURITY.md, CONTRIBUTING.md, LICENSE (MIT)
├── start.sh                 from the stick on a fresh install: copies Wren Linux home, unmounts,
│                            wifi.sh if needed, install-base.sh
├── install-base.sh          the core desktop: explains and asks, packages, sway, bar, every part,
│                            then the extras list
├── install-extras.sh        pick optional programs from a list (install-base.sh ends with it)
├── wifi.sh                  get online over Wi-Fi, whatever is installed
├── status.sh                security at a glance first, then what's installed
├── update.sh                bring Wren Linux up to date and rerun the scripts whose files changed
├── encrypt-usb.sh           erases a USB stick and makes it encrypted (LUKS), for backups and keys
├── test.sh                  checks scripts, packages, downloads and keys still work
├── packages.sh              the core's package list and the order of the parts
├── pins.sh                  every signing key Wren Linux trusts, with the date it was checked
├── lib.sh, lib/             shared helpers (sourced, not run): apt, sway, network, ...
├── parts/                   one script per core piece; install-base.sh runs them all
├── extras/                  optional apps, one script each (and firefox-profiles/)
├── bin/                     the small commands the scripts install into ~/.local/bin
├── data/                    key cheat sheet, foot and Mousepad settings, Tor Browser and
│                            incognito prefs
├── prep/                    intro.sh (what the base install does, and the question);
│                            before a reinstall: fetch-offline-debs.sh, fetch-tor-browser.sh;
│                            setup-sudo.sh (run as root if the installer left sudo out)
├── tools/                   for working on Wren Linux, in a git copy only: pack-usb.sh, tests
├── vendor/mockvps-kvm/      the mockvps-kvm project, with its own README and license
├── docs/                    the longer guides
├── .github/workflows/       shellcheck and test.sh --offline on every push
├── offline/                 saved downloads, not published (in .gitignore)
└── ignore/                  your own setup, never published (in .gitignore)
```

`offline/` holds the large downloads: `debs/` (Wi-Fi packages and their
signed Debian lists), `torbrowser/` and `whonix/`. When Wren Linux runs from a
folder you can't write to (the package's root-owned `/usr/share/wren`),
they go in `~/.local/share/wren/offline` instead. Run every script with
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
4. Copy Wren Linux to a USB stick: `bash tools/pack-usb.sh /media/you/STICK`
   copies the last commit and `offline/` (not your `ignore/` folder),
   labels the stick `WREN` (it asks) and adds a `START-HERE.txt` you can
   read on another computer. The label is what lets one line find the stick
   on the new system. Or copy the whole Wren Linux folder yourself and label
   the stick yourself (`fatlabel /dev/sdX1 WREN` for FAT,
   `e2label /dev/sdX1 WREN` for ext4).

## An automatic install stick

Instead of installing Debian by hand and copying Wren Linux over, you can build a stick that does both:

```bash
bash prep/make-install-iso.sh
```

**What it builds.** It downloads Debian 13's live "standard" image, text only, checked against the Debian
CD signing key pinned in `pins.sh`. It adds Wren Linux's answers and Wren Linux itself, and can write it
to a USB stick.

**What it does when you boot from it.** "Automatic install with Wren Linux" installs Debian as below:

- Encrypted LVM over the whole disk, and no root password.
- The installer copies the live system, and the base install's `parts/no-live-extras.sh` takes out what
  that brings and Wren Linux doesn't use, such as avahi and printing.
- Wren Linux goes in as its package, root's, in `/usr/share/wren`. Nothing of it is in your home: the saved
  downloads go to `~/.local/share/wren/offline`, and the docs are linked in `~/Documents/wren-docs`.

It asks only for the disk passphrase, your password, and the final "write the changes to disks?", which
names the disk it erases. The stick itself is never offered.

**At the first login** on the console, it asks once "Set it up now?". Enter runs
`bash /usr/share/wren/start.sh` (the usual introduction and questions), and n leaves it for later.

**Options:**

| Option | What it does |
|---|---|
| `--user NAME` | The user to make |
| `--keymap de` | The keyboard layout |
| `--locale de_DE.UTF-8` | The language and formats |
| `--timezone Europe/Berlin` | The clock's time zone. By default, the one of the computer building the image |
| `--no-erase` | Skip filling the disk with random data |
| `--noencrypt` | No disk encryption: no passphrase at boot, but anyone with the laptop can read the disk. It asks first |
| `--autologin` | tty1 logs you in without your password and starts sway |
| `--simplesway` | One workspace: the first install list starts with `one-workspace` ticked |
| `--scripts FOLDER` | Your own files, to `~/scripts` |
| `--public` | An image for anyone (`tools/publish-image.sh`): the user "user", UTC, a US keyboard, disk encryption, and no saved downloads |

**What it needs:** xorriso, wget, gpg and git, which it installs first if they're missing. xorriso it
removes again at the end.

**The offline Wi-Fi packages** (`offline/debs`, for a laptop with no network at first boot) are refreshed
first when they'd soon be too old for `wifi.sh` to take, and it says until when they work: about a week
after the build, since Debian's security and updates lists are only valid that long. An older stick still
installs, over a cable or a phone.

**Try the image in a VM first:** `bash tools/try-install-iso.sh` starts it the way a laptop would (UEFI, the
image as a USB stick, an empty 20 GB disk), says what to check, then starts the installed system.

- `--two-disks` checks that it asks which disk.
- `--clean` deletes the VM to start over.
- `--remove` removes the packages it installed (QEMU stays if Whonix, claude-vm or mockvps-kvm use it).

In the VM's window, your own sway takes Super+Enter, Super+d and the rest first. Press Ctrl+Alt+G there to
give the VM the keyboard (again to take it back), or click **Wren Menu** in the VM's bar and choose Terminal.

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
# 1. Get the scripts. From the USB stick (labelled WREN):
sudo mount -L WREN /mnt
cp -r /mnt/wren ~ && sudo umount /mnt
#    If it can't find the label, lsblk -f lists the drives and dmesg | tail
#    shows the name the stick got (e.g. sdb1): sudo mount /dev/sdb1 /mnt
#
#    Or, with no stick, if you're already online (a cable, USB tethering from
#    a phone, or Wi-Fi you set up in the installer; wifi.sh is one of the
#    scripts you're downloading, so it can't help yet):
#    wget -qO- https://github.com/cjboon/wren-linux/archive/refs/heads/main.tar.gz | tar xz
#    mv wren-linux-main wren
#    (git isn't part of "standard system utilities", wget is. Read the
#    scripts before you run them: this comes over https from GitHub only.)
cd ~/wren

# 2. Get online (skip if you already are: a cable, or the installer's Wi-Fi)
bash wifi.sh

# 3. Only if you set a root password in the installer
su -c "bash $HOME/wren/prep/setup-sudo.sh $USER"    # then log out and back in

# 4. The core desktop
bash install-base.sh
```

Then log out (`exit`) and log in on tty1: sway starts by itself if you said yes to that, otherwise type
`sway`. The key cheat sheet opens on your first login. Super+? brings it back, and so does typing `keys`
or opening `~/KEYS.txt`.

**The status bar:**

- **Wren Menu, at its left:** click it for a black-and-gray menu in a floating window over what you were
  doing, with your browser, password manager and terminal, the lists Apps, Wi-Fi, Settings, System and
  Power, and Help (the sheet). Use arrow keys and Enter, or click. Esc
  goes back from a list, and closes the rest.
- **The Wi-Fi name,** next to it, opens nmtui.
- **`vol` and `bright`:** scrolling over them changes them, and clicking `vol` mutes.
- **`bat`:** clicking it says how long the battery will last.

**Timers and alarms:** click the time (or press Super+t), for this month's calendar (`cal`, from `ncal`) and
today's date. Type `10m` or `7:30` and press Enter. Esc, or another click on the time, closes it.

The same goes for the Wren menu and the Wi-Fi screen: click again to close. Only one of them is open at a
time: clicking another closes it (except the menu while it runs Update or Install apps, which stays).

From a terminal:

- `timer 10m tea`
- `timer at 7:30 wake up`
- `timer clock` (date in the bar or not)

Timers last until you log out, and a sleeping laptop does not wake for them.

### Getting updates from GitHub

The copy from the stick has the files but no git history. Once you're
online, this makes it a git checkout of the published Wren Linux
(`WREN_GIT_URL` in `pins.sh`), without changing a file:

```bash
bash ~/wren/git-helper.sh
```

**What it asks:**

- First, your name and email for commits. On GitHub, it offers your no-reply address, since GitHub refuses
  pushes that carry an email you keep private.
- At the end, how git logs in to push from here: a token you paste at each push (nothing saved), the same
  kept in memory for an hour, or, with GitHub's gh installed by you, its login (saved in plain text).

It never pushes by itself. `wrenctl git` does the same for any repository of yours (`wrenctl git DIR`, or run
inside it).

**What it does:** it finds the published commit whose files are exactly yours and sets your copy there, so
`bash ~/wren/update.sh` then shows and brings in what came after.

- If your files match nothing that was published (you changed them, or someone changed them on the stick), it
  says so. Look at `git -C ~/wren status` and `git -C ~/wren diff` before you run anything with sudo.
- Once `pins.sh` names Wren Linux's signing key, it also refuses a server whose newest commit that key didn't sign.

After that, `update.sh` (or `claude-pull`) shows what's new and asks before bringing it in. Plain `git pull`
works too. (`claude-pull` is installed by the Claude Code sandboxes, `extras/claude-code.sh` and
`extras/claude-vm.sh`.)

**If Claude Code pushes to the repository,** add the ssh key its sandbox prints as a deploy key on GitHub (with
write access), replacing the old install's. `wrenctl gh deploy-key` does it from the command line, no browser:

- It reads the VM's key and adds it, with a token that stays on your computer, never in the VM.
  Making the token is the one step in a browser: GitHub makes tokens nowhere else. Its link fills in
  the form but can't pick the repository, so pick it yourself (Only select repositories). Don't delete
  that token afterwards: GitHub deletes a deploy key along with the token that added it.
- It checks the rules on `main` first and offers to add any that are missing. No key goes on while `main` is
  open or can't be checked.
- It then offers to remove the last VM's key, which a rebuild leaves on GitHub, still able to push.

## The `wrenctl` command

In a terminal, `wrenctl --help` lists what it does and `man wrenctl` has the details. Each option works with or
without its dashes (`wrenctl update`, `wrenctl --update`).

| Command | What it does |
|---|---|
| `wrenctl --update` | Brings Wren Linux up to date (see below) |
| `wrenctl --apps` | Picks optional programs |
| `wrenctl --status` | Shows what is set up |
| `wrenctl --test` | Runs the checks |
| `wrenctl --welcome` | Shows the key cheat sheet again |
| `wrenctl` | On a sway screen, alone (or a click on **Wren Menu** in the bar), opens the menu |

One extra at a time:

| Command | What it does |
|---|---|
| `wrenctl install NAME` | Installs it, or repairs or updates it |
| `wrenctl remove NAME` | Takes it out |
| `wrenctl manual NAME` | Prints the steps to do it by hand |
| `wrenctl list` | Lists them all |
| `wrenctl part NAME` | Runs one part of the base again |

Tab completes the name. Only the exact name of an extra is accepted, so nothing else is run. Options after the
name go to its script (`wrenctl install claude-vm --account work`).

## Updating

```bash
bash ~/wren/update.sh
```

or click **Wren Menu** at the left of the status bar and choose Update. Install apps (`install-extras.sh`) opens in the
same window, and Esc on its list with nothing picked closes the window at once.

**What's new.** It fetches what's new, shows you every change, and asks before bringing it in. It's only ever a
plain fast-forward, so your own edits are never overwritten.

**The signature.** Once `pins.sh` names Wren Linux's signing key (`WREN_SIGNING_FPR`), it brings a change in only
if the newest commit carries a good signature from exactly that key, checked with the key in the copy you already
have. Until then, it says that it didn't check.

**Running scripts again.** It lists the parts and extras you have set up whose files changed, and offers to run them
again, one after the other. Running a script again is how a change reaches `/usr/local`, the firewall or Firefox's policy.

- If a script fails, it says so and offers it again next time.
- A part of the base desktop that is new in an update is offered too, even though it isn't set up yet.
- An extra Wren Linux has retired (its `# retired:` line says why) gets no more runs. If you still have it, it asks
  whether to take it out with its own `--remove`, and Enter keeps it until next time. Otherwise it never runs `--remove`.

**Signing keys.** Each run also checks the signing keys of the apt repositories Wren Linux added (Claude Code, Signal,
Mullvad, the Tor Project's for lyrebird). One that has expired, or will within 60 days, is fetched again, and the new
one goes in only if it is exactly the pinned key (`pins.sh`) and lasts longer. Without this, a key that runs out would
quietly stop that program's updates. `status.sh` shows the same check.

**The first run** takes what you have now as already applied. If you updated by hand earlier,
`bash update.sh --since COMMIT` offers what changed after that commit (`git log` shows it), and `bash update.sh --all`
offers everything that is set up.

## More

| Page | What it covers |
|---|---|
| [docs/first-time.md](docs/first-time.md) | Your first install and first day, step by step |
| [docs/wifi.md](docs/wifi.md) | `wifi.sh`, and how the packages on the stick are checked |
| [docs/install-base.md](docs/install-base.md) | What `install-base.sh` sets up, and every part |
| [docs/extras.md](docs/extras.md) | The optional apps, Firefox with its hardening and `incognito`, Firefox profiles |
| [docs/extras/](docs/extras/README.md) | One page per extra: its commands, what it is, what it doesn't protect against, and every step to install it by hand (`wrenctl manual NAME` prints them) |
| [docs/vps.md](docs/vps.md) | The website, its git mirror and onion addresses on a VPS (`tools/setup-vps.sh`), tried in a local VM first |
| [docs/bios.md](docs/bios.md) | The BIOS (UEFI firmware) settings for a Wren Linux install, and for security in general, with a checklist |
| [docs/opsec.md](docs/opsec.md) | Operations security in general: laptops, USB drives, networks, passwords, encryption, private communication, physical security, and what to do when something goes wrong |
| [docs/maintaining.md](docs/maintaining.md) | In a git copy (`wrenctl install wren-dev` gets one): `test.sh`, `pins.sh`, shellcheck, the other scripts |
| [docs/distro-plan.md](docs/distro-plan.md) | In a git copy too: the plan from these scripts to a Debian-based distribution: a package, a signed apt repository, a website, an installer image |
| [THREAT-MODEL.md](THREAT-MODEL.md) | What this protects against, and what it doesn't |

## Removing things

`wrenctl remove NAME` (for an extra; `bash extras/NAME.sh --remove` does the
same) and `bash parts/NAME.sh --remove` undo one piece.

Several pieces need the same packages (QEMU for Whonix and mockvps-kvm, XWayland for every app that only speaks X11), so a script
doesn't install its packages directly. It installs a tiny package of its
own, `wren-NAME`, that depends on them. `--remove` removes that package
and lets apt autoremove what nothing else needs, so a shared package stays
until the last script that uses it is removed.

- `bash status.sh` lists every script's package list under "Packages
  Wren Linux installed".
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
for x in keepassxc git; do bash "$WREN_DIR/extras/$x.sh"; done
put_snippet look <<'EOF'
default_border none
output eDP-1 scale 1.25
EOF
bash "$WREN_DIR/extras/firefox-profiles/new-profile.sh" mail https://mail.example --fast-js
```

`put_snippet NAME` writes `~/.config/sway/config.d/NAME.conf`, checks it
with `sway -C` and reloads sway.

## Keys

Super is the Windows / Cmd key. The first time sway starts, it asks whether
its shortcuts should use Super or Alt (for a keyboard without a Windows key);
`keys --mod alt` or `keys --mod super` switches later, and the cheat sheet
shows whichever you use. Super+? shows the full list (`data/keys.txt`); the
main ones:

| Key | Action |
|---|---|
| Super+Enter | terminal (foot) |
| Super+d | launcher (type e.g. `firefox`) |
| Super+Shift+q | close window |
| Super+1 … 0, Super+Shift+1 … 0 | go to / send window to workspace |
| Super+h/j/k/l or arrows | move focus |
| Super+f | fullscreen |
| Super+Escape | lock (by itself, the screen turns off after 5 minutes idle and locks a minute later; `timer lock 10` changes that) |
| Brightness keys, Super+F1 / F2 | brightness down / up |
| Print, Super+Shift+p | screenshot of the whole screen to ~/Pictures |
| Shift+Print, Super+Shift+s | screenshot of a region |
| Ctrl+Print, Super+Shift+x | region to the clipboard |
| Super+n / Super+Shift+n | dismiss one / all notifications |
| Super+Shift+c | reload config |
| Super+Shift+e | exit sway |

## Troubleshooting

- **A site doesn't work in Firefox**: if you chose uBlock's medium mode, it is
  probably blocking a script the site needs (`ublock-allow --list` says the mode).
  `ublock-allow thatsite.com`, then restart Firefox. To try it first: in uBlock's popup, make the red box next to
  "3rd-party scripts" grey and reload the page (that lasts until Firefox
  restarts).
- **A web app is slow**: give it its own profile with fast JavaScript:
  `bash extras/firefox-profiles/new-profile.sh NAME URL --fast-js`.
- **sway won't start**: switch to another console with Ctrl+Alt+F2, log
  in, and run `sway -d 2>~/sway.log` from tty1 to see why. Missing GPU
  drivers (`libgl1-mesa-dri`) is the usual cause.
- **You want a plain shell on tty1**: use Ctrl+Alt+F2. To stop the
  autostart, delete the `Wren Linux autostart` block in `~/.profile`.
- **A part failed during install-base.sh**: re-run just that one, e.g.
  `wrenctl part NAME` (or `wrenctl install NAME` for an extra).
- **Wi-Fi gone after install-base.sh**: NetworkManager took it over. Run
  `nmtui` to pick the network, or `bash wifi.sh` to rescue it.
- **A Wi-Fi login page keeps asking again**: that's the random MAC; see
  [docs/install-base.md](docs/install-base.md#networks-and-dns).
- **USB stick doesn't mount, or you can't write to it**: `usb` lists your
  sticks and `usb mount` mounts one as you. Don't use `sudo mount`: a FAT or
  exFAT stick mounted that way is root's, all of it (`usb mount` offers to
  fix that). Before pulling it out: `usb unmount`.
- **No sound**: `wpctl status`. If nothing is listed, log out and back in.
- **Brightness keys do nothing**: log out and back in after
  `brightnessctl.sh` added you to the `video` group.
- **`wifi.sh` can't connect with a password**: the password is given to
  NetworkManager on its standard input. If your `nmcli` doesn't take it
  that way, run `WREN_PASSWORD_ON_COMMAND_LINE=1 bash wifi.sh`.
- **`wifi.sh` says the packages can't be matched to Debian's lists**: the
  stick's `offline/debs` is from an older version of Wren Linux, a
  package changed, or the saved lists are old (Debian's security and
  updates lists are good for a week, the stable list for about 4 months;
  the message names which). On a machine you trust:
  `bash prep/fetch-offline-debs.sh`. To accept old lists on purpose:
  `WREN_OFFLINE_ALLOW_STALE=1 bash wifi.sh`.
- **A program on a USB stick won't run**: drives mount `noexec`. Run it
  with its interpreter, copy it off, or see [docs/install-base.md](docs/install-base.md#usb).
- **Something that used to work doesn't**: `bash test.sh` shows what
  changed outside Wren Linux.

## License

[MIT](LICENSE), for all of Wren Linux (`vendor/mockvps-kvm/` keeps its own
copy of the same license).

The pictures in `data/wallpapers/` aren't under it: each keeps its own licence, named with its author in
`data/wallpapers/CREDITS.txt`.
