# Keeping it working

Things outside debsway change: download pages move, signing keys are
replaced, packages get renamed, and new Whonix or Tor Browser versions
can change what the scripts rely on.

- **`bash test.sh`** checks it all without installing anything: every
  script parses and passes shellcheck; every Debian package still
  exists; every pinned signing key is still published, still has that
  fingerprint and isn't expiring; the newest release of each downloaded
  app can still be found and its signature verifies; the Debian and
  Firefox features the hardening relies on are still there; and the saved
  downloads still verify. `bash test.sh --offline` skips the network.
  Run it now and then, and before a reinstall.
- **`pins.sh`** holds every fingerprint and the outside versions the
  scripts were written against, each with the date it was last checked
  by hand (`# checked: YYYY-MM-DD`). `test.sh` warns when one is over a
  year old, and when Tor Browser or Whonix reach a new major version.
- **`bash tools/test-apt-markers.sh`** (run by `test.sh`) checks the
  package bookkeeping behind `--remove` against fakes of apt, so it
  changes nothing.
- **shellcheck on every change:** `git config core.hooksPath hooks` runs
  it before each commit (`hooks/pre-commit`; needs
  `sudo apt install shellcheck`), and the GitHub workflow in
  `.github/workflows/` runs it and `test.sh --offline` on every push.
  Settings are in `.shellcheckrc`.

## Other scripts

- `prep/setup-sudo.sh USER` (as root): installs sudo and adds USER to the
  sudo group.
- `status.sh`: what's installed, the Firefox hardening, sway snippets,
  how each Wi-Fi device is set up, and a warning if `/`, `/home` or swap
  isn't encrypted.
- `prep/fetch-offline-debs.sh`, `prep/fetch-tor-browser.sh`: download
  things you need before a reinstall (see the README).
- `tools/pack-usb.sh /path/to/stick`: puts the last commit and `offline/`
  on a stick, without personal files, labels the stick `DEBSWAY` (only a
  removable drive, and it asks first) and writes `START-HERE.txt`.
- `start.sh`: what a user runs from the stick on a fresh install
  (`sudo mount -L DEBSWAY /mnt && bash /mnt/debsway/start.sh`).
