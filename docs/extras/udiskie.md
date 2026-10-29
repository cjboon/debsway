# USB drives that mount by themselves, safely (`extras/udiskie.sh`)

You get USB drives and cards that appear under `/media/YOU/` as soon as you plug them in, without typing a command. They are mounted so that nothing on them can run by itself. Encrypted (LUKS) drives ask for their passphrase in a small prompt.

## The problem it solves

On a minimal desktop, a USB stick does nothing when you plug it in: you must mount it by hand with a root command. Making it automatic is easy, but it also means a stranger's stick is opened the moment it goes in. A stick can hold programs, special files that act like devices, and files with extra powers. None of that should run from a stick you do not know.

## The ideas behind it

**Mounting.** Linux makes a drive's contents visible by attaching it to a folder. That attaching is called mounting. Unmounting detaches it safely, before you unplug it.

**udisks2 and udiskie.** `udisks2` is the system service that mounts drives. `udiskie` is a small program running in your sway session that notices a new drive and asks udisks2 to mount it. `polkitd` is the part that lets you mount without sudo.

**Mount options.** Switches set when mounting. debsway sets three:
- `nosuid`: files on the drive cannot gain extra powers (setuid files run as their owner, often root).
- `nodev`: special device files on the drive are ignored.
- `noexec`: programs on the drive cannot be started directly.

**LUKS.** The standard Linux disk encryption. A LUKS drive is unreadable until you give its passphrase. `cryptsetup` is the tool that unlocks it.

**A password prompt.** udiskie's own prompt needs GTK, a toolkit debsway does not install, so debsway adds a small one: `luks-askpass`.

## How it works, step by step

When you run `bash extras/udiskie.sh`:

1. It installs `udiskie`, `udisks2`, `cryptsetup`, `polkitd` and `gir1.2-notify-0.7` (so mount messages can show as notifications when `mako` is installed).
2. It installs `luks-askpass` into `~/.local/bin`. It shows a prompt with `wmenu` in password mode if `wmenu` is installed, otherwise a floating `foot` window that does not echo what you type.
3. It writes `~/.config/udiskie/config.yml` with `mount_options: [nosuid, nodev, noexec]`, unless you already have that file, which it keeps. The comment in it says to delete `noexec` to run programs from a stick.
4. It writes a sway snippet `~/.config/sway/config.d/automount.conf`. It starts `udiskie --no-tray --no-file-manager` with `luks-askpass` as the password prompt every time sway starts, and makes the prompt window floating. The snippet is checked with sway, and the old one put back if sway rejects it.
5. If sway is running and udiskie is not, it starts it now.

When you plug a drive in, udiskie mounts it under `/media/YOU/NAME` with those options. For a LUKS drive, it asks for the passphrase first.

## What it changes on your computer

- Packages: `udiskie`, `udisks2`, `cryptsetup`, `polkitd`, `gir1.2-notify-0.7`.
- `~/.local/bin/luks-askpass`.
- `~/.config/udiskie/config.yml` (if it did not exist).
- `~/.config/sway/config.d/automount.conf`.
- A running `udiskie` process.

## Using it

- Plug the drive in: it mounts by itself under `/media/YOU/`.
- `udiskie-umount /media/YOU/NAME`: unmount one drive before you unplug it.
- `udiskie-umount -a`: unmount all.
- `udiskie-info -a`: show what udiskie sees, if a stick does not mount.
- To run a program from a stick, run it as `bash x.sh`, or delete `noexec` from `~/.config/udiskie/config.yml` and restart udiskie.

## What it protects against

- **A stranger's stick running something.** With `nosuid`, `nodev` and `noexec`, nothing on a stick can run from it by itself.
- **Typing root commands for each stick.** polkit lets you mount as yourself.
- **A password shown on screen.** The LUKS prompt hides what you type.

## What it doesn't protect against

- **Flaws in how the kernel reads a filesystem.** The drive is mounted the moment it is plugged in, so the kernel reads whatever the stick contains. A badly made or malicious stick can attack that code. Do not plug in sticks you do not trust.
- **Files you open.** A document, image or script that you open or run from the stick yourself can still be harmful. `noexec` does not stop `bash script.sh` or an interpreter.
- **Unplugging without unmounting.** That can damage the drive's files.
- **Reading your unencrypted drive if someone takes it.** Use LUKS for sensitive data.
- **Mounts made by other programs.** The options apply to udiskie's mounts.

## Removing it

`bash extras/udiskie.sh --remove` removes the sway snippet, stops the running `udiskie`, deletes `luks-askpass`, and deletes `~/.config/udiskie/config.yml` only if it still carries debsway's mark. It then purges `udiskie`, `udisks2` and `gir1.2-notify-0.7` unless another extra needs them. `cryptsetup` is kept (marked as manually installed), because an encrypted system disk needs it to boot. Your drives and their files are untouched.
