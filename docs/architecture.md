# How Wren Linux fits together

A map for people reading or changing the code. To use Wren Linux, start with
[first-time.md](first-time.md). To change it, [CONTRIBUTING.md](../CONTRIBUTING.md) has
the steps.

Wren Linux isn't a distribution. It's scripts run on an ordinary Debian 13. What it does
is what the scripts do, and you can read them.

## From a bare Debian to a desktop

```
start.sh               from the stick: copies Wren Linux home, gets online if needed (wifi.sh)
  └ install-base.sh    explains and asks (prep/intro.sh), then, in this order:
      1. the list of extras: you choose now, and they install at the end
      2. offers apt over Tor, before anything is downloaded
      3. packages.sh's PKGS, then sway's config, the bar and the keys
      4. packages.sh's PARTS, one script each, in that order
      5. the extras you chose (install-extras.sh --install)
```

Every script can also be run by itself, as `bash extras/w3m.sh` or `wrenctl install w3m`.
That's on purpose: running one again is how it gets repaired, and how an update reaches
your computer. A part that needs hardware this computer lacks skips itself during the base
install (`skip_unless`), but always installs when you run it by hand.

## Two ways Wren Linux is on a computer

- **A git copy**, as `~/wren` from a stick, or `~/wren-linux` from `wrenctl install wren-dev`. It's
  yours to change, and it has the tests and build tools.
- **The package**, root's and read-only, in `/usr/share/wren` (`tools/build-deb.sh`). A program running
  as you can't change these scripts to wait for your password. It has no install scripts,
  leaves out `tools/` and the signing key's tools, and the same commit always builds the same file,
  so anyone can check a published package against the source.

Scripts find their files through `WREN_DIR`, so they work from either. Saved downloads go to
`offline/` in a copy you can write to, or to `~/.local/share/wren/offline` from the package.

## The promises every script keeps

- **Run it again, and it repairs.** It never assumes a clean start.
- **`--remove` undoes it.** Packages another script still needs stay.
- **An extra's `--manual` prints the steps by hand**, from its page in `docs/extras/`.
- **Nothing from outside Debian is used before it's checked** against a key in `pins.sh`.

Tests check these: `tools/test-manual.sh` for the pages, `tools/test-apt-markers.sh` for
what `--remove` takes out.

## Shared code

`lib.sh` is sourced by every script. It sets `set -euo pipefail` and a fixed `PATH`, finds
`WREN_DIR`, and loads:

| File | What it gives you |
| --- | --- |
| `pins.sh` | every trusted key and outside version, each with the date it was checked |
| `lib/core.sh` | `say`, `note`, `warn`, `die`, `ask`, `need_user`, `install_bin`, `printable` |
| `lib/apt.sh` | `apt_install`, `apt_purge` |
| `lib/sway.sh` | sway config snippets |
| `lib/net.sh`, `lib/tor.sh`, `lib/mime.sh` | networking, Tor and bridges, default apps |

Other helpers in `lib/` are sourced only by the scripts that need them, such as
`lib/appimage.sh` for signature checks.

**How `--remove` knows what to take out.** `apt_install` doesn't just install packages. It
builds a small empty package named after the script (`wren-w3m`) that depends on them. Removing
that package lets apt take out what nothing else needs, so two extras can share a package safely.

**Why scripts run as you.** Most run as your normal user (`need_user`) and use `sudo` for each
system change. Files in your home come from `install_bin`, which puts `bin/NAME` into
`~/.local/bin`.

## How risky programs are kept apart

This is the pattern behind most of the [threat model](../THREAT-MODEL.md). The stronger the
wall, the further down this list:

1. **bubblewrap**, for files you open. `imv`, `mpv`, `zathura` and GIMP run with only what they need.
   See `bin/media-sandbox`.
