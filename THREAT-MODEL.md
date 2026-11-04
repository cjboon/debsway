# What Wren Linux protects against, and what it doesn't

Wren Linux is a minimal Debian desktop with careful defaults. It makes the
common attacks harder; it doesn't make you invisible or untouchable. Use
this page to decide what else you need.

## What it protects against

- **Known bugs being used against you.** Debian's security fixes install
  themselves every day (`parts/unattended-upgrades.sh`), and you're told
  when the Firefox you run as yourself (`firefox-esr`) needs a restart to use
  its fixed version (not the sandboxed `firefox`, its profiles or
  `incognito`, which run as other users: reopen those after an update). Packages from
  Mullvad's, Anthropic's, Signal's and the Tor Project's apt repositories are updated the same way. The
  apps downloaded straight from their makers (the Feather and SimpleX
  AppImages, Sparrow's .deb) are not: run their script again, or let
  `test.sh` tell you when a newer release is out.
- **Attacks through websites.** In every Firefox profile (the Firefox
  extra, `extras/firefox-sandbox.sh`), uBlock Origin
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
  computer's name to the network (avahi, which a live-image install brings
  and which announces the name on every network, is removed by
  `parts/no-live-extras.sh`), and uses temporary IPv6 addresses
  (`parts/random-mac.sh`).
- **Your network seeing which packages you install**, if you chose to
  download through Tor (`parts/apt-tor.sh`, with a bridge if you need one).
- **A tampered Wren Linux update**, once Wren Linux's signing key is pinned
  (`WREN_SIGNING_FPR` in `pins.sh`, the key in
  `data/wren-signing-key.asc`). `update.sh` runs what it brings in with
  sudo, so whoever could change what GitHub serves (a taken-over account, or
  someone on the way) could otherwise run anything as root. With the key
  pinned, `update.sh` brings a change in only if the newest commit has a good
  signature from that key, checked with the key and pin of the copy you
  already have, never ones that come with the change. Not covered: the copy
  you first got (a stick, or the download in the README) is trusted as it is;
  someone in the way can still hold updates back; and until the key is
  pinned, updates come in unchecked (`update.sh` says so each time).
  On the computer Wren Linux is published from, `extras/signing-key.sh` keeps
  the signing subkey with its own user, `wren-signer`, off every network
  and unreadable to your user, and signs only after your sudo password; the
  primary key lives only in the encrypted backup on your USB stick. Root
  there can still read the subkey, and a program running as you can have
  something signed while sudo remembers your password (a few minutes, in
  that terminal).
- **Tampered downloads.** Everything Wren Linux downloads from outside
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
  you close it. The Wi-Fi sign-in window is the same, as another such user,
  `wifi-signin`, except that it may reach your local network (sign-in pages
  are often there; this computer stays closed to it) and uses the network's
  DNS: open it for sign-in pages only. Video and sound work; the sound leaves through a one-way
  pipe, so it can't hear your microphone or your other programs. A hacked
  browser there gets a user that owns nothing.
- **A browser exploit reaching your files.** `firefox` (`extras/firefox-sandbox.sh`)
  runs Firefox as its own user with no password, login or access to your
  files; only `~/Downloads` and the clipboard (while its window has focus) are
  shared, it gets no screen-reading or typing protocols from sway, no audio
  server or microphone, and a firewall rule keeps it off your local network.
  (What it is handed, the restricted socket and the sound pipe, is in a private
  folder of its own: it gets no passage through your runtime folder, where your
  audio server's sockets are open to anyone who reaches them, with your
  microphones and camera behind them. `incognito` is the same.)
  WebRTC is off in it and in `incognito`: less code for a page to attack, and
  no direct connections that could show your address if a VPN lets them past.
  A profile made with `firefox-profiles/new-profile.sh` gets a user of its own the
  same way, so profiles cannot read each other either. `incognito` is the same
  idea with nothing kept and no shared clipboard. They
  share your kernel: a kernel bug could still get out, and an exploit that
  stays in the browser still has that profile's logins. `firefox-esr` runs as
  you and has none of this.
- **A video downloader, or the site JavaScript it runs, reaching your
  files.** `yt-dlp` (`extras/yt-dlp.sh`) runs as its own user, `ytdlp`, with
  no password, login or access to your home; what it downloads is copied out
  into `~/Downloads` by your user afterwards (regular files only). yt-dlp is
  the official release checked against its pinned signing key and owned by
  root, so it can't change itself; YouTube's JavaScript runs in Debian's
  QuickJS as `ytdlp`, which QuickJS itself doesn't restrict; a firewall rule
  keeps `ytdlp` off your local network, not off the internet. It shares your
  kernel, and the files it brings are still untrusted.
