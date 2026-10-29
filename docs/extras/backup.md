# Encrypted backups of your home folder (`extras/backup.sh`)

You get a `backup` command that saves your home folder to a USB drive or any folder you choose, encrypted with a password. Each backup stores only what changed since the last one. It uses restic, a backup program from Debian.

## The problem it solves

Disks die, laptops get lost or stolen, and files get deleted by mistake. Without a copy elsewhere, they are gone. A backup on the same disk does not help, and an unencrypted backup on a USB stick gives your files to whoever finds the stick.

## The ideas behind it

**A backup.** A second copy of your files kept somewhere else, so you can get them back.

**restic and a repository.** restic is the program. The folder where it keeps the backup is called the repository. It is not a plain copy of your files: restic cuts them into pieces and stores the pieces.

**Encryption.** Scrambling data so it can only be read with the right password. Everything in the repository is encrypted, so the USB stick alone reveals nothing. The password is never written down by debsway.

**A snapshot.** Each run of `backup` creates one snapshot, a record of what your files looked like at that moment. Because unchanged pieces are shared, many snapshots take little extra space.

**Excludes.** Things deliberately left out: caches, the trash, and things that can be downloaded again.

**A password command (optional).** A command that prints the password, so backups can run without you typing it. debsway stores the command, never the password.

## How it works, step by step

When you run `bash extras/backup.sh`:

1. It installs `restic`.
2. It asks where backups should go, a folder on a USB drive is best. If a drive is mounted under `/media/YOU/`, it offers a `debsway-backup` folder on it. You must give a full path.
3. If the folder does not already hold a restic repository, it creates one with `restic init`. restic asks you for a password twice. The script warns you to choose a strong one and keep it somewhere safe outside the laptop (on paper too). Without it the backup cannot be opened, and your KeePassXC database is inside the backup.
4. It asks for an optional password command. If you leave it empty, restic asks for the password each time.
5. It writes `~/.config/debsway/backup.conf` (the repository, and the password command if you gave one) and, if missing, `~/.config/debsway/backup-excludes`, which lists `~/.cache`, `~/.local/share/Trash`, `~/.local/share/libvirt/images` and debsway's `offline` folder. You can edit that file, one pattern per line.
6. It installs the `backup` command in `~/.local/bin` and prints examples.

When you run `backup` with no arguments, it checks the repository is there ("Is the drive plugged in?"), then runs `restic backup` on your whole home folder, skipping the excludes and any folder marked as a cache (`--exclude-caches`). With any arguments, it passes them straight to restic.

## What it changes on your computer

- Package: `restic`.
- `~/.local/bin/backup`.
- `~/.config/debsway/backup.conf` and `backup-excludes`.
- A new repository in the folder you chose.

No user, service or timer is added. A timer would be something you set up yourself with the password command.

## Using it

- `backup`: back up your home folder now.
- `backup snapshots`: list your backups.
- `backup ls latest`: list the files in the newest one.
- `backup restore latest --target ~/restored`: get everything back into `~/restored`. Restored files keep their full path, such as `~/restored/home/you/.electrum`; look there and copy back what you need.
- `backup restore latest --target ~/restored --include ~/.electrum`: one folder only.
- `backup diff ID1 ID2`: what changed between two snapshots.
- `backup check`: check that the backup is not damaged.
- `backup forget --keep-last 10 --prune`: keep only the 10 newest.

Each command asks for the password unless you set a password command.

## What it protects against

- **A dead, lost or stolen disk or laptop.** Your files are on the other drive.
- **Mistakes.** You can bring back an older version of a file or folder.
- **Someone reading the backup drive.** Everything in it is encrypted.
- **Damage to the backup going unnoticed**, if you run `backup check`.

## What it doesn't protect against

- **Losing the password.** Nothing can open the backup without it.
- **Keeping the drive plugged in.** A backup you leave connected next to the laptop is lost in the same fire or theft, and a program running as you could damage it. Keep it elsewhere.
- **A stored password command.** If you set one, any program running as you could run the same command. The password itself is not stored.
- **Things not in your home folder.** The sandboxed Firefox profiles (`/var/lib/debsway-firefox`, `/var/lib/debsway-fx`), the Claude Code agent's home, and system settings are not backed up.
- **Things you exclude**, such as the caches and VM disks.
- **A compromised computer.** Malware running as you could read the files before they are encrypted.
- **Automatic backups.** Nothing runs on a schedule unless you set it up.

## Removing it

`bash extras/backup.sh --remove` deletes the `backup` command, `~/.config/debsway/backup.conf` and `backup-excludes`, and removes `restic` unless another extra needs it. Your backups themselves are left where they are; you can open them later with restic and your password.
