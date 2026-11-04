#!/bin/bash
# Checks what extras/backup.sh leaves out of backups (write_excludes), in a
# pretend home folder, and the backup command's reminder (bin/backup remind),
# pretend home folder: big things that can be downloaded or built again, VM
# disks included, and that a list you edited keeps your edits. Changes nothing
# outside a temp folder. Run by test.sh, or:  bash tools/test-backup.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

HOME=$T/home WREN_DIR=$T/wren OFFLINE_DIR=$T/wren/offline
eval "$(sed -n '/^write_excludes() {/,/^}/p' "$HERE/extras/backup.sh")"
F=$T/excludes

write_excludes "$F"
for line in "$HOME/.cache" "$HOME/.local/share/Trash" "$HOME/.local/share/libvirt/images" "$HOME/vpskvm" "$OFFLINE_DIR"; do
    check "a new list leaves out ${line#"$T"/}" grep -qxF "$line" "$F"
done

# A list from an earlier version, which you edited: .cache taken out, a line added
printf '%s\n' "# Left out of backups (written by Wren Linux extras/backup.sh)" "$HOME/.local/share/Trash" \
    "$HOME/.local/share/libvirt/images" "$HOME/Videos" >"$F"
write_excludes "$F"
check "an existing list gains mockvps-kvm's VM disks (~/vpskvm)" grep -qxF "$HOME/vpskvm" "$F"
check "...and the saved downloads" grep -qxF "$OFFLINE_DIR" "$F"
check "...keeps the line you added" grep -qxF "$HOME/Videos" "$F"
check "...and doesn't put back the line you took out" not grep -qxF "$HOME/.cache" "$F"
write_excludes "$F"
check "running it again adds nothing twice" test "$(grep -cxF "$HOME/vpskvm" "$F")" = 1

# ---- the backup command: the time of the last backup, and the reminder ----
B=$T/b
mkdir -p "$B/home/.config/wren" "$B/repo" "$B/bin"
: >"$B/repo/config"
printf 'BACKUP_REPO=%s\n' "$B/repo" >"$B/home/.config/wren/backup.conf"
printf '#!/bin/sh\necho "restic $*" >>"%s/calls"\n[ ! -e "%s/restic-fails" ]\n' "$B" "$B" >"$B/bin/restic"
chmod +x "$B/bin/restic"
bk() { env -u WAYLAND_DISPLAY HOME="$B/home" XDG_STATE_HOME= PATH="$B/bin:$PATH" bash "$HERE/bin/backup" "$@" 2>&1; }
L=$B/home/.local/state/wren/backup-last
export -f bk; export B HERE
check "remind: no backup made yet: it says so, and to unplug the drive afterwards" bash -c 'out=$(bk remind); grep -q "No backup has been made here yet" <<<"$out" && grep -q "unplug it again" <<<"$out"' _
out=$(bk)
check "a backup that worked: its time is kept, and it says to unplug the drive" bash -c '[ -s "$1" ] && grep -q "Unplug the backup drive now" <<<"$2"' _ "$L" "$out"
check "...then remind says nothing" test -z "$(bk remind)"
echo $(($(date +%s) - 40 * 86400)) >"$L"
check "remind, 40 days later: the last backup was 40 days ago" bash -c 'grep -q "Your last backup was 40 days ago" <<<"$(bk remind)"' _
before=$(cat "$L")
: >"$B/restic-fails"
bk >/dev/null
check "a backup that failed: the time stays, and it fails too" bash -c '[ "$(cat "$1")" = "$2" ] && ! bk' _ "$L" "$before"
rm -f "$B/restic-fails"
rm -f "$B/home/.config/wren/backup.conf"
check "remind with backup not set up: nothing said" test -z "$(bk remind)"
check "the extra runs the reminder at login: in sway, and on a text console" bash -c '
    grep -q "put_snippet backup-reminder" "$1" && grep -q "exec ~/.local/bin/backup remind" "$1" && grep -q "~/.local/bin/backup remind. \"\$RC_END\" >>\"\$RC\"" "$1" &&
    grep -q "remove_snippet backup-reminder" "$1"' _ "$HERE/extras/backup.sh"

[ "$fails" -eq 0 ]
