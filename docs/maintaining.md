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
- **`update.sh`** decides which scripts to rerun from the files each one
  uses: the script itself, every `"$DEBSWAY_DIR/bin|data|vendor|lib/..."` it
  names, every `install_bin NAME`, any pinned name from `pins.sh` it (or a
  library it sources) uses, and the files on a `# files: bin/x data/y`
  header line. Put a `# files:` line in a script that gets a file installed
  by a library function, where the script's own text doesn't show it (the
  Landlock wrapper, `bin/no-abstract-sockets`, is the example). The shared
  libraries `lib.sh` loads for everyone are only reported, never counted.
  `tools/test-update.sh` checks this against a pretend server.
- **`tools/test-*.sh`** (run by `test.sh`) cover the parts that guard
  something: the signature checks (with throwaway expired and revoked
  keys), the sshd settings check, old package lists, the media sandbox,
  and `bin/no-abstract-sockets` (needs Linux 6.12; skipped on an older
  kernel).
- **shellcheck on every change:** run `bash test.sh` before you commit
  (it runs shellcheck; needs `sudo apt install shellcheck`), and the
  GitHub workflow in `.github/workflows/` runs it and `test.sh --offline`
  on every push. Settings are in `.shellcheckrc`. There is deliberately
  no git hook for it: a hook is a file in the project that runs as you on
  every commit, and the project's files can come from someone else.

## Signing debsway's commits

`update.sh` runs what it brings in, with sudo. To make sure it is yours, sign
your commits and pin the key: from then on every debsway computer brings in a
change only when the newest commit carries a good signature from that key
(`update_signed` in `lib/update.sh`, tested by `tools/test-update-signed.sh`
with throwaway keys). One signed commit on top vouches for everything under
it, since each commit's id covers the ones before it.

1. Make the key on a computer you trust, best one that is offline: a primary
   key that only certifies, and a signing subkey for every day.
   `gpg --quick-generate-key "debsway signing key <you@example.org>" ed25519 cert never`,
   then `gpg --quick-add-key FINGERPRINT ed25519 sign 2y`.
   Keep a revocation certificate and a backup of the primary key apart from
   the computer (an encrypted stick, and on paper with `paperkey`).
2. Put the public half in the repository and pin the **primary** key's
   fingerprint (a signature by a subkey counts for its primary key, so the
   subkey can be renewed or replaced without a new pin):
   `gpg --export --armor FINGERPRINT >data/debsway-signing-key.asc`, and
   `DEBSWAY_SIGNING_FPR=FINGERPRINT` in `pins.sh`. `bash test.sh` checks the
   file is exactly that key and can still sign.
3. Sign from then on: `git config commit.gpgsign true` and
   `git config user.signingkey FINGERPRINT` in `~/debsway`. Check one with
   `git log --show-signature -1`.
4. Commit and push all of this as one signed commit. Computers that update to
   it take it unchecked (their copy has no pin yet); every update after that
   is checked.

A new subkey: export the key again into `data/debsway-signing-key.asc` and
commit that with the old subkey's signature, before it expires. A key that has
expired or been revoked fails the check, and updates stop until a copy with
the new key is brought in by hand.

## The debsway package

