# From scripts to a distribution: the plan

## In short

1. Decide the name (done: Wren Linux, command `wrenctl`), and make an
   offline signing key (`wrenctl install signing-key`, then `wren-key`).
2. `wrenctl install NAME`, with Tab completion. (Done.)
3. A `.deb` that installs Wren Linux root-owned in `/usr/share/wren`. (Done.)
4. A signed apt repository. Signing happens on your own computer, so a
   broken-into VPS can't forge updates. (The tools are done:
   `tools/make-apt-repo.sh`, `parts/wren-repo.sh`, and `update.sh` for the
   package. They wait for the key and an address.)
5. A static website on a hardened VPS, with an onion mirror.
6. An installer ISO, built on Debian's own installer and signed shim.
7. DistroWatch.

About seven to nine working sessions in all. Start with step 2: it is useful
at once, and everything later builds on it.

**Where it stands (2026-11-06):** steps 1 to 3 are done, and the tools for steps 4 to 6:
the key is pinned and `update.sh` takes only what it signed, the site and its server have
their scripts, an install image builds, and releases and their images are one command each
("Making a release" in `docs/maintaining.md`). What waits: a full install tried start to end, the
server and the repository's address, then real releases, and an outside review before
people at risk are pointed at it. A second release, then DistroWatch.

---

Where Wren Linux is now, where it could go, and the order that gets there with
the least rework, without loosening any security Wren Linux already gives.

**Now:** a git checkout in `~/wren`, run as you, with root steps through
sudo. 32 base parts, 47 extras, 62 test scripts, about 360 files, MIT licensed.
`update.sh` pulls from GitHub and re-runs what changed.

**The goal:**
1. A Debian package (`.deb`) that installs Wren Linux root-owned.
2. A signed apt repository that delivers its updates.
3. An installer image (ISO) that installs Debian and Wren Linux in one go.
4. A website that hosts all of that.
5. A DistroWatch listing.

Each phase below stands on its own: Wren Linux gets safer at every step, even
if the next one waits.

---

## Why this order

- **The package comes first.** It is what everything else delivers: the
  repository serves it and the ISO installs it. It also closes the biggest
  gap in the current design: today `update.sh` runs, with sudo, whatever
  arrives from GitHub. Whoever takes over the GitHub account, or a machine
  on the way, decides what runs as root on every Wren Linux computer. A signed
  package checked by apt with your key moves that trust from GitHub to a key
  you hold.
- **The website comes after the repository.** The website only hosts
  signed files. A broken-into web server should be able to stop updates,
  never forge them.
- **The ISO comes last.** It is the most work and adds the least security.
  It's mostly convenience, plus DistroWatch's expectations.

---

## Phase 0: decisions to make first (an hour, no code)

1. **Name.** Decided: **Wren Linux** (it was debsway), with `wrenctl` as its
   command; `wren-` and `wren_` in its internal names, `wren-linux` as its
   package. Quiet on a boot screen, for people a border agent may look at.
   There is a small programming language called Wren (its command is `wren`,
   so the distribution's isn't); always say "Wren Linux", and give the key's
   fingerprint wherever people find the download, so a look-alike site can't
   pass. Still to do:
   - (Done: the GitHub repository is cjboon/wren-linux.)
   - Read Debian's trademark policy (debian.org/trademark). The word
     "Debian" is what it protects; "Wren Linux" doesn't use it.
   - Write "based on Debian, not affiliated with or endorsed by the Debian
     project" in the README and on the website.
   - If unsure, ask trademark@debian.org.
   - Check that no other project uses the name.
2. **Version scheme.** For example `2026.11` (year.month), tied to Debian
   stable (`13` now). Every release is a signed git tag.
