# What debsway protects against, and what it doesn't

debsway is a minimal Debian desktop with careful defaults. It makes the
common attacks harder; it doesn't make you invisible or untouchable. Use
this page to decide what else you need.

## What it protects against

- **Known bugs being used against you.** Debian's security fixes install
  themselves every day (`parts/unattended-upgrades.sh`), and you're told
  when Firefox needs a restart to use its fixed version.
- **Attacks through websites.** In every Firefox profile, uBlock Origin
  blocks scripts and frames from other sites, where most malicious ads
  and drive-by attacks come from; the JavaScript JIT, the part of
  Firefox most exploits target, is off; and HTTPS-Only Mode refuses
  unencrypted pages unless you agree (`parts/firefox-hardening.sh`).
- **People on the same network.** Nothing on the laptop accepts incoming
  connections (`parts/ufw.sh`). HTTPS-Only Mode stops tampering on café
  and hotel Wi-Fi.
- **Being recognised from network to network.** Wi-Fi uses a new,
  made-up hardware (MAC) address every time it connects
  (`parts/random-mac.sh`).
- **Tampered downloads.** Everything debsway downloads from outside
  Debian is checked against the project's signing key, pinned by
  fingerprint in `pins.sh`, before it's used. `test.sh` re-checks them.
- **Sites tracking you across each other**, if you give the sites you
  log into their own Firefox profile (`firefox-profiles/`).
- **A stolen laptop, while it's switched off**, if you installed Debian
  with disk encryption (see the README). `status.sh` warns when you
  didn't.

With the extras:

- **Your network or ISP seeing that you use Tor**: Tor Browser
  (`extras/tor-browser.sh`), OnionShare and Whonix connect through
  bridges you supply, set up before their first connection.
- **A hacked browser revealing your real IP address**: Whonix
  (`extras/whonix.sh`) runs the browser in a virtual machine whose only
  way out is Tor.
- **Losing everything to a dead or stolen disk**: encrypted backups
  (`extras/backup.sh`).
- **Hidden data in files you share**: mat2 (`extras/mat2.sh`).

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
- **Being identified while logged in.** A VPN, Tor or Mullvad Browser
  hides your IP address, not who you are to a site you've logged into.
- **Your Wi-Fi network or ISP seeing where you go**, outside Tor or a
  VPN. They see which sites you visit (not what's on the pages).
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
  back in their own profile (`firefox-profiles/new-profile.sh`, "fast
  JavaScript").
- **Wi-Fi login pages may ask again** after reconnecting, because of the
  random MAC address. Switch to one made-up address per network in
  `/etc/NetworkManager/conf.d/90-debsway-random-mac.conf` (`stable`).
- **Security fixes install themselves.** Rarely, an update changes
  something you relied on; the log is in `/var/log/unattended-upgrades/`.
