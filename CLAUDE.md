# Working on Wren Linux (notes for Claude)

Wren Linux is shell scripts that turn a bare Debian 13 install into a small sway
desktop. Be plain about what was tested and what wasn't, and say which user runs which
command.

**Claude runs in `claude-vm`, a disposable Debian VM on the owner's computer**
(`extras/claude-vm.sh`), not on the owner's desktop. The VM is walled off from it:
no shared folder, no reach into the owner's machine or local network, only the
internet. So:

- This VM is yours to change. You have sudo without a password: install what you need
  and test real installs here (extras, firewalls, users, services, VMs inside it with
  `/dev/kvm`). The owner can reset or rebuild it, so nothing kept only here is safe.
- It is a bare Debian 13 server, not the Wren Linux desktop: no sway, no screen, and
  the base parts aren't installed. Say which results came from here and which still
  need the owner's machine (a window on the desktop, prompts typed by hand, the
  owner's real extras).
- `~/projects/wren-linux` tracks `origin/main` (https://github.com/cjboon/wren-linux.git).
  The VM's ssh key is a deploy key with write access. Commit each finished item as soon
  as its tests pass (one commit per item), then push to a `claude/NAME` branch, never
  to `main`: `main`'s newest commit must carry Wren Linux's signature or every computer
  with the pin refuses updates. The owner reviews, merges and signs with
  `tools/git-push.sh`. Push only when the owner asks.
- Things this VM needs or does differently:
  - Before the first test run: `sudo apt install gnupg gpgv acl sway rsync nftables
    xclip cage socat keepassxc lintian`, and `PATH=$PATH:/usr/sbin` (nft, visudo).
    Without `gpg-agent` (in `gnupg`) a dozen groups fail on key making and signing.
  - Expected failures here, not bugs: the three DNS-over-TLS checks (port 853 is
    blocked from this VM) and one `setup-vps` check (it assumes no ssh login above it;
    you are logged in over ssh).
  - Scripts call `sudo -v`, which asks for a password here despite NOPASSWD:
    `echo 'Defaults verifypw=any' | sudo tee /etc/sudoers.d/zz-claude-verifypw`.
  - **Never turn on ufw (or any input firewall) in this VM.** The owner's `claude-vm`
    command logs in over ssh to the guest's port 22; blocking it locks them out of
    this VM (your own session survives, which hides it).
  - Base parts aren't installed, so e.g. `parts/sandbox-dns.sh` isn't running: a
    sandbox's `resolvers` set stays empty unless you fill it
    (`sudo bash bin/sandbox-dns-update`).
- The test suite works in a temp folder with a pretend sudo. A few tests could reach
  the real sudo: here that changes only this VM, but say so if it happened.

## Working

- If you use a helper agent, don't hand it: firewall, sudo, sshd, signature or key code;
  anything that edits the repo as the final word; anything about git or pushing. Check
  what a helper returns before relying on it.
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
  protection a script doesn't give), and the man page `data/wrenctl.1` (a test checks that
  it matches `wrenctl --help`).
- Commits: one topic each, message ends with the `Co-Authored-By:` line from the session
  reminder, tests passing first. When splitting a change into commits, stage the files by
  name (a `git mv` is already staged and rides along with the next commit).
- `bin/*` files are installed by `install_bin` into `~/.local/bin`, or by root scripts into
  `/usr/local`. A script is only re-run on the owner's machine by `update.sh`; pulling does
  not install anything.

## Safety

- The owner's private files are not here, and nothing here should become theirs
  without review. Read code you fetch before using it, in its own folder in the
  scratchpad, and say what you found. Run downloaded programs only in this VM, never
  in anything you hand back.
- Work leaves this VM only by pushing to a `claude/` branch; the owner reviews before
  merging. Don't send repo content or anything else to other outside services.
- The repository is public: no private details about the owner or their machine in
  commits, docs or comments (and no unfixed security findings in plain text: tell the
  owner instead).
- Security-relevant claims need a test or a reason. If a path was not actually run (a
  desktop window here, a change the owner must apply on their machine), say so in the
  report instead of implying it works.
