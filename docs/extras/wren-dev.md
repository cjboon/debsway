# Tools for working on Wren Linux (`extras/wren-dev.sh`)

## SYNOPSIS

```
wrenctl install wren-dev                     install them
wrenctl remove wren-dev                      remove them (shellcheck stays while the Claude Code sandbox uses it)
wrenctl manual wren-dev                      print the manual steps below

bash test.sh                   in ~/wren-linux: every check, shellcheck on every script included
bash extras/signing-key.sh     the key to sign Wren Linux with, if you publish it
wren-release --username        change the GitHub username it pushes as (it asks once, and remembers)
wren-release                   from any folder: publish, then install here (--local: install only)
bash tools/git-push.sh         publish: signs, checks, asks, pushes
bash tools/build-deb.sh        build the package; lintian checks it
lintian FILE.deb               check any package
shellcheck SCRIPT              check one script
```

For the computer where you work on Wren Linux and build its package: `lintian`,
Debian's own checker for packages, which `tools/build-deb.sh` runs on every
package it builds, and `shellcheck`, which `test.sh` runs on every script.
Both come from Debian. They aren't in the base install: lintian brings over a
hundred packages (mostly Perl), and every other Wren Linux computer is better
off without code it never uses. It also gets you a git copy of Wren Linux in
`~/wren-linux`, unless you are in one or have one there: the package leaves out the
tests (`tools/`), the build tools, `docs/maintaining.md`, `docs/distro-plan.md` and
the signing key's tools, which only someone working on Wren Linux uses. It is fetched
from `@WREN_GIT_URL@`, and checked against Wren Linux's key once one is pinned.

## LIMITS

- lintian and shellcheck point out mistakes they know about; a package or script they pass can still be wrong or unsafe.
- lintian unpacks the packages it checks: check only packages you built or trust.
- Until a signing key is pinned, the copy is what the server gives you: read it before you run it.

## MANUAL INSTALL

```
# lintian and shellcheck, from Debian
sudo apt install --no-install-recommends lintian shellcheck git
# A copy of Wren Linux to work on, unless you have one
git clone @WREN_GIT_URL@ ~/wren-linux
# wren-release, to publish and install from any folder
printf '#!/bin/bash\nexec bash ~/wren-linux/tools/release.sh "$@"\n' >~/.local/bin/wren-release
chmod +x ~/.local/bin/wren-release
```

To undo:

```
# lintian goes; shellcheck is marked automatic, so apt removes it once nothing
# else needs it (the Claude Code sandbox installs it too)
sudo apt purge lintian
sudo apt-mark auto shellcheck
sudo apt autoremove --purge
rm ~/.local/bin/wren-release
```
