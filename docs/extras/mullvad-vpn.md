# Mullvad VPN (`extras/mullvad-vpn.sh`)

This installs the Mullvad VPN app and its `mullvad` command-line tool from Mullvad's own apt repository. A VPN sends your internet traffic through an encrypted tunnel to a server run by Mullvad. You need a Mullvad account number (from mullvad.net).

## The problem it solves

On a café or hotel network, the people running it can see which sites you connect to, and the sites see the address of that network. At home, your internet provider sees the same. A VPN moves that trust: your local network sees only an encrypted connection to the VPN, and sites see the VPN server's address.

## The ideas behind it

**A VPN (virtual private network).** Think of a sealed pipe from your computer to a VPN company's server. Everything you send goes into the pipe; at the other end, the server forwards it onwards. The network between you and the server cannot read what is in the pipe. The VPN company, however, sees what the network used to see. You are choosing who to trust, not removing the need to trust someone.

**A tunnel.** The name for that pipe. On Linux it shows up as a network interface (names like `wg0` for WireGuard).

**An apt repository.** A website that serves software packages for `apt`. Mullvad runs its own. A repository's packages are only trusted if they are signed by a key you have approved. debsway fetches Mullvad's key and accepts it only if its fingerprint exactly matches the one pinned in `pins.sh`, taken from Mullvad's published verification page.

**DNS.** The system that turns a name (`example.org`) into a number. See `docs/extras/secure-dns.md`. While Mullvad is connected, it uses its own DNS server inside the tunnel.

**Lockdown mode.** A setting that blocks all internet traffic when the VPN is off, so nothing leaks if the tunnel drops.

## How it works, step by step

1. **Adds Mullvad's apt repository.** The script fetches the signing key, checks its fingerprint against `MULLVAD_FPR` in `pins.sh`, saves it as `/usr/share/keyrings/mullvad-keyring.asc`, and writes `/etc/apt/sources.list.d/mullvad.list` pointing at `https://repository.mullvad.net/deb/stable`. It also allows unattended upgrades for that repository, so Mullvad's updates install themselves with Debian's.
2. **Installs the `mullvad-vpn` package.** That gives the background service, the `mullvad` command and the graphical app.
3. **Installs a launcher** `~/.local/bin/mullvad-vpn`. The app lives in `/opt/Mullvad VPN/` and is not on your PATH; the launcher makes it findable from Super+d.
4. **Prints examples** of `mullvad` commands.

The script does not log you in, connect, or change any setting. You do that.

## What it changes on your computer

- Mullvad's key `/usr/share/keyrings/mullvad-keyring.asc` and source file `/etc/apt/sources.list.d/mullvad.list`.
- An unattended-upgrades allowance for `repository.mullvad.net`.
- The package `mullvad-vpn` (its service, `mullvad` command, app under `/opt`).
- `~/.local/bin/mullvad-vpn`.
- No firewall rules of debsway's own. (The Mullvad app manages its own.) debsway's sandboxes with a firewall rule (Firefox, yt-dlp, Claude Code) keep working with it: each rule is a table of its own that only rejects traffic to your local network, and lets DNS through first, Mullvad's (10.64.0.1) included. With lockdown mode they too lose the internet while the VPN is off.

## Using it

- `mullvad account login 1234123412341234` logs in with your account number.
- `mullvad relay set location se` chooses a country (`se` is Sweden); `mullvad relay set location se mma` a city.
- `mullvad relay list` lists countries, cities and servers.
- `mullvad connect`, `mullvad status`, `mullvad disconnect`.
- `mullvad auto-connect set on` connects whenever the laptop starts.
- `mullvad lockdown-mode set on` blocks all internet while the VPN is off. It also blocks Tor Browser.
- `mullvad dns set default --block-ads --block-trackers --block-malware` uses Mullvad's DNS to block those.
- `mullvad lan set allow` still lets you reach printers and the like at home.
- `mullvad-vpn` (or Super+d) opens the graphical app.

## What it protects against

- **Your local network or ISP seeing which sites you visit.** They see a connection to Mullvad, not the sites. (`THREAT-MODEL.md` lists this under the things a VPN covers that debsway alone does not.)
- **Sites seeing your real address,** while connected. They see the server's.
- **Tampered Mullvad packages,** because the repository key is pinned by fingerprint.
- **Name look-ups seen by your network,** while connected, because Mullvad's DNS is inside the tunnel.

## What it doesn't protect against

- **Mullvad itself seeing your traffic's destinations.** You trust the company.
- **Being identified while logged in.** A VPN hides your address, not who you are to a site you log into (`THREAT-MODEL.md`).
- **Browser fingerprints and cookies,** which still tell sites apart. See `docs/extras/mullvad-browser.md`.
- **Leaks when the VPN is off,** unless you turn on lockdown mode. The script does not turn it on.
- **Anything running as you,** which can ignore the VPN or read your files.
- **A determined, well-funded attacker** who targets you.
- It is not Tor: one company sits in the middle, instead of three unrelated relays.

## Removing it

`bash extras/mullvad-vpn.sh --remove` runs `mullvad disconnect`, uninstalls `mullvad-vpn`, removes `~/.local/bin/mullvad-vpn`, and removes Mullvad's apt repository and key, but only if Mullvad Browser (`extras/mullvad-browser.sh`) is not installed either. It does not touch anything that Mullvad's own package may have left in your home folder; the script does not look for those.
