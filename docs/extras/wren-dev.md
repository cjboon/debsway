# Tools for working on Wren Linux (`extras/wren-dev.sh`)

## SYNOPSIS

```
wrenctl install wren-dev                     install them
wrenctl remove wren-dev                      remove them (shellcheck stays while the Claude Code sandbox uses it)
wrenctl manual wren-dev                      print the manual steps below

bash test.sh                   every check, shellcheck on every script included
bash tools/build-deb.sh        build the package; lintian checks it
lintian FILE.deb               check any package
shellcheck SCRIPT              check one script
```

For the computer where you work on Wren Linux and build its package: `lintian`,
Debian's own checker for packages, which `tools/build-deb.sh` runs on every
package it builds, and `shellcheck`, which `test.sh` runs on every script.
Both come from Debian. They aren't in the base install: lintian brings over a
hundred packages (mostly Perl), and every other Wren Linux computer is better
off without code it never uses.

## LIMITS

- lintian and shellcheck point out mistakes they know about; a package or script they pass can still be wrong or unsafe.
- lintian unpacks the packages it checks: check only packages you built or trust.

## MANUAL INSTALL

```
# lintian and shellcheck, from Debian
sudo apt install --no-install-recommends lintian shellcheck
```

To undo:

```
# lintian goes; shellcheck is marked automatic, so apt removes it once nothing
# else needs it (the Claude Code sandbox installs it too)
sudo apt purge lintian
sudo apt-mark auto shellcheck
sudo apt autoremove --purge
```
