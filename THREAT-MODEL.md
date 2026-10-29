# What debsway protects against, and what it doesn't

debsway is a minimal Debian desktop with careful defaults. It makes the
common attacks harder; it doesn't make you invisible or untouchable. Use
this page to decide what else you need.

## What it protects against

- **Known bugs being used against you.** Debian's security fixes install
  themselves every day (`parts/unattended-upgrades.sh`), and you're told
  when Firefox needs a restart to use its fixed version. Packages from
  Mullvad's and Anthropic's apt repositories are updated the same way. The
  AppImages (Feather, SimpleX) are not: run their script again, or let
  `test.sh` tell you when a newer release is out.
- **Attacks through websites.** In every Firefox profile (the Firefox
  extra, `extras/firefox.sh`), uBlock Origin
  blocks scripts and frames from other sites, where most malicious ads
  and drive-by attacks come from; the JavaScript JIT, the part of
  Firefox most exploits target, is off; and HTTPS-Only Mode refuses
  unencrypted pages unless you agree (`parts/firefox-hardening.sh`).
- **Some kernel attacks.** Kernel addresses are hidden, memory is cleared
  when it is allocated and freed, rare protocols and filesystems and
  FireWire can't be loaded (`parts/sysctl-hardening.sh`,
  `parts/boot-hardening.sh`, `parts/module-blacklist.sh`). These make
  exploits harder; they don't make the kernel bug-free.
- **People on the same network.** Nothing on the laptop accepts incoming
  connections (`parts/ufw.sh`). HTTPS-Only Mode stops tampering on café
  and hotel Wi-Fi.
- **Being recognised from network to network.** Wi-Fi uses a new,
  made-up hardware (MAC) address every time it connects, doesn't send this
  computer's name to the network, and uses temporary IPv6 addresses
  (`parts/random-mac.sh`).
- **Your network seeing which packages you install**, if you chose to
  download through Tor (`parts/apt-tor.sh`, with a bridge if you need one).
- **Tampered downloads.** Everything debsway downloads from outside
  Debian is checked against the project's signing key, pinned by
  fingerprint in `pins.sh`, before it's used. `test.sh` re-checks them.
  The Wi-Fi packages carried on a USB stick (`offline/debs`) are matched,
  one by one, to Debian's signed package lists before `wifi.sh` installs
  them as root.
- **Sites tracking you across each other**, if you give the sites you
  log into their own Firefox profile (`extras/firefox-profiles/`).
- **A risky website reaching the rest of your session.** `incognito`
  (`parts/incognito.sh`) opens Firefox as a separate user with no
  password and no files of yours, in its own window system so the
  clipboard isn't shared, with everything kept in memory and deleted when
  you close it. Video and sound work; the sound leaves through a one-way
  pipe, so it can't hear your microphone or your other programs. A hacked
  browser there gets a user that owns nothing.
- **A browser exploit reaching your files.** `firefox` (`extras/firefox-sandbox.sh`)
  runs Firefox as its own user with no password, login or access to your
  files; only `~/Downloads` and the clipboard (while its window has focus) are
  shared, it gets no screen-reading or typing protocols from sway, no audio
  server or microphone, and a firewall rule keeps it off your local network.
  `incognito` is the same idea with nothing kept and no shared clipboard. They
  share your kernel: a kernel bug could still get out, and an exploit that
  stays in the browser still has that profile's logins. `firefox-esr` runs as
  you and has none of this.
- **A booby-trapped image or video, or a coding assistant that goes wrong,
  reaching your files.** `imv` and `mpv` (`extras/media.sh`) start inside
  bubblewrap: they see only the files you open, read-only, and have no
  network unless you give mpv a URL. `claude` (`extras/claude-code.sh`)
  runs Claude Code as its own user, `claude-agent`, which has no password
  and can't read your home folder, ssh keys, passwords or browser
  profiles; it works in `~/projects`, which you share with it. A firewall
  rule on that user keeps it off your router, printers and the programs
  listening on this machine; it reaches the internet only. For a stronger
  boundary, `claude-vm` (`extras/claude-vm.sh`) runs the agent inside a
  disposable Debian VM (QEMU/KVM) with no shared folder: a kernel bug that
  would let `claude-agent` escape its user boundary reaches only a VM you can
  throw away, and the agent hands work back only by pushing to a git host you
  pull from. The same kind of firewall, on its `claude-vm` user, keeps the
  guest off your network. The two can be installed together. Use the VM if
  your computer has KVM (`docs/extras.md` says how to check); `claude` is
  the weaker, lighter choice for computers that can't run it.
- **A stranger's USB stick running something.** Drives mount with
  `nosuid`, `nodev` and `noexec` (`extras/udiskie.sh`), so nothing on a stick
  can run from it by itself. They still mount the moment they're plugged
  in, so the kernel's filesystem code reads whatever a stick contains:
  don't plug in sticks you don't trust.
