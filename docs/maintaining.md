# Keeping it working

Things outside Wren Linux change: download pages move, signing keys are
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
  uses: the script itself, every `"$WREN_DIR/bin|data|vendor|lib/..."` it
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

## Signing Wren Linux's commits

`update.sh` runs what it brings in, with sudo. To make sure it is yours, sign
your commits and pin the key: from then on every Wren Linux computer brings in a
change only when the newest commit carries a good signature from that key
(`update_signed` in `lib/update.sh`, tested by `tools/test-update-signed.sh`
with throwaway keys). One signed commit on top vouches for everything under
it, since each commit's id covers the ones before it.

To publish, use `bash tools/git-push.sh`: it sets up signing and the pin the first
time, says what CI thinks of the commit and asks first if CI failed or hasn't finished (GitHub
doesn't enforce this, since a signed commit on top hasn't been through CI, and so that an outage
can't hold back a fix), signs the newest commit if it isn't (with an empty commit on top), checks that
signature as a computer updating would, and asks before it pushes. Computers with
the pin refuse an update whose newest commit isn't signed.

The easy way to make the key: `bash extras/signing-key.sh` in a git copy (the package leaves it out; `wrenctl install wren-dev` gets a copy), then `wren-key` with a USB
stick mounted. Its first run explains and asks, makes the key in two parts
(a primary key that only certifies, in an encrypted backup on the stick and
nowhere else; and a signing subkey, kept here by its own user with no network,
that your own user can't read), and offers to set git up to sign every commit
and to pin the key. Then commit what `wren-key pin` changed, signed, and
push it: computers that update to it take it unchecked (their copy has no pin
yet); every update after that is checked. On a new computer, or after
reinstalling, don't make a second key: `wren-key restore BACKUP` takes it
from the backup on your stick. `man wren-key` and
[extras/signing-key.md](extras/signing-key.md) have the rest, the steps by
hand included. In short, by hand:

1. Make the key on a computer you trust, best one that is offline: a primary
   key that only certifies, and a signing subkey for every day.
   `gpg --quick-generate-key "Wren Linux signing key <you@example.org>" ed25519 cert never`,
   then `gpg --quick-add-key FINGERPRINT ed25519 sign 2y`.
   Keep a revocation certificate and a backup of the primary key apart from
   the computer (an encrypted stick, and on paper with `paperkey`).
2. Put the public half in the repository and pin the **primary** key's
   fingerprint (a signature by a subkey counts for its primary key, so the
   subkey can be renewed or replaced without a new pin):
   `gpg --export --armor FINGERPRINT >data/wren-signing-key.asc`, and
   `WREN_SIGNING_FPR=FINGERPRINT` in `pins.sh`. `bash test.sh` checks the
   file is exactly that key and can still sign.
3. Sign from then on: `git config commit.gpgsign true` and
   `git config user.signingkey FINGERPRINT` in `~/wren`. Check one with
   `git log --show-signature -1`.
4. Commit and push all of this as one signed commit.

A new subkey, or a renewed one (`wren-key renew BACKUP`): export the key
again into `data/wren-signing-key.asc` (`wren-key pin`) and commit that
with the old subkey's signature, before it expires. A key that has
expired or been revoked fails the check, and updates stop until a copy with
the new key is brought in by hand.

## Trying it for real

Tests with pretend programs show what you believed the real ones do, and have passed over real
bugs. These need a throwaway computer or VM, and root, and have caught what they missed:

- **A DHCP client:** in network namespaces, joined by a veth pair, with `dnsmasq --log-dhcp` as the
  server, whose log says what each client sent. Give the client a fresh `/run` and `/var/lib`
  (`unshare -m`), and `/etc/netns/NAME/resolv.conf` so the real one isn't touched: dhcpcd's control
  socket isn't per namespace, so don't stop one by name.
- **NetworkManager:** in a privileged container (`podman run --privileged`), with dbus and udev running,
  on a veth it's told to manage, since it leaves those alone by default.
- **Whonix:** unpack the real image, boot a qcow2 overlay of it with QEMU, and over QMP press
  its power button (`system_powerdown`) and take screenshots (`screendump`). Your user needs
  the `kvm` group. Check the disk with `debugfs -R features` and `e2fsck -fn` once it's off.
- **A window:** a headless sway (`WLR_BACKENDS=headless WLR_RENDERER=pixman`), asked for its windows
  with `swaymsg -t get_tree`.
- **CI's own steps:** `.github/workflows/shellcheck.yml` run by hand, in a Debian 13 container.

And run a command as a normal user: `/usr/sbin` isn't on that `PATH`, which testing as root hides.

## Making a release

A release is a signed tag on what's already published. Its name is the year and month
(`2026.11`, then `2026.11.1`), and its message is the release notes.

```bash
wren-release --tag                 # publish, mark it as a release, install it here
bash tools/tag-release.sh          # only mark what's already published
bash tools/publish-image.sh        # its install image, signed, on the server
```

`tag-release.sh` writes the notes from the commits since the last release, for you to edit,
signs the tag, checks it with the pinned key alone, and asks before pushing. Write the notes
for people who use Wren Linux: what changed for them, and what they should do.

`publish-image.sh` needs a commit with such a tag. It builds with
`make-install-iso.sh --public`, which puts nothing of this computer's on the image, signs
`SHA256SUMS`, checks that, and copies them to `/srv/wren-images/VERSION` on the server, as
`images/VERSION/` on the site, beside `RELEASE-NOTES.txt`. It never replaces what's there.

The image hands out Debian's programs, many under the GPL, which asks that their source be offered
too. So Debian's source for that exact image goes beside it (about 3 GB), checked against Debian's
signed list, with a `SOURCE.txt`, and without it nothing is published. Keep each image's source
up for as long as the image is. This is a good-faith reading of the licence, not legal advice.

A server set up before this needs `setup-vps.sh` run again for that folder.

Neither can run by itself. The key signs only after your sudo password, on purpose: a script
that could sign alone means anything running as you could too.

The package's version still comes from its commit (`0~git...`), so a later commit always
sorts higher, whether or not it's a release. The image isn't built byte for byte the same
twice: anyone can rebuild the package on it and compare, but only check the image's signature.

## The Wren Linux package

`bash tools/build-deb.sh` builds `wren-linux_VERSION_all.deb` from a commit
(`--commit REV`, by default HEAD; never from files that aren't committed).
`--version` sets the version; without it the version is `0~git`, the commit's
time and its id, so a later commit always has a higher version. `tools/test-build-deb.sh` checks it.

- **What it installs:** the scripts in `/usr/share/wren`, owned by root and
  writable by no one else; the `wrenctl` command in `/usr/bin`; its man page and
  Tab completion; the licenses. Nothing outside `/usr`, nothing setuid.
- **What it runs when installed:** nothing. It has no install scripts, so
  installing it changes no setting. The desktop is set up as before, as you:
  `wrenctl part NAME`, `wrenctl install NAME`, `bash /usr/share/wren/install-base.sh`.
- **Why:** with the scripts root's, a program running as you can no longer
  change one and wait for you to run it with sudo. The `wrenctl` command uses
  `/usr/share/wren` whenever it is there (`WREN_DIR=~/wren wrenctl ...`
  uses your own copy instead).
- **The same file every time:** every date in it is the commit's, so two builds
  of one commit are the same, byte for byte; the build prints the SHA-256.
  Publish that next to the package: anyone can build it again and compare.
- **lintian** checks it when installed (`wrenctl install wren-dev`); it isn't
  needed to build. Debian's debhelper isn't used: the package is files only,
  and `dpkg-deb` with a short script is easier to read and to build the same
  way every time.

On the computer you publish from, `wren-release` (or `bash tools/release.sh`) does it all, stopping at the
first step that fails: `git-push.sh`, the package in a new private folder, `sudo apt
install` of that one file, `wrenctl --update`. `--local` installs the last commit
without pushing. Don't build into `/tmp` and install by a wildcard: every user can
write there, the sandboxes' too, and apt installs as root.

Install it on another computer with `sudo apt install ./wren-linux_VERSION_all.deb`.
apt brings a newer one (the same way, or from the signed apt repository
below); `wrenctl update` then runs again the parts and extras whose files
changed, as it does for a git copy. Without git it compares the files with a
record it keeps after each run (`~/.local/state/wren/applied-files`, and a
copy of `pins.sh`); the first run takes what is set up as up to date
(`wrenctl update --all` offers everything). `tools/test-update-package.sh`
checks it.

## The signed apt repository

`bash tools/make-apt-repo.sh --key FINGERPRINT --out FOLDER wren-linux_*.deb`
makes an apt repository (`pool/`, `dists/trixie/`) of Wren Linux's packages and
signs it, on your own computer, with your key (the pinned `WREN_SIGNING_FPR`
once it is set; gpg asks for the passphrase or the token). Upload FOLDER as it
is to any web server or mirror (`rsync -a --delete FOLDER/ server:/var/www/debian/`);
`tools/test-apt-repo.sh` checks it with throwaway keys and Debian's own apt.

- **The server can't change a package.** apt checks every file against
  `InRelease`, and `InRelease` against your key. Whoever runs the server can
  only hold updates back.
- **Nor serve an old one for long:** `InRelease` is good for 14 days
  (`--valid-days N`, 1 to 90), after which apt refuses the repository. Sign it
  again within that time, even when nothing changed.
- **Only Wren Linux's packages** go in (`wren-linux` and `wren-*`); the script
  refuses anything else.

On a Wren Linux computer, `wrenctl part wren-repo` adds it, once `pins.sh`
names both the key (`WREN_SIGNING_FPR`) and the address
(`WREN_REPO_URL`, https:// or an .onion address); until then it changes
nothing. The key comes from the copy's own `data/wren-signing-key.asc`,
only if it is exactly the pinned one, and is trusted for that repository
alone (`Signed-By`). An apt pin lets only the package `wren-linux` come from it,
so even someone with your key or the server couldn't replace a Debian package
or add another (`tools/test-wren-repo.sh` checks the pin with Debian's own
apt). unattended-upgrades then installs Wren Linux's updates like Debian's. It
is not in the base list yet: add it to `PARTS` in `packages.sh` once the
repository is live.

## The website

`site/` is the website, plain HTML with no JavaScript, and `tools/build-site.sh`
builds it from one commit, with a browsable copy of every file
(`bash tools/build-site.sh --preview` builds this copy's pages, committed or
not, into `~/Downloads/wren-site-preview` and opens them in the sandboxed
Firefox; the server's headers are seen only on the test VM). `tools/setup-vps.sh` sets up the server,
`tools/publish-site.sh` puts the site and the git mirror on it from a signed
commit only, and `tools/try-vps.sh` tries it all in a local VM first: see
[vps.md](vps.md).

## Other scripts

- `prep/setup-sudo.sh USER` (as root): installs sudo and adds USER to the
  sudo group.
- `status.sh`: what's installed, the Firefox hardening, sway snippets,
  how each Wi-Fi device is set up, and a warning if `/`, `/home` or swap
  isn't encrypted.
- `prep/make-install-iso.sh`: an automatic Debian 13 install image with Wren Linux
  on it (see the README, "Before you reinstall"). What runs inside the
  installer is `data/install-iso-*`; `tools/test-install-iso.sh` checks it.
  `tools/try-install-iso.sh` installs from a built image in a throwaway QEMU VM.
- `prep/fetch-offline-debs.sh`, `prep/fetch-tor-browser.sh`: download
  things you need before a reinstall (see the README).
- `tools/pack-usb.sh /path/to/stick`: puts the last commit and `offline/`
  on a stick, without personal files, labels the stick `WREN` (only a
  removable drive, and it asks first) and writes `START-HERE.txt`.
- `start.sh`: what a user runs from the stick on a fresh install
  (`sudo mount -L WREN /mnt && bash /mnt/wren/start.sh`).
