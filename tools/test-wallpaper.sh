#!/bin/bash
# Checks bin/wallpaper (the newest real JPEG or PNG in ~/Pictures/wren/desktop
# goes up; a file that only says it's a picture, an odd file name or an empty
# folder changes nothing), parts/wallpaper.sh (the sway snippet), and
# extras/wallpapers.sh (copies pictures that come with Wren Linux, fetches nothing,
# strong only if ticked; --remove keeping what you added, and what an earlier
# version fetched from NASA and ESA), and the credits of the pictures themselves.
# Uses a pretend swaymsg and a home in a temp folder; SWAYSOCK is unset, so the running sway isn't
# touched. Run by test.sh, or:  bash tools/test-wallpaper.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
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
# (no notification may pop up on the real desktop)
printf '#!/bin/sh\necho "$*" >>"%s/notify"\n' "$T" >"$T/fake/notify-send"
# sudo: "may I" (-v) is yes; anything else is logged, and refused
printf '#!/bin/sh\n[ "$1" = -v ] && exit 0\necho "sudo $*" >>"%s/sudo"\nexit 1\n' "$T" >"$T/fake/sudo"
chmod +x "$T/fake/"*
png() { printf '\x89PNG\r\n\x1a\n' >"$1"; head -c "${2:-200000}" /dev/zero >>"$1"; }
jpg() { printf '\xff\xd8\xff\xe0' >"$1"; head -c "${2:-200000}" /dev/zero >>"$1"; }
D=$T/home/Pictures/wren/desktop
C=$T/home/.cache/wren
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

# ---- the default: a wren for each theme
rm -f "$D"/*
DF=$T/home/.local/share/wren/wallpapers
mkdir -p "$DF" "$T/home/.config/wren" "$T/home/.config/sway"
jpg "$DF/default-dark.jpg"; jpg "$DF/default-light.jpg"
up() { readlink "$(sed -E 's/.* bg "([^"]*)".*/\1/' "$T/sway")"; }
wp
check "no picture of yours: the default wren goes up, the dark one in the dark theme" test "$(up)" = "$DF/default-dark.jpg"
wp status
check "...and status says so" grep -q "the default wren (dark)" "$T/out"
echo light >"$T/home/.config/wren/theme"
wp
check "the light theme: the light wren (a theme switch reloads sway, which runs this)" test "$(up)" = "$DF/default-light.jpg"
echo dark >"$T/home/.config/wren/theme"
wp
check "...and back again" test "$(up)" = "$DF/default-dark.jpg"
echo 'x; reboot' >"$T/home/.config/wren/theme"
wp
check "a theme file saying something else: dark" test "$(up)" = "$DF/default-dark.jpg"
rm "$T/home/.config/wren/theme"
jpg "$D/mine.jpg"
wp
check "a picture of yours wins, in any theme" test "$(up)" = "$D/mine.jpg"
rm "$D/mine.jpg"
wp none
wp
check "\"no wallpaper\" means no wren either" not grep -q " bg " "$T/sway"
rm -f "$C/chosen-wallpaper"
printf 'output * bg /some/where/mine.png fill\n' >"$T/home/.config/sway/config"
wp
check "a background of your own in your sway config stays" not grep -q " bg " "$T/sway"
printf '# output * bg /usr/share/backgrounds/sway/x.png fill\n' >"$T/home/.config/sway/config"
wp
check "...a commented-out line isn't one" test "$(up)" = "$DF/default-dark.jpg"
rm -f "$T/home/.config/sway/config" "$DF"/*
wp
check "with the defaults gone, sway is left alone" test ! -s "$T/sway"

# ---- choosing from ~/Pictures/Wallpapers: next, previous, pick
rm -f "$D"/*
CO=$T/home/Pictures/Wallpapers
mkdir -p "$CO"
jpg "$CO/earth_eo1a.jpg"
png "$CO/nasa_iss1.png"
jpg "$CO/my mountain_lake.jpg"
printf 'GIF89a' >"$CO/not-a.jpg"
printf '\xff\xd8\xff' >"$CO/found.webp"
printf 'earth_eo1a.jpg: A vista of stellar birth. Credit: NASA Earth Observatory. https://x\nnasa_iss1.png: Aurora over the sea. Credit: NASA. https://y\n' >"$CO/CREDITS.txt"
touch -d '2026-01-01' "$CO/earth_eo1a.jpg"
touch -d '2026-02-01' "$CO/nasa_iss1.png"
touch -d '2026-03-01' "$CO/my mountain_lake.jpg"
mine() { readlink "$(sed -E 's/.* bg "([^"]*)".*/\1/' "$T/sway" | tail -1)"; }
wp next
check "Super+]: the first picture of the folder, up at once, kept as chosen.jpg in the desktop folder" \
    bash -c '[ "$(cat "$1")" = earth_eo1a.jpg ] && cmp -s "$2/earth_eo1a.jpg" "$3/chosen.jpg" && [ "$4" = "$3/chosen.jpg" ]' _ "$C/chosen-wallpaper" "$CO" "$D" "$(mine)"
