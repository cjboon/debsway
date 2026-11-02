#!/bin/bash
# Your own wallpaper: put a JPEG or PNG in ~/Pictures/debsway/desktop and it
# becomes the desktop's at the next login or sway reload (Super+Shift+c); the
# newest one there wins. With the folder empty nothing changes: your sway
# config's own "output * bg" line, or sway's plain background, stays.
# bin/wallpaper does the work; "wallpaper status" says which picture is used.
# (extras/wallpapers.sh fills ~/Pictures/Wallpapers with pictures to pick from.)
# Usage: bash wallpaper.sh [--remove]
# status: bin:wallpaper
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

PICS="$HOME/Pictures/debsway"

if [ "${1:-}" = --remove ]; then
    remove_snippet wallpaper
    remove_bin wallpaper
    rm -f "${XDG_CACHE_HOME:-$HOME/.cache}"/debsway/wallpaper-*
    note "Your pictures in $PICS are left in place."
    exit
fi

say "Your own wallpaper ($PICS/desktop)"
install_bin wallpaper
mkdir -p "$PICS/desktop"
# rewritten while its first line is debsway's, so it never tells of an older
# debsway; once you change that line it is yours and left alone
if [ ! -e "$PICS/README.txt" ] || head -1 "$PICS/README.txt" | grep -q 'written by debsway'; then
    cat >"$PICS/README.txt" <<'EOF'
debsway's picture folders (written by debsway parts/wallpaper.sh)

desktop/   Put a JPEG or PNG here and it becomes your wallpaper at the next
           login, or press Super+Shift+c. With several, the newest is used;
           with none, the default. "wallpaper status" says which, and why a
           file isn't used.

Pictures to choose from: bash ~/debsway/extras/wallpapers.sh fills
~/Pictures/Wallpapers with NASA's, Hubble's, Webb's, Earth Observatory's and
Budgie's, next to personal/ for the ones you find yourself (copy one into
desktop/).
EOF
fi
# exec_always: at every start and every reload, so a new picture shows on Super+Shift+c
put_snippet wallpaper <<EOF
# Your own wallpaper: the newest picture in ~/Pictures/debsway/desktop (debsway parts/wallpaper.sh)
exec_always $BIN/wallpaper
EOF
note "Put a picture in $PICS/desktop, then press Super+Shift+c."
