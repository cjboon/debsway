# Handoff: read this first (notes for the next Claude working on Wren Linux)

Written 2026-11-07. Remove this file, and its line at the top of CLAUDE.md, once the work below is
done or has moved on. This file is public: **no unfixed security findings go in it, or in any commit
or doc.** The owner has been told those in person; ask them.

Greet the owner, say what you found here, and report early and often: they dislike a long silent
read. Commit each finished small step. Lives may depend on this project: fail safe, test for real,
say plainly what ran and what didn't.

## Where the work is

- `main`: what the owner reviewed and signed. Only they update it.
- `claude`: finished, tested work, for `claude-pull`. Push only there, and only after reading a full
  suite result, in a separate command from the test. `set -e` doesn't stop at a failing `test && x`:
  that committed a failing fix twice, and pushed a failed suite once.
- `claude-wip`: **unfinished and untested. Never merge it as it is, and never push it to `claude`.**
  It holds `claude`'s commits and, on top, the work in progress and this file.

A Claude on another account (`claude --account NAME`) has another VM, with none of this one's files or
memory: this file and GitHub are all it has. It needs its own deploy key (`wrenctl gh deploy-key --account NAME`).

To go on: `git fetch origin && git checkout -b claude-wip origin/claude-wip`. Before anything goes to
`claude`, split that last commit by topic, each with its tests.

## First things to do

1. **CI is red on `main` since 50c098b** (the step running `test.sh --offline`). Its logs need a
   login, so ask the owner for the `FAIL` lines; the API shows only which step failed. Likely cause:
   `no-abstract-sockets --userns` gave a Python traceback where Ubuntu's AppArmor lets a user
   namespace be made and refuses to set it up, and the test's skip didn't recognise that. Fixed in
   9860d15 and reproduced with a lab AppArmor profile that denies `capability sys_admin`, but **not
   confirmed**: only CI on GitHub's Ubuntu host can. Check it after pushing.
