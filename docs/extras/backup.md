# Encrypted backups (`extras/backup.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/backup.sh            set it up (asks where backups go, and the password)
bash ~/debsway/extras/backup.sh --remove   remove it (the backups themselves stay)
bash ~/debsway/extras/backup.sh --manual   print the manual steps below

backup                         back up your home folder now
backup snapshots               list your backups
backup ls latest               the files in the newest backup
backup restore latest --target ~/restored [--include ~/.electrum]
                               get everything (or one folder) back, into ~/restored
backup diff ID1 ID2            what changed between two backups
backup check                   make sure the backup isn't damaged
backup forget --keep-last 10 --prune   keep only the 10 newest
```

Encrypted backups of your home folder with restic, from Debian, to a folder
you choose, best on a USB drive. Everything in a backup is encrypted with a
password restic asks for each time, which is never written down (for
unattended backups, the settings can hold a command that prints it), and each
backup stores only what changed since the last. Caches, the Trash, VM disks
and debsway's offline downloads are left out (`~/.config/debsway/backup-excludes`,
yours to edit). The `backup` command (`bin/backup`) runs restic on your
backup; restored files keep their full path, e.g. `~/restored/home/you/.electrum`.

## LIMITS

- Without the password the backup can't be opened, and your KeePassXC database is inside it: keep the password somewhere safe outside this laptop.
- A backup on a drive that stays plugged in can be lost with the laptop; keep one away from it.
- Nothing runs by itself: you run `backup`.
- Anything running as you can read your files before they're backed up, and the password command's output.

## MANUAL INSTALL

```
# restic, from Debian
sudo apt install --no-install-recommends restic

# Where backups go: a folder on a USB drive (plug it in first)
REPO=/media/$USER/NAME/debsway-backup
mkdir -p "$REPO"
# A new, encrypted backup there: choose a strong password, and keep it
# somewhere safe outside this laptop (on paper, too)
restic -r "$REPO" init

# The settings the backup command reads (add a line
# PASSWORD_COMMAND=... with a command that prints the password, for backups
# that run without you)
mkdir -p ~/.config/debsway
printf 'BACKUP_REPO=%s\n' "$REPO" >~/.config/debsway/backup.conf
# What is left out, one pattern per line
printf '%s\n' "$HOME/.cache" "$HOME/.local/share/Trash" "$HOME/.local/share/libvirt/images" \
    "$HOME/vpskvm" "@DEBSWAY_DIR@/offline" >~/.config/debsway/backup-excludes

# The backup command
install -D -m 0755 @DEBSWAY_DIR@/bin/backup ~/.local/bin/backup
backup
```

To undo (your backups themselves stay where they are):

```
# The command and its settings
rm ~/.local/bin/backup ~/.config/debsway/backup.conf ~/.config/debsway/backup-excludes
# restic
sudo apt purge restic
```
