# extras/

Install one with `wrenctl install NAME` (Tab completes the name; it runs
`extras/NAME.sh`); run it again to repair it or, for downloaded apps, update
to the newest release; undo it with `wrenctl remove NAME`.
The Wren menu's Install apps and Remove apps (`bash install-extras.sh`,
`bash install-extras.sh --remove`) do the same from a list.
`wrenctl manual NAME` prints the steps to do it all by hand instead,
and changes nothing. Each one has a page in [extras/](extras/README.md): its
commands, what it is, what it doesn't protect against, and those manual steps.
Removing an app never deletes its data: wallets, chats and keyrings stay.

| Script | What you get |
|---|---|
| `pipewire-audio.sh` | Sound. `timer` and the alarm clock ring with `pw-play` (part of PipeWire) and Wren Linux's own bell sound (an alarm repeats it for up to 5 minutes; click or dismiss the notification, or `timer stop`, to end it); without sound set up they only show a notification, and say so. The microphone is muted at every login and stays off until you switch it on (Wren menu > Microphone, or `wrenctl --mic on`); that is software muting, so a program running as you could unmute it, and a hardware switch is stronger. `volume up\|down\|mute\|micmute [STEP]` (5% steps, never above 100%, unmutes on a change, refreshes the bar); the volume and mute keys use it, and Super+F10 / F11 / F12 (mute / down / up) do for keyboards without them (packages: pipewire-audio) |
| `grim-slurp.sh` | `screenshot` and its keys (packages: grim, slurp) |
| `udiskie.sh` | USB drives mount under `/media/$USER/` with `nosuid,nodev,noexec`; encrypted (LUKS) sticks ask for their passphrase (packages: udiskie, udisks2, cryptsetup, polkitd) |
| `emoji-font.sh` | Color emoji (packages: fonts-noto-color-emoji) |
| `bluetooth.sh` | Bluetooth for headphones, keyboards and mice (bluez; `bluetoothctl` pairs). The adapter starts **off** at every boot; switch it from the Wren menu or `wrenctl --bluetooth on`. With sound set up, also installs PipeWire's Bluetooth audio |
| `autologin.sh` | Log in on tty1 without your password, straight into sway (the disk passphrase, the screen lock and sudo still ask). Warns and asks first on a disk that isn't encrypted. See [extras/autologin.md](extras/autologin.md) |
| `lid-awake.sh` | Closing the lid no longer suspends the laptop (Debian's default does): it locks the screen and turns the laptop's own panel off, while the network, downloads and the timer's alarms keep going; an external screen stays on. A `systemd-logind` setting (`HandleLidSwitch=ignore`, plugged in and docked too) and sway's lid switch (`bin/lid`). It keeps running in a closed bag, getting warm: power it off before packing it |
| `one-workspace.sh` | One workspace: Super+1 … 0 and Super+Shift+1 … 0 do nothing and the bar shows no workspace buttons, so no window ends up out of sight (`make-install-iso.sh --simplesway` ticks it in the first install list) |
| `webcam.sh` | A webcam switch: a USB camera (most laptops' built-in ones) starts **off** at every boot and when plugged in, and the Wren menu gets a Webcam line (`wrenctl --camera on\|off`). Off disconnects its USB device, as if unplugged. A root helper does it; your user may run it with `on` or `off` only. See [extras/webcam.md](extras/webcam.md) |
| `phone-tethering.sh` | Use a phone's mobile data over the USB cable (usbmuxd and the iPhone pairing tools; Android needs nothing but its own "USB tethering" switch). Switch Wi-Fi off from the menu to use only the phone |
| `firefox-sandbox.sh` | `firefox`: Firefox as its own locked-down user (`firefox`), as a normal window. Your logins and history are kept in that user's home, not yours; a hacked page reaches only that, not your files. Clipboard shared while it has focus; `~/Downloads` shared both ways; sound through a pipe (it cannot hear your microphone); firewalled off your router and local services; links from other programs open in the running window. `firefox-unsafe` runs Firefox as you; `firefox-esr` (and `x-www-browser`) open the sandboxed one. See the section below |
| `pdf-viewer.sh` | zathura PDF viewer, in a sandbox |
| `gimp.sh` | GIMP image editor, in a sandbox: `~/Pictures` to open and save in, no network |
| `archive-tools.sh` | unzip, zip, 7z, bzip2 and zstd for archives |
| `w3m.sh` | w3m, a text-mode web browser for the terminal (no JavaScript) |
| `vim.sh` | Debian's full vim, with colors for each programming language, and a `~/.vimrc` (light or dark with the theme, modelines off) |
| `console-only.sh` | log in to tmux (the same bar and keys) instead of starting sway |
| `keepassxc.sh` | KeePassXC password manager, the minimal build (`keepassxc-minimal`): no browser integration and no Firefox add-on, so no web page can talk to it; copy and paste a password, or use auto-type. On a computer with the full build and the add-on, running it again switches to the minimal one |
| `signing-key.sh` | In a git copy only (see `wren-dev.sh`). Wren Linux's signing key, for the computer you publish Wren Linux from: `wren-key` makes it (the first run explains and asks), writes an encrypted backup of the whole key to your USB stick, and keeps only the signing subkey here, held by its own user `wren-signer` with no network, that your user can't read; signing asks for your sudo password. Then git signs every commit with it, `pins.sh` pins it and `wren-key sign-repo` signs the apt repository. See [extras/signing-key.md](extras/signing-key.md) and `man wren-key` |
| `wren-dev.sh` | For working on Wren Linux itself, on the computer where you build its package: lintian (Debian's package checker, which `tools/build-deb.sh` runs) and shellcheck (which `test.sh` runs), and a git copy in `~/wren-linux`, which has what the package leaves out (tests, build tools, the signing key). Not in the base: lintian brings over a hundred packages that other computers never use |
| `git.sh` | git; then `wrenctl git` sets your commit name and email and how you log in to push |
| `claude-regular.sh` | **Retired** (`update.sh` offers its removal). Claude Code as you, the easy way (`--account NAME` adds a second login in `~/.claude-NAME`, not walled off: both run as you): in any folder, from Anthropic's signed apt repo (shared with `claude-code.sh`; removing one keeps the other's updates). Claude Code's own sandbox is on (bubblewrap: its commands write only in your project and can't read your keys, passwords or wallets), and its file tools are kept from those and from what runs at login. Command: `claude-regular` (and `claude`, unless `claude-code.sh` is set up). See [extras/claude-regular.md](extras/claude-regular.md) |
| `claude-code.sh` | Claude Code, from Anthropic's signed apt repo. `claude` runs it as its own user (`claude-agent`), working in `~/projects` and unable to read the rest of your home (the lighter sandbox: it shares your kernel, so prefer `claude-vm.sh` if your computer has KVM); `claude-unsandboxed` runs it as you. `--account NAME` adds another account (its own login and memories) as its own user, `claude-agent-NAME`, in `~/projects-NAME`, walled off from the first: `claude --account NAME`. Your own `git` gets a guard inside `~/projects` (and each `~/projects-NAME`) that refuses repositories with hooks or settings that could run a program |
| `claude-vm.sh` | The `claude-vm` command runs Claude Code inside a disposable Debian VM (QEMU/KVM, built with `mockvps-kvm`), so a kernel bug that would escape a user-level sandbox only reaches a VM you can delete (the stronger of the two Claude Code sandboxes: [which one?](#which-claude-code-sandbox-claude-vmsh-or-claude-codesh)). No shared folder — the agent hands work back only by pushing to a git host you pull from (it installs `claude-pull` for that). The VM reaches the internet but nothing on your machine or network (a firewall on its `claude-vm` user). Needs KVM. Type `claude-vm` in a terminal or in wmenu (Super+d), which opens it in its own foot window. It boots the VM if it is off (about a minute, with progress shown; and it powers itself off when you exit, unless another window is still connected; `claude-vm stop` does it by hand). Running it again (as `update.sh` offers to) keeps a VM that is already built, with whatever is unpushed in it; `claude-vm rebuild` makes a fresh one. `--account NAME` adds another account (its own Claude login and memories) in a VM of its own, run by its own user `claude-vm-NAME`, with its own console port that only it may reach: `claude-vm --account NAME`. Self-contained, and can run alongside `claude-code.sh`. See `THREAT-MODEL.md` |
| `opencode-vm.sh` | **Retired** (`update.sh` offers its removal). opencode, the open-source coding agent (free models too, for those who can't pay for Claude), in a disposable VM built like claude-vm's: no shared folder, the guest off your network, its work handed back only by git push. opencode has no signatures: the VM takes only an immutable GitHub release with GitHub's own SHA-256. Ends with the git steps for reviewing and merging its work. See [extras/opencode-vm.md](extras/opencode-vm.md) |
| `tor-browser.sh` | Tor Browser (Safest, JavaScript off, a bridge before its first connection if you need one: obfs4, webtunnel, Snowflake or meek). See below |
| `whonix.sh` | Whonix Gateway + Workstation VMs on KVM. See below |
| `onionshare.sh` | Share files, receive files, host a site or a chat over Tor, with a bridge if you need one (obfs4 or Snowflake). Prints `onionshare-cli` examples |
| `onion-site.sh` | Your own onion site, able to run more than static files: nginx in front and your own app server, or a Python (Flask) app run by gunicorn. It runs in a VM with **no network at all**, so nothing the site does can give away your address; only Tor on this computer reaches it. Public, or private with client keys. Needs KVM. See below |
| `get-iso.sh` | `get-iso`: downloads Debian, Tails, Kicksecure, Qubes, Kali, Parrot or Arch (through Tor when Tor runs here), keeps it only if it is the newest release and its project's pinned key vouches for it, and offers to write it to a USB stick you pick and type the name of. See [extras/get-iso.md](extras/get-iso.md) |
| `tails-usb.sh` | `tails-usb`: downloads the newest Tails (through Tor when Tor runs here), uses it only if it is signed by the pinned Tails key and is the current release, writes it to a USB stick you pick and type the name of, and reads it back to check. See [extras/tails-usb.md](extras/tails-usb.md) |
| `remote-access.sh` | ssh into this computer from another one over a Tor onion service, with no firewall port opened. sshd listens on 127.0.0.1 only (keys only, your user only) and the onion service needs a client key. Shows the address and the exact setup lines for the other computer. See below |
| `mullvad-vpn.sh` | Mullvad VPN (app and `mullvad` command), from Mullvad's signed apt repo. Prints `mullvad` examples |
| `mullvad-browser-regular.sh` | Mullvad Browser as you: Tor Browser's anti-tracking without Tor, for use with a VPN (no sandbox from Wren Linux) |
| `sparrow-wallet.sh` | Sparrow Bitcoin wallet, the signed official .deb. Command: `sparrow` |
| `electrum.sh` | Electrum Bitcoin wallet, from Debian |
| `feather-wallet.sh` | Feather Monero wallet, the signed official AppImage. Command: `feather` |
| `hardware-wallet.sh` | Hardware wallets over USB (Trezor, Ledger, Coldcard, BitBox02, KeepKey) for Sparrow, Electrum and Feather: a udev rule gives them to the person at the keyboard only, and no maker's app is installed. Says how to sign air-gapped instead. See [extras/hardware-wallet.md](extras/hardware-wallet.md) |
| `wallet-sandbox.sh` | **Retired** (`update.sh` offers its removal). Feather, Sparrow and Electrum each as its own user, on Tor only, for a computer that can't run VMs (Whonix is safer). Command: `wallet` |
| `signal.sh` | Signal Desktop, from Signal's signed apt repo (updated by unattended-upgrades), linked to your phone's Signal; its sandbox helper isn't setuid root. Command: `signal-desktop`. See [extras/signal.md](extras/signal.md) |
| `simplex-chat.sh` | SimpleX Chat desktop, the signed official AppImage. Command: `simplex` |
| `seahorse.sh` | Seahorse and the GNOME keyring, unlocked by your login password (edits `/etc/pam.d/login`; `--remove` takes the lines out) |
| `startup-watch.sh` | Notices changes to what starts at your login (shell startup files, sway's config, autostart, systemd user units, `~/.local/bin`, ...): their fingerprints are root's, compared at boot and every 15 minutes; a change shows as "startup changed" in the bar until `sudo wren-watch accept`. `wrenctl` takes its own runs' changes. See [extras/startup-watch.md](extras/startup-watch.md) |
| `security-key.sh` | A FIDO2 hardware security key (YubiKey, Nitrokey...): SSH keys that need it (`ed25519-sk`), website logins in the sandboxed Firefox if you say so, and sudo with your password and a touch (`--sudo`), tried first and undone by itself unless it works. See [extras/security-key.md](extras/security-key.md) |
| `vault.sh` | `~/Vault`, an encrypted folder (gocryptfs) with its own password: `vault open` opens it for an hour (`--for 2h`, `--no-timeout`), and it closes itself when its time is up or the screen locks (idle, before sleep, Super+Escape, the lid). Closed, its key isn't in memory, so a laptop taken while on and locked doesn't give its files away. See [extras/vault.md](extras/vault.md) |
| `backup.sh` | Encrypted backups of your home folder with restic, and a `backup` command. Prints examples |
| `metadata-cleaner.sh` | Metadata Cleaner, the graphical program Tails ships, and the `mat2` command: removes hidden metadata from photos, PDFs and documents before you share them. Prints examples |
| `media.sh` | imv (images) and mpv (video, music), each started in a bubblewrap sandbox that sees only the files you open. Prints examples and keys |
| `yt-dlp.sh` | yt-dlp, the video downloader, as its own locked-down user (`ytdlp`): `yt-dlp URL` works as usual and the files land in `~/Downloads`, copied out as you. The official release, checked against yt-dlp's pinned signing key and installed as root's file (it can't change itself); YouTube's JavaScript runs in Debian's QuickJS, as `ytdlp`; config files ignored; a firewall rule keeps it off your local network. Run it again to update yt-dlp. See [extras/yt-dlp.md](extras/yt-dlp.md) |
| `mockvps-kvm.sh` | `mockvps-kvm`: a disposable Debian "VPS" in a local QEMU/KVM VM for trying out server setups, with snapshots and one-command removal. See `vendor/mockvps-kvm/README.md`. Run `wrenctl install mockvps-kvm` once, then use the `mockvps-kvm` command; the script in `vendor/` is the program itself and refuses to run directly until that setup is done (`MOCKVPS_FORCE=1` overrides) |
| `distro-vm.sh` | **Retired** (`update.sh` offers its removal). Kali, Tails and Arch, each in a throwaway QEMU/KVM VM run by its own locked user (`dvm-NAME`), behind a firewall that gives it the internet but not your computer or local network, or for Kali and Arch, if you say so before install, Tor only (with the bridge questions). The VM won't start without that firewall, and is ended if it goes. Images come from each project's release list and are kept only if signed by its pinned key. The screen opens in a window (`remote-viewer`); no clipboard, files or USB cross. Command: `distro-vm NAME`. Tails on a USB stick (`tails-usb.sh`) and Whonix stay the safer choices for real use. See [extras/distro-vm.md](extras/distro-vm.md) |
| `mousepad.sh` | Mousepad, a simple graphical text editor (made the default for text files). It also sets its look: white text on black in the terminal's colours with dark menus, DejaVu Sans Mono 14, tabs of 4 spaces, line numbers, matching braces highlighted and a line at column 80 (`data/mousepad.settings`, `data/mousepad-dark.xml`); later runs leave your changes alone unless Wren Linux's settings changed |
| `file-manager.sh` | Thunar, a light graphical file manager, with Trash and thumbnails (made the default for folders). Prints its keys |

Programs from Mullvad's, Anthropic's and Signal's apt repositories are updated by
unattended-upgrades along with Debian's; the apps downloaded straight from
their makers (the Feather and SimpleX AppImages, Sparrow's .deb) are updated
by running their script again, and `bash test.sh` tells you when a newer
release is out.

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
and a bridge if you say you need one (it asks first, then offers obfs4,
webtunnel, Snowflake or meek: see [Bridges](install-base.md#bridges)), so its
very first connection goes through it. These are reapplied at every start;
run the script again to change them. It also fixes Tor's AppArmor
profile so webtunnel bridges can look up their host names. If
`prep/fetch-tor-browser.sh` saved a copy, that's installed instead of
downloading one, so torproject.org is never contacted.

**Whonix.** Tor runs in the Gateway VM and your apps in the Workstation
VM, whose only network is the Gateway, so even a hacked browser can't
learn your real IP address. Everything runs as your user
(`qemu:///session`). The download (about 1.9 GB) is kept in `offline/whonix/`;
`--fetch` only downloads it. Before the first boot the script writes into
the disk images (with `qemu-img` and `debugfs`; nothing is mounted): your
bridge for the Gateway if you say you need one (obfs4 lines you paste, or
Snowflake; the Gateway has no webtunnel client; Whonix 18 connects at first
boot, and if you need a bridge but have none yet, Tor is kept off until you
turn it on), and Safest with JavaScript off for the Workstation's Tor
Browser. Then `whonix` starts both and opens each on an empty workspace
(the Gateway on yours if it is empty, else the next empty one; the Workstation
on the one after, where you are left), `whonix gateway` opens the
Gateway's Tor settings, `whonix stop` shuts both down (switching off a VM that
only opens its shutdown dialog, after 20 seconds: save your work inside first).

**OnionShare.** Debian's package pulls in the system tor service, which
would connect to Tor directly the moment it's installed, so the script
masks it first (unless apt over Tor or remote access already uses it, with
its bridge); OnionShare starts its own private tor, with your bridges.

**Backups.** `backup.sh` asks where backups go (a folder on a USB drive
is best) and creates an encrypted restic repository there. The password
is asked for every time and stored nowhere: keep it somewhere safe
outside the laptop. For backups that run without you, give `backup.sh` a
command that prints the password (it is stored in
`~/.config/wren/backup.conf`, the password never is). Then `backup` backs up your home folder (caches,
trash, VM disks and big downloads are left out; see
`~/.config/wren/backup-excludes`), and `backup snapshots`,
`backup restore latest --target ~/restored` and the like work on it.

**Not included: a BitTorrent client.** BitTorrent always shares: every
client uploads to the other peers while it downloads, and announces your IP
address to everyone sharing the same files. What's legally offered as a
torrent (Linux images, archive.org, Blender's films) is almost always a plain
download too, which only that site sees.

## Which Claude Code sandbox? (`claude-vm.sh` or `claude-code.sh`)

Both run Claude Code away from your files and your local network. They
differ in how strong the wall is:

| | `claude-vm.sh` (`claude-vm`) | `claude-code.sh` (`claude`) |
|---|---|---|
| Runs as | its own throwaway Debian VM (QEMU/KVM) | its own user, `claude-agent`, on your computer |
| Kernel | its own (the guest's) | yours: a kernel bug that escapes the user could reach your computer |
| Your files | no shared folder; work comes back only by `git push` to a host you pull from (`claude-pull`) | `~/projects` is shared both ways; the rest of your home is not readable |
| Your network | firewalled off: internet only | firewalled off: internet only |
| Needs | KVM (see below), disk and memory for the guest, a first-time build | nothing special; light and quick to start |

**Use `claude-vm.sh` if your computer can.** Use `claude-code.sh` if it
can't, or if you want the lightest setup and accept that it shares your
kernel. Installing both is fine; they don't interfere.

Does this computer have KVM? Both of these should succeed:

```bash
grep -cE 'vmx|svm' /proc/cpuinfo     # a number above 0: the CPU can do it
ls -l /dev/kvm                       # the file exists: the kernel can too
```

No `/dev/kvm` usually means one of: virtualization (Intel VT-x or AMD-V) is
switched off in the BIOS/firmware, the CPU is too old, or Wren Linux itself is
running inside a VM that doesn't pass virtualization through. The first is
fixable in the BIOS; the others mean `claude-code.sh` is your option.

What neither one protects: the internet (the agent can still send anything
it can read to anywhere), and what you pull from it. Read what it leaves
before you run it. See `THREAT-MODEL.md`.

## The sandboxed Firefox (`extras/firefox-sandbox.sh`)

`firefox` opens Firefox as a different Linux user, so a browser exploit lands in a
user with no password, no login and none of your files. It looks like any other
window. What is shared with you, and what is not:

| | |
|---|---|
| Your files, ssh keys, passwords | **not** reachable (only `~/Downloads`) |
| Logins, history, bookmarks | kept, in `/var/lib/wren-firefox` (that user's home) |
| Clipboard | shared while its window has focus |
| `~/Downloads` | shared both ways; treat what lands there as untrusted |
| Screen and keyboard | **no** screen reading, typing for you or session locking: it gets a restricted Wayland socket (`wayland-restrict`) |
| Microphone and your audio server | **no**: sound goes through one pipe into a player of yours |
| Your local network and this computer's services | **blocked** by a firewall rule; `sudo systemctl stop wren-firefox-firewall` lifts it for a while |
| Other programs' links | open in the running Firefox (a private message bus carries them) |
| KeePassXC | no browser add-on (Wren Linux's KeePassXC has none); copy and paste a password |

It also becomes your **default browser**: links from other programs (a terminal, a file
manager) open in it, because the desktop entry `wren-firefox.desktop` is set as the
handler for web links in `~/.config/mimeapps.list` (undone by `--remove`).

`firefox-unsafe` runs the same Firefox as you, with everything you can reach, if the
sandbox is ever in the way: Debian's `firefox-esr` is moved there (with `dpkg-divert`,
so its updates land there too), and `firefox-esr` by name, `/usr/bin/firefox` and
`x-www-browser` open the sandboxed Firefox, so nothing starts the unsandboxed one by
accident. `--remove` puts `firefox-esr` back.
Profiles made with `firefox-profiles/new-profile.sh` each get a user of their own like
this one (`fx-NAME`), so a hacked page in one reaches neither your files nor the other
profiles; they share the one firewall rule through the group `wren-fx`.

## Your onion site (`extras/onion-site.sh`)

A website at a `.onion` address, served from this computer, for sites that
need more than static files. The most common way an onion site gives away
where it runs is its own software reaching out to the internet (an image, a
font, an update check, an email, a DNS lookup), so here the site runs in a VM
that **can't reach any network at all**:

```
Tor Browser → Tor network → Tor on this computer → 127.0.0.1:18080 → the VM: nginx → your app
```

- **The VM** is built with the bundled `mockvps-kvm` and run by a locked user,
  `onion-site`, like `claude-vm`. After its first setup QEMU runs it with
  `restrict=on`: the guest can't send a single packet out. Two ports on this
  computer's loopback lead in: its SSH console (2243) and its nginx (18080).
  A firewall rule on the `onion-site` user keeps even the QEMU process off
  your network.
- **Inside**, nginx serves `/srv/site/static` and passes everything else to
  the app on `127.0.0.1:8000`. It shows no version and keeps no access log;
  the time zone is UTC. You pick the app when you set it up:
  - **any**: you run your own app server on `127.0.0.1:8000` (`onion-site shell`);
  - **python**: gunicorn runs a Flask app (`app.py` with `app = Flask(...)`)
    as a locked-down service; a small one is there to start from. Anything the
    app keeps goes in `/srv/site/data`.
- **Public or private**, also chosen at setup. Private: only visitors you give
  a client key can find the site; Tor Browser asks for the key the first time.
- **Tor** is the system tor service on this computer (shared with apt over Tor
  and remote access, with your bridge if you need one), with Tor's defences
  against floods of visits. Its config is checked before Tor restarts.
- **No shared folder.** `onion-site upload static FOLDER` and
  `onion-site upload app FOLDER` send a folder in; it replaces what was there.
- **Updates.** `onion-site update` restarts the VM with one more way out, a
  relay to this computer's Tor for apt only, upgrades it, and restarts it
  without that.

The app can't fetch anything from the internet, ever: no packages from pip or
npm at run time, no outside images or fonts, no email. What it needs goes in
with `upload`, or comes from Debian during `onion-site update`.

What it can't hide: the site is only up while this computer is on and the VM
runs (it starts at every boot; `onion-site stop` and `start` by hand), and that
timing can link it to you; a dedicated
machine is the right host for anything serious. A hole in your app gets the
VM and the site's data, not this computer. Back up `/var/lib/tor/wren-onion-site`
(as root) to keep the address; `--remove` asks before deleting it.

## Remote access (`extras/remote-access.sh`)

For logging in to this computer from another one without opening a port:
the firewall stays closed, and nothing on the local network can reach ssh.

- **What it sets up.** `openssh-server` listening on `127.0.0.1` only (key
  login only, root login off, only your user), and a Tor onion service
  that passes port 22 through to it. Tor connects outward, so `ufw` is
  unchanged. It asks first whether you need a bridge, like apt over Tor.
- **Who can connect.** Only a computer that has the client key. The onion
  service uses Tor's client authorization, so without the key it can't even
  be found. The key is made here and shown once; only its public half is
  kept on this computer. Your own ssh key still has to be accepted
  (`~/.ssh/authorized_keys`; it asks you to paste one if there is none).
- **On the computer you connect from**, install `tor` and `netcat-openbsd`,
  put the key line in Tor's `ClientOnionAuthDir`, and add a `Host` block
  with `ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p` to `~/.ssh/config`. The
  script prints all of it, ready to paste.
- **Run it again** to see the address or to authorize another computer (a new
  client key). The address stays the same as long as
  `/var/lib/tor/wren-ssh` does; back that folder up (as root).
- **If you're logged in over ssh when you run it**, it warns you: ssh
  moves to `127.0.0.1`, so that way in closes. Use Tor, or the machine's
  own screen.
- `--remove` stops it, deletes the onion address for good (it asks first)
  and purges what it installed. The ssh server stays if you had it before.

Turn it on only if you need it: it is a service that other computers can
try to reach, even if only the holder of your keys can get in.

## extras/firefox-profiles/

`bash extras/firefox-profiles/new-profile.sh` gives a website you stay logged
into (a bank, email, shopping, a work account) its own Firefox profile
and a command named after it (`bank`, or `firefox-bank` when a program has
that name). See `extras/firefox-profiles/README.md` for why
that's useful.

## Firefox (`extras/firefox-sandbox.sh`)

Installs Firefox ESR with the video codecs and uBlock Origin, runs the
hardening below, runs it as its own locked-down user (`firefox`), and sets up
`incognito` too. `firefox-unsafe` runs the same Firefox as you, for the odd
page the sandbox's firewall blocks (your router's, say).
`wrenctl remove firefox-sandbox` takes all of it out again (it asks
about incognito; your profiles stay).

### Firefox hardening

`extras/firefox-sandbox.sh` runs `parts/firefox-hardening.sh`, which sets these for every Firefox profile:

- **uBlock Origin, in the mode you choose at install**: standard blocks
  ads, trackers and known malware sites with its filter lists, and sites
  work. "Medium mode", the default, also blocks scripts and frames from
  other sites everywhere. That's where most malicious ads and drive-by
  attacks come from, and most trackers. Some sites break then: allow one
  with `ublock-allow example.com` (then restart Firefox).
  `ublock-allow --mode standard|medium` switches later.
  `ublock-allow --list` and `ublock-allow --remove example.com` manage
  the list. Changes made by clicking in uBlock's popup work too, but
  only until Firefox restarts, because uBlock re-reads Wren Linux's rules at
  every start.
- **The JavaScript JIT is off.** Most serious Firefox exploits target the
  JIT, the part that turns JavaScript into fast machine code. JavaScript
  still works, just slower; heavy web apps can feel sluggish. Turn it back
  on for one site by giving it its own profile with fast JavaScript
  (`extras/firefox-profiles/new-profile.sh`).
- **Cookies and site data deleted when it closes** (the sandboxed
  Firefox's default; its install asks): websites, and the trackers behind
  them, can't recognise you from one visit to the next. Sites you allow
  under Settings > Privacy & Security > Cookies and Site Data > Manage
  Exceptions keep theirs, so you stay logged in to those. History,
  bookmarks and saved passwords stay: no website can read them.
- **Saved passwords fill in on a click**, not as the page loads: tracking
  scripts have added hidden login boxes to read what Firefox filled in.
- **No "save this password?"**: Firefox never offers to save a password, nor
  makes one up or offers Relay addresses. KeePassXC (`wrenctl install
  keepassxc`) keeps them, encrypted with your own passphrase and apart from
  the browser that pages run in. Logins saved before stay in Firefox's list
  (Settings, Passwords), so you can move them over.
- **A "Learn (Wren Linux)" bookmarks folder**, read-only and apart from your
  own bookmarks: Linux and the command line, Bash, sed and awk, security and
  privacy, programming and full-stack web (`data/firefox-bookmarks.json`).
- **HTTPS-Only Mode**: Firefox won't load an unencrypted page without
  asking first, so nobody on café or hotel Wi-Fi can tamper with it.
- **Its DNS, encrypted either way** (set at each start, never a provider
  Firefox picks itself): with secure DNS on, its own DNS-over-HTTPS is
  off and it looks names up the way the rest of the system does, encrypted;
  with it off, Firefox encrypts its own lookups to Quad9 (DNS over HTTPS),
  strict by default (never plain DNS) or with fallback to the network's, as
  chosen at the sandboxed Firefox's install. Every Firefox Wren Linux runs gets
  this, `incognito` and the sandboxed `firefox` included, except the Wi-Fi
  sign-in window (`wifi-signin`), which uses the network's DNS so a sign-in
  page can load, and is thrown away when it closes.
- **A notice when Firefox needs a restart**: after an update, the running
  browser keeps the old, unfixed version until you restart it. A check
  every 10 minutes shows a notification when that's the case.

How: default prefs in `/etc/firefox-esr/wren-hardening.js` (any
profile can change them at `about:config`), a uBlock and DNS policy in
`/usr/share/firefox-esr/distribution/policies.json` (only written if no other
policies file exists), and a systemd user timer.
`bash parts/firefox-hardening.sh --remove` undoes all of it.

### incognito

`incognito` opens Firefox as a different, locked-down user, for sites you
don't trust or don't want tied to the rest of your browsing. `incognito
https://example.org/` opens a page. `wifi-signin` (the Wren menu's
"Wi-Fi sign-in") opens it as the Wi-Fi sign-in window: the network's own DNS
and plain http allowed, for a café's or hotel's sign-in page, with secure
DNS off only while it is open. What `parts/incognito.sh` sets up:

- **A user with nothing**: no password, no login, no home folder on disk,
  no group but its own and `render` (so no sound card, no USB; `render` lets
  cage open the graphics card's render node, which it needs to start, but
  not take over the screen), and a limit on how many processes it may start. It can't read your files.
- **Its own window system**: Firefox runs inside `cage`, a tiny Wayland
  compositor that appears as one window in sway. The clipboard belongs to
  the window system, so what you copy in your programs can't be pasted
  there, and the other way round. There is no shared folder: a download
  stays in memory and is gone when the window closes.
- **Nothing kept**: the profile, cache, cookies and history live in memory
  (`/dev/shm`) and the folder is deleted when you close the window; the
  profile is always in private browsing, with tracking protection and
  fingerprinting resistance on and WebRTC off (`data/incognito-user.js`; some
  sites break with fingerprinting resistance, turn it off there). Wren Linux's defaults for every profile
  still apply: HTTPS-Only Mode, no JavaScript JIT, uBlock Origin.
- **Sound and video**: YouTube and the like play, with sound. `incognito`
  has no sound card, so it runs its own small audio server (PipeWire) whose
  only output is a pipe; a player running as you (`pw-cat`, shown in your
  volume control as a normal stream) reads that pipe and plays it through
  your speakers. The pipe carries sound in one direction only, so the
  window can't hear your microphone or your other programs, and your audio
  server is never reachable from it. Rendering is in software, so
  the CPU decodes the video: 720p is comfortable, 1080p may stutter, and
  sound can drift a fraction of a second behind the picture. Protected
  (DRM) video doesn't play. `incognito --no-audio` leaves the pipe out.
  If uBlock's medium mode (if you chose it) breaks a player, `ublock-allow site.com` applies
  here too.
- **Off your network**: a firewall rule that matches only the `incognito`
  user (`data/incognito-firewall.nft`, loaded at every boot) turns away its
  connections to your router, printers, other computers on the local network
  and to programs listening on this machine (including Tor Browser's
  proxy). DNS and the internet stay open, over IPv4 only: on a network with
  global IPv6 addresses a fixed rule can't tell the router from the internet, so
  the sandbox users get no IPv6 (on an IPv6-only network they get no internet). Wi-Fi sign-in pages are often on
  the local network, so the Wi-Fi sign-in window runs as a second such user,
  `wifi-signin`, whose own rule (`data/wifi-signin-firewall.nft`) lets it reach
  the local network but not this computer. That user runs only the sign-in
  window, and the two can be open at the same time.
- **A narrow door**: your user may run one thing as `incognito` (and as
  `wifi-signin`), the wrapper `/usr/local/libexec/incognito-session`, through a rule in
  `/etc/sudoers.d/wren-incognito` that was checked with `visudo`. The
  `incognito` command gives that user a restricted Wayland socket only
  while the window is open, and takes it away afterwards. It is made with
  sway's security-context protocol (`bin/wayland-restrict`): the window
  works, but sway doesn't offer that user the protocols that read your
  screen, type for you or lock the session, as your real socket would.
  `media-sandbox` (imv and mpv) uses the same kind of socket.
- **No way into X11**: XWayland (installed for Tor Browser, Feather and
  other X11-only apps) listens on an "abstract" socket that every user on
  the computer can connect to, and anyone connected to X11 can read its
  windows and type into them. `incognito`, `claude`, `claude-vm`, the sandboxed
  Firefox, the onion site, `yt-dlp` and a media viewer given a web address start
  through `/usr/local/libexec/wren-no-abstract-sockets`, which uses the
  kernel's Landlock (Linux 6.12 or newer, Debian 13's own) to stop them
  connecting to abstract sockets made outside them. Files, the network and
  their own sockets are unaffected. On an older kernel they refuse to start
  (`WREN_ALLOW_ABSTRACT_SOCKETS=1` runs one without it).

What it doesn't do: it uses your network and your IP address (use Tor
Browser or a VPN for that), and it uses the same kernel, so a kernel bug
could get out of it. Pages are drawn by software, so heavy sites are
slower. The keyboard layout inside it is the US one. Remove it with `bash parts/incognito.sh --remove`, which also
deletes the user.