- **A booby-trapped image or video, or a coding assistant that goes wrong,
  reaching your files.** `imv` and `mpv` (`extras/media.sh`) start inside
  bubblewrap: they see only the files you open, read-only, and have no
  network unless you give mpv a URL. zathura (`extras/pdf-viewer.sh`) runs in
  the same sandbox, and so does GIMP (`extras/gimp.sh`), which besides gets
  `~/Pictures` read-write to save in, and never the network: a crafted
  picture in GIMP can reach `~/Pictures`, but not the rest of your files. `claude` (`extras/claude-code.sh`)
  runs Claude Code as its own user, `claude-agent`, which has no password
  and can't read your home folder, ssh keys, passwords or browser
  profiles; it works in `~/projects`, which you share with it. A firewall
  rule on that user keeps it off your router, printers and the programs
  listening on this machine; it reaches the internet only. Another account
  (`--account NAME`) is another such user, `claude-agent-NAME`, with its own
  home, firewall line and folder (`~/projects-NAME`); accounts can't read
  each other's logins, memories or folders, but share the one kernel. For a stronger
  boundary, `claude-vm` (`extras/claude-vm.sh`) runs the agent inside a
  disposable Debian VM (QEMU/KVM) with no shared folder: a kernel bug that
  would let `claude-agent` escape its user boundary reaches only a VM you can
  throw away, and the agent hands work back only by pushing to a git host you
  pull from. The same kind of firewall, on its `claude-vm` user, keeps the
  guest off your network. Another account (`--account NAME`) is another VM,
  run by its own user `claude-vm-NAME`, whose firewall lines let it reach
  only its own guest's console port, not the first VM's. The two can be installed together. Use the VM if
  your computer has KVM (`docs/extras.md` says how to check); `claude` is
  the weaker, lighter choice for computers that can't run it. `opencode-vm`
  (`extras/opencode-vm.sh`) puts opencode in the same kind of VM. Its
  download has no signature, only GitHub's own SHA-256 for an immutable
  release, so a hijacked maintainer account could slip in a bad one: the VM
  limits what that reaches, not whether it runs.
- **A stranger's USB stick running something.** Drives mount with
  `nosuid`, `nodev` and `noexec` (the `usb` command, `parts/usb.sh`, and
  `extras/udiskie.sh`), so nothing on a stick can run from it by itself.
  With udiskie they mount the moment they're plugged in, and either way the
  kernel's filesystem code reads whatever a stick contains: don't plug in
  sticks you don't trust. FAT, exFAT and NTFS keep no permissions, so `usb`
  mounts them readable by you alone on this computer; on another computer
  anyone holding the stick reads all of it (an encrypted stick doesn't
  have that problem: `usb mount` unlocks LUKS).
- **A stolen laptop, while it's switched off**, if you installed Debian
  with disk encryption (see the README). `status.sh` warns when you
  didn't. An install stick made with `--noencrypt` gives none of this:
  anyone with the laptop can read and change the disk.

With the extras:

- **Your network or ISP seeing that you use Tor**, if you say you need a
  bridge: Tor Browser, OnionShare, Whonix and the system Tor (apt over Tor,
  remote access, the onion site) ask first, then offer obfs4, webtunnel,
  Snowflake or meek, whichever that program can use (docs/install-base.md,
  "Bridges"). The bridge is set up before the first connection. webtunnel
  for the system Tor is lyrebird from the Tor Project's repository, with its
  key pinned and an apt pin that lets nothing else come from there: trusting
  the Tor Project for that one program, as Tor Browser users do.
- **A hacked browser revealing your real IP address**: Whonix
  (`extras/whonix.sh`) runs the browser in a virtual machine whose only
  way out is Tor.
- **Losing everything to a dead or stolen disk**: encrypted backups
  (`extras/backup.sh`).
- **Hidden data in files you share**: Metadata Cleaner and mat2 (`extras/metadata-cleaner.sh`).
- **Your network reading or forging the names you look up**: with secure
  DNS on (`parts/secure-dns.sh`, in the base, with a switch), Unbound checks every answer with DNSSEC and asks
  one resolver you pick over DNS over TLS; a firewall rule lets only Unbound
  send DNS out, so nothing goes around it unencrypted (DNS over HTTPS can't
  be stopped that way). If the resolver can't be reached, names stop
  resolving instead of falling back, and Wi-Fi sign-in pages don't work.
  Switched off (for such a page; the Wi-Fi sign-in window does it only while
  it is open), other programs use the network's DNS unencrypted; Firefox
  encrypts its own, except that throwaway sign-in window. Your user may
  switch it without a password, so a program running as you could too.

