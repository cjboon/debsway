#!/bin/bash
# Checks bin/wallpaper (the newest real JPEG or PNG in ~/Pictures/debsway/desktop
# goes up; a file that only says it's a picture, an odd file name or an empty
# folder changes nothing), parts/wallpaper.sh (the sway snippet), and
# extras/wallpapers.sh (Debian's collections unpacked, never installed: no
# sudo, no package script, no links; --remove keeps what you added). Uses a
# pretend swaymsg, a pretend apt-get download serving packages built here,
# and a home in a temp folder; SWAYSOCK is unset, so the running sway isn't
# touched. Run by test.sh, or:  bash tools/test-wallpaper.sh
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
unset SWAYSOCK

mkdir -p "$T/fake" "$T/home"
printf '#!/bin/sh\necho "$*" >>"%s/sway"\n' "$T" >"$T/fake/swaymsg"
# sudo: "may I" (-v) is yes; anything else is logged, and refused
printf '#!/bin/sh\n[ "$1" = -v ] && exit 0\necho "sudo $*" >>"%s/sudo"\nexit 1\n' "$T" >"$T/fake/sudo"
chmod +x "$T/fake/"*
png() { printf '\x89PNG\r\n\x1a\n' >"$1"; head -c "${2:-200000}" /dev/zero >>"$1"; }
jpg() { printf '\xff\xd8\xff\xe0' >"$1"; head -c "${2:-200000}" /dev/zero >>"$1"; }
D=$T/home/Pictures/debsway/desktop
C=$T/home/.cache/debsway
wp() { : >"$T/sway"; env PATH="$T/fake:$PATH" HOME="$T/home" XDG_CACHE_HOME="$T/home/.cache" bash "$HERE/bin/wallpaper" "$@" >"$T/out" 2>&1; }

# ---- bin/wallpaper
mkdir -p "$D"
wp
check "an empty folder: sway is left alone (its own setting stays)" test ! -s "$T/sway"
wp status
check "...and status says the default" grep -q "the default" "$T/out"
png "$D/old.png"
touch -d '2026-01-01' "$D/old.png"
jpg "$D/new.JPG"
wp
check "the newest picture goes up, filling the screen" grep -qE '^-q output \* bg ".*/wallpaper-[0-9]+-[0-9]+\.jpg" fill$' "$T/sway"
link=$(sed -E 's/.* bg "([^"]*)".*/\1/' "$T/sway")
check "...through a link to it" test "$(readlink "$link")" = "$D/new.JPG"
printf 'not a picture' >"$D/newest.png"
printf 'GIF89a' >"$D/anim.gif"
wp
check "a file named .png that isn't one is passed over" test "$(readlink "$(sed -E 's/.* bg "([^"]*)".*/\1/' "$T/sway")")" = "$D/new.JPG"
wp status
check "...status names the picture in use" grep -q "Wallpaper: new.JPG" "$T/out"
check "...and why the others aren't used" bash -c 'grep -q "newest.png: not really a JPEG or PNG" "$1" && grep -q "anim.gif: not a .jpg" "$1"' _ "$T/out"
rm "$D/newest.png"
# a file name made to end sway's command and start one of its own
png "$D/x\"; exec touch pwned; \".png"
wp
check "a file name with a quote and ; in it: sway gets only a link named with digits" \
    bash -c 'grep -qE "^-q output \* bg \"[^\";]*/wallpaper-[0-9]+-[0-9]+\.png\" fill$" "$1" && ! grep -q exec "$1"' _ "$T/sway"
check "...that leads to that picture" bash -c 'readlink "$(sed -E "s/.* bg \"([^\"]*)\".*/\1/" "$1")" | grep -q "exec touch"' _ "$T/sway"
check "...and only the one link is kept" test "$(find "$C" -name 'wallpaper-*' | wc -l)" = 1
rm -f "$D/x"*
png "$D/esc$(printf '\033')]52;c;SGk=$(printf '\007').txt"
wp status
check "status prints no escape codes from a file name" not grep -q "$(printf '\033')" "$T/out"
rm -f "$D/"esc*
head -c $((51 * 1024 * 1024)) /dev/zero >>"$D/new.JPG"
touch "$D/new.JPG"
wp status
check "a picture bigger than 50 MB isn't used" grep -q "new.JPG: bigger than 50 MB" "$T/out"

# lib.sh sets PATH itself: a copy that keeps the pretend programs first
R=$T/r
mkdir -p "$R/extras" "$R/parts"
sed 's|^export PATH=.*|export PATH="$WP_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q WP_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
for f in packages.sh pins.sh lib data docs bin; do ln -s "$HERE/$f" "$R/$f"; done
cp "$HERE/extras/wallpapers.sh" "$R/extras/"
cp "$HERE/parts/wallpaper.sh" "$R/parts/"
H=$T/xhome
mkdir -p "$H"
xw() { : >"$T/apt"; env -u SWAYSOCK WP_TEST_PATH="$T/fake:$PATH" HOME="$H" bash "$R/extras/wallpapers.sh" "$@" >"$T/out" 2>&1 </dev/null; }
[ "$(WP_TEST_PATH="$T/fake:$PATH" bash -c '. "$1/lib.sh"; command -v sudo' _ "$R")" = "$T/fake/sudo" ] || { echo "  FAIL  the real sudo would run; stopping"; exit 1; }


# ---- parts/wallpaper.sh: the snippet sway runs at every start and reload
P=$T/part
mkdir -p "$P/home"
if env -u SWAYSOCK WP_TEST_PATH="$T/fake:$PATH" HOME="$P/home" bash "$R/parts/wallpaper.sh" >"$T/out" 2>&1; then :; fi
check "the part: sway runs wallpaper at every start and reload" grep -qx "exec_always $P/home/.local/bin/wallpaper" "$P/home/.config/sway/config.d/wallpaper.conf"
check "...the command is installed, the folder made, with a README" \
    bash -c '[ -x "$1/.local/bin/wallpaper" ] && [ -d "$1/Pictures/debsway/desktop" ] && grep -q "Super+Shift+c" "$1/Pictures/debsway/README.txt"' _ "$P/home"
