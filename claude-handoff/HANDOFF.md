# Wren Linux handoff (written 2026-11-04)

Start here, then read `memory/` in this folder. Project rules are in
`~/wren-linux/CLAUDE.md` and still apply. Claude runs on the owner's real PC.

## State of the repo

Everything is committed on `main`. Nothing is pushed by Claude; the owner pushes.
Commits made this session after the owner's last known push (check with
`git log origin/main..HEAD`, some may be published by now):

| Commit | What |
|---|---|
| `669d36f` | Terminal on workspace 1, KeePassXC on 2; KeePassXC asks once |
| `a5fd46a` | `wren-vps --ssh-onion-only` and `--ssh-public` ask nothing again |
| `351a8dc` | `tools/release.sh`: publish and install in one command |
| `682e68b` | Sandboxed wallets (`extras/wallet-sandbox.sh`, command `wallet`) |
| `0e852bb` | `wren-release` command, from the `wren-dev` extra |
| `bf6730e` | `claude-vm`: passwordless sudo in the guest, firmer walls |
| `e23dc71` | `build-deb`: current lintian option; lintian failing no longer looks like remarks |
| `3f7c579` | `git-push.sh` doesn't say to install by hand during a release |

Last full suite: 122 ok, 0 failures, before the last small changes. Since then only
single tests ran: claude-vm, manual, build-deb, release, git-push. **Run
`bash test.sh --offline` first.** It takes about 10 minutes; use the background.

## What has not been run for real

Say this plainly in any report.

- **Wallet sandbox:** install under real sudo, opening any wallet, the clipboard through
  a real X server (`xclip`), Sparrow's and Electrum's Tor settings, hardware wallet and
  camera options. Real so far: the firewall in a network namespace, cage's X socket
  with no screen. Most likely first failure: `wallet clip`. It runs in its own Landlock
  domain, so xclip should fall back from the abstract socket to the private file socket.
- **claude-vm:** a VM booting under QEMU's `-sandbox`, the sudo rule in a real guest, a
  real snapshot and reset. Existing VMs need `claude-vm rebuild`, which deletes
  unpushed work.
- **`release.sh`:** real push and sudo steps had not been run when this was written.
- **Waiting on the owner's reports:** pages and sound in Firefox and incognito after the
  socket fix; `try-vps` retest and the onion site in Tor Browser; autostart order after
  login; `wren-watch` under real sudo.

## Next, in order

1. Owner runs `bash ~/wren-linux/tools/release.sh` if not yet done. After that,
   `wren-release` exists (if not: `wrenctl install wren-dev`).
2. Owner tries the wallet sandbox with no real money. Act on the results.
3. **Awaiting owner's go:** move Install apps and Remove apps to the bottom of the
   menu's Apps list. Owner seemed to favour it; confirm.
4. After real wallet tests: `electrum`, `feather`, `sparrow` open sandboxed by default,
   with `-regular` versions (the `claude-regular` pattern), and menu installs set up
   the sandbox. Owner's point: judge by how the pros receive it at release.
5. Experimental webtunnel for Whonix: `memory/whonix-webtunnel-plan.md`. **Approved.**
6. Penetration test: `memory/vm-testing-plan.md`. Owner's newer idea, not in that file:
   a **spare laptop** running Wren, with Claude in a guest VM (Kali if needed) attacking
   the host. Fake data only, separate network or phone hotspot, wipe it afterwards. A
   real VM escape is unlikely to be found, so "no escape" is weak evidence.

## Other open items

- Possible new messenger: Cwtch (Delta Chat if Cwtch fails checks on maintenance, audit
  or signed releases). Based on memory, not checked.
- **Unfixed review findings:** other sandbox firewalls fail open and `status.sh` doesn't
  notice (the wallet and claude-vm net checks show the fix); the established-first rule
  lets sandboxes listen on loopback and impersonate (9050, 18080); raw terminal escapes
  from commit messages in `update.sh` and `wifi.sh`. Low: mpv URL full network, tumbler
  thumbnails unsandboxed, yt-dlp plugin dirs, wren-idle hooks before lock, whonix
  `libvirt` group, mockvps should set REQUIRE_SIGNATURE, encrypt-usb "erased for good",
  `/dev/shm/firefox-run` fixed name, THREAT-MODEL's stale "a few minutes" of sudo.
  Possible bug: `wifi.sh` under sudo looks in `/usr/share/wren/offline`.
- **The sandboxed Firefox gets passage through `$HOME`:** it can open any file there
  whose name it guesses and whose permissions allow it. Wallets avoid this with a folder
  outside home. Owner's `~/note.txt` was `-rw-rw-r--`; `chmod 600` was suggested.
- **Other tests may reach the real sudo:** `lib.sh` resets PATH, so a fake on PATH is
  ignored. It happened once this session and stopped at the password prompt; nothing
  changed. `tools/test-wallet-sandbox.sh` uses exported functions, and
  `tools/test-wren-dev.sh` has a guard. Worth checking across all tests.
- Timing the suite's slowest groups, and tidying lintian's `E:` and `W:` remarks.
- Firefox VM: owner wanted to discuss it after the wallets.

## Things learned

- Run tests with `dangerouslyDisableSandbox: true`; in the sandbox about 18 groups fail
  (no Wayland socket, gpg, X sockets). Those sandbox stand-ins (`.bashrc` etc.) show as
  `??` in sandboxed `git status` and aren't real.
- Commit with `git -c commit.gpgsign=false commit`; `git-push.sh` signs on top.
- Never run two test runs at once. The owner's tests count too.
- Run tests before committing, and make each new check fail on the old code. Twice this
  session a first version of a check could not fail.
- Don't edit files while a suite runs. `tools/test-build-deb.sh` takes over 200 seconds.
- `cage` in Debian has no data-control protocol, so `wl-copy` fails inside it. The
  bridge uses `xclip`, and all three wallets run under X for that reason.
- Don't send a plain `wait` in tests with long background listeners, and redirect their
  output: they hold pipes open and the run looks hung.
- The owner watches usage closely; idle waiting is cheap, reading and writing aren't.
  Be plain in reports, and say which user runs which command.