wp next
check "...again: the next one, by name" \
    bash -c '[ "$(cat "$1")" = my\ mountain_lake.jpg ] && [ -f "$2/chosen.jpg" ] && [ ! -e "$2/chosen.png" ]' _ "$C/chosen-wallpaper" "$D"
wp next
check "...and the next (a PNG: chosen.png, the JPEG gone; files that aren't JPEG or PNG passed over)" bash -c '[ "$(cat "$1")" = nasa_iss1.png ] && [ -f "$2/chosen.png" ] && [ ! -e "$2/chosen.jpg" ]' _ "$C/chosen-wallpaper" "$D"
wp next
check "...past the last, round to the first" test "$(cat "$C/chosen-wallpaper")" = earth_eo1a.jpg
wp previous
check "Super+[: back round to the last" test "$(cat "$C/chosen-wallpaper")" = nasa_iss1.png
check "...its name shows in a notification for a moment" grep -q "Wallpaper NASA: Aurora over the sea" "$T/notify"
wp status
check "status names it by its title from CREDITS.txt" grep -q "Wallpaper: NASA: Aurora over the sea" "$T/out"
check "...and says why a WebP or a fake JPEG isn't used" bash -c 'grep -q "found.webp: a WebP picture" "$1" && grep -q "not-a.jpg: not really a JPEG" "$1"' _ "$T/out"
jpg "$D/my-own.jpg"
wp
check "a picture you copy into the desktop folder later wins over the chosen one" test "$(mine)" = "$D/my-own.jpg"
rm "$D/my-own.jpg"
# pick: a pretend wmenu shows what it was given and answers with line 3
cat >"$T/fake/wmenu" <<EOF
#!/bin/sh
cat >"$T/menu"
sed -n 3p "$T/menu"
EOF
chmod +x "$T/fake/wmenu"
wp pick
check "Super+Shift+w: \"0  No wallpaper\" first, then newest first, by title (yours by its tidied name)" \
    bash -c '[ "$(sed -n 1p "$1")" = "0  No wallpaper" ] && [ "$(sed -n 2p "$1")" = "1  my mountain lake" ] && [ "$(sed -n 3p "$1")" = "2  NASA: Aurora over the sea" ] && [ "$(sed -n 4p "$1")" = "3  Earth Observatory: A vista of stellar birth" ] && [ "$(wc -l <"$1")" = 4 ]' _ "$T/menu"
check "...the line picked becomes the wallpaper" bash -c '[ "$(cat "$1")" = nasa_iss1.png ] && [ -f "$2/chosen.png" ]' _ "$C/chosen-wallpaper" "$D"
printf '#!/bin/sh\ncat >/dev/null\necho "99  nope"\n' >"$T/fake/wmenu"
before=$(cat "$C/chosen-wallpaper")
wp pick
check "...an answer that isn't one of the lines changes nothing" test "$(cat "$C/chosen-wallpaper")" = "$before"
printf '#!/bin/sh\ncat >/dev/null\nexit 1\n' >"$T/fake/wmenu"
wp pick
check "...nor does Esc" test "$(cat "$C/chosen-wallpaper")" = "$before"
# a file name made to put escape codes on the screen, in the list
jpg "$CO/x$(printf '\033')]52;c;SGk=$(printf '\007').jpg"
printf '#!/bin/sh\ncat >"%s/menu"\nexit 1\n' "$T" >"$T/fake/wmenu"
wp pick
check "...a file name's escape codes never reach the list" not grep -q "$(printf '\033')" "$T/menu"
rm -f "$CO"/x*
# no wallpaper: Super+\, or "0  No wallpaper" in the list
jpg "$D/my-own.jpg"
touch -d '2026-01-01' "$D/my-own.jpg"
wp next
wp none
check "Super+\\ (no wallpaper): the chosen picture goes, and sway reloads its own background" \
    bash -c '[ ! -e "$1/chosen.jpg" ] && [ ! -e "$1/chosen.png" ] && [ "$(cat "$2")" = none ] && grep -qx -- "-q reload" "$3"' _ "$D" "$C/chosen-wallpaper" "$T/sway"