env -u SWAYSOCK WP_TEST_PATH="$T/fake:$PATH" HOME="$P/home" bash "$R/parts/wallpaper.sh" --remove >"$T/out" 2>&1
check "...--remove takes the snippet and the command, and leaves your pictures" \
    bash -c '[ ! -e "$1/.config/sway/config.d/wallpaper.conf" ] && [ ! -e "$1/.local/bin/wallpaper" ] && [ -d "$1/Pictures/debsway/desktop" ]' _ "$P/home"
check "it's in the base" bash -c '. "$1/packages.sh"; printf "%s\n" "${PARTS[@]}" | grep -qx wallpaper' _ "$HERE"

# ---- extras/wallpapers.sh, with packages built here
# mkdeb NAME: a package like Debian's wallpaper ones
mkdeb() {
    local b=$T/build/$1
    mkdir -p "$b/DEBIAN" "$b/usr/share/doc/$1" "$b/usr/share/backgrounds/$1"
    printf 'Package: %s\nVersion: 1\nArchitecture: all\nMaintainer: t <t@t>\nDescription: t\n' "$1" >"$b/DEBIAN/control"
    # a package script that must never run
    printf '#!/bin/sh\ntouch %s/postinst-ran\n' "$T" >"$b/DEBIAN/postinst"
    chmod 755 "$b/DEBIAN/postinst"
    echo "Licence: CC-BY-SA-4.0" >"$b/usr/share/doc/$1/copyright"
    png "$b/usr/share/backgrounds/$1/big.png"
    png "$b/usr/share/backgrounds/$1/icon.png" 3000
    echo '<svg/>' >"$b/usr/share/backgrounds/$1/vector.svg"
    ln -s /etc/passwd "$b/usr/share/backgrounds/$1/link.png"
}
mkdeb sway-backgrounds
mkdeb desktop-base
# desktop-base: a 1920x1080.png in each theme's images folder
for th in emerald ceratopsian; do
    mkdir -p "$T/build/desktop-base/usr/share/desktop-base/$th-theme/wallpaper/contents/images"
    jpg "$T/build/desktop-base/usr/share/desktop-base/$th-theme/wallpaper/contents/images/1920x1080.jpg"
done
mkdir -p "$T/debs"
for p in sway-backgrounds desktop-base; do dpkg-deb -Zxz --root-owner-group --build "$T/build/$p" "$T/debs/$p.deb" >/dev/null; done
cat >"$T/fake/apt-get" <<EOF
#!/bin/sh
echo "apt-get \$*" >>"$T/apt"
[ "\$1" = download ] || exit 1
for a; do p=\$a; done
[ -f "$T/debs/\$p.deb" ] || { echo "E: Unable to locate package \$p" >&2; exit 100; }
cp "$T/debs/\$p.deb" "./\${p}_1_all.deb"
EOF
chmod +x "$T/fake/apt-get"
W=$H/Pictures/Wallpapers
xw
rc=$?
check "without a terminal: the collections ticked by default are fetched with apt-get download" \
    bash -c 'grep -q "download.* sway-backgrounds$" "$1" && grep -q "download.* gnome-backgrounds$" "$1" && ! grep -q plasma "$1"' _ "$T/apt"
check "...a wallpaper comes out, into a folder per collection" test -f "$W/sway-backgrounds/big.png"
check "...with the package's licence next to it" grep -q CC-BY-SA "$W/sway-backgrounds/LICENCE.txt"
check "...icons (small pictures) and SVGs stay out" bash -c '[ ! -e "$1/icon.png" ] && [ ! -e "$1/vector.svg" ]' _ "$W/sway-backgrounds"
check "...no links come out (a .png pointing at /etc/passwd)" bash -c '[ ! -e "$1/link.png" ] && [ -z "$(find "$2" -type l)" ]' _ "$W/sway-backgrounds" "$W"
check "...nothing is installed: no sudo, no package script ran" bash -c '[ ! -e "$1/sudo" ] && [ ! -e "$1/postinst-ran" ]' _ "$T"
check "...two themes' 1920x1080.jpg both kept, under their own names" \
    test "$(find "$W/desktop-base" -name '*1920x1080.jpg' | wc -l)" = 2
check "...a collection that can't be downloaded is said, and the run fails" bash -c '[ "$1" -ne 0 ] && grep -q "Not downloaded: .*budgie-backgrounds" "$2"' _ "$rc" "$T/out"
n=$(find "$W" -type f | wc -l)
xw
check "run again: the same files, nothing doubled" bash -c '[ "$(find "$1" -type f | wc -l)" = "$2" ] && [ "$(sort "$1/.debsway-wallpapers" | uniq -d | wc -l)" = 0 ]' _ "$W" "$n"
png "$W/sway-backgrounds/mine.png"
xw --remove
check "--remove takes out what it put there" bash -c '[ ! -e "$1/sway-backgrounds/big.png" ] && [ ! -d "$1/desktop-base" ] && [ ! -e "$1/.debsway-wallpapers" ]' _ "$W"
check "...and keeps a picture you added" test -f "$W/sway-backgrounds/mine.png"
check "...no sudo there either" test ! -e "$T/sudo"
check "the summary fits the list (52 characters)" bash -c '[ "$(sed -n "s/^# summary: //p" "$1" | wc -m)" -le 53 ]' _ "$HERE/extras/wallpapers.sh"

[ "$fails" -eq 0 ]
