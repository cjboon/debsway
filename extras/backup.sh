#!/bin/bash
# Encrypted backups of your home folder with restic (from Debian), to a
# USB drive or any folder you choose. Everything in the backup is
# encrypted with a password that restic asks for each time; it isn't
# stored anywhere. Backups only store what changed since the last one.
# This sets up the backup place and a "backup" command.
# For backups that run without you (a timer, a script), the config can hold
# a command that prints the password, e.g. one that asks a password manager;
# the password itself is never written down.
# Usage: bash backup.sh [--remove]
# summary: Encrypted backups of your home folder (restic)
# status: apt:restic
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

CONF_DIR="$HOME/.config/debsway"
CONF="$CONF_DIR/backup.conf"
EXCLUDES="$CONF_DIR/backup-excludes"

if [ "${1:-}" = --remove ]; then
    remove_bin backup
    rm -f "$CONF" "$EXCLUDES"
    apt_purge restic
    note "Your backups themselves are left where they are."
    exit
fi

say "Installing restic"
apt_install restic

# Where the backups go
repo=
if [ -f "$CONF" ]; then
    repo=$(sed -n 's/^BACKUP_REPO=//p' "$CONF")
    ask "Keep backing up to $repo?" y || repo=
fi
if [ -z "$repo" ]; then
    default=
    for d in /media/"$USER"/*/; do
        [ -d "$d" ] && { default="${d%/}/debsway-backup"; break; }
    done
    note "Where should backups go? A folder on a USB drive is best (plug it in first)."
    [ -z "$default" ] || note "Press Enter for: $default"
    tty_read repo "    folder> "
    repo=${repo:-$default}
    [ -n "$repo" ] || die "No folder given."
    repo=${repo/#\~/$HOME}
    [[ $repo == /* ]] || die "Give the full path, starting with /."
fi

if [ -f "$repo/config" ]; then
    note "Using the existing backup in $repo."
else
    mkdir -p "$repo"
    say "Creating an encrypted backup in $repo"
    warn "Choose a strong password and keep it somewhere safe outside this laptop"
    warn "(on paper, too): without it the backup can't be opened, and your"
    warn "KeePassXC database is inside the backup."
    restic -r "$repo" init </dev/tty || die "restic couldn't create the backup."
fi

mkdir -p "$CONF_DIR"
cmd=$(sed -n 's/^PASSWORD_COMMAND=//p' "$CONF" 2>/dev/null || true)
if [ -n "$cmd" ]; then
    ask "Keep getting the backup password with: $cmd ?" y || cmd=
else
    note "restic asks for the backup password each time. To run backups without typing it,"
    note "give a command that prints it (for example one that reads a secret store you unlock at login)."
    tty_read cmd "    password command (Enter to be asked each time)> "
fi
printf '# Written by debsway extras/backup.sh\nBACKUP_REPO=%s\n' "$repo" >"$CONF"
if [ -n "$cmd" ]; then printf 'PASSWORD_COMMAND=%s\n' "$cmd" >>"$CONF"; fi

# Left out: caches, trash, and big things that can be downloaded again.
# Edit the file to change it; one pattern per line.
if [ ! -f "$EXCLUDES" ]; then
    cat >"$EXCLUDES" <<EOF
# Left out of backups (written by debsway extras/backup.sh)
$HOME/.cache
$HOME/.local/share/Trash
$HOME/.local/share/libvirt/images
$DEBSWAY_DIR/offline
EOF
fi
# Folders of earlier versions moved into offline/
grep -qxF "$DEBSWAY_DIR/offline" "$EXCLUDES" || echo "$DEBSWAY_DIR/offline" >>"$EXCLUDES"

install_bin backup
note "Backups go to: $repo"
note "Left out (edit to change): $EXCLUDES"

cat <<'EOF'

    How to use backup:
      backup                         back up your home folder now
      backup snapshots               list your backups
      backup ls latest               list the files in the newest backup
      backup restore latest --target ~/restored
                                     get everything back, into ~/restored
      backup restore latest --target ~/restored --include ~/.electrum
                                     get back one folder
      backup diff ID1 ID2            what changed between two backups
                                     (IDs come from "backup snapshots")
      backup check                   make sure the backup isn't damaged
      backup forget --keep-last 10 --prune
                                     keep only the 10 newest backups

    Each command asks for the backup password. Restored files keep their
    full path, e.g. ~/restored/home/you/.electrum: look there, then copy
    back what you need.
EOF
