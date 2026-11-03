# From scripts to a distribution: the plan

## In short

1. Decide the name, and make an offline signing key.
2. `debsway install NAME`, with Tab completion. (Done.)
3. A `.deb` that installs debsway root-owned in `/usr/share/debsway`. (Done.)
4. A signed apt repository. Signing happens on your own computer, so a
   broken-into VPS can't forge updates.
5. A static website on a hardened VPS, with an onion mirror.
6. An installer ISO, built on Debian's own installer and signed shim.
7. DistroWatch.

About seven to nine working sessions in all. Start with step 2: it is useful
at once, and everything later builds on it.

---

Where debsway is now, where it could go, and the order that gets there with
the least rework, without loosening any security debsway already gives.

**Now:** a git checkout in `~/debsway`, run as you, with root steps through
sudo. 32 base parts, 47 extras, 62 test scripts, about 360 files, MIT licensed.
`update.sh` pulls from GitHub and re-runs what changed.

**The goal:**
1. A Debian package (`.deb`) that installs debsway root-owned.
2. A signed apt repository that delivers its updates.
3. An installer image (ISO) that installs Debian and debsway in one go.
4. A website that hosts all of that.
5. A DistroWatch listing.

Each phase below stands on its own: debsway gets safer at every step, even
if the next one waits.

---

## Why this order

- **The package comes first.** It is what everything else delivers: the
  repository serves it and the ISO installs it. It also closes the biggest
  gap in the current design: today `update.sh` runs, with sudo, whatever
  arrives from GitHub. Whoever takes over the GitHub account, or a machine
  on the way, decides what runs as root on every debsway computer. A signed
  package checked by apt with your key moves that trust from GitHub to a key
  you hold.
- **The website comes after the repository.** The website only hosts
  signed files. A broken-into web server should be able to stop updates,
  never forge them.
- **The ISO comes last.** It is the most work and adds the least security.
  It's mostly convenience, plus DistroWatch's expectations.

---

## Phase 0: decisions to make first (an hour, no code)

1. **Name.** Renaming later touches every file, every user's machine and
   every link, so settle it now.
   - Read Debian's trademark policy (debian.org/trademark). The word
     "Debian" is what it protects; "debsway" doesn't use it.
   - Write "based on Debian, not affiliated with or endorsed by the Debian
     project" in the README and on the website.
   - If unsure, ask trademark@debian.org.
   - Check that no other project uses the name.
2. **Version scheme.** For example `2026.11` (year.month), tied to Debian
   stable (`13` now). Every release is a signed git tag.
3. **The signing key.** One OpenPGP key that signs the repository and the
   ISO checksums. It is the most valuable thing in the project.
   - Make it on an offline machine, or at least a fresh debsway user. Keep
     the primary key offline (an encrypted USB stick and a paper backup).
   - Use only a signing subkey day to day, ideally on a hardware token
     (Nitrokey, YubiKey).
   - Never put it on the VPS.
   - Publish its fingerprint in the README, on the website, and in the
     package that installs it.
   - Write down how to revoke it.