- **A stolen laptop, while it's switched off**, if you installed Debian
  with disk encryption (see the README). `status.sh` warns when you
  didn't.

With the extras:

- **Your network or ISP seeing that you use Tor**, if you say you need a
  bridge: Tor Browser, OnionShare, Whonix and apt over Tor ask first, then
  offer obfs4, webtunnel, Snowflake or meek, whichever that program can use
  (docs/install-base.md, "Bridges"). The bridge is set up before the first
  connection.
- **A hacked browser revealing your real IP address**: Whonix
  (`extras/whonix.sh`) runs the browser in a virtual machine whose only
  way out is Tor.
- **Losing everything to a dead or stolen disk**: encrypted backups
  (`extras/backup.sh`).
- **Hidden data in files you share**: Metadata Cleaner and mat2 (`extras/metadata-cleaner.sh`).

## What it doesn't protect against

- **Anything running as you.** If you run a malicious program, or an
  attack escapes the browser, it can read all your files, every Firefox
  profile's logins and your wallets. debsway doesn't sandbox your own
  user. Only install software you trust.
- **A laptop that's on, asleep or locked.** The disk key is in memory
  then. Shut down before leaving it somewhere or crossing a border.
- **Physical tampering.** Someone with the laptop alone for a while
  could install a hardware keylogger or tamper with the boot process.
  debsway doesn't set up Secure Boot measurement or tamper evidence.
- **A program listening through the microphone.** With the sound extra, the
  microphone is muted at every login and stays off until you switch it on
  (`debsway --mic on`, or the debsway menu). Wi-Fi and Bluetooth have the same
  switches, on the radio itself (rfkill), and the Bluetooth extra starts its
  adapter off. The microphone mute is software: a program running as you can
  unmute it, so against that a hardware switch or unplugging is the stronger
  kind. `incognito` and the sandboxed `firefox` never get your audio server.
- **Being identified while logged in.** A VPN, Tor or Mullvad Browser
  hides your IP address, not who you are to a site you've logged into.
- **What you share with the sandboxes.** `claude-agent` and you both
  read and write `~/projects`, and it has your network. Anything it leaves
  there is untrusted: read scripts before you run them, and look at
  `.git/config` and `.git/hooks` before you tell your own git to trust a
  repository it made. debsway puts a guard in front of your git inside
  `~/projects` (`bin/git`): it refuses to run when a repository's
  `.git/config` or `.git/hooks` could run a program as you. A file could
  change between that check and the run, so it stops a confused assistant,
  not one racing your keystrokes. Don't switch git's own "dubious
  ownership" warning off with `safe.directory '*'`. mpv in its sandbox can
  use your audio server, which could also record the microphone. `claude-unsandboxed` and
  starting `/usr/bin/mpv` by full path skip the sandboxes. `claude-vm` shares
  no folder with you, so this whole row is lighter for it — the only way out
  is a git push you review before merging — but a VM is not a perfect wall:
  the remaining path is a QEMU or hypervisor escape (a smaller, more
  scrutinised surface than the shared kernel `claude-agent` runs on), and
  work you pull in is still untrusted until you have read it.
- **`incognito` hiding who you are**: it is your network and your IP
  address, it shares the kernel (a kernel bug could get out), and the
  window is visible to you and to your screenshots, as any window is.
- **Your Wi-Fi network or ISP seeing where you go**, outside Tor or a
  VPN. They see which sites you visit (not what's on the pages).
- **A listening service, if you turn on remote access**
  (`extras/remote-access.sh`). Nothing listens by default. With it on,
  sshd runs (on 127.0.0.1, keys only) behind a Tor onion service that
  needs a client key. That is far less exposed than an open port, but a
  hole in sshd or Tor, or a stolen client key, would be a way in. Turn it
  off when you don't need it.
- **Weak or reused passwords, or phishing.** Use a password manager
  (`extras/keepassxc.sh`) and two-factor login, preferably a hardware
  key.
- **A determined, well-funded attacker who targets you.** That needs
  more than a well-set-up laptop: look at Tails or Qubes OS, and at your
  habits.
- **Mistakes in debsway itself.** It's a small project. Read the scripts
  before running them; they're written to be readable.

## Trade-offs it makes

- **Some sites break** with uBlock's medium mode. Allow one with
  `ublock-allow example.com`, then restart Firefox.
- **JavaScript is slower** without the JIT. Heavy web apps can get it
  back in their own profile (`extras/firefox-profiles/new-profile.sh`, "fast
  JavaScript").
- **Wi-Fi login pages may ask again** after reconnecting, because of the
  random MAC address. Switch to one made-up address per network in
  `/etc/NetworkManager/conf.d/90-debsway-random-mac.conf` (`stable`).
- **Security fixes install themselves.** Rarely, an update changes
  something you relied on; the log is in `/var/log/unattended-upgrades/`.
