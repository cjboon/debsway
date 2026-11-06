#!/bin/bash
# Pictures to pick a wallpaper from, copied into ~/Pictures/Wallpapers from
# data/wallpapers/ (copy one into ~/Pictures/wren/desktop: parts/wallpaper.sh). They
# come with Wren Linux, so nothing is downloaded and Wren Linux's signature covers them.
# A list asks which: basic (wrens, art, Earth and space), and, if this copy has it,
# strong: real violence and death, and nudity. Strong is never on unless you tick it.
# Your own pictures can go there too: --remove takes out only what it put there, and
# a picture you already have isn't replaced. Run it again to choose again. --remove
# also ends "no wallpaper", or a choice of one of its pictures: the default wren is back.
# Usage: bash wallpapers.sh [--remove | --manual]
# summary: Wallpapers to pick from: wrens, art, Earth, space
# security: some
# status: file:~/Pictures/Wallpapers/.wren-shipped
# files: data/wallpapers/CREDITS.txt data/wallpapers/shock/CREDITS.txt
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

DEST="$HOME/Pictures/Wallpapers"
PICS=$WREN_DIR/data/wallpapers
# what an earlier version put there, which fetched them; --remove takes out those
LIST="$DEST/.wren-wallpapers"
# what this version copied, one file name a line
SHIPPED="$DEST/.wren-shipped"

# forget NAME: NAME's credit goes, and it comes off the list
forget() {
    local f
    for f in "$DEST/CREDITS.txt" "$SHIPPED"; do
        [ -f "$f" ] || continue
        awk -v n="$1" 'index($0, n ": ") != 1 && $0 != n' "$f" >"$f.new" && mv "$f.new" "$f"
    done
}

# back_to_default: "no wallpaper", or one of these pictures as the wallpaper (bin/wallpaper
# keeps a copy), ends with them. Fails if there is nothing to end. A picture of your own
# stays chosen, and so does a chosen.jpg that isn't a copy of that picture any more.
back_to_default() {
    local state=${XDG_CACHE_HOME:-$HOME/.cache}/wren/chosen-wallpaper desk=$HOME/Pictures/wren/desktop chose f
    chose=$(head -c 256 "$state" 2>/dev/null)
    if [ "$chose" != none ]; then
        [ -n "$chose" ] && grep -qxFs -- "$chose" "$SHIPPED" || return 1
        for f in "$desk/chosen.jpg" "$desk/chosen.png"; do
            if cmp -s -- "$DEST/$chose" "$f"; then rm -f -- "$f"; fi
        done
    fi
    rm -f -- "$state"
}

if [ "${1:-}" = --remove ]; then
    # (before the pictures go: it compares with them)
    ended=
    if back_to_default; then ended=1; fi
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
    fi
    if [ -f "$SHIPPED" ]; then
        while IFS= read -r f; do
            case $f in "" | */* | .*) continue ;; esac
            rm -f -- "${DEST:?}/$f"
            forget "$f"
        done < <(cat "$SHIPPED")
        rm -f "$SHIPPED"
        [ -s "$DEST/CREDITS.txt" ] || rm -f "$DEST/CREDITS.txt"
    fi
    note "Removed the wallpapers it put there; pictures of your own in $DEST are still there."
    if [ -n "$ended" ]; then reload_sway; fi
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

CREDITS.txt names each one's title, credit, page and licence. Keep it if you share
them: most ask for a credit.

nasa_, webb_ and earth_ pictures you already had stay yours: nothing here replaces
or removes them.

Your own pictures (JPEG or PNG), e.g. from an image search, can go here too:
save them through Firefox into ~/Downloads, then move them here, with a name
you will recognise. Wren Linux never changes or removes them. Pictures from the
web are often copyrighted: fine on your own screen, but don't share them on.

More to choose from: https://www.pexels.com/search/desktop%20wallpaper/
Free for your own screen, and no credit needed. Their terms don't allow passing the
pictures on as they are, so don't share them as wallpapers. Their licence, which can
change: https://www.pexels.com/license/

wrenctl install wallpapers asks again which to have;
wrenctl remove wallpapers takes out what it put here, nothing of yours. If one of its
pictures is your wallpaper, or you chose "No wallpaper", the default wren comes back.
EOF
}

# copy_set DIR: DIR's pictures and their credits come here; one you already have stays
copy_set() {
    local f name
    for f in "$1"/*.jpg "$1"/*.png; do
        [ -f "$f" ] || continue
        name=${f##*/}
        if [ -e "$DEST/$name" ] && ! grep -qxF -- "$name" "$SHIPPED"; then continue; fi
        install -m 0644 -- "$f" "$DEST/$name"
        grep -qxF -- "$name" "$SHIPPED" || echo "$name" >>"$SHIPPED"
        grep -qF -- "$name: " "$DEST/CREDITS.txt" 2>/dev/null ||
            awk -v n="$name" 'index($0, n ": ") == 1' "$1/CREDITS.txt" >>"$DEST/CREDITS.txt"
    done
}
# drop_set DIR: what it copied from DIR goes again
drop_set() {
    local f name
    for f in "$1"/*.jpg "$1"/*.png; do
        name=${f##*/}
        grep -qxF -- "$name" "$SHIPPED" || continue
        rm -f -- "${DEST:?}/$name"
        forget "$name"
    done
}

# Which: a list when there is a terminal to show it on
chosen=(basic)
if [ -t 0 ] && [ -t 1 ]; then
    . "$WREN_DIR/lib/checklist.sh"
    ITEMS=(basic "Wrens, art, Earth and space (about 24 MB)" ON)
    if [ -d "$PICS/shock" ]; then
        ITEMS+=(strong "Strong: real violence and death, and nudity (about 4 MB)" OFF)
    fi
    CL_TITLE="Wallpapers" CL_OK=Copy CL_CANCEL=Cancel
    CL_TEXT="Which? They go in ~/Pictures/Wallpapers.\nYour own pictures can go there too: nothing of yours is changed or removed."
    checklist || { note "Nothing copied."; exit 0; }
fi

mkdir -p "$DEST"
touch "$SHIPPED"
readme
wanted() { printf '%s\n' "${chosen[@]}" | grep -qx "$1"; }
if wanted basic; then copy_set "$PICS"; else drop_set "$PICS"; fi
if [ -d "$PICS/shock" ]; then
    if wanted strong; then copy_set "$PICS/shock"; else drop_set "$PICS/shock"; fi
fi

note "To use one: Super+] and Super+[ step through them, or: wallpaper pick"
note "Your own pictures can go in $DEST too. $DEST/README.txt says more."