wp
check "...at the reload (or the next login) no picture goes up, not even an older one of yours" not grep -q " bg " "$T/sway"
wp status
check "...status says no wallpaper" grep -q "Wallpaper: none" "$T/out"
touch -d 'now + 5 seconds' "$D/my-own.jpg"
wp
check "...until you copy a newer picture into the desktop folder" test "$(mine)" = "$D/my-own.jpg"
rm "$D/my-own.jpg"
wp next
printf '#!/bin/sh\ncat >/dev/null\necho "0  No wallpaper"\n' >"$T/fake/wmenu"
wp pick
check "...\"0  No wallpaper\" in the list does the same" bash -c '[ "$(cat "$1")" = none ] && [ ! -e "$2/chosen.jpg" ] && [ ! -e "$2/chosen.png" ]' _ "$C/chosen-wallpaper" "$D"
wp next
check "...and the next Super+] chooses one again" test -f "$D/chosen.jpg" -o -f "$D/chosen.png"
rm -rf "${CO:?}" "${D:?}"/* "${C:?}"
mkdir -p "$D"

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
[ "$(WP_TEST_PATH="$T/fake:$PATH" bash -c '. "$1/lib.sh"; command -v sudo' _ "$R")" = "$T/fake/sudo" ] || { echo "  FAIL  the real sudo would run; stopping"; exit 1; }


# ---- parts/wallpaper.sh: the snippet sway runs at every start and reload
P=$T/part
mkdir -p "$P/home"
if env -u SWAYSOCK WP_TEST_PATH="$T/fake:$PATH" HOME="$P/home" bash "$R/parts/wallpaper.sh" >"$T/out" 2>&1; then :; fi
check "the part: sway runs wallpaper at every start and reload" grep -qx "exec_always $P/home/.local/bin/wallpaper" "$P/home/.config/sway/config.d/wallpaper.conf"
check "...Super+] and Super+[ step through the pictures, Super+Shift+w lists them, Super+\\ is none" \
    bash -c 'grep -qx "bindsym \$mod+bracketright exec $2/wallpaper next" "$1" && grep -qx "bindsym \$mod+bracketleft exec $2/wallpaper previous" "$1" && grep -qx "bindsym \$mod+Shift+w exec $2/wallpaper pick" "$1" && grep -qx "bindsym \$mod+backslash exec $2/wallpaper none" "$1"' _ "$P/home/.config/sway/config.d/wallpaper.conf" "$P/home/.local/bin"
check "...the two default wrens, and their credits" \
    bash -c 'd=$1/.local/share/wren/wallpapers; cmp -s "$d/default-light.jpg" "$2/wren-explored.jpg" && cmp -s "$d/default-dark.jpg" "$2/wren-juvenile.jpg" && grep -q "^wren-juvenile.jpg: " "$d/CREDITS.txt"' _ "$P/home" "$HERE/data/wallpapers"
check "...which get no extra: it costs the base about 2 MB" bash -c '[ "$(du -sk "$1/.local/share/wren/wallpapers" | cut -f1)" -lt 4000 ]' _ "$P/home"
check "...its README doesn't promise pictures from outside" not grep -qE 'NASA|Budgie' "$P/home/Pictures/wren/README.txt"
check "...the command is installed, the desktop and firefox folders made, with a README" \
    bash -c '[ -x "$1/.local/bin/wallpaper" ] && [ -d "$1/Pictures/wren/desktop" ] && [ -d "$1/Pictures/wren/firefox" ] && grep -q "Super+Shift+c" "$1/Pictures/wren/README.txt" && grep -q "^firefox/" "$1/Pictures/wren/README.txt"' _ "$P/home"
env -u SWAYSOCK WP_TEST_PATH="$T/fake:$PATH" HOME="$P/home" bash "$R/parts/wallpaper.sh" --remove >"$T/out" 2>&1
check "...--remove takes the default wrens" test ! -e "$P/home/.local/share/wren/wallpapers/default-dark.jpg"
check "...--remove takes the snippet and the command, and leaves your pictures" \
    bash -c '[ ! -e "$1/.config/sway/config.d/wallpaper.conf" ] && [ ! -e "$1/.local/bin/wallpaper" ] && [ -d "$1/Pictures/wren/desktop" ]' _ "$P/home"
check "it's in the base" bash -c '. "$1/packages.sh"; printf "%s\n" "${PARTS[@]}" | grep -qx wallpaper' _ "$HERE"

# ---- extras/wallpapers.sh, with a small set of pictures of its own
R3=$T/r3
mkdir -p "$R3/extras" "$R3/lib" "$R3/data/wallpapers/shock"
cp "$R/lib.sh" "$R3/lib.sh"
for f in packages.sh pins.sh docs bin; do ln -s "$HERE/$f" "$R3/$f"; done
for f in "$HERE"/lib/*; do ln -s "$f" "$R3/lib/${f##*/}"; done
for f in "$HERE"/data/*; do [ "${f##*/}" = wallpapers ] || ln -s "$f" "$R3/data/${f##*/}"; done
cp "$HERE/extras/wallpapers.sh" "$R3/extras/"
P3=$R3/data/wallpapers
jpg "$P3/wren.jpg"; png "$P3/nasa_new.png"; jpg "$P3/nasa_mine.jpg"
printf 'Header line.\n\nwren.jpg: A wren. Credit: Someone. https://x.example/w. Licence: CC0.\nnasa_new.png: Space. Credit: NASA. https://x.example/n. Licence: PD.\nnasa_mine.jpg: Mine. Credit: NASA. https://x.example/m. Licence: PD.\n' >"$P3/CREDITS.txt"
jpg "$P3/shock/hard.jpg"
printf 'hard.jpg: Hard. Credit: Someone. https://x.example/h. Licence: CC0.\n' >"$P3/shock/CREDITS.txt"
# nothing may be fetched or installed: every one of these logs, if it is run
for c in apt-get wget curl python3; do printf '#!/bin/sh\necho "%s $*" >>"%s/apt"\n' "$c" "$T" >"$T/fake/$c"; chmod +x "$T/fake/$c"; done
H=$T/h3
W=$H/Pictures/Wallpapers
mkdir -p "$W"
# from before: a list with what an earlier version fetched, and a bigger nasa_mine.jpg
jpg "$W/nasa_old.jpg"; jpg "$W/budgie_old.jpg"; jpg "$W/nasa_mine.jpg" 900000
big=$(stat -c %s "$W/nasa_mine.jpg")
printf 'nasa_old.jpg: Old. Credit: NASA.\n' >"$W/CREDITS.txt"
printf 'nasa_old.jpg\nbudgie_old.jpg\nnasa_mine.jpg\nCREDITS.txt\n../mine.png\ninner/found.png\n' >"$W/.wren-wallpapers"
png "$W/mine.png"; mkdir -p "$W/inner"; png "$W/inner/found.png"
xw() { : >"$T/apt"; env -u SWAYSOCK WP_TEST_PATH="$T/fake:$PATH" HOME="$H" bash "$R3/extras/wallpapers.sh" "$@" >"$T/out" 2>&1; }
xw
rc=$?
check "without a terminal: the basic set is copied in" bash -c '[ -f "$1/wren.jpg" ] && [ -f "$1/nasa_new.png" ]' _ "$W"
check "...and never the strong one" test ! -e "$W/hard.jpg"
check "...nothing fetched, nothing installed: no apt, wget, python or sudo" bash -c '[ ! -s "$1/apt" ] && [ ! -e "$1/sudo" ]' _ "$T"
check "...their credits join yours in CREDITS.txt, in the form bin/wallpaper reads" \
    bash -c 'grep -q "^wren.jpg: A wren. Credit:" "$1" && grep -q "^nasa_old.jpg: Old" "$1" && ! grep -q "Header line" "$1"' _ "$W/CREDITS.txt"
check "...a picture you already have stays yours, bigger original and all" test "$(stat -c %s "$W/nasa_mine.jpg")" = "$big"
check "...a README, which says your own pictures can go there too" grep -q "Your own pictures" "$W/README.txt"
check "...and where to find more for your own screen, with its licence" \
    bash -c 'grep -q "https://www.pexels.com/search/desktop%20wallpaper/" "$1/README.txt" && grep -q "https://www.pexels.com/license/" "$1/README.txt"' _ "$W"
check "...and the run succeeds" test "$rc" -eq 0
n=$(find "$W" -type f | wc -l)
xw
check "run again: the same files, no credit doubled" \
    bash -c '[ "$(find "$1" -type f | wc -l)" = "$2" ] && [ "$(sort "$1/CREDITS.txt" | uniq -d | wc -l)" = 0 ]' _ "$W" "$n"
echo "my notes" >"$W/README.txt"
xw
check "a README you rewrote yourself is left alone" grep -qx "my notes" "$W/README.txt"
rm "$W/README.txt"

# With a terminal: the list. A stand-in for lib/checklist.sh; script(1) gives the run a terminal
rm "$R3/lib/checklist.sh"
cat >"$R3/lib/checklist.sh" <<'EOF'
# shellcheck shell=bash
checklist() { printf '%s\n' "${ITEMS[@]}" >"$CL_SEEN"; read -ra chosen <"$CL_PICK"; [ -n "${chosen[*]}" ]; }
EOF
ty() { echo "$1" >"$T/pick"; env -u SWAYSOCK WP_TEST_PATH="$T/fake:$PATH" HOME="$H" CL_SEEN="$T/seen" CL_PICK="$T/pick" script -qec "bash $R3/extras/wallpapers.sh" /dev/null >"$T/out" 2>&1 </dev/null; }
ty 'basic strong'
check "the list: basic ticked, strong not, and it says what strong holds" \
    bash -c 'grep -A2 -x basic "$1" | tail -1 | grep -qx ON && grep -A2 -x strong "$1" | tail -1 | grep -qx OFF && grep -A1 -x strong "$1" | grep -qi "violence and death, and nudity"' _ "$T/seen"
check "...no Budgie and no \"none\" to pick" bash -c '! grep -qix -e budgie -e none "$1"' _ "$T/seen"
check "ticked: the strong pictures come too, with their credits" bash -c '[ -f "$1/hard.jpg" ] && grep -q "^hard.jpg: Hard" "$1/CREDITS.txt"' _ "$W"
ty basic
check "unticked again: they go, and their credits" bash -c '[ ! -e "$1/hard.jpg" ] && ! grep -q "^hard.jpg" "$1/CREDITS.txt" && [ -f "$1/wren.jpg" ]' _ "$W"
ty strong
check "strong alone: no basic ones are forced on you" bash -c '[ -f "$1/hard.jpg" ]' _ "$W"
ty basic
mv "$P3/shock" "$T/shock-away"
ty basic
check "with no strong set in this copy, it isn't offered" not grep -qx strong "$T/seen"
mv "$T/shock-away" "$P3/shock"

xw --remove
check "--remove takes out the copied pictures and their credits" \
    bash -c '[ ! -e "$1/wren.jpg" ] && [ ! -e "$1/nasa_new.png" ] && ! grep -q "^wren.jpg" "$1/CREDITS.txt" && [ ! -e "$1/.wren-shipped" ]' _ "$W"
check "...and what an earlier version fetched from Debian" test ! -e "$W/budgie_old.jpg"
check "...but never the NASA and ESA pictures an earlier version fetched, or their credits" \
    bash -c '[ -f "$1/nasa_old.jpg" ] && [ -f "$1/nasa_mine.jpg" ] && grep -q "^nasa_old.jpg" "$1/CREDITS.txt"' _ "$W"
check "...and keeps what you added, in the folder or below, whatever the list says" \
    bash -c '[ -f "$1/mine.png" ] && [ -f "$1/inner/found.png" ]' _ "$W"
check "...no sudo there either" test ! -e "$T/sudo"

# ---- the pictures that ship with Wren Linux: each named in the credits, with its author,
# page and licence, or it can't be shipped
PICS=$HERE/data/wallpapers
uncredited=
for f in "$PICS"/*.jpg "$PICS"/*.jpeg "$PICS"/*.png "$PICS"/shock/*.jpg "$PICS"/shock/*.png; do
    [ -e "$f" ] || continue
    line=$(grep -F "${f##*/}: " "${f%/*}/CREDITS.txt" | grep -m1 "^${f##*/}: ")
    grep -q '\. Credit: .*https://.*Licence: .*Changes: ' <<<"$line" || uncredited+=" ${f##*/}"
done
check "every picture in data/wallpapers has its author, page, licence and changes in CREDITS.txt${uncredited:+: not$uncredited}" test -z "$uncredited"
big=$(find "$PICS" -type f -size +3M -printf '%f ')
check "...and none is over 3 MB: git keeps them forever${big:+: $big}" test -z "$big"
check "...there is at least the wren" test -f "$PICS/eurasian-wren.jpg"
check "...and the README says the MIT licence doesn't cover them" grep -q 'data/wallpapers/' "$HERE/README.md"

check "the summary fits the list (52 characters)" bash -c '[ "$(sed -n "s/^# summary: //p" "$1" | wc -m)" -le 53 ]' _ "$HERE/extras/wallpapers.sh"

[ "$fails" -eq 0 ]