- **A sudo password that was seen or logged**, with the security-key extra
  and its `--sudo` (`extras/security-key.sh`): sudo then also needs a touch
  of your hardware key, which never gives its secret out. A sudo that is
  still remembered (sudo keeps it a few minutes, in the terminal it was typed
  in) needs no touch, and a program in that terminal can use it. Lose every
  registered key and sudo is closed to you (the extra's page says how to get
  back in).
- **Logins phished or taken from the computer**, for sites and SSH servers
  that take a security key: the key signs only for the site it was registered
  with, and only when touched.
- **A hacked wallet reading your files or showing your address**, with the
  wallet sandbox (`extras/wallet-sandbox.sh`), for a computer that can't run VMs:
  each wallet is its own user, the firewall lets it reach Tor's port and nothing
  else, checked from its own side, and it has its own window system. It shares
  this computer's kernel, so a kernel flaw gets out: Whonix is stronger. It can't
  stop a hacked wallet showing you a false address.
- **Coins spent behind your back**, with a hardware wallet
  (`extras/hardware-wallet.sh`): the device shows what it signs on its own
  screen and signs only when you agree there. It doesn't protect the
  recovery words, a fake device, or an address you don't check on its screen.
- **A program that quietly makes itself start at every login**, with the
  startup watch (`extras/startup-watch.sh`): the files it would change are
  compared with a record only root can change, and a change shows in the
  bar. It notices, it doesn't prevent, and it sees only the files it watches.

## What it doesn't protect against

- **A hacked sandbox sending data out.** Wren Linux's sandbox users (the
  sandboxed Firefox, incognito, yt-dlp, Claude's own user, the VMs) reach the
  internet, so one that is hacked can send out what it can read. Their DNS
  goes only to the resolver this computer uses (`parts/sandbox-dns.sh`),
  which keeps them off whatever else listens on port 53 nearby, but not from
  sending data through that resolver or over the web.
- **A local network with public addresses.** The firewall rules that keep sandbox
  users off your network know IPv4's private ranges and give those users no IPv6.
  On a network where computers have public IPv4 addresses (some universities and
  offices), a sandbox user can still reach them: nothing marks them as local.
- **The agent in `claude-vm`, with root in its VM.** It has sudo without a password
  there, on purpose. What holds it is the VM, QEMU's syscall filter, a firewall
  checked at every start, and an ssh login that forwards nothing. A bug in QEMU or
  KVM could still get out, and it reaches the internet, so nothing private belongs
  in the VM. Read what it pushes.
- **Anything running as you.** If you run a malicious program, or an
  attack escapes the browser, it can read all your files, every Firefox
  profile's logins and your wallets (except those kept in the wallet sandbox,
  `extras/wallet-sandbox.sh`, which it could still reach by waiting for your
  password). Wren Linux doesn't sandbox your own user. Only install software you trust. (With the Wren Linux package
  installed, the scripts Wren Linux runs with sudo are root's files in
  `/usr/share/wren`, so such a program can't change them to wait for your
  password; from your own copy in `~/wren` it could.) `claude-regular`
  (`extras/claude-regular.sh`) and `mullvad-browser-regular` run as you on
  purpose, for ease: a hacked page in Mullvad Browser reaches your files, and
  so does `firefox-esr` started by name. `claude-regular`'s
  sandbox and deny rules are Claude Code's own: it enforces them, they
  name only some folders, and you can turn them off in it.
