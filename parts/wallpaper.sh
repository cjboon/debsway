#!/bin/bash
# Your own wallpaper: put a JPEG or PNG in ~/Pictures/debsway/desktop and it
# becomes the desktop's at the next login or sway reload (Super+Shift+c); the
# newest one there wins. With the folder empty nothing changes: your sway
# config's own "output * bg" line, or sway's plain background, stays.
# bin/wallpaper does the work; "wallpaper status" says which picture is used.
# Super+] and Super+[ step through ~/Pictures/Wallpapers as the wallpaper,
# Super+Shift+w lists it by name (wmenu); the one chosen stays. Super+\
# goes back to no wallpaper (sway's own background).
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

Wallpapers/ (one folder up) is to choose from: Super+] and Super+[ step
through it on the desktop itself, Super+Shift+w (or "wallpaper pick")
lists it by name, and Super+\ goes back to no wallpaper. The one you stop
on is copied here as chosen.jpg, so it stays.
bash ~/debsway/extras/wallpapers.sh fills it with space and Earth pictures
(NASA, Webb, Earth Observatory) and Budgie's photos, or just sets it up for
pictures of your own.
EOF
fi
# exec_always: at every start and every reload, so a new picture shows on
# Super+Shift+c. The keys step through ~/Pictures/Wallpapers, or list it.
put_snippet wallpaper <<EOF
# Your own wallpaper: the newest picture in ~/Pictures/debsway/desktop (debsway parts/wallpaper.sh)
exec_always $BIN/wallpaper
bindsym \$mod+bracketright exec $BIN/wallpaper next
bindsym \$mod+bracketleft exec $BIN/wallpaper previous
bindsym \$mod+Shift+w exec $BIN/wallpaper pick
bindsym \$mod+backslash exec $BIN/wallpaper none
EOF
note "Super+] and Super+[ step through ~/Pictures/Wallpapers; Super+Shift+w lists it."
note "Or put a picture in $PICS/desktop, then press Super+Shift+c."
