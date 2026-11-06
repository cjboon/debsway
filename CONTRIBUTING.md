# Working on Wren Linux

Wren Linux is shell scripts that turn a bare Debian 13 install into a small, careful
desktop. If you can read bash, you can read all of it, and help is welcome: a typo, a
test, a new extra, or a page that explains something better.

**Found a security hole? Don't open a public issue.** [SECURITY.md](SECURITY.md) says
how to report it.

## Get a copy and run the tests

```bash
git clone https://github.com/cjboon/wren-linux.git
cd wren-linux
sudo apt install shellcheck gnupg gpgv acl sway foot rsync nftables xclip cage socat keepassxc lintian python3 wget
PATH=$PATH:/usr/sbin bash test.sh --offline
```

That takes about 10 minutes. It installs nothing, and the tests work in temp folders with a
pretend `sudo`, `apt` and the like. A few could reach the real `sudo`, so a throwaway VM is
the safest place for them. Use Debian 13 if you can, since
that's what Wren Linux is written for. On another system some checks can fail for
reasons that have nothing to do with your change.

While you work, run only the test for what you changed:

```bash
bash tools/test-w3m.sh
```

Don't start two test runs at once, or edit files while one runs: some tests depend on
timing, and all of them copy your folder.

To try a change for real, use a computer or VM you can throw away. The scripts change
system files: that's their job.

## Find your way around

[docs/architecture.md](docs/architecture.md) shows how the pieces fit together, in about
five minutes. In short:

| Folder | What's in it |
| --- | --- |
| `parts/` | the base install, one script per piece |
| `extras/` | optional programs, one script each |
| `bin/` | the small commands those scripts install |
| `lib/` | shared helpers |
| `data/` | settings and files the scripts put in place |
| `docs/extras/` | one page per extra |
| `tools/` | tests and build tools |
| `pins.sh` | every signing key Wren Linux trusts |

## What a good change looks like

- **It does one thing.** One topic per commit, and a message that says why.
- **It has a test that can fail.** Every behaviour has a check in `tools/test-*.sh`. Run it
  on the old code and watch it fail, or it proves nothing.
- **It's shellcheck-clean.** `test.sh` runs shellcheck, with the settings in `.shellcheckrc`.
- **It's as plain as it can be.** Someone should be able to read the script before they run
  it. A comment says why, not what.
- **It keeps its promises.** Re-running a script repairs. `--remove` undoes. Never claim
  protection a script doesn't give: if you change what something protects, change
  [THREAT-MODEL.md](THREAT-MODEL.md) in the same commit.
- **It uses `foot`.** It's the only terminal the scripts support. Install another for your
  own use if you like, but a change that adds another for the scripts won't be taken.
- **It says what was tested.** "Ran on a real desktop" and "passes with a pretend sway" are
  different, and both are fine to say.

Some code needs extra care: firewall rules, sudo rules, sshd settings, signature checks and
anything that downloads. These changes are welcome, but expect slower review and more
questions. A new outside key goes in `pins.sh` with the date you checked it and where.

## Add an extra

An extra is one script in `extras/`. `extras/w3m.sh` is a short one to copy. It needs:

```bash
#!/bin/bash
# What it is, and why it's set up this way. Comments here are for the person
# deciding whether to run it.
# Usage: bash NAME.sh [--remove | --manual]
# summary: One line for the install list, 52 characters at most
# security: some
# status: apt:PACKAGE bin:COMMAND
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

if [ "${1:-}" = --remove ]; then
    apt_purge PACKAGE
    exit
fi

say "Installing NAME"
apt_install PACKAGE
```

- **`# security:`** is which group of the install list it goes in. `extras/whonix.sh`
  says `most`; a text browser says `some`. `install-extras.sh` explains the groups.
- **`# status:`** lists what only this script sets up, so `status.sh` can tell if it's
  there: `apt:`, `bin:`, `opt:`, `file:`, or `gone:` for something it removes. A package
  another script also installs doesn't belong here.
- **`# files:`** names repository files a library function installs for the script, so
  `update.sh` knows when to run it again.
- **`docs/extras/NAME.md`** is required, and a test checks it. Copy `docs/extras/w3m.md`:
  SYNOPSIS, one paragraph, LIMITS (be honest), and MANUAL INSTALL. That last section is
  what `--manual` prints, and it's also how someone can do it all by hand without trusting
  the script. Values from `pins.sh` go in as `@NAME@`, never typed in.
- **A row in `docs/extras.md`**, and a line in `README.md` if people will look for it.
- **Anything from outside Debian** must be checked against a key pinned in `pins.sh` before
  it's used.

To drop an extra, don't delete it at once: add `# retired: WHY` under its first line. It
leaves the install list, and `update.sh` offers its `--remove` to anyone who still has it.
The file goes a release or two later.

## Add a test

A test is a script in `tools/` named `test-NAME.sh`, added to `test.sh` with a line like:

```bash
dev_test w3m "w3m keeps cookies only while it is open (bin/w3m), with a pretend w3m" "w3m checks"
```

`tools/test-w3m.sh` is a small one to copy. Tests work in a temp folder and put pretend
programs first on the `PATH`. Some replace `sleep` with one that returns at once, so use
`/bin/sleep` where a test must really wait.

## Send your change

1. Fork the repository, and make a branch.
2. Run `bash test.sh --offline`, and say what it shows, including any failures you think
   aren't yours.
3. Open a pull request saying what changed, why, and what you tested.

Everything reaches `main` the same way, whoever wrote it. Wren Linux's computers take an
update only if its newest commit is signed by the project's key, so the maintainer reads
each change, then signs on top. That signature vouches for every line below it, so review
takes as long as it takes, and small changes get in faster.

The project is under the [MIT license](LICENSE), and so is what you send.

## Places to start

Some things that would help, none of them urgent:

- **More systems in `get-iso`:** SystemRescue, GParted Live, Clonezilla and Fedora. Each one
  needs its signing key found in two independent places, and a test (`tools/test-get-iso.sh`).
- **A guide:** the [docs](docs/) are for people who are new to this. If something took you a
  while to understand, a page explaining it may be the most useful thing you can send.
- **Try it on your hardware:** install it and report what didn't work. Laptops differ, and
  this has been tested on few of them.
- **A test for something untested:** many checks use pretend programs, and
  [docs/extras/whonix.md](docs/extras/whonix.md) lists what hasn't been tried for real.

If you want to take on something bigger, open an issue first, so nobody's work is wasted.