2. **A user of its own**, for programs that need the network. The sandboxed Firefox (and one user per
   profile), `incognito`, `yt-dlp` and Claude's user each get a system user with no password, no login
   and no access to your home. The pieces repeat from one to the next. `extras/firefox-sandbox.sh`,
   `lib/firefox-sandbox.sh` and `bin/firefox-session` are the fullest example:
   - a **session script** (`bin/*-session`) installed root's, in `/usr/local/libexec`, so that user
     can't change it. It treats its arguments as coming from someone it doesn't trust, and accepts
     only what it expects.
   - a **sudo rule** that lets you run exactly that one script as that user, checked with `visudo`
     before it's installed, since a broken one would lock you out of sudo
   - a **firewall rule** on that user (`data/*-firewall.nft`) that keeps it off this computer and your
     network. It may send DNS only to the resolver this computer uses (`parts/sandbox-dns.sh`).
   - a **check that the rule is really there** (`bin/sandbox-net-check`), because a service saying
     "active" isn't enough: anything that runs "flush ruleset" takes the rule away and leaves
     the service active. Running as that user, it connects to a closed port here. The rule makes
     that "no route", and without the rule it would be "refused". The session runs this before it
     starts, then every 5 seconds, and ends every process of that user if the rule goes.
   - a **restricted Wayland socket** (`bin/wayland-restrict`), so it can't read your screen or type,
     and no way to X11's abstract socket (`bin/no-abstract-sockets`, with Landlock)
3. **A VM**, where a kernel bug must not reach you. `claude-vm` is QEMU under its own user, built on
   `vendor/mockvps-kvm`, with no shared folder. Whonix's two VMs run under libvirt as you.

## Updates and releases

Getting changes to a computer is where a project like this could hurt people most, so
it's worth knowing:

```
tools/release.sh         publish, and install here
  ├ tools/git-push.sh    signs on top of what's new, checks it, asks, pushes main
  ├ tools/build-deb.sh   the package, from that commit
  └ wrenctl --update     runs update.sh
```

`git-push.sh` signs with an empty commit on top, when the newest commit isn't signed. Since each
commit's id covers the ones before it, that one signature vouches for everything below it.

`update.sh` runs on each computer. In a git copy, it fetches what's new and shows it. With a key
pinned, it brings in a change only if the newest commit has a good signature from that key, checked
with the key and pin in the copy you already have, never ones that came with the change. It only
fast-forwards, so it can't overwrite your own changes. In the package's copy, apt brings what's new
instead (`parts/wren-repo.sh`, where the repository's key can't replace a Debian package), and
`update.sh` compares against its record of every file.

Either way, it then works out which scripts you have set up use files that changed (`lib/update.sh`:
the script, the `bin/`, `data/`, `vendor/` and `lib/` files it names, the `pins.sh` lines it uses, and
its `# files:` line), and offers to run those again. Bringing a change in installs nothing by itself.
A retired extra isn't run again: `update.sh` offers its `--remove`.

GitHub's rules only limit who may update `main`. They don't check signatures: `update.sh` does.

## DNS

Worth a look, since much depends on it. `parts/secure-dns.sh` sends every lookup to Unbound on this
computer, which checks DNSSEC and asks one resolver you chose over TLS. It fails closed: a firewall
rule lets only Unbound send DNS out. It has a switch, for Wi-Fi sign-in pages, and your user may flip
that without a password (`THREAT-MODEL.md` says what that means). `/etc/resolv.conf` is the one place
that says which is on: a Firefox session reads it at start to decide about its own encrypted DNS,
and a path unit refills the sandboxes' resolver sets when it changes.

## The website

`tools/build-site.sh` makes the site from one commit: the pages in `site/`, plus a browsable
copy of every file in the repository. It's plain HTML with no JavaScript and no cookies, so it
works in Tor Browser's Safest mode. Since the source is most of the site, the code and these docs
are also what visitors read.

## Tests

`test.sh` runs everything, and `--offline` skips what needs the network. Each `tools/test-NAME.sh`
copies the idea of the real thing into a temp folder:

- **Pretend programs** come first on the `PATH`, and write down how they were called. Tests check
  those calls, and what the script said.
- **Real ones are used where it matters:** real `nft` rules in a network namespace, real disk images
  with `debugfs`, a headless sway, real signatures with throwaway keys.

A pretend program only shows what you believed the real one does. The launcher in `bin/whonix`
once hung on a real desktop while its tests passed, because the pretend `virt-manager` returned
at once and the real one didn't. So say what ran for real, and write down what hasn't.
