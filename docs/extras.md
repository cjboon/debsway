# extras/

Run one with `bash extras/NAME.sh`; run it again to repair it or, for
downloaded apps, update to the newest release; undo it with `--remove`.
Removing an app never deletes its data: wallets, chats and keyrings stay.

| Script | What you get |
|---|---|
| `firefox.sh` | Firefox ESR with uBlock Origin in medium mode, HTTPS-Only Mode, the JavaScript JIT off, a restart notice, and (if you want it) `incognito`, a throwaway Firefox as a locked-down user. See below |
| `pipewire-audio.sh` | Sound. `timer` and the alarm clock ring with `pw-play` (part of PipeWire) and debsway's own three-beep sound; without sound set up they only show a notification, and say so. The microphone is muted at every login and stays off until you switch it on (debsway menu > Microphone, or `debsway --mic on`); that is software muting, so a program running as you could unmute it, and a hardware switch is stronger. `volume up\|down\|mute\|micmute [STEP]` (5% steps, never above 100%, unmutes on a change, refreshes the bar); the volume and mute keys use it, and Super+F10 / F11 / F12 (mute / down / up) do for keyboards without them (packages: pipewire-audio) |
| `grim-slurp.sh` | `screenshot` and its keys (packages: grim, slurp) |
| `udiskie.sh` | USB drives mount under `/media/$USER/` with `nosuid,nodev,noexec`; encrypted (LUKS) sticks ask for their passphrase (packages: udiskie, udisks2, cryptsetup, polkitd) |
| `emoji-font.sh` | Color emoji (packages: fonts-noto-color-emoji) |
| `bluetooth.sh` | Bluetooth for headphones, keyboards and mice (bluez; `bluetoothctl` pairs). The adapter starts **off** at every boot; switch it from the debsway menu or `debsway --bluetooth on`. With sound set up, also installs PipeWire's Bluetooth audio |
| `phone-tethering.sh` | Use a phone's mobile data over the USB cable (usbmuxd and the iPhone pairing tools; Android needs nothing but its own "USB tethering" switch). Switch Wi-Fi off from the menu to use only the phone |
| `firefox-sandbox.sh` | `firefox`: Firefox as its own locked-down user (`firefox`), as a normal window. Your logins and history are kept in that user's home, not yours; a hacked page reaches only that, not your files. Clipboard shared while it has focus; `~/Downloads` shared both ways; sound through a pipe (it cannot hear your microphone); firewalled off your router and local services; links from other programs open in the running window. `firefox-esr` still runs Firefox as you. See the section below |
| `w3m.sh` | w3m, a text-mode web browser for the terminal (no JavaScript) |
| `keepassxc.sh` | KeePassXC password manager, the minimal build (`keepassxc-minimal`): no browser integration and no Firefox add-on, so no web page can talk to it; copy and paste a password, or use auto-type. On a computer with the full build and the add-on, running it again switches to the minimal one |
| `git.sh` | git, and optionally GitHub's `gh`; sets your commit name and email |
| `claude-code.sh` | Claude Code, from Anthropic's signed apt repo. `claude` runs it as its own user (`claude-agent`), working in `~/projects` and unable to read the rest of your home (the lighter sandbox: it shares your kernel, so prefer `claude-vm.sh` if your computer has KVM); `claude-unsandboxed` runs it as you. Your own `git` gets a guard inside `~/projects` that refuses repositories with hooks or settings that could run a program |
| `claude-vm.sh` | The `claude-vm` command runs Claude Code inside a disposable Debian VM (QEMU/KVM, built with `mockvps-kvm`), so a kernel bug that would escape a user-level sandbox only reaches a VM you can delete (the stronger of the two Claude Code sandboxes: [which one?](#which-claude-code-sandbox-claude-vmsh-or-claude-codesh)). No shared folder — the agent hands work back only by pushing to a git host you pull from (it installs `claude-pull` for that). The VM reaches the internet but nothing on your machine or network (a firewall on its `claude-vm` user). Needs KVM. Self-contained, and can run alongside `claude-code.sh`. See `THREAT-MODEL.md` |
| `tor-browser.sh` | Tor Browser (Safest, JavaScript off, a bridge before its first connection if you need one: obfs4, webtunnel, Snowflake or meek). See below |
| `whonix.sh` | Whonix Gateway + Workstation VMs on KVM. See below |
| `onionshare.sh` | Share files, receive files, host a site or a chat over Tor, with a bridge if you need one (obfs4 or Snowflake). Prints `onionshare-cli` examples |
| `remote-access.sh` | ssh into this computer from another one over a Tor onion service, with no firewall port opened. sshd listens on 127.0.0.1 only (keys only, your user only) and the onion service needs a client key. Shows the address and the exact setup lines for the other computer. See below |
| `mullvad-vpn.sh` | Mullvad VPN (app and `mullvad` command), from Mullvad's signed apt repo. Prints `mullvad` examples |
| `mullvad-browser.sh` | Mullvad Browser: Tor Browser's anti-tracking without Tor, for use with a VPN |
| `sparrow-wallet.sh` | Sparrow Bitcoin wallet, the signed official .deb. Command: `sparrow` |
| `electrum.sh` | Electrum Bitcoin wallet, from Debian |
| `feather-wallet.sh` | Feather Monero wallet, the signed official AppImage. Command: `feather` |
| `simplex-chat.sh` | SimpleX Chat desktop, the signed official AppImage. Command: `simplex` |
| `seahorse.sh` | Seahorse and the GNOME keyring, unlocked by your login password (edits `/etc/pam.d/login`; `--remove` takes the lines out) |
| `backup.sh` | Encrypted backups of your home folder with restic, and a `backup` command. Prints examples |
| `metadata-cleaner.sh` | Metadata Cleaner, the graphical program Tails ships, and the `mat2` command: removes hidden metadata from photos, PDFs and documents before you share them. Prints examples |
| `media.sh` | imv (images) and mpv (video, music), each started in a bubblewrap sandbox that sees only the files you open. Prints examples and keys |
| `mockvps-kvm.sh` | `mockvps-kvm`: a disposable Debian "VPS" in a local QEMU/KVM VM for trying out server setups, with snapshots and one-command removal. See `vendor/mockvps-kvm/README.md`. Run `bash extras/mockvps-kvm.sh` once, then use the `mockvps-kvm` command; the script in `vendor/` is the program itself and refuses to run directly until that setup is done (`MOCKVPS_FORCE=1` overrides) |
| `mousepad.sh` | Mousepad, a simple graphical text editor (made the default for text files). The first time it also sets its look: solarized-dark, 16 pt monospace, tabs of 4 spaces, line numbers and a margin at column 80 (`data/mousepad.settings`); later runs leave your changes alone |
| `file-manager.sh` | Thunar, a light graphical file manager, with Trash and thumbnails (made the default for folders). Prints its keys |

Programs from Mullvad's and Anthropic's apt repositories are updated by
unattended-upgrades along with Debian's; the AppImages (Feather, SimpleX)
are updated by running their script again, and `bash test.sh` tells you
when a newer release is out.

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
Browser. Then `whonix` starts both, `whonix gateway` opens the
Gateway's Tor settings, `whonix stop` shuts both down.

**OnionShare.** Debian's package pulls in the system tor service, which
would connect to Tor directly the moment it's installed, so the script
masks it first; OnionShare starts its own private tor, with your bridges.

**Backups.** `backup.sh` asks where backups go (a folder on a USB drive
is best) and creates an encrypted restic repository there. The password
is asked for every time and stored nowhere: keep it somewhere safe
outside the laptop. For backups that run without you, give `backup.sh` a
command that prints the password (it is stored in
`~/.config/debsway/backup.conf`, the password never is). Then `backup` backs up your home folder (caches,
trash, VM disks and big downloads are left out; see
`~/.config/debsway/backup-excludes`), and `backup snapshots`,
`backup restore latest --target ~/restored` and the like work on it.

**Not included: yt-dlp.** It has to run YouTube's own JavaScript, and
the one runtime that sandboxes that code (deno) isn't in Debian;
Debian's yt-dlp is also too old to keep working.

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
switched off in the BIOS/firmware, the CPU is too old, or debsway itself is
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
| Logins, history, bookmarks | kept, in `/var/lib/debsway-firefox` (that user's home) |
| Clipboard | shared while its window has focus |
| `~/Downloads` | shared both ways; treat what lands there as untrusted |
| Screen and keyboard | **no** screen reading, typing for you or session locking: it gets a restricted Wayland socket (`wayland-restrict`) |
| Microphone and your audio server | **no**: sound goes through one pipe into a player of yours |
| Your local network and this computer's services | **blocked** by a firewall rule; `sudo systemctl stop debsway-firefox-firewall` lifts it for a while |
| Other programs' links | open in the running Firefox (a private message bus carries them) |
| KeePassXC | no browser add-on (debsway's KeePassXC has none); copy and paste a password |

It also becomes your **default browser**: links from other programs (a terminal, a file
manager) open in it, because the desktop entry `debsway-firefox.desktop` is set as the
handler for web links in `~/.config/mimeapps.list` (undone by `--remove`).

`firefox-esr` runs the same Firefox as you, with everything you can reach, if the
sandbox is ever in the way; it stays installed, and starting it by name still works.
Profiles made with `firefox-profiles/new-profile.sh` each get a user of their own like
this one (`fx-NAME`), so a hacked page in one reaches neither your files nor the other
profiles; they share the one firewall rule through the group `debsway-fx`.

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
  `/var/lib/tor/debsway-ssh` does; back that folder up (as root).
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
and a `firefox-NAME` command. See `extras/firefox-profiles/README.md` for why
that's useful.

## Firefox (`extras/firefox.sh`)

Installs Firefox ESR with the video codecs and uBlock Origin, runs the
hardening below, and offers `incognito`. `bash extras/firefox.sh --remove`
takes all of it out again (your profiles stay).

### Firefox hardening

`extras/firefox.sh` runs `parts/firefox-hardening.sh`, which sets these for every Firefox profile:

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
  (`extras/firefox-profiles/new-profile.sh`).
- **HTTPS-Only Mode**: Firefox won't load an unencrypted page without
  asking first, so nobody on café or hotel Wi-Fi can tamper with it.
- **A notice when Firefox needs a restart**: after an update, the running
  browser keeps the old, unfixed version until you restart it. A check
  every 10 minutes shows a notification when that's the case.

How: default prefs in `/etc/firefox-esr/debsway-hardening.js` (any
profile can change them at `about:config`), a uBlock policy in
`/usr/share/firefox-esr/distribution/policies.json` (only written if no other
policies file exists), and a systemd user timer.
`bash parts/firefox-hardening.sh --remove` undoes all of it.

### incognito

`incognito` opens Firefox as a different, locked-down user, for sites you
don't trust or don't want tied to the rest of your browsing. `incognito
https://example.org/` opens a page. What `parts/incognito.sh` sets up:

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
  fingerprinting resistance on (`data/incognito-user.js`; some sites break
  with the latter, turn it off there). debsway's defaults for every profile
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
  If uBlock's medium mode breaks a player, `ublock-allow site.com` applies
  here too.
- **Off your network**: a firewall rule that matches only the `incognito`
  user (`data/incognito-firewall.nft`, loaded at every boot) turns away its
  connections to your router, printers, other computers on the local network
  and to programs listening on this machine (including Tor Browser's
  proxy). DNS and the internet stay open. Cafe Wi-Fi login pages are on the
  local network, so sign in with your own Firefox first.
- **A narrow door**: your user may run one thing as `incognito`, the
  wrapper `/usr/local/libexec/incognito-session`, through a rule in
  `/etc/sudoers.d/debsway-incognito` that was checked with `visudo`. The
  `incognito` command gives that user a restricted Wayland socket only
  while the window is open, and takes it away afterwards. It is made with
  sway's security-context protocol (`bin/wayland-restrict`): the window
  works, but sway doesn't offer that user the protocols that read your
  screen, type for you or lock the session, as your real socket would.
  `media-sandbox` (imv and mpv) uses the same kind of socket.
- **No way into X11**: XWayland (installed for Tor Browser, Feather and
  other X11-only apps) listens on an "abstract" socket that every user on
  the computer can connect to, and anyone connected to X11 can read its
  windows and type into them. `incognito`, `claude` and `claude-vm` start
  through `/usr/local/libexec/debsway-no-abstract-sockets`, which uses the
  kernel's Landlock (Linux 6.12 or newer, Debian 13's own) to stop them
  connecting to abstract sockets made outside them. Files, the network and
  their own sockets are unaffected. On an older kernel they refuse to start
  (`DEBSWAY_ALLOW_ABSTRACT_SOCKETS=1` runs one without it).

What it doesn't do: it uses your network and your IP address (use Tor
Browser or a VPN for that), and it uses the same kernel, so a kernel bug
could get out of it. Pages are drawn by software, so heavy sites are
slower. The keyboard layout inside it is the US one. Remove it with `bash parts/incognito.sh --remove`, which also
deletes the user.