`bash tools/build-deb.sh` builds `debsway_VERSION_all.deb` from a commit
(`--commit REV`, by default HEAD; never from files that aren't committed).
`--version` sets the version; without it the version is `0~git`, the commit's
date and its id. `tools/test-build-deb.sh` checks it.

- **What it installs:** the scripts in `/usr/share/debsway`, owned by root and
  writable by no one else; the `debsway` command in `/usr/bin`; its man page and
  Tab completion; the licenses. Nothing outside `/usr`, nothing setuid.
- **What it runs when installed:** nothing. It has no install scripts, so
  installing it changes no setting. The desktop is set up as before, as you:
  `debsway part NAME`, `debsway install NAME`, `bash /usr/share/debsway/install-base.sh`.
- **Why:** with the scripts root's, a program running as you can no longer
  change one and wait for you to run it with sudo. The `debsway` command uses
  `/usr/share/debsway` whenever it is there (`DEBSWAY_DIR=~/debsway debsway ...`
  uses your own copy instead).
- **The same file every time:** every date in it is the commit's, so two builds
  of one commit are the same, byte for byte; the build prints the SHA-256.
  Publish that next to the package: anyone can build it again and compare.
- **lintian** checks it when installed (`debsway install debsway-dev`); it isn't
  needed to build. Debian's debhelper isn't used: the package is files only,
  and `dpkg-deb` with a short script is easier to read and to build the same
  way every time.

Install it on a computer with `sudo apt install ./debsway_VERSION_all.deb`.
apt brings a newer one (the same way, or from the signed apt repository
below); `debsway update` then runs again the parts and extras whose files
changed, as it does for a git copy. Without git it compares the files with a
record it keeps after each run (`~/.local/state/debsway/applied-files`, and a
copy of `pins.sh`); the first run takes what is set up as up to date
(`debsway update --all` offers everything). `tools/test-update-package.sh`
checks it.

## The signed apt repository

`bash tools/make-apt-repo.sh --key FINGERPRINT --out FOLDER debsway_*.deb`
makes an apt repository (`pool/`, `dists/trixie/`) of debsway's packages and
signs it, on your own computer, with your key (the pinned `DEBSWAY_SIGNING_FPR`
once it is set; gpg asks for the passphrase or the token). Upload FOLDER as it
is to any web server or mirror (`rsync -a --delete FOLDER/ server:/var/www/debian/`);
`tools/test-apt-repo.sh` checks it with throwaway keys and Debian's own apt.

- **The server can't change a package.** apt checks every file against
  `InRelease`, and `InRelease` against your key. Whoever runs the server can
  only hold updates back.
- **Nor serve an old one for long:** `InRelease` is good for 14 days
  (`--valid-days N`, 1 to 90), after which apt refuses the repository. Sign it
  again within that time, even when nothing changed.
- **Only debsway's packages** go in (`debsway` and `debsway-*`); the script
  refuses anything else.

On a debsway computer, `debsway part debsway-repo` adds it, once `pins.sh`
names both the key (`DEBSWAY_SIGNING_FPR`) and the address
(`DEBSWAY_REPO_URL`, https:// or an .onion address); until then it changes
nothing. The key comes from the copy's own `data/debsway-signing-key.asc`,
only if it is exactly the pinned one, and is trusted for that repository
alone (`Signed-By`). An apt pin lets only the package `debsway` come from it,
so even someone with your key or the server couldn't replace a Debian package
or add another (`tools/test-debsway-repo.sh` checks the pin with Debian's own
apt). unattended-upgrades then installs debsway's updates like Debian's. It
is not in the base list yet: add it to `PARTS` in `packages.sh` once the
repository is live.

## Other scripts

- `prep/setup-sudo.sh USER` (as root): installs sudo and adds USER to the
  sudo group.
- `status.sh`: what's installed, the Firefox hardening, sway snippets,
  how each Wi-Fi device is set up, and a warning if `/`, `/home` or swap
  isn't encrypted.
- `prep/make-install-iso.sh`: an automatic Debian 13 install image with debsway
  on it (see the README, "Before you reinstall"). What runs inside the
  installer is `data/install-iso-*`; `tools/test-install-iso.sh` checks it.
  `tools/try-install-iso.sh` installs from a built image in a throwaway QEMU VM.
- `prep/fetch-offline-debs.sh`, `prep/fetch-tor-browser.sh`: download
  things you need before a reinstall (see the README).
- `tools/pack-usb.sh /path/to/stick`: puts the last commit and `offline/`
  on a stick, without personal files, labels the stick `DEBSWAY` (only a
  removable drive, and it asks first) and writes `START-HERE.txt`.
- `start.sh`: what a user runs from the stick on a fresh install
  (`sudo mount -L DEBSWAY /mnt && bash /mnt/debsway/start.sh`).
