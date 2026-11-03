# Working on debsway (notes for Claude)

debsway is shell scripts that turn a bare Debian 13 install into a small sway
desktop. Be plain about what was tested and what wasn't, and say which user runs which
command.

**For now Claude runs on the owner's own PC, not in a VM.** This is the installed
debsway desktop: sway is running, there is a real GPU and `/dev/kvm`, the extras are
installed (`~/.local/bin`), and other users exist (e.g. `onion-site`). So:

- Anything you run acts on the owner's real system and session. Don't run install,
  `--remove`, `update.sh` or `bin/*` commands, change system settings, or stop/start
  services and VMs unless the owner asks; say the command and let them run it.
- sudo asks for a password, so it can't run unattended. Never try to get around that.
- The home folder holds private files (password database, keys, `~/.gnupg`, notes,
  logs). Read nothing outside `~/debsway` and the scratchpad unless the owner points you
  to a specific file.
- `~/debsway` is a git repo tracking `origin/main` (https://github.com/cjboon/debsway.git).
  There is no `~/.ssh` here; pushing uses the owner's own credential, so the owner pushes.
  Commit each finished item of work as soon as its tests pass (one commit per item);
  push only when the owner asks.
- The test suite works in a temp folder with a pretend sudo. Still check a test doesn't
  touch the real home or desktop before running it here.

## Efficiency

- When a job is self-contained and cheap to check, hand it to a smaller model through a
  helper agent: read-only searches over many files, summarizing long test or log output,
  drafting boilerplate (tests, docs) from a clear spec that you then review. Use only its
  short result.
- Don't hand off: firewall, sudo, sshd, signature or key code; anything that edits the
  repo as the final word; anything about git or pushing. Check what a helper returns
  before relying on it. Start few helpers: each begins with no memory of the session.
- Don't re-read a file you already have; send small edits; read only the part you need.
- `bash test.sh --offline` takes a few minutes. Run it once per finished piece, not after
  every edit; run the single `tools/test-*.sh` for what you changed. Run slow things in
  the background writing to a file in the scratchpad, then poll it with short checks.
  Never run two test runs at once: the pty-based tests (menu, timer) are timing-sensitive.
  Don't wait with `pgrep -f` or `pkill -f` patterns that match your own command line.

## Conventions

- Scripts are bash, shellcheck-clean (`.shellcheckrc`). New scripts: `chmod +x`.
- `parts/` is the base (the `PARTS` list in `packages.sh`); `extras/` is optional and is
  listed by `install-extras.sh`. An extra needs `# summary:` (52 characters at most, the
  checklist cuts it off), `# status:`, a `--remove`, and a `--manual` with its page
  in `docs/extras/` (SYNOPSIS, one paragraph, LIMITS, MANUAL INSTALL; a test checks). The `# status:` line lists only
  what that script alone sets up: a package another script installs makes a permanent `*`.
  `# files:` names repo files that a library function installs for the script, so that
  `update.sh` knows when to run it again.
- Every behaviour has a test in `tools/test-*.sh`, registered in `test.sh`. Make a test
  that can fail: check that it fails on the old code. The test suite replaces `sleep` with
  a no-op; use `/bin/sleep` where a test must really wait.
- An extra's `## MANUAL INSTALL` section in `docs/extras/` is what its `--manual`
  prints (`print_manual`). Change those steps in the same commit as the script;
  tests compare only a few of them with the script (Unbound's settings, sshd's,
  claude-vm's provisioning). Values from `pins.sh` or the script go in as `@NAME@`,
  never typed in. Undo steps purge only the extra's own packages: shared ones are
  marked `apt-mark auto` (a purge also removes whatever depends on them).
- Keep docs in step with behaviour: `README.md`, `docs/`, `THREAT-MODEL.md` (do not claim
  protection a script doesn't give), and the man page `data/debsway.1` (a test checks that
  it matches `debsway --help`).
- Commits: one topic each, message ends with the `Co-Authored-By:` line from the session
  reminder, tests passing first. When splitting a change into commits, stage the files by
  name (a `git mv` is already staged and rides along with the next commit).
- `bin/*` files are installed by `install_bin` into `~/.local/bin`, or by root scripts into
  `/usr/local`. A script is only re-run on the owner's machine by `update.sh`; pulling does
  not install anything.

## Safety

- This is the owner's own account, with their private files. Do not run downloaded binaries
  or large third-party programs under it. Read code you fetch before using it, in its own
  folder in the scratchpad, and say what you found.
- Work leaves this PC only by the owner's commit and push; the owner reviews. Don't send
  repo content or anything from this machine to outside services.
- Security-relevant claims need a test or a reason. If a path was not actually run (real
  sudo, a change you left for the owner to apply), say so in the report instead of
  implying it works.