3. **The signing key.** One OpenPGP key that signs the repository and the
   ISO checksums. It is the most valuable thing in the project.
   - Make it on an offline machine, or at least a fresh Wren Linux user. Keep
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
5. **The project's identity, apart from yours.** The maintainer is public (the
   git history names them), and that can't be undone. So the danger isn't
   being found, it is being made to sign: whoever holds the key can be
   pressured, threatened or legally compelled to publish a bad update, and for
   people who use Wren Linux against a government that is the cheapest attack.
   Make the project its own thing, so that pressure has less to grip:
   - **A project address, not yours**, on the key, the website and the
     security contact: say "<name> signing key <security@project-domain>".
     Every signature carries the key's name and email, for good.
   - **A project account** on the git host (an organization), and no personal
     address in new commits (GitHub's "keep my email addresses private").
   - **Write down now what happens if you are pressured**: you won't sign a
     backdoor; you would rather stop publishing, and say so, than publish one.
     Say it publicly in `SECURITY.md`, so a demand to sign is also a demand to
     break a public promise.
   - **Make a forced backdoor easy to see.** Builds are already reproducible:
     anyone can rebuild a release from its tag and compare. Keep it that way,
     and ask a few people to check each release (see Ongoing).

---

## Phase 1: Wren Linux as a Debian package

The repository stays your workshop in `~/wren`: you edit and test there
as now. Installed systems get a built package instead.

### 1a. One command, `wrenctl`, in front of everything (done)

The `wrenctl` command already exists (the menu, `--apps`, `--update`).
Extend it before anything moves, so the docs can switch to it early:

```
wrenctl install NAME      runs extras/NAME.sh       (Tab lists the extras)
wrenctl remove NAME       runs extras/NAME.sh --remove
wrenctl manual NAME       runs extras/NAME.sh --manual
wrenctl list              the extras: installed or not, with their summary
wrenctl status            status.sh
wrenctl update            update.sh (later: apt, see Phase 2)
wrenctl part NAME         re-runs one base part
```

- **Arguments:** checked against the list of extras by exact name only, so
  nothing else is ever run.
- **Tab completion:** a bash-completion file that lists the extras.
- **The hints:** the command hints (`parts/command-hints.sh`) then say
  `wrenctl install claude-vm` instead of a path.
- **Docs and tests:** change the docs from `bash ~/wren/extras/X.sh` to
  `wrenctl install X` (about 170 places, mechanical), and update the man
  page and its test.

*Cost:* one session. *Security:* none lost, and from here on the docs don't
depend on where Wren Linux lives.

### 1b. Make every script work from wherever it is installed (done)

Done: the commands look for `WREN_DIR`, then a root-owned
`/usr/share/wren`, then `~/wren`; messages say `wrenctl install NAME`
or name the folder the script runs from; `tools/test-location.sh` checks it.


- **The folder:** `WREN_DIR` is already worked out from where `lib.sh`
  is. Check that nothing assumes `~/wren`: grep for it in the scripts
  (not the docs), and route it through `WREN_DIR`.
- **What is yours stays in your home:** state in `~/.local/state/wren`,
  settings in `~/.config/wren`, pictures in `~/Pictures`, unchanged.
- **Tests:** they keep running from the checkout (`bash test.sh`); one new
  test runs a few of them from a copy in another folder.

*Cost:* half a session.

### 1c. The package (done)

Done, a little differently from below: `tools/build-deb.sh` builds it with
`dpkg-deb` from a commit, without debhelper (the package is files only, and a
short script is easier to read and to build the same way every time). It has
no install scripts at all. `tools/test-build-deb.sh` checks it; lintian runs
when it is installed. See docs/maintaining.md, "The Wren Linux package".


Build with Debian's own tools: `debhelper` (`dh`), `dpkg-buildpackage`, and
`lintian` to check the result. A `debian/` folder in the repository holds:

- `control`:
  - The package `wren-linux`, Architecture `all` (scripts only).
  - Depends on what every part needs before it runs: bash, sudo, git (for
    now), python3, acl, nftables.
  - The rest stays installed by the parts as now, with apt markers.
- `install`:
  - `parts/ extras/ lib/ data/ bin/ vendor/ *.sh` to `/usr/share/wren/`.
  - The `wrenctl` command to `/usr/bin/wrenctl`.
  - The man page to `/usr/share/man/man1/`.
  - The docs to `/usr/share/doc/wren-linux/`.
  - The completion file to `/usr/share/bash-completion/completions/wrenctl`.
- `changelog`: one entry per release (`dch` writes it).
- `copyright`: MIT, and the vendored `mockvps-kvm` with its own license.
- `rules`: the default `dh $@`. No build step: the files are copied.

Everything in `/usr/share/wren` is root-owned and read-only to you.
Malware running as you can't change a script and wait for you to run it
with sudo.

**What stays the same:** parts still run as you and use sudo for root steps,
and `~/.local/bin` commands are still installed per user by the parts, from
`/usr/share/wren/bin`.

**One open choice:** user commands that are only a launcher (`firefox`,
`incognito`, `wifi-signin`) can move to `/usr/bin` in the package, root-owned
like the sessions. Do that one at a time, each with its test, later.

**Migrating your own machine:**
1. Install the package.
2. Run `wrenctl update`, which re-runs every part from
   `/usr/share/wren`. The new stale-command check in `update.sh` offers
   whatever the new location changed.
3. Keep `~/wren` as your development copy.

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
reprepro), only for Wren Linux's packages, good for 14 days; Debian's own apt
takes it, and refuses it signed with another key, past its Valid-Until or
with a changed package list (`tools/test-apt-repo.sh`). `parts/wren-repo.sh`
adds it on a Wren Linux computer: the pinned key only, and an apt pin so it can
bring nothing but the Wren Linux package (checked with real apt). It changes
nothing until pins.sh names the key and the address. After apt upgrades the
package, `update.sh` runs again the parts whose files changed, from a record of
every file it keeps (no git needed). Still to do: adding the part to the base
list once the repository is live. A separate keyring package isn't needed: the key comes with Wren Linux
itself, checked against the pin.


