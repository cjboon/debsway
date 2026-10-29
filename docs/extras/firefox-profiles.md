# One Firefox profile per site (`extras/firefox-profiles/new-profile.sh`)

For a site you stay logged into (a bank, email, shopping), you get a Firefox of its own with a command `firefox-NAME`. It has its own cookies, logins and history, and it runs as its own locked-down Linux user, so it cannot read your files or the other profiles. It is built on the sandboxed Firefox from `extras/firefox-sandbox.sh`.

## The problem it solves

If you are logged into your bank, your email and a social network in the same browser, they share one place to store cookies and logins. A tracker on one site, or a hacked page, is in the same browser as the others. Advertising companies also follow you across sites by using what a shared browser remembers.

Keeping each important site in its own compartment limits what any one page can see.

## The ideas behind it

**A browser profile.** A profile is a folder where Firefox keeps your cookies, logins, history, bookmarks and settings. Two profiles do not see each other's data. It is like having two separate browsers.

**Cookies.** Small notes a site asks your browser to keep, such as "this person is logged in". Trackers also use them to recognise you from site to site.

**A separate Linux user.** Linux gives each account its own files. A program running as another user cannot read yours. Each profile here gets its own user, named `fx-NAME`, with no password and no login, so one profile cannot read another's data either.

**sudo and a sudoers rule.** `sudo` runs a command as another user. A sudoers rule, a line under `/etc/sudoers.d/`, says who may run what. Here your user may run one helper script as `fx-NAME`, without a password, and nothing else.

**A firewall rule.** A rule telling the network layer which connections to refuse. One rule covers every profile, because all these users share the group `debsway-fx`.

**A sandbox.** A box around a program that limits what it can touch. The details are in `docs/extras/firefox-sandbox.md`.

## How it works, step by step

`bash extras/firefox-profiles/new-profile.sh` asks for a short name (lowercase letters, digits and dashes, starting with a letter, up to 28 characters, for example `bank`) and the site's address. You can give both in one go: `bash extras/firefox-profiles/new-profile.sh bank https://mybank.example`. A missing `https://` is added. Only plain web addresses are accepted.

It also asks "Fast JavaScript for this site?" (default no); `--fast-js` as a third word answers yes. debsway turns off Firefox's JavaScript JIT everywhere, because most serious exploits target it. Heavy web apps like webmail or office suites may feel slow without it, so this turns the JIT back on for that one profile only.

Then it:

1. Checks that the sandboxed Firefox is set up. If not, it offers to run `extras/firefox-sandbox.sh` first, and stops if you say no.
2. Creates the user `fx-NAME` (home `/var/lib/debsway-fx/NAME`, mode 700, no password, nologin shell, group `debsway-fx`, plus `render`).
3. Writes `/etc/debsway/firefox-profiles/NAME.conf` with the address and the JavaScript choice. Only root can write it, so a taken-over profile cannot change them.
4. Writes `/etc/sudoers.d/debsway-fx-NAME`, checked with `visudo`.
5. Writes the launcher `~/.local/bin/firefox-NAME`, a two-line script that runs `firefox --profile NAME`. If a file by that name exists and is not debsway's, it warns and leaves it.

When you start `firefox-NAME`, the same machinery as the sandboxed Firefox runs, with these differences: the user is `fx-NAME`; its sockets, sound pipe and runtime folder in memory are named for the profile; its downloads go to `~/Downloads/NAME`, a folder shared with you and with no other profile; and at every start the helper rewrites the profile's `user.js` so it opens the saved address and, if chosen, turns the JIT back on. Profiles can be open side by side. An address after the command, `firefox-bank https://mybank.example/statements`, opens in that profile.

## What it changes on your computer

- If missing, everything the sandboxed Firefox installs (see `docs/extras/firefox-sandbox.md`).
- The user `fx-NAME` and its home `/var/lib/debsway-fx/NAME`.
- `/etc/debsway/firefox-profiles/NAME.conf`.
- `/etc/sudoers.d/debsway-fx-NAME`.
- `~/.local/bin/firefox-NAME`.
- While it runs, `~/Downloads/NAME` (created on first start) and temporary access for the user, as for the sandboxed Firefox.

## Using it

- `firefox-NAME` (or Super+d): open that profile. Add an address to open it.
- `bash extras/firefox-profiles/new-profile.sh`: make another profile.
- `bash extras/firefox-profiles/new-profile.sh --remove NAME`: remove one.
- `sudo systemctl stop debsway-firefox-firewall`: lift the network rule for all sandboxed users for a while; `start` puts it back.
- Good candidates: banking, email, exchanges, shopping, a Google or work account. Sites you never log into do not need one.

## What it protects against

- **Sites tracking you across each other.** Cookies and logins do not cross between profiles.
- **A hacked page reaching your files or another profile.** Each profile is a user that owns nothing of yours, and cannot read other profiles' homes or downloads.
- **Your own programs reading the logins.** The profile's home is mode 700 and owned by its user.
- **Reading the screen, typing for you, hearing the microphone, reaching your local network.** The same restricted Wayland socket, one-way sound pipe and firewall rule as the sandboxed Firefox.
- **Changing the profile's address or JavaScript setting from inside.** The settings file is writable by root only.

## What it doesn't protect against

- **A kernel bug.** All profiles share your kernel.
- **An exploit inside one profile.** It can still use that profile's logins and cookies and send them out.
- **Your IP address.** It is your network. Tor Browser is the tool for anonymity.
- **What lands in `~/Downloads/NAME`.** It is shared with you; do not run it unread.
- **The clipboard.** It is shared with you while that window has focus.
- **A slower or less safe fast-JavaScript profile.** With `--fast-js` the JIT is back on for that profile.
- **Profiles made by an earlier version** (in your own Firefox, as you) keep working but have none of this.

## Removing it

`bash extras/firefox-profiles/new-profile.sh --remove NAME` removes `firefox-NAME`, the sudoers rule and the settings file, then asks whether to delete the profile's logins and the user. The default is no: the profile stays in `/var/lib/debsway-fx/NAME` and the user stays locked. If you say yes, the user, the folder and its memory folder are deleted. Files it downloaded stay in `~/Downloads/NAME`. For a profile made by the older version, only the launcher is removed and the profile stays.
