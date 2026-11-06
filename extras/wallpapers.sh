#!/bin/bash
# Pictures to pick a wallpaper from, in ~/Pictures/Wallpapers (copy one into
# ~/Pictures/wren/desktop: parts/wallpaper.sh): budgie_*, Budgie's photos, from
# Debian. The package is only downloaded (apt-get download: checked against
# Debian's signed lists, through Tor if apt goes through Tor) and its pictures
# unpacked: nothing installed, no package script, no sudo.
# Your own pictures can go there too: --remove takes out only what it downloaded.
# A list asks whether to download them, or not ("I'll find my own": the folder and
# its README are still set up). Run it again to fetch them again.
# Usage: bash wallpapers.sh [--remove | --manual]
# summary: Wallpapers to pick from: Budgie's photos
# security: some
# status: file:~/Pictures/Wallpapers/.wren-wallpapers
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

DEST="$HOME/Pictures/Wallpapers"
# what this script put there, one file name a line; --remove takes out
# exactly these, so pictures you add yourself stay
LIST="$DEST/.wren-wallpapers"
# pictures in Budgie's package smaller than this are icons, not wallpapers
MIN_BYTES=100000

# listed NAME: NAME goes on the list (once)
listed() { grep -qxF -- "$1" "$LIST" || echo "$1" >>"$LIST"; }

if [ "${1:-}" = --remove ]; then
    if [ -f "$LIST" ]; then
        while IFS= read -r f; do
            # only plain names: nothing outside the folder, nor in a folder in it
            case $f in "" | */* | .*) continue ;; esac
            # An earlier version also fetched these from NASA and ESA. They're yours
            # now: Wren Linux no longer has them to give back.
            case $f in nasa_* | webb_* | earth_* | CREDITS.txt) continue ;; esac
            rm -f -- "${DEST:?}/$f"
        done <"$LIST"
        rm -f "$LIST"
        note "Removed the wallpapers it downloaded; pictures of your own in $DEST are still there."
    fi
    exit
fi

# readme: what is in the folder (rewritten while it is Wren Linux's own)
readme() {
    local f="$DEST/README.txt"
    if [ -e "$f" ] && ! head -1 "$f" | grep -q 'written by Wren Linux'; then return; fi
    cat >"$f" <<'EOF'
Wallpapers to choose from (written by Wren Linux extras/wallpapers.sh)

To make one your wallpaper: Super+] and Super+[ step through them on the
desktop itself, and "wallpaper pick" lists them by name. (Or copy one into
~/Pictures/wren/desktop and press Super+Shift+c.)

budgie_ pictures are Budgie's photos, from Debian. Free licences: budgie_LICENCE.txt.

nasa_, webb_ and earth_ pictures came from an earlier version of Wren Linux, from
NASA and ESA, and stay yours: nothing here removes them. CREDITS.txt names each
one's title, credit and page, so keep it if you share them.

Your own pictures (JPEG or PNG), e.g. from an image search, can go here too:
save them through Firefox into ~/Downloads, then move them here, with a name
you will recognise. Wren Linux never changes or removes them. Pictures from the
web are often copyrighted: fine on your own screen, but don't share them on.

More to choose from: https://www.pexels.com/search/desktop%20wallpaper/
Free for your own screen, and no credit needed. Their terms don't allow passing the
pictures on as they are, so don't share them as wallpapers. Their licence, which can
change: https://www.pexels.com/license/

wrenctl install wallpapers fetches Budgie's again;
wrenctl remove wallpapers takes out what it downloaded, nothing of yours.
EOF
    listed README.txt
}

# Whether to download them: a list when there is a terminal to show it on
chosen=()
declare -A used
if [ -t 0 ] && [ -t 1 ]; then
    . "$WREN_DIR/lib/checklist.sh"
    ITEMS=(budgie "Budgie's photos, from Debian's budgie-backgrounds (11 MB)" ON)
    # ticked, it unticks the other (CL_ALONE); and nothing is downloaded
    # whatever else would be ticked
    ITEMS+=(none "No wallpapers downloaded, I'll find my own" OFF)
    CL_TITLE="Wallpapers" CL_OK=Download CL_CANCEL=Cancel CL_ALONE=none
    CL_TEXT="Download these? They go in ~/Pictures/Wallpapers.\nYour own pictures can go there too: nothing of yours is changed or removed."
    checklist || { note "Nothing downloaded."; exit 0; }
    if printf '%s\n' "${chosen[@]}" | grep -qx none; then chosen=(); fi
else
    chosen=(budgie)
fi

mkdir -p "$DEST"
touch "$LIST"
readme
if [ ${#chosen[@]} -eq 0 ]; then
    note "Nothing downloaded. Put pictures (JPEG or PNG) in $DEST, then"
    note "Super+] and Super+[ step through them, and Super+Shift+w lists them."
    exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
failed=()
for src in "${chosen[@]}"; do
    pkg=budgie-backgrounds
    say "Wallpapers: Budgie's, from Debian's $pkg"
    rm -rf "${tmp:?}"/*
    # apt checks the file against the hash in Debian's signed lists
    if ! (cd "$tmp" && apt-get download -q "$pkg" >/dev/null 2>"$tmp/err"); then
        warn "Couldn't download $pkg: $(tail -1 "$tmp/err")"
        warn "(Old package lists? sudo apt update, then run this again.)"
        failed+=(budgie)
        continue
    fi
    deb=$(ls "$tmp"/*.deb)
    mkdir "$tmp/x"
    # only regular files come out (no links, no device files), owned by you
    dpkg-deb --fsys-tarfile "$deb" | tar -x -C "$tmp/x" --no-same-owner --no-same-permissions \
        --wildcards --no-anchored '*.jpg' '*.jpeg' '*.png' '*.JPG' '*.PNG' "usr/share/doc/$pkg/copyright" 2>/dev/null || true
    n=0
    used=()
    while IFS= read -r -d '' f; do
        [ "$(stat -c %s -- "$f")" -ge "$MIN_BYTES" ] || continue
        # name: budgie_ and the file's own; if this run already used it, or a
        # file of yours has it, its whole path in the package
        name=${f##*/}
        if [ -n "${used[$name]:-}" ] || { [ -e "$DEST/budgie_$name" ] && ! grep -qxF -- "budgie_$name" "$LIST"; }; then
            name=${f#"$tmp/x/"}
            name=${name#./}
            name=${name#usr/share/}
            name=${name//\//_}
        fi
        name=${name//[^A-Za-z0-9._+-]/_}
        used[$name]=1
        install -m 0644 -- "$f" "$DEST/budgie_$name"
        listed "budgie_$name"
        n=$((n + 1))
    done < <(find "$tmp/x" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) -print0)
    if [ -f "$tmp/x/usr/share/doc/$pkg/copyright" ]; then
        install -m 0644 "$tmp/x/usr/share/doc/$pkg/copyright" "$DEST/budgie_LICENCE.txt"
        listed budgie_LICENCE.txt
    fi
    note "$n of Budgie's pictures in $DEST"
done

note "To use one: Super+] and Super+[ step through them, or: wallpaper pick"
note "Your own pictures can go in $DEST too. $DEST/README.txt says more."
if [ ${#failed[@]} -gt 0 ]; then
    warn "Not downloaded: ${failed[*]}"
    exit 1
fi
