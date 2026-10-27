#!/bin/bash
# Encrypted backups of your home folder with restic (from Debian), to a
# USB drive or any folder you choose. Everything in the backup is
# encrypted with a password that restic asks for each time; it isn't
# stored anywhere. Backups only store what changed since the last one.
# This sets up the backup place and a "backup" command.
# Usage: bash backup.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

CONF_DIR="$HOME/.config/debsway"
CONF="$CONF_DIR/backup.conf"
EXCLUDES="$CONF_DIR/backup-excludes"
CMD="$HOME/.local/bin/backup"

if [ "${1:-}" = --remove ]; then
    if grep -qs 'written by debsway extras/backup.sh' "$CMD"; then rm -f "$CMD"; fi
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

mkdir -p "$CONF_DIR" "$(dirname -- "$CMD")"
printf '# Written by debsway extras/backup.sh\nBACKUP_REPO=%s\n' "$repo" >"$CONF"

# Left out: caches, trash, and big things that can be downloaded again.
# Edit the file to change it; one pattern per line.
if [ ! -f "$EXCLUDES" ]; then
    cat >"$EXCLUDES" <<EOF
# Left out of backups (written by debsway extras/backup.sh)
$HOME/.cache
$HOME/.local/share/Trash
$HOME/.local/share/libvirt/images
$HOME/debsway/debs
$HOME/debsway/torbrowser
$HOME/debsway/whonix
EOF
fi

cat >"$CMD" <<'EOF'
#!/bin/bash
# backup: written by debsway extras/backup.sh
#   backup            back up your home folder now
#   backup ARGS...    any restic command, on your backup (e.g. backup snapshots)
conf="$HOME/.config/debsway/backup.conf"
[ -f "$conf" ] || { echo "Not set up. Run: bash ~/debsway/extras/backup.sh" >&2; exit 1; }
repo=$(sed -n 's/^BACKUP_REPO=//p' "$conf")
if [ ! -f "$repo/config" ]; then
    echo "Backup not found at $repo. Is the drive plugged in?" >&2
    exit 1
fi
export RESTIC_REPOSITORY="$repo"
if [ $# -eq 0 ]; then
    exec restic backup --exclude-caches --exclude-file="$HOME/.config/debsway/backup-excludes" "$HOME"
fi
exec restic "$@"
EOF
chmod +x "$CMD"
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