2. On `claude`, suite clean here (141 ok but for `setup-vps`): the git guard, bridge lines, the bar, the
   `--userns` refusal, the serial log cap and the onion site's QEMU filter, and the retirement of Claude Code
   as its own user (10c772c). CI went green at 9860d15, so that was the cause of the red. Check CI on 10c772c.
   Also on `claude`: a699bbd, a bridge line Tor would refuse is refused when pasted (a stray word had stopped the
   owner's Gateway from starting Tor). CI green at 10c772c; check it at a699bbd.
   The owner's own test, real Whonix on their computer: webtunnel connects (the first real try). They were then
   running `whonix update` through it. Ask how it went: did it finish, did a bookmark and a download survive, still
   Safest, did `whonix stop` end with no dialog? Then fill in docs/extras/whonix.md's LIMITS, which still say those
   weren't tried. Say only what they report.
   Their first run through webtunnel: the Gateway updated; the Workstation's Tor Browser download (15 to 16) was cut
   off (`curl: (56) unexpected eof`, status 17), and the script rolled back as designed. **To do, small and worth it:**
   `data/whonix-update-browser` gives the download one chance. Retry a few times, with `update-torbrowser --resume`
   (Whonix's own advice), keeping the checks as they are; a bridge is where this happens, and people on bridges have
   the worst connections. It is written into the images at install, so it reaches people at their next install. Test
   with `tools/test-whonix-update.sh`, failing first.
   A second run through webtunnel finished: "Whonix is up to date". The rollback on the first run really worked: 15
   came back with the owner's bookmark and download. Ask them to confirm 16, bookmark, download and Safest now.
   **The owner's decisions on `whonix update`, each with a failing test first, in the same files as the retry above:**
   - `data/whonix-update-browser`: carry over only Downloads and the bookmarks, not the whole profile, which would
     keep whatever a hacked page planted in it. Everything else fresh; Safest comes from
     /usr/local/etc/torbrowser.d/user.js (check it applies on a fresh profile). `places.sqlite` holds bookmarks and is
     itself a file a hacked browser could change: see if bookmarks alone can be taken out without running the browser.
     Lost, and to be said in the docs: per-site NoScript choices, saved onion keys. Try it on a real profile.
   - `data/whonix-update`: stop `--force-confold`, which silently keeps old config files, security fixes in them too.
     Take the maintainer's version (`--force-confnew`, as Whonix's own tool), and put back Wren's one edit afterwards,
     the `nameserver 10.0.2.3` line in the Gateway's `/etc/resolv.conf.whonix`, noting before the upgrade whether it was
     on. Check first that it is the only packaged file Wren edits. Fails closed: Tor just won't connect. Say in the docs
     that a hand-edited packaged file is replaced (dpkg keeps `.dpkg-old`), and to use /usr/local/etc. Correct the
     LIMITS and the comments that defend the old way; there's a test to change, and the notes in `extras/whonix.sh`.
3. Suggest a release when CI is green: 8d28954 (git guard) and those above are fixes people should take.

## The owner's decisions, in the order to do them

Each finished, tested and pushed before the next. Told to the owner in this order.

1. **Tor Browser and Mullvad Browser sandboxes, with Tor as a user of its own.** See below.
2. **A warning when updates stop arriving** (bar and `status.sh`): someone in the way can quietly hold
   updates back for ever, and `update.sh` only says so if you run it. Wren Linux's own updates; the
   bar already has this for Debian's (`updates()` in `bin/sway-status`). Being offline isn't a failure.
3. **Delete the retired extras**: `grep -l '^# retired:' extras/*` (wallet-sandbox, distro-vm,
   opencode-vm, claude-regular). `update.sh` offers each one's `--remove` to whoever still has it, so
   leave one small way to clean up rather than strand them, and say what you did. Their tests, docs,
   pages, firewalls, session scripts, and the lists naming them go too (`remove_no_abstract`,
   `TOR_SERVICE_MARKS`, `FIREWALLS`, `tools/test-sandbox-net.sh`...). The browser sandbox borrowed its
   window and clipboard design from wallet-sandbox: don't let it depend on those files.
4. **Claude Code as its own user (`extras/claude-code.sh`) is retired (10c772c): `claude-vm` is the only sandbox for
   an AI agent** (the owner, after asking whether Claude was sure: "vm is ultimately safest"). This replaces
   the earlier plan to stop sharing `~/projects` and pull through an upload-pack: there is nothing left to
   share. Retired the normal way: no new installs, `update.sh` offers its `--remove`, which leaves people's
   `~/projects` alone. Delete it, `bin/git`, `bin/claude-session`, `bin/claude-sandbox`, `tools/test-git-guard.sh`
   and the rest with the other retired extras in step 3, keeping `claude-pull`, `claude-share` and whatever
   `claude-vm` installs. Wren as a whole stays usable without VM hardware: the owner decided this only for AI.
5. **One shared sandbox launcher, `wren-sandbox`** (the owner let Claude pick the name). The session
   scripts repeat the same pieces: user check, wrapper, firewall check and watch, socket folder, sound.
   That is how a fix misses some of them. Do this last, when there is less to move: one sandbox at a
   time, each tried for real. `docs/architecture.md` says what they have in common.

Then the older list: hidepid for sandbox users (exempt what logind and polkit need; try bwrap and
Firefox's own sandbox for real), `wrnctl` as a second name for `wrenctl` with Tab completion (a real
command, not an alias), the test speed report (slowest: package 398 s, shellcheck 152 s, whonix cmd
86 s), `whonix sysmaint`, the permissions part, the rest of the security review, the pentest.

The owner has not decided these, which Claude recommended, and is thinking about them: a feature
freeze until Wren has been attacked; the pentest before new work; an outside human reviewer before
people in danger rely on it; the installer steering people at real risk to Tails or Whonix. Don't add
other new features meanwhile.

The owner also asked whether to add Anthropic's courses to the Learn bookmarks. Claude advised against
it in the Programming folder, offered a line in the Claude pages instead, and has no answer yet.

## The browser sandboxes: where they stand

On `claude-wip`. **Written, and never run as a whole.**

- `lib/browser-sandbox.sh`, `bin/browser-sandbox` (the command, and the clipboard),
  `bin/browser-session` (what the owner may run as that user), `data/{tor,mullvad}-browser-firewall.nft`,
  `extras/tor-browser.sh` (reworked), `extras/mullvad-browser-sandbox.sh` (new, beside `-regular`),
  `tools/test-browser-sandbox.sh` (62 checks pass; registered), docs, THREAT-MODEL, key sheet, menu.
- Facts found by real tests, don't lose them:
  - Tor Browser's AppArmor profile attaches only under `/home/*`, so its home is `/home/tor-browser`.
  - Under no_new_privs AppArmor refuses browser -> Tor (`px`), so Tor never starts: its session uses
    `no-abstract-sockets --userns` (Landlock without no_new_privs; caps 0, root unmapped, sudo gives
    nothing). Mullvad's profile is `flags=(unconfined)`: the plain wrapper.
  - A bridge's program listens on a port the system picks, on 127.0.0.1, and Tor connects to it. A
    plain firewall breaks every bridge. Opening those ports opens the owner's services too. The answer,
    proven with real sockets (`fw-try.py` in `~/browser-lab`, if this VM still has it): mark that user's
    loopback connections with `ct mark`, and reject a marked connection's answer from any other user.
    **The rule letting answers out must say `ct direction reply`**: without it a new connection, whose
    source port is high too, goes out unmarked to anything on this computer. That bug passed for
    strict until it was tried. `tools/test-browser-sandbox.sh` fails 8 ways if it comes back.
  - `no launcher window`: `torbrowser-launcher` exits after starting the browser, which would close cage.
- **Still to do for it:**
  1. **Tor as its own user** (owner's decision): user e.g. `tor-browser-tor` running Tor with the bridge
     in its torrc; the browser with Tor Browser's own switches for using an outside Tor (`TOR_SKIP_LAUNCH`
     and friends; look at how Whonix's Workstation starts it, a lab Whonix may be in
     `~/.local/share/libvirt/images`). Then the browser's firewall: on this computer only Tor's SOCKS port,
     **and nothing to the internet at all**, which is the point: a hacked browser has no way out but Tor.
     Check it from the browser's user, also that its updater and New Identity still work, and what a user
     loses (the bridge settings screen; the installer chooses bridges). Say that limit plainly. Replace the
     lines in `docs/extras/tor-browser.md` and THREAT-MODEL that say a hacked browser can go around Tor,
     only once that is proven.
  2. Real install in this VM: `bash extras/tor-browser.sh`, then in a headless sway
     (`WLR_BACKENDS=headless WLR_RENDERER=pixman`) with `grim` for pictures: the window opens; Tor
     bootstraps, directly and through a bridge (Snowflake needs no lines); `ss` and a capture show nothing
     but Tor leaving; the firewall from its own user (LAN, loopback); it can't read the owner's home; X0's
     abstract socket refused; downloads reach `~/Browsers/NAME` and the owner can read them; the clipboard
     both ways; `journalctl -k | grep -i apparmor` for denials (the rule for the folder, and for sound, were
     written without being tried); `nft flush ruleset` ends it within seconds. The same for Mullvad.
     `pipewire-bin`, `wl-clipboard` aren't on this VM until something installs them.
  3. `--remove` for real; a reinstall over a kept home; an owner who already had Tor Browser as themselves.
  4. "Tried here" lines in LIMITS saying only what ran. `tools/test-manual.sh`, `test-sandbox-net.sh`,
     `test-wren-menu.sh`, `test-tor-service.sh`; then the full suite; split the commit; push to `claude`.
- This VM's lab, if it survived: `~/browser-lab` (Tor Browser 15.0.25 in `tb/`, Mullvad 16.0 unpacked in
  `deb/mb`, `mb.deb`, `tbl.deb`), user `tor-browser` made by hand, AppArmor profiles loaded by hand. The
  user `agentx` and `/tmp/gg.*` are from a test: remove them. Prefer not fetching Tor Browser again (140 MB,
  and the owner's network can be slow): ask before big downloads.

## Done this session (on `claude`, or in the list above)

- The git guard looked only at a repository and those above it, not inside it. Fixed in 8d28954.
- Finding 2's fix had missed `remote-access` and `onion-site`. The test now covers every script that
  writes bridge lines to the system torrc, not a list of names.

## How to work here

CLAUDE.md has the rules. Also learned the hard way:

- Run a check, read the exit code, commit in a **separate** command. See above.
- A test must fail on the old code: put the bug back and see. A pretend program shows only what you
  believed the real one does; `docs/maintaining.md` says how to try things for real here.
- One test run at a time, each under a hard `timeout`. `/tmp` is a RAM disk, wiped by a restart.
- Never put a line that ends a here-document inside the file you're writing with one (a real `EOF` in a
  function cut a file in half): use the Write tool for files.
- A safety check refuses `rm` inside an inner `bash -c`. Don't work around it: don't need the removal.
- Never turn on an input firewall in this VM. Stop lab processes by number, never a broad `pkill`.
- The owner reads the code, and has said not to ask about implementation choices: take them and say so.
  They want docs and scripts easy to read, for contributors. Plain words, short sentences.
- When the session ends, the owner is owed **a full rundown of all security-relevant information**: what
  was found, fixed and left, what ran for real and what didn't. Give it to them directly, not in a commit.
