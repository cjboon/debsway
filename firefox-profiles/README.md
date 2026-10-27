# firefox-profiles/

Give a website you stay logged into its own Firefox profile:

```bash
bash firefox-profiles/new-profile.sh
```

It asks for a short name (e.g. `bank`) and the site's address, and makes:

- a Firefox profile with its own cookies, logins, history and settings,
  which opens that site when it starts, and
- a command, `firefox-bank`, that starts it. Super+d finds it too.

Or in one go: `bash firefox-profiles/new-profile.sh bank https://mybank.example`.

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

Each profile runs as its own Firefox, so they can be open side by side.
Pass an address to open it in that profile: `firefox-bank https://mybank.example/statements`.

Good candidates: banking, email, crypto exchanges, shopping, a Google
or work account, social media. Sites you don't log into don't need one.

## What it doesn't do

Profiles keep sites apart from **each other**. They aren't a wall
against malware on your computer: anything running as you can read
every profile. All profiles also share your IP address. Disk
encryption, few extensions and Tor Browser (for anonymity) cover the
rest; see `THREAT-MODEL.md` in the main folder.

## Fast JavaScript

debsway turns Firefox's JavaScript JIT off in every profile (see
`parts/firefox-hardening.sh`): JavaScript runs slower, but most serious
browser exploits target the JIT. Heavy web apps such as webmail, online
office suites or chat may feel sluggish without it. Answer yes to "Fast
JavaScript for this site?" (or add `--fast-js`) to turn it back on for
that one profile only.

## Removing one

`bash firefox-profiles/new-profile.sh --remove bank` removes the
`firefox-bank` command. The profile and its logins are kept; delete it
in Firefox at `about:profiles` if you want it gone.

## Files

- `new-profile.sh`: the script you run.
- `profiles.sh`: its helpers (sourced, not run).

Each profile's settings are in its `user.js`, applied at every start.
Profiles live in `~/.config/mozilla/firefox/`.
