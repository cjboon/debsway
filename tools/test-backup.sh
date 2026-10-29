#!/bin/bash
# Checks what extras/backup.sh leaves out of backups (write_excludes), in a
# pretend home folder: big things that can be downloaded or built again, VM
# disks included, and that a list you edited keeps your edits. Changes nothing
# outside a temp folder. Run by test.sh, or:  bash tools/test-backup.sh
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

HOME=$T/home DEBSWAY_DIR=$T/debsway
eval "$(sed -n '/^write_excludes() {/,/^}/p' "$HERE/extras/backup.sh")"
F=$T/excludes

write_excludes "$F"
for line in "$HOME/.cache" "$HOME/.local/share/Trash" "$HOME/.local/share/libvirt/images" "$HOME/vpskvm" "$DEBSWAY_DIR/offline"; do
    check "a new list leaves out ${line#"$T"/}" grep -qxF "$line" "$F"
done

# A list from an earlier version, which you edited: .cache taken out, a line added
printf '%s\n' "# Left out of backups (written by debsway extras/backup.sh)" "$HOME/.local/share/Trash" \
    "$HOME/.local/share/libvirt/images" "$HOME/Videos" >"$F"
write_excludes "$F"
check "an existing list gains mockvps-kvm's VM disks (~/vpskvm)" grep -qxF "$HOME/vpskvm" "$F"
check "...and the saved downloads" grep -qxF "$DEBSWAY_DIR/offline" "$F"
check "...keeps the line you added" grep -qxF "$HOME/Videos" "$F"
check "...and doesn't put back the line you took out" not grep -qxF "$HOME/.cache" "$F"
write_excludes "$F"
check "running it again adds nothing twice" test "$(grep -cxF "$HOME/vpskvm" "$F")" = 1

[ "$fails" -eq 0 ]