- **Someone at the computer while you're logged in**, with autologin
  (`extras/autologin.sh`, which the base install sets up on an encrypted
  disk, or the stick's `--autologin`): switching it on
  (and typing the disk passphrase, on an encrypted disk) is enough to be
  you until the screen locks. Without disk encryption, switching it on is
  enough.
- **A laptop that's on, asleep or locked.** The disk key is in memory
  then. Shut down before leaving it somewhere or crossing a border. With
  `extras/lid-awake.sh` a closed lid means on and locked, not asleep: the
  same applies. The vault (`extras/vault.sh`) narrows this for the files
  in `~/Vault`: it closes itself after its time (an hour by default) and
  whenever the screen locks, and closed its key isn't in memory. While it
  is open it protects nothing, and what programs keep about its files
  elsewhere (thumbnails, recent-file lists, swap) isn't covered.
- **Physical tampering.** Someone with the laptop alone for a while
  could install a hardware keylogger or tamper with the boot process.
  Wren Linux doesn't set up Secure Boot measurement or tamper evidence.
  Firmware settings (a supervisor password, no booting from USB, chassis
  intrusion detection: `docs/bios.md`) slow this down; they don't stop it.
- **A program listening through the microphone.** With the sound extra, the
  microphone is muted at every login and stays off until you switch it on
  (`wrenctl --mic on`, or the Wren menu). Wi-Fi and Bluetooth have the same
  switches, on the radio itself (rfkill), and the Bluetooth extra starts its
  adapter off. The microphone mute is software: a program running as you can
  unmute it, so against that a hardware switch or unplugging is the stronger
  kind. `incognito` and the sandboxed `firefox` never get your audio server.
  With `extras/webcam.sh` a USB webcam is disconnected at every boot until
  you switch it on, the same kind of software switch: a cover over the lens
  is the stronger kind.
- **Being identified while logged in.** A VPN, Tor or Mullvad Browser
  hides your IP address, not who you are to a site you've logged into.
- **Your home, from the sandbox users.** The sandboxed Firefox's and
  Claude's users pass through your home to the one folder they share with
  you; they can't list it, but could open any file in it whose name they
  guess if "others" may read it, which Debian's default umask allows.
  `parts/home-private.sh` closes everything directly in your home to others
  (shared folders keep their named user) and makes new files private
  (umask 077). Something you open up yourself later (chmod o+r) is open to
  them again.
- **What you share with the sandboxes.** `claude-agent` and you both
  read and write `~/projects`, and it has your network. Anything it leaves
  there is untrusted: read scripts before you run them, and look at
  `.git/config` and `.git/hooks` before you tell your own git to trust a
  repository it made. Wren Linux puts a guard in front of your git inside
  `~/projects` (`bin/git`): it refuses a bare repository you did not name, and refuses to run when a repository's
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
- **Your network reading or forging the names you look up (DNS).** Every
  name the computer looks up goes, unencrypted, to the DNS server the
  network hands out (usually the router, and from there your ISP). They see
  each name, and anyone on the way can answer with a false address. HTTPS
  and apt's signatures catch a false answer for the browser and for
  packages (a certificate or a signature that doesn't match is refused);
  other programs may not check. Wren Linux's Firefox never sends your lookups
  to a provider it picked: with secure DNS on its own DNS-over-HTTPS
  is off and it uses the system's (encrypted); with it off, it encrypts its
  own lookups to Quad9, strictly (never plain DNS) unless "fallback" was
  chosen at its install, and only Firefox's lookups are protected then. Tor Browser, Whonix and apt over Tor
  look names up through Tor, and a connected VPN through its tunnel.
  Secure DNS encrypts the rest while it is on (see above); the resolver you
  pick still sees every name, and the name of each site also travels
  unencrypted at the start of most HTTPS connections, so it hides where
  you go from your network less than a VPN or Tor does.
- **Your network seeing or forging the time** (`parts/clock.sh`). The clock
  is set over plain NTP from `debian.pool.ntp.org`: your network sees that
  this computer asks for the time (and so that it runs Debian), and someone
  on the way could answer with a wrong time, which systemd-timesyncd
  accepts (it only refuses a time before it was built). A clock pushed far
  off shows as Tor failing to connect and certificate errors; it can also
  make an expired signature look current, or a current one look expired.
- **Being found through your onion site**, if you run one
  (`extras/onion-site.sh`). Its VM has no network, so the site's own software
  can't give away your address, but the site is only up while your computer is
  on: when it is up can link it to you. A hole in the app gets the VM and the
  site's data (not your computer), and anything you put in the site itself
  (names, metadata in files, writing style) is yours to watch.
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
- **Mistakes in Wren Linux itself.** It's a small project. Read the scripts
  before running them; they're written to be readable.

## Trade-offs it makes

- **uBlock's mode is a choice** at the sandboxed Firefox's install. Medium
  (the default) also blocks other sites' scripts and frames, where most
  malicious ads come from, and some sites break: allow one with
  `ublock-allow example.com`, then restart Firefox. Standard blocks ads,
  trackers and known malware sites but lets other sites' scripts run, so
  sites work.
- **JavaScript is slower** without the JIT. Heavy web apps can get it
  back in their own profile (`extras/firefox-profiles/new-profile.sh`, "fast
  JavaScript").
- **Wi-Fi login pages may ask again** after reconnecting, because of the
  random MAC address. Switch to one made-up address per network in
  `/etc/NetworkManager/conf.d/90-wren-random-mac.conf` (`stable`).
- **The screen locks by itself only after 5 minutes idle**, so a laptop
  left open is usable by whoever sits down until then. Lock it yourself
  when you step away (Super+Escape), or make the wait shorter:
  `timer lock 2`.
- **Security fixes install themselves.** Rarely, an update changes
  something you relied on; the log is in `/var/log/unattended-upgrades/`.
