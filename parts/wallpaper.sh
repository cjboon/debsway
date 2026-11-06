#!/bin/bash
# Your own wallpaper: put a JPEG or PNG in ~/Pictures/wren/desktop and it
# becomes the desktop's at the next login or sway reload (Super+Shift+c); the
# newest one there wins. With the folder empty, the default: a wren for the
# theme in use, swapped when the theme is (data/wallpapers, CREDITS.txt there).
# Your sway config's own "output * bg" line stays instead, if it has one.
# bin/wallpaper does the work; "wallpaper status" says which picture is used.
# Super+] and Super+[ step through ~/Pictures/Wallpapers as the wallpaper,
# Super+Shift+w lists it by name (wmenu); the one chosen stays. Super+\
# goes back to no wallpaper (the theme's plain background, parts/theme.sh).
# (extras/wallpapers.sh fills ~/Pictures/Wallpapers with pictures to pick from.)
# Usage: bash wallpaper.sh [--remove]
# status: bin:wallpaper
# files: data/wallpapers/wren-explored.jpg data/wallpapers/wren-juvenile.jpg data/wallpapers/CREDITS.txt
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

PICS="$HOME/Pictures/wren"

if [ "${1:-}" = --remove ]; then
    remove_snippet wallpaper
    remove_bin wallpaper
    rm -f "$HOME/.local/share/wren/wallpapers"/default-*.jpg "$HOME/.local/share/wren/wallpapers/CREDITS.txt"
    rmdir "$HOME/.local/share/wren/wallpapers" 2>/dev/null || true
    rm -f "${XDG_CACHE_HOME:-$HOME/.cache}"/wren/wallpaper-*
    note "Your pictures in $PICS are left in place."
    exit
fi

say "Your own wallpaper ($PICS/desktop)"
install_bin wallpaper
DEFAULTS=$HOME/.local/share/wren/wallpapers
install -D -m 0644 "$WREN_DIR/data/wallpapers/wren-juvenile.jpg" "$DEFAULTS/default-dark.jpg"
install -D -m 0644 "$WREN_DIR/data/wallpapers/wren-explored.jpg" "$DEFAULTS/default-light.jpg"
install -m 0644 "$WREN_DIR/data/wallpapers/CREDITS.txt" "$DEFAULTS/CREDITS.txt"
mkdir -p "$PICS/desktop" "$PICS/firefox"
# rewritten while its first line is Wren Linux's, so it never tells of an older
# Wren Linux; once you change that line it is yours and left alone
if [ ! -e "$PICS/README.txt" ] || head -1 "$PICS/README.txt" | grep -q 'written by Wren Linux'; then
    cat >"$PICS/README.txt" <<'EOF'
Wren Linux's picture folders (written by Wren Linux parts/wallpaper.sh)

desktop/   Put a JPEG or PNG here and it becomes your wallpaper at the next
           login, or press Super+Shift+c. With several, the newest is used;
           with none, the default: a wren for the light or dark theme.
           "wallpaper status" says which, and why a file isn't used.

firefox/   Put a JPEG or PNG here (at most 10 MB) and it is the background
           of the sandboxed Firefox's New Tab page instead of the fox, from
           its next start; the newest one counts. Firefox never sees this
           folder: a checked copy is handed over at each start.

Wallpapers/ (one folder up) is to choose from: Super+] and Super+[ step
through it on the desktop itself, Super+Shift+w (or "wallpaper pick")
lists it by name, and Super+\ goes back to no wallpaper. The one you stop
on is copied here as chosen.jpg, so it stays.
wrenctl install wallpapers fills it with pictures that come with Wren Linux,
and pictures of your own can go there too.
EOF
fi
# exec_always: at every start and every reload, so a new picture shows on
# Super+Shift+c. The keys step through ~/Pictures/Wallpapers, or list it.
put_snippet wallpaper <<EOF
# Your own wallpaper: the newest picture in ~/Pictures/wren/desktop (Wren Linux parts/wallpaper.sh)
exec_always $BIN/wallpaper
bindsym \$mod+bracketright exec $BIN/wallpaper next
bindsym \$mod+bracketleft exec $BIN/wallpaper previous
bindsym \$mod+Shift+w exec $BIN/wallpaper pick
bindsym \$mod+backslash exec $BIN/wallpaper none
EOF
note "Super+] and Super+[ step through ~/Pictures/Wallpapers; Super+Shift+w lists it."
note "Or put a picture in $PICS/desktop, then press Super+Shift+c."
