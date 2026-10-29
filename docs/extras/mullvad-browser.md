# Mullvad Browser (`extras/mullvad-browser.sh`)

Mullvad Browser is a web browser made by the Tor Project and Mullvad. It has Tor Browser's protections against tracking and fingerprinting but does not use Tor. It is meant to be used together with a VPN, and it forgets everything when you close it.

## The problem it solves

Websites can often recognise you without any cookie, from small details of your browser and computer: screen size, installed fonts, how it draws things. This is called fingerprinting. A VPN changes your address, but does nothing about fingerprints. Mullvad Browser is built so that all its users look alike, which makes you harder to pick out.

## The ideas behind it

**Fingerprinting.** Imagine many people each describing their coat: colour, length, buttons. Together the details single you out. A browser that makes everyone wear the same grey coat is harder to track.

**Tor Browser without Tor.** Tor Browser is a modified Firefox. Mullvad Browser keeps the anti-tracking changes, but sends traffic by your normal connection. The address sites see is whatever your connection (or your VPN) shows.

**A VPN.** An encrypted tunnel to a company's server, so sites see the server's address instead of yours. See `docs/extras/mullvad-vpn.md`. This browser does not hide your address by itself. The script says so at the end.

**An apt repository.** A website `apt` installs packages from. This browser comes from Mullvad's repository, whose signing key debsway accepts only if its fingerprint matches the one pinned in `pins.sh`.

**X11 and XWayland.** The browser is built on Tor Browser, which runs on X11 (an older window system). XWayland lets X11 programs run under sway.

## How it works, step by step

1. **Adds Mullvad's apt repository** (the same one the VPN uses): fetches the key, checks the fingerprint (`MULLVAD_FPR` in `pins.sh`), writes the key to `/usr/share/keyrings/mullvad-keyring.asc` and `/etc/apt/sources.list.d/mullvad.list`, and allows unattended upgrades for that repository.
2. **Installs XWayland.** Log out and back in once after the first X11 app, because sway only notices XWayland when it starts.
3. **Installs the `mullvad-browser` package** and tells you to run `mullvad-browser`.

The script writes no browser settings of its own. Whatever the package does is how the browser behaves.

## What it changes on your computer

- Mullvad's key `/usr/share/keyrings/mullvad-keyring.asc` and `/etc/apt/sources.list.d/mullvad.list`.
- An unattended-upgrades allowance for `repository.mullvad.net`, so updates install themselves.
- Packages: `mullvad-browser`, and XWayland.
- No files in `~/.local/bin`, no firewall rules, no users.

## Using it

- `mullvad-browser` (or Super+d) starts it.
- Connect a VPN first if you want your address hidden, for example `mullvad connect` with `extras/mullvad-vpn.sh`.

## What it protects against

- **Tracking by fingerprint and cookies,** to the degree Tor Browser's design provides, because the browser tries to look the same for everyone and forgets everything on close.
- **Tampered packages,** because the repository key is pinned.

## What it doesn't protect against

- **Your address.** It does not hide it. Without a VPN, sites see your real address and your network sees where you go.
- **Being identified while logged in.** Hiding your address does not hide who you are to a site you have logged into (`THREAT-MODEL.md`).
- **The rest of your computer.** It runs as you, with no sandbox from debsway. For that, `extras/firefox-sandbox.sh` or `incognito` exist (`extras/firefox.sh`).
- **DNS over HTTPS.** The browser keeps its own DNS over HTTPS (sending name look-ups, encrypted, to a provider it chooses), which `extras/secure-dns.sh` cannot stop with a firewall rule (`docs/extras.md`).
- **It is not Tor.** There is no three-relay hiding.
- **A determined, well-funded attacker.**

## Removing it

`bash extras/mullvad-browser.sh --remove` uninstalls `mullvad-browser` and, if Mullvad VPN is not installed either, removes Mullvad's apt repository and key. XWayland and anything in your home folder are not touched by the script (the browser forgets its data on close anyway).
