#!/bin/bash
# Debian's wallpaper collections, as pictures in ~/Pictures/Wallpapers to pick
# from (copy one into ~/Pictures/debsway/desktop: parts/wallpaper.sh). The
# packages are only downloaded, with apt-get download (checked against
# Debian's signed package lists, through Tor if apt goes through Tor), and the
# JPEG and PNG pictures and each package's licence file are unpacked: nothing
# is installed, no package script runs, no sudo. (Installed, desktop-base would
# also change the boot and login screens.) A list asks which collections.
# Usage: bash wallpapers.sh [--remove | --manual]
# summary: Debian's wallpapers to pick from (no install)
# security: most
# status: file:~/Pictures/Wallpapers/.debsway-wallpapers
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

DEST="$HOME/Pictures/Wallpapers"
# what this script put there, one path (under DEST) a line; --remove takes
# out exactly these, so pictures you add yourself stay
LIST="$DEST/.debsway-wallpapers"
# PACKAGE|WHAT|ON or OFF in the list (the big ones start unticked)
COLLECTIONS=(
    "sway-backgrounds|sway's own (4 MB)|ON"
    "desktop-base|Debian's release artwork, old and new (9 MB)|ON"
    "budgie-backgrounds|Budgie's photos (11 MB)|ON"
    "gnome-backgrounds|GNOME's photos and abstracts (35 MB)|ON"
    "mate-backgrounds|MATE's collection (44 MB)|OFF"
    "plasma-workspace-wallpapers|KDE's large set, high resolution (124 MB)|OFF"
    "xfdesktop4-data|Xfce's few (1 MB)|OFF"
)
# pictures smaller than this are icons and boot-screen pieces, not wallpapers
MIN_BYTES=100000

if [ "${1:-}" = --remove ]; then
    if [ -f "$LIST" ]; then
        while IFS= read -r f; do
            case $f in "" | /* | *..*) continue ;; esac
            rm -f -- "${DEST:?}/$f"
        done <"$LIST"
        rm -f "$LIST"
        # the collection folders, if nothing of yours is left in them
        find "$DEST" -mindepth 1 -type d -empty -delete 2>/dev/null || true
        rmdir "$DEST" 2>/dev/null || true
        note "Removed Debian's wallpapers; anything you put in $DEST yourself is still there."
    fi
    exit
fi

# Which collections: a list when there is a terminal to show it on
chosen=()
declare -A used
if [ -t 0 ] && [ -t 1 ]; then
    . "$DEBSWAY_DIR/lib/checklist.sh"
    ITEMS=()
    for c in "${COLLECTIONS[@]}"; do
        IFS='|' read -r pkg what on <<<"$c"
        ITEMS+=("$pkg" "$what" "$on")
    done
    CL_TITLE="Wallpapers from Debian" CL_OK=Download CL_CANCEL=Cancel
    CL_TEXT="Which collections? They go in ~/Pictures/Wallpapers, one folder each.\nNothing is installed: only the pictures are unpacked."
    checklist || { note "Nothing downloaded."; exit 0; }
else
    for c in "${COLLECTIONS[@]}"; do
        IFS='|' read -r pkg _ on <<<"$c"
        [ "$on" = ON ] && chosen+=("$pkg")
    done
fi
[ ${#chosen[@]} -gt 0 ] || { note "Nothing chosen, nothing downloaded."; exit 0; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$DEST"
touch "$LIST"
failed=()
for pkg in "${chosen[@]}"; do
    say "Wallpapers: $pkg"
    rm -rf "${tmp:?}"/*
    # apt checks the file against the hash in Debian's signed lists
    if ! (cd "$tmp" && apt-get download -q "$pkg" >/dev/null 2>"$tmp/err"); then
        warn "Couldn't download $pkg: $(tail -1 "$tmp/err")"
        warn "(Old package lists? sudo apt update, then run this again.)"
        failed+=("$pkg")
        continue
    fi
    deb=$(ls "$tmp"/*.deb)
    mkdir "$tmp/x"
    # only regular files come out (no links, no device files), owned by you
    dpkg-deb --fsys-tarfile "$deb" | tar -x -C "$tmp/x" --no-same-owner --no-same-permissions \
        --wildcards --no-anchored '*.jpg' '*.jpeg' '*.png' '*.JPG' '*.PNG' "usr/share/doc/$pkg/copyright" 2>/dev/null || true
    mkdir -p "$DEST/$pkg"
    n=0
    used=()
    while IFS= read -r -d '' f; do
        [ "$(stat -c %s -- "$f")" -ge "$MIN_BYTES" ] || continue
        # name: the file's own; if this run already used it, or a file of
        # yours has it, its whole path in the package (desktop-base has a
        # 1920x1080.png for each theme)
        name=${f##*/}
        if [ -n "${used[$name]:-}" ] || { [ -e "$DEST/$pkg/$name" ] && ! grep -qxF -- "$pkg/$name" "$LIST"; }; then
            name=${f#"$tmp/x/"}
            name=${name#./}
            name=${name#usr/share/}
            name=${name//\//_}
        fi
        name=${name//[^A-Za-z0-9._+-]/_}
        used[$name]=1
        install -m 0644 -- "$f" "$DEST/$pkg/$name"
        grep -qxF -- "$pkg/$name" "$LIST" || echo "$pkg/$name" >>"$LIST"
        n=$((n + 1))
    done < <(find "$tmp/x" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print0)
    if [ -f "$tmp/x/usr/share/doc/$pkg/copyright" ]; then
        install -m 0644 "$tmp/x/usr/share/doc/$pkg/copyright" "$DEST/$pkg/LICENCE.txt"
        grep -qxF -- "$pkg/LICENCE.txt" "$LIST" || echo "$pkg/LICENCE.txt" >>"$LIST"
    fi
    note "$n pictures in $DEST/$pkg"
done

note "To use one: copy it into ~/Pictures/debsway/desktop, then press Super+Shift+c."
note "They are freely licensed (each folder's LICENCE.txt): to share one, credit its artist as the licence says."
if [ ${#failed[@]} -gt 0 ]; then
    warn "Not downloaded: ${failed[*]}"
    exit 1
fi