- **The archive tool:** `reprepro` builds a Debian archive (the `dists/`
  and `pool/` folders) and signs its `InRelease` file with your signing
  subkey. **Signing happens on your computer**, never on the server.
- **Publishing:** the signed archive is copied to the website (`rsync` over
  ssh) and to GitHub Releases or Pages as a mirror. Both serve the same
  signed files, so neither has to be trusted.
- **A `wren-archive-keyring` package:** holds the public key, in
  `/usr/share/keyrings/wren-archive-keyring.gpg`.
  - The source line uses `Signed-By:` that file, so the key vouches for
    Wren Linux's repository only, never for Debian's packages.
  - Wren Linux already does this for Anthropic's and Mullvad's repositories,
    with the fingerprint pinned in `pins.sh`; do the same for your own key.
- **Updates:** unattended-upgrades gets an origin line for Wren Linux, so
  security fixes arrive like Debian's. `update.sh` becomes "apt update,
  apt upgrade Wren Linux, then re-run the parts whose files changed". The
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
   - Wren Linux's sshd settings (`extras/remote-access.sh`) are a good start.
2. **The web server:** Caddy (automatic HTTPS) or nginx with Let's Encrypt.
   - HTTPS only, HSTS, and a strict Content-Security-Policy, since a static
     site needs no scripts from elsewhere.
3. **DNS:** a registrar that supports DNSSEC; turn it on.
   - CAA records naming your certificate authority only.
   - A domain that doesn't depend on any one free service.
   - **The apt repository goes on an onion address (decided):** computers contact it regularly, so
     a rare domain would mark them as Wren Linux's to anyone watching their network.
     `parts/wren-repo.sh` already takes one. So a computer that takes the package needs the
     system Tor running, and a failure to reach it mustn't quietly stop updates.
4. **Content:**
   - What Wren Linux is, the threat model in plain words, screenshots.
   - Install steps, and verification steps: check the ISO's checksum, and
     the checksum file's signature with your key's fingerprint.
   - Release notes, and the security contact.
   - The apt repository under `/debian/`.
5. **An onion mirror:** Wren Linux already has `extras/onion-site.sh`. The
   same signed files over Tor cost almost nothing and suit Wren Linux's users.
6. **Backups and monitoring:** a copy of the site comes from the repository
   itself (it is rebuilt from files you keep). Set up an uptime check, and
   an alert when a certificate is about to expire.

*Cost:* one session to set up, a little upkeep a month.

---

## Phase 4: the installer image (ISO)

The aim: boot the ISO, answer a few questions, and end with Debian 13 and
Wren Linux's base on an encrypted disk.

- **Build on Debian's live standard image:** `prep/make-install-iso.sh` repacks it with a preseed
  file (answers built in), and that's the choice for now. Its list (13.7.0) has `wpasupplicant`,
  `iw`, `dhcpcd` and the Wi-Fi firmware in the system it copies to disk, so `wifi.sh` should get a
  computer online with nothing added: to be tried on a real laptop, with a `--public` image, since
  a personal one carries saved packages that would hide the answer. Netinst (0.8 GB) left a
  Wi-Fi-only install without the standard utilities, and DVD-1 (4 GB) still has no sway or foot,
  so neither makes the base installable offline. If people ask for that, the image could carry the
  base's packages with a list signed by Wren Linux's key (Debian's own go stale in about
  a week), at the cost of packages that age. `simple-cdd` stays an option for full control.
- **The preseed:**
  - Encrypted LVM as the default, and the Wren Linux repository and its key.
  - A late command that installs the `wrenctl` package and runs the base at
    first login, as the user, since parts need a user session.
- **Secure Boot:** keep Debian's own signed shim, GRUB and kernel; never
  build your own kernel. Secure Boot then works as on Debian.
- **Releases:** publish the ISO with `SHA256SUMS` and `SHA256SUMS.sign`
  (signed with your key), checked by the steps on the website. Build it
  reproducibly from a tagged release.
- **Licensing:** an image hands out Debian's programs, many under the GPL, so their source has to be
  offered too, and for those exact versions: a link to Debian's newest won't stay right.
  `tools/publish-image.sh` publishes Debian's source for that image beside it (about 3 GB per
  release, so plan the server's disk). That's a good-faith reading, not legal advice: ask someone
  who knows (the Software Freedom Conservancy helps projects like this) before the first public
  image. The name and wording stay within Debian's trademark policy (debian.org/trademark):
  "Debian" names what it's based on, is never in the product's name, and implies no endorsement.
