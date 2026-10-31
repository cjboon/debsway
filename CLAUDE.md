# Working on debsway (notes for Claude)

debsway is shell scripts that turn a bare Debian 13 install into a small sway
desktop. The owner tests every push on their own machine, so: be plain about what was
tested here and what wasn't (nothing in this VM has sway, a GPU or the real users), and
say which user runs which command.

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
  checklist cuts it off), `# status:` and a `--remove`. The `# status:` line lists only
  what that script alone sets up: a package another script installs makes a permanent `*`.
  `# files:` names repo files that a library function installs for the script, so that
  `update.sh` knows when to run it again.
- Every behaviour has a test in `tools/test-*.sh`, registered in `test.sh`. Make a test
  that can fail: check that it fails on the old code. The test suite replaces `sleep` with
  a no-op; use `/bin/sleep` where a test must really wait.
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

- This VM holds the deploy key `~/.ssh/id_ed25519`. Do not run downloaded binaries or large
  third-party programs under this account. Read code you fetch before using it, in its own
  folder in the scratchpad, and say what you found.
- Work leaves the VM only by commit and push; the owner reviews. Don't send repo content
  to outside services.
- Security-relevant claims need a test or a reason. If a path could not be run here (real
  sway, real sudo, real hardware), say so in the report instead of implying it works.