4. **Security contact.** A `SECURITY.md`: how to report a problem privately
   (an email address, the key's fingerprint), and what you promise in return
   (an answer within days, a fix in the next release).

---

## Phase 1: debsway as a Debian package

The repository stays your workshop in `~/debsway`: you edit and test there
as now. Installed systems get a built package instead.

### 1a. One command, `debsway`, in front of everything (done)

The `debsway` command already exists (the menu, `--apps`, `--update`).
Extend it before anything moves, so the docs can switch to it early:

```
debsway install NAME      runs extras/NAME.sh       (Tab lists the extras)
debsway remove NAME       runs extras/NAME.sh --remove
debsway manual NAME       runs extras/NAME.sh --manual
debsway list              the extras: installed or not, with their summary
debsway status            status.sh
debsway update            update.sh (later: apt, see Phase 2)
debsway part NAME         re-runs one base part
```

- **Arguments:** checked against the list of extras by exact name only, so
  nothing else is ever run.
- **Tab completion:** a bash-completion file that lists the extras.
- **The hints:** the command hints (`parts/command-hints.sh`) then say
  `debsway install claude-vm` instead of a path.
- **Docs and tests:** change the docs from `bash ~/debsway/extras/X.sh` to
  `debsway install X` (about 170 places, mechanical), and update the man
  page and its test.

*Cost:* one session. *Security:* none lost, and from here on the docs don't
depend on where debsway lives.

### 1b. Make every script work from wherever it is installed (done)

Done: the commands look for `DEBSWAY_DIR`, then a root-owned
`/usr/share/debsway`, then `~/debsway`; messages say `debsway install NAME`
or name the folder the script runs from; `tools/test-location.sh` checks it.


- **The folder:** `DEBSWAY_DIR` is already worked out from where `lib.sh`
  is. Check that nothing assumes `~/debsway`: grep for it in the scripts
  (not the docs), and route it through `DEBSWAY_DIR`.
- **What is yours stays in your home:** state in `~/.local/state/debsway`,
  settings in `~/.config/debsway`, pictures in `~/Pictures`, unchanged.
- **Tests:** they keep running from the checkout (`bash test.sh`); one new
  test runs a few of them from a copy in another folder.

*Cost:* half a session.

### 1c. The package (done)

Done, a little differently from below: `tools/build-deb.sh` builds it with
`dpkg-deb` from a commit, without debhelper (the package is files only, and a
short script is easier to read and to build the same way every time). It has
no install scripts at all. `tools/test-build-deb.sh` checks it; lintian runs
when it is installed. See docs/maintaining.md, "The debsway package".


Build with Debian's own tools: `debhelper` (`dh`), `dpkg-buildpackage`, and
`lintian` to check the result. A `debian/` folder in the repository holds:

- `control`:
  - The package `debsway`, Architecture `all` (scripts only).
  - Depends on what every part needs before it runs: bash, sudo, git (for
    now), python3, acl, nftables.
  - The rest stays installed by the parts as now, with apt markers.
- `install`:
  - `parts/ extras/ lib/ data/ bin/ vendor/ *.sh` to `/usr/share/debsway/`.
  - The `debsway` command to `/usr/bin/debsway`.
  - The man page to `/usr/share/man/man1/`.
  - The docs to `/usr/share/doc/debsway/`.
  - The completion file to `/usr/share/bash-completion/completions/debsway`.
- `changelog`: one entry per release (`dch` writes it).
- `copyright`: MIT, and the vendored `mockvps-kvm` with its own license.
- `rules`: the default `dh $@`. No build step: the files are copied.

Everything in `/usr/share/debsway` is root-owned and read-only to you.
Malware running as you can't change a script and wait for you to run it
with sudo.

**What stays the same:** parts still run as you and use sudo for root steps,
and `~/.local/bin` commands are still installed per user by the parts, from
`/usr/share/debsway/bin`.

**One open choice:** user commands that are only a launcher (`firefox`,
`incognito`, `wifi-signin`) can move to `/usr/bin` in the package, root-owned
like the sessions. Do that one at a time, each with its test, later.

**Migrating your own machine:**
1. Install the package.
2. Run `debsway update`, which re-runs every part from
   `/usr/share/debsway`. The new stale-command check in `update.sh` offers
   whatever the new location changed.
3. Keep `~/debsway` as your development copy.

*Cost:* one to two sessions, most of it the first lintian-clean build.

### 1d. Building it the same way every time (done)

Done: every date in the package is the commit's, so two builds of one commit
are the same file (a test builds it twice and compares), and CI builds it on
every push as part of `test.sh --offline`. Build a release from its signed
tag: `bash tools/build-deb.sh --commit TAG --version VERSION`.


- **Make target:** `make deb` (or `tools/build-deb.sh`) builds in a clean
  folder from a git tag only, never from uncommitted files.
- **Checksums:** it prints the package's SHA-256 checksum. Two builds of the
  same tag must give the same file. Debian's `reprotest` can check that.
- **CI:** builds the package and runs `test.sh --offline` on every push, so
  a release is never built from a broken tree.

*Cost:* half a session.

---

## Phase 2: a signed apt repository

Started: `tools/make-apt-repo.sh` makes and signs the repository on your own
computer (with `apt-ftparchive` and gpg, which Debian has, instead of
reprepro), only for debsway's packages, good for 14 days; Debian's own apt
takes it, and refuses it signed with another key, past its Valid-Until or
with a changed package list (`tools/test-apt-repo.sh`). `parts/debsway-repo.sh`
adds it on a debsway computer: the pinned key only, and an apt pin so it can
bring nothing but the debsway package (checked with real apt). It changes
nothing until pins.sh names the key and the address. Still to do: re-running
the parts whose files changed after apt upgrades the package (update.sh does
it from git today), and adding the part to the base list once the repository
is live. A separate keyring package isn't needed: the key comes with debsway
itself, checked against the pin.


- **The archive tool:** `reprepro` builds a Debian archive (the `dists/`
  and `pool/` folders) and signs its `InRelease` file with your signing
  subkey. **Signing happens on your computer**, never on the server.
- **Publishing:** the signed archive is copied to the website (`rsync` over
  ssh) and to GitHub Releases or Pages as a mirror. Both serve the same
  signed files, so neither has to be trusted.
- **A `debsway-archive-keyring` package:** holds the public key, in
  `/usr/share/keyrings/debsway-archive-keyring.gpg`.
  - The source line uses `Signed-By:` that file, so the key vouches for
    debsway's repository only, never for Debian's packages.
  - debsway already does this for Anthropic's and Mullvad's repositories,
    with the fingerprint pinned in `pins.sh`; do the same for your own key.
- **Updates:** unattended-upgrades gets an origin line for debsway, so
  security fixes arrive like Debian's. `update.sh` becomes "apt update,
  apt upgrade debsway, then re-run the parts whose files changed". The
  re-run logic stays and reads what changed between the installed versions
  instead of git commits.
- **Fixes for a broken release:** a version number only goes up. To undo a
  bad release, publish a newer one that fixes it.

**What this protects:** whoever controls the web server or the GitHub
account can at most hold updates back, or serve an older signed version.
The archive's `Valid-Until` field limits how long an old version is taken
for current. Set it to about two weeks and re-sign weekly, from a timer on
your own computer.

*Cost:* one session, plus a written checklist for signing and publishing.

---

## Phase 3: the website on a VPS

The site and the repository are static files: no CMS, no PHP, no database.
There's nothing to break into but ssh and the web server.

1. **The server:** Debian stable, minimal.
   - ssh with keys only, no root login, and a non-standard port if you like
     (that only cuts down log noise).
   - unattended-upgrades, the firewall open for 22, 80 and 443 only.
   - debsway's sshd settings (`extras/remote-access.sh`) are a good start.
2. **The web server:** Caddy (automatic HTTPS) or nginx with Let's Encrypt.
   - HTTPS only, HSTS, and a strict Content-Security-Policy, since a static
     site needs no scripts from elsewhere.
3. **DNS:** a registrar that supports DNSSEC; turn it on.
   - CAA records naming your certificate authority only.
   - A domain that doesn't depend on any one free service.
4. **Content:**
   - What debsway is, the threat model in plain words, screenshots.
   - Install steps, and verification steps: check the ISO's checksum, and
     the checksum file's signature with your key's fingerprint.
   - Release notes, and the security contact.
   - The apt repository under `/debian/`.
5. **An onion mirror:** debsway already has `extras/onion-site.sh`. The
   same signed files over Tor cost almost nothing and suit debsway's users.
6. **Backups and monitoring:** a copy of the site comes from the repository
   itself (it is rebuilt from files you keep). Set up an uptime check, and
   an alert when a certificate is about to expire.

*Cost:* one session to set up, a little upkeep a month.

---

## Phase 4: the installer image (ISO)

The aim: boot the ISO, answer a few questions, and end with Debian 13 and
debsway's base on an encrypted disk.

- **Build on Debian's own installer:** debian-installer with a preseed file
  (answers built in), packed with `simple-cdd` or by repacking Debian's
  netinst ISO. debsway already has `prep/make-install-iso.sh` (a preseeded
  install from Debian's live image) and an offline install path to start from.
- **The preseed:**
  - Encrypted LVM as the default, and the debsway repository and its key.
  - A late command that installs the `debsway` package and runs the base at
    first login, as the user, since parts need a user session.
- **Secure Boot:** keep Debian's own signed shim, GRUB and kernel; never
  build your own kernel. Secure Boot then works as on Debian.
- **Releases:** publish the ISO with `SHA256SUMS` and `SHA256SUMS.sign`
  (signed with your key), checked by the steps on the website. Build it
  reproducibly from a tagged release.
- **Testing:** install it in a VM for every release (debsway's QEMU tooling
  from claude-vm can drive that), once with UEFI and once with Secure Boot.

*Cost:* two to three sessions, and the most testing of any phase.

---

## Phase 5: DistroWatch

Read DistroWatch's own submission page for its current rules. A new
project goes onto a waiting list and is looked at after some time. What
counts:
- an installable ISO;
- a website with a download page;
- release notes;
- a project that keeps going (regular releases matter more than many
  features).

Have Phases 1 to 4 done and a second release out before you submit. Then
add the listing's details (based on Debian stable, desktop sway, init
systemd, architecture amd64).

---

## Ongoing: keeping a distribution safe

- **Releases:** every release is a signed tag, a reproducible package, a
  re-signed repository, and an ISO when the installer changes.
- **Debian:** follow Debian's security announcements. debsway's own
  packages are scripts, so Debian's fixes reach users through Debian's
  repository as today.
- **The key:** rotate the signing subkey every year or two (the primary
  key stays). Keep the revocation certificate somewhere separate.
- **One topic per change, tests first:** the rules in `CLAUDE.md` scale as
  they are.

---

## Effort, in working sessions

| Phase | What | Sessions |
|---|---|---|
| 0 | Name, versions, key, security contact | (yours, offline) |
| 1a | `debsway install NAME`, completion, docs moved to it | 1 |
| 1b | Location-independent scripts | ½ |
| 1c | The `.deb` package, lintian-clean | 1–2 |
| 1d | Clean builds, CI | ½ |
| 2 | Signed apt repository, keyring package, apt-based update | 1 |
| 3 | VPS and website | 1 |
| 4 | Installer ISO, tested in VMs | 2–3 |
| 5 | DistroWatch submission | (yours) |

Seven to nine sessions in all. **Start with 1a:** it is useful at once, and
it is what every later step stands on.