- **What the image holds:** `make-install-iso.sh --public` has nothing of the builder's on it. Still
  to do: the installer asks the username and time zone, instead of the fixed `user` and UTC.
- **Testing:** install it in a VM for every release (Wren Linux's QEMU tooling
  from claude-vm can drive that), once with UEFI and once with Secure Boot.

*Cost:* two to three sessions, and the most testing of any phase.

### 4b. An amnesic mode for the installed system (planned, after the installer)

A second entry in the boot menu, "Wren Linux (forget this session)": the
installed system starts with its disk read-only and every change in memory
(an overlay, set up by a small initramfs hook), and all of it is gone at power
off. For a risky session: opening an untrusted file, a site you don't trust,
or a laptop carried through a checkpoint, when nothing new may be written to
the disk. An extra, so it is chosen, like the rest.

- It is the installed system, so it has its security updates: nothing goes
  stale.
- It hides nothing already on the disk, and the normal entry writes as usual:
  the threat model must say both.
- Swap stays off in that mode (or it would write memory to the disk).
- Tested in a VM: a file written in the mode is gone after a reboot, and the
  normal entry still works.

*Cost:* one session.

### 4c. A live Wren Linux (considered, not now)

A "Wren Linux Live" boot entry on the stick, Tails' way: started from the
stick, everything in memory, gone at power off, nothing installed. Not now,
for three reasons:

- **It goes stale.** A live system forgets its updates too: every boot runs
  the packages of the day the stick was made, holes and all. Tails puts out a
  new image about every month; that is a release cycle of its own, too much
  for one maintainer now.
- **It would be taken for Tails, and isn't.** Tails sends everything through
  Tor and has years of audits; a Wren Live would forget, not hide your
  network. For people who need both, `tails-usb` already makes the stronger
  tool easy to get, and mixing the two up could hurt someone.
- **It is a lot to build and keep working** (live-build, a root chroot, the
  base set up inside the image, its own VM tests), for what Tails does better.

Not "install it fresh at every boot" either: that downloads packages each
time (slow, impossible offline, and visible to the network). Revisit if
people who use Wren Linux ask for it and someone can rebuild the image
often; the amnesic mode (4b) covers much of the same need meanwhile.

### 4d. Tor first (an idea, not a plan)

Worth looking at again some day, as a choice at install. It isn't the default, and it isn't Tails:
it could say your network can't see what you install, not that you are anonymous.

Snowflake needs no line from you, so it could make the first connection. Over Tor, `lyrebird` then
comes from the Tor Project's repository and you get a webtunnel line (a CAPTCHA, by hand: the Tor
Project guards bridges against collection, and Wren Linux shouldn't get around that). Tor then
switches to webtunnel, with Snowflake as its fallback, for apt and whatever else takes Tor.

What stands in the way:

- **"Nothing connects first" needs a firewall from the first boot,** and plain NTP (`parts/clock.sh`)
  has to wait, though Tor needs a roughly right clock to connect. Wi-Fi and DHCP can't be hidden.
- **The first moment still looks like Snowflake.** Someone in a risky place should bring a webtunnel
  line from another device instead.
- **A dead bridge mustn't quietly stop security updates,** so it needs a warning.
- **Other things go direct today:** other apt repositories, and what's fetched with `wget`.
- **webtunnel is still experimental** here, and has yet to be tried with a real bridge.
- **It doesn't hide traffic patterns.** Mullvad's DAITA does that with Maybenot (open source), but
  that needs both ends, and a Wren Linux-only pattern would make its users easier to spot: it belongs
  in Tor itself, if and when Tor ships it.

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

- **More than one signer, as soon as there is a second maintainer.** One key
  held by one person is one person to coerce. With two or more maintainers:
  each keeps their own key; a release needs signatures from at least two of
  them (update.sh and the apt repository then check for that); and each
  release is rebuilt and compared by someone other than the one who built it.
  Then forcing one person isn't enough to reach users.

- **Releases:** every release is a signed tag, a reproducible package, a
  re-signed repository, and an ISO when the installer changes.
- **Debian:** follow Debian's security announcements. Wren Linux's own
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
| 1a | `wrenctl install NAME`, completion, docs moved to it | 1 |
| 1b | Location-independent scripts | ½ |
| 1c | The `.deb` package, lintian-clean | 1–2 |
| 1d | Clean builds, CI | ½ |
| 2 | Signed apt repository, keyring package, apt-based update | 1 |
| 3 | VPS and website | 1 |
| 4 | Installer ISO, tested in VMs | 2–3 |
| 5 | DistroWatch submission | (yours) |

Seven to nine sessions in all. **Start with 1a:** it is useful at once, and
it is what every later step stands on.
