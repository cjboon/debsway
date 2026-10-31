# extras/firefox-profiles/

Give a website you stay logged into its own Firefox profile:

```bash
bash extras/firefox-profiles/new-profile.sh
```

It asks for a short name (e.g. `bank`) and the site's address, and makes:

- a Linux user of its own, `fx-bank`, locked down like the sandboxed Firefox
  (`extras/firefox-sandbox.sh`): no password, no login, none of your files,
- a Firefox profile in that user's home, with its own cookies, logins,
  history and settings, which opens that site when it starts, and
- a command, `firefox-bank`, that starts it. Super+d finds it too.

It needs the sandboxed Firefox set up first, and offers to do that.

Or in one go: `bash extras/firefox-profiles/new-profile.sh bank https://mybank.example`.

## Why it's useful

A browser profile is a separate compartment. Sites in one profile can't
see the cookies, logins or stored data of another, so:

- **Trackers can't follow you between them.** If your Google, shopping
  or social media accounts live in their own profiles, those companies
  don't see what you do in the rest of your browsing.
- **Your most sensitive logins are kept apart.** A banking or email
  profile that only ever opens that one site is never exposed to the
  random sites you visit elsewhere.
- **You stay logged in** where you want to, without that login being
  available to every other site.

Each profile runs as its own Firefox, as its own user, so they can be open side by side.
Pass an address to open it in that profile: `firefox-bank https://mybank.example/statements`.

Good candidates: banking, email, crypto exchanges, shopping, a Google
or work account, social media. Sites you don't log into don't need one.

## What each user is, and what it shares

- **Your files are out of reach.** The profile's user can read none of your
  files, ssh keys or passwords, and a program running as *you* cannot read the
  profile's logins either (its home is `/var/lib/debsway-fx/NAME`, mode 700).
- **Profiles can't read each other.** Each has its own user, its own sound pipe,
  its own folder in memory, and its own downloads folder, `~/Downloads/NAME`,
  which is shared with you and with no other profile.
- **Shared with you:** the clipboard (while that window has focus) and its
  downloads folder. Treat what lands there as untrusted.
- **No screen reading or typing for you**, and no audio server or microphone:
  the same restricted screen access and sound pipe as the sandboxed Firefox.
- **Blocked from your local network:** one firewall rule covers every profile
  (they all share the group `debsway-fx`). `sudo systemctl stop
  debsway-firefox-firewall` lifts it for a while.
- **Still shared:** the kernel (a kernel bug could still get out), and your IP
  address. Disk encryption, few extensions and Tor Browser (for anonymity)
  cover the rest; see `THREAT-MODEL.md` in the main folder.
- **Settings:** the address and the JavaScript choice are in
  `/etc/debsway/firefox-profiles/NAME.conf`, writable only by root, so a hacked
  profile can't change them.

Profiles made by an earlier version of this script (in your own Firefox, as
you) keep working; `--remove NAME` still removes them as before.

## Fast JavaScript

debsway turns Firefox's JavaScript JIT off in every profile (see
`parts/firefox-hardening.sh`): JavaScript runs slower, but most serious
browser exploits target the JIT. Heavy web apps such as webmail, online
office suites or chat may feel sluggish without it. Answer yes to "Fast
JavaScript for this site?" (or add `--fast-js`) to turn it back on for
that one profile only.

## Removing one

`bash extras/firefox-profiles/new-profile.sh --remove bank` removes the
`firefox-bank` command, the permission to run it and its settings file, then
asks whether to delete the profile's logins and its user too. Say no and they
are kept (the user stays locked) until you remove them. Files it downloaded
stay in `~/Downloads/bank`.

## Files

- `new-profile.sh`: the script you run.
- `../../lib/firefox-profiles.sh`, `../../lib/firefox-sandbox.sh`: its helpers
  (sourced, not run): the profile, the user, the sudo rule.

Each profile's settings are in its `user.js`, written at every start from
`/etc/debsway/firefox-profiles/NAME.conf`. Profiles live in
`/var/lib/debsway-fx/NAME/profile`.
