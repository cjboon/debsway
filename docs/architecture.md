# How Wren Linux fits together

A map for people reading or changing the code. To use Wren Linux, start with
[first-time.md](first-time.md). To change it, [CONTRIBUTING.md](../CONTRIBUTING.md) has
the steps.

Wren Linux isn't a distribution. It's scripts run on an ordinary Debian 13. What it does
is what the scripts do, and you can read them.

## From a bare Debian to a desktop

```
start.sh               from the stick: copies Wren Linux home, gets online if needed
  └ install-base.sh    explains, asks, then installs:
      ├ packages.sh    PKGS: the core packages. PARTS: the parts, and their order
      ├ parts/*.sh     one script per piece: firewall, lock screen, kernel settings...
      └ install-extras.sh    the checklist of optional programs
          └ extras/*.sh      one script per program
```

Every script can also be run by itself, as `bash extras/w3m.sh` or `wrenctl install w3m`.
That's on purpose: running one again is how it gets repaired, and how an update reaches
your computer.

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
2. **A user of its own**, for programs that need the network. The sandboxed Firefox, `incognito`,
   `yt-dlp` and Claude's user each get a user with no password and no access to your home. The
   pieces repeat from one to the next:
   - a **session script** (`bin/*-session`) installed root's, in `/usr/local/libexec`, so that
     user can't change it
   - a **sudo rule** that lets you run exactly that one script as that user
   - a **firewall rule** on that user that keeps it off your network (`data/*-firewall.nft`)
   - a **check** that the rule is really there, seen from that user's side, before it starts
     and while it runs (`bin/sandbox-net-check`). A sandbox whose firewall is gone doesn't run.
   - a **restricted Wayland socket** (`bin/wayland-restrict`), so it can't read your screen or type
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

`update.sh` runs on each computer. It fetches what's new and shows it. With a key pinned, it
brings in a change only if the newest commit has a good signature from that key, checked with the
pin in the copy you already have, never one that came with the change. It then works out which
scripts you have set up use files that changed, and offers to run those again. Pulling alone
installs nothing.

GitHub's rules only limit who may update `main`. They don't check signatures: `update.sh` does.

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
