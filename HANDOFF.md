# Handoff for the next Claude session

**Claude: read this first, then save what it says into your memory folder (one
memory per topic, as your instructions say), then delete this file and the
HANDOFF.md line in CLAUDE.md in one commit ("Handoff read; moved into memory"),
and push it to `claude`.** The owner rebuilt the VM, so the previous session's
memory is gone; this is it. Owner, you can read it too: it is what the next
session starts from.

## Where things stand (2026-11-05)

Everything below is on the `claude` branch; the owner pulls it with `claude-pull` and
releases it with `wren-release`. Expected VM-only test failures: one `setup-vps` check
(always) and, now and then, the timing-sensitive timer check under load.

Done in that session:

- io_uring off (sysctl); IOMMU on and strict (boot-hardening; needs a reboot).
- Launchers open their window from wmenu again (they test `/dev/tty`, not stdin:
  sway on tty1 hands that console to what it starts).
- `whonix` puts the Gateway and the Workstation each on an empty workspace.
- A way to retire an extra (`# retired: WHY`; `update.sh` offers its `--remove`).
  Retired: distro-vm, wallet-sandbox, opencode-vm, claude-regular. **Delete their
  files a release or two later** (about 1500 lines, their tests, docs, data).
- get-iso (Debian, Tails, Kicksecure, Qubes 4.3, Kali, Parrot, Arch; pinned keys;
  through Tor when it runs; writes a USB stick with lib/usb-stick.sh). tails-usb's
  EXIT trap fixed (every successful run used to end in an error).
- Wallets: Tor offered before a wallet's first run (Feather, Sparrow, Electrum).
- claude-vm: memory and disk chosen within what the computer can spare
  (`/etc/wren/claude-vm-size`, root's).
- Firefox: `firefox-esr` opens the sandbox, Firefox as you is `firefox-unsafe`
  (dpkg-divert); no password-saving prompts (KeePassXC keeps them); a read-only
  "Learn (Wren Linux)" bookmarks folder; 34 ready-made profiles
  (`data/firefox-profiles.list`, `firefox --choose-profiles` check boxes, each with
  the uBlock exception its site needs).

Owner's decisions to keep:

- Push only to `claude`, never `main` (see CLAUDE.md).
- **Keep the Wren menu in the base** (it is how newcomers reach the switches). The
  owner is still thinking about it: don't remove or move it.
- Keep onion-site and mockvps-kvm. Keep the Firefox New Tab picture and theme (checked:
  not security problems).
- No Kicksecure repository: take its settings one at a time, credited, tested.
- Don't kill a stuck unattended-upgrade in the VM (the owner said no once).
- The owner's network can drop to slow phone tethering: ask before big downloads.

## What's next, in this order

1. **Whonix, with the real image** (the bigger VM is for this):
   - `whonix stop` without Whonix LXQt's shutdown dialog (find what shows it; make the
     power button shut down cleanly, written into the images like GW_FILES in
     extras/whonix.sh; keep a `--force`). A switched-off Gateway once needed e2fsck.
   - `whonix update`: a root service written into each image at install, run only when
     the host passes a note through SMBIOS (systemd credentials from OEM strings), before
     the display manager, apt shown on the VM's console, then power off. Gateway first.
     The owner wants to watch the windows do it.
   - `whonix live`: host side, the disk opened as libvirt `<transient/>`.
   - `whonix sysmaint`: a GRUB snippet in the image that reads the SMBIOS note and boots
     `boot-role=sysmaint systemd.unit=sysmaint-boot.target`. Riskiest: match Whonix's
     menu entries exactly.
2. `gh` offered when the git extra is installed (install only, default yes; point to
   `wrenctl gh`; never log in during the install).
3. `help` (the key sheet, `keys`, in a window) and `update` (`wrenctl update` in a window)
   as commands wmenu finds; both must open their window when started from wmenu.

Later: one sandbox launcher for the sandboxes' session scripts; a fresh install of the
base tested start to end in a nested VM; get-iso SystemRescue, GParted, Clonezilla and
Fedora (each key from two sources); a "first onion site" guide in the docs.

## Lessons

- Keep big downloads out of the scratchpad: /tmp is a RAM disk here.
- Never two test runs at once; don't edit files while the suite runs (it read a
  half-made file once and failed).
- Make a test that fails on the old code; check it does.
- Say plainly what ran on a real desktop and what only ran here.
