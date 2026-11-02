#!/bin/bash
# Checks bin/wallpaper (the newest real JPEG or PNG in ~/Pictures/debsway/desktop
# goes up; a file that only says it's a picture, an odd file name or an empty
# folder changes nothing), parts/wallpaper.sh (the sway snippet), and
# extras/wallpapers.sh (every source in one folder, named after it; Budgie's
# unpacked from Debian's package, never installed: no sudo, no package
# script, no links; personal/ and --remove keeping what you added) and
# lib/wallpaper-sources.py's rules (only https, to each source's own hosts;
# size from the file, shape, credit; the feeds read right), offline. Uses a
# pretend swaymsg, a pretend apt-get download serving a package built here, a
# pretend download from the sources,
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
mkdeb budgie-backgrounds
# two pictures with the same name in different folders
for th in evening morning; do
    mkdir -p "$T/build/budgie-backgrounds/usr/share/backgrounds/budgie/$th"
    jpg "$T/build/budgie-backgrounds/usr/share/backgrounds/budgie/$th/1920x1080.jpg"
done
mkdir -p "$T/debs"
dpkg-deb -Zxz --root-owner-group --build "$T/build/budgie-backgrounds" "$T/debs/budgie-backgrounds.deb" >/dev/null
cat >"$T/fake/apt-get" <<EOF
#!/bin/sh
echo "apt-get \$*" >>"$T/apt"
[ "\$1" = download ] || exit 1
for a; do p=\$a; done
[ -f "$T/debs/\$p.deb" ] || { echo "E: Unable to locate package \$p" >&2; exit 100; }
cp "$T/debs/\$p.deb" "./\${p}_1_all.deb"
EOF
# python3 -I wallpaper-sources.py DEST SOURCE COUNT: two pictures named after
# the source, a credits line, and names that try to reach outside the folder
# or another source's files (none of those may get on the list)
cat >"$T/fake/python3" <<EOF
#!/bin/sh
echo "python3 \$*" >>"$T/apt"
[ -e "$T/fails-\$4" ] && exit 1
for n in A1 B2; do printf '\377\330\377' >"\$3/\$4_\$n.jpg"; echo "\$4_\$n.jpg"; done
echo "\$4_A1.jpg: credit" >>"\$3/CREDITS.txt"
echo "../../.bashrc"
echo "\$4_x/../../.bashrc"
echo "personal/found.png"
echo "nasa_not-mine.jpg"
EOF
chmod +x "$T/fake/apt-get" "$T/fake/python3"
W=$H/Pictures/Wallpapers
xw
rc=$?
check "without a terminal: every source, Budgie's with apt-get download" \
    bash -c 'grep -q "download.* budgie-backgrounds$" "$1" && for s in "nasa 24" "hubble 12" "webb 12" "earth 10" "wild 32"; do grep -q "python3 -I .*/lib/wallpaper-sources.py $2 $s$" "$1" || exit 1; done' _ "$T/apt" "$W"
check "...all in one folder, named after the source" \
    bash -c 'for f in budgie_big.png nasa_A1.jpg hubble_A1.jpg webb_B2.jpg earth_B2.jpg wild_A1.jpg; do [ -f "$1/$f" ] || exit 1; done' _ "$W"
check "...Budgie's licence next to them" grep -q CC-BY-SA "$W/budgie_LICENCE.txt"
check "...icons (small pictures) and SVGs stay out" bash -c '[ ! -e "$1/budgie_icon.png" ] && [ -z "$(find "$1" -name "*.svg")" ]' _ "$W"
check "...no links come out (a .png pointing at /etc/passwd)" bash -c '[ ! -e "$1/budgie_link.png" ] && [ -z "$(find "$1" -type l)" ]' _ "$W"
check "...nothing is installed: no sudo, no package script ran" bash -c '[ ! -e "$1/sudo" ] && [ ! -e "$1/postinst-ran" ]' _ "$T"
check "...two pictures with the same name both kept, under their own names" \
    test "$(find "$W" -name 'budgie_*1920x1080.jpg' | wc -l)" = 2
check "...the downloads are on the list; paths out of the folder, personal/ and another source's names aren't" \
    bash -c 'grep -qx hubble_A1.jpg "$1" && grep -qx CREDITS.txt "$1" && ! grep -qE "\.\.|/" "$1" && [ "$(grep -c "^nasa_not-mine" "$1")" = 1 ]' _ "$W/.debsway-wallpapers"
check "...a personal folder for your own, and a README" bash -c '[ -d "$1/personal" ] && grep -q "personal/" "$1/README.txt"' _ "$W"
check "...and the run succeeds" test "$rc" -eq 0
n=$(find "$W" -type f | wc -l)
xw
check "run again: the same files, nothing doubled" bash -c '[ "$(find "$1" -type f | wc -l)" = "$2" ] && [ "$(sort "$1/.debsway-wallpapers" | uniq -d | wc -l)" = 0 ]' _ "$W" "$n"
echo "my notes" >"$W/README.txt"
xw
check "a README you rewrote yourself is left alone" grep -qx "my notes" "$W/README.txt"
rm "$W/README.txt"
touch "$T/fails-webb"
xw
rc=$?
check "a source failing is said, and the run fails" bash -c '[ "$1" -ne 0 ] && grep -q "Not downloaded: webb" "$2"' _ "$rc" "$T/out"
rm "$T/fails-webb"
png "$W/mine.png"
png "$W/personal/found.png"
echo "../mine.png" >>"$W/.debsway-wallpapers"
echo "personal/found.png" >>"$W/.debsway-wallpapers"
xw --remove
check "--remove takes out what it put there" \
    bash -c '[ ! -e "$1/budgie_big.png" ] && [ ! -e "$1/nasa_A1.jpg" ] && [ ! -e "$1/CREDITS.txt" ] && [ ! -e "$1/.debsway-wallpapers" ]' _ "$W"
check "...and keeps what you added, personal/ and all, whatever the list says" \
    bash -c '[ -f "$1/mine.png" ] && [ -f "$1/personal/found.png" ]' _ "$W"
check "...no sudo there either" test ! -e "$T/sudo"

# ---- lib/wallpaper-sources.py's rules, offline (no connection is made)
cat >"$T/rules.py" <<'PY'
import importlib.util, json, struct, sys, urllib.error
spec = importlib.util.spec_from_file_location("ws", sys.argv[1])
n = importlib.util.module_from_spec(spec); spec.loader.exec_module(n)
for good in ("https://images-assets.nasa.gov/x", "https://cdn.esahubble.org/x",
             "https://cdn.esawebb.org/x", "https://assets.science.nasa.gov/x"):
    assert n.allowed(good), good
for bad in ("http://images-assets.nasa.gov/x", "https://evil.example/x",
            "https://cdn.esahubble.org.evil.example/x", "file:///etc/passwd"):
    assert not n.allowed(bad), bad
    try:
        n.fetch(bad, 10)
        raise SystemExit("fetched " + bad)
    except ValueError:
        pass
try:
    n.HttpsOnly().redirect_request(None, None, 302, "", {}, "http://cdn.esahubble.org/x")
    raise SystemExit("followed a redirect to http")
except urllib.error.HTTPError:
    pass
# sizes read from the file itself
png = b"\x89PNG\r\n\x1a\n" + b"\0\0\0\rIHDR" + struct.pack(">II", 2560, 1440) + b"\0" * 20
assert n.picture_size(png) == (2560, 1440)
app0 = b"\xff\xe0" + struct.pack(">H", 16) + b"JFIF\0" + b"\0" * 9
sof = b"\xff\xc0" + struct.pack(">HBHH", 17, 8, 1200, 1920) + b"\0" * 10
assert n.picture_size(b"\xff\xd8" + app0 + sof) == (1920, 1200)
assert n.picture_size(b"<html>") is None and n.picture_size(b"\xff\xd8\x00\x00") is None
assert n.size_ok(1920, 1200) is None and n.size_ok(4613, 3318) is None
assert "smaller" in n.size_ok(1280, 720)
assert "landscape" in n.size_ok(2160, 3840)
# NASA's library: size, type and credit
ok = {"File:ImageWidth": 2800, "File:ImageHeight": 1400, "File:MIMEType": "image/jpeg", "XMP:Credit": "NASA/JPL-Caltech"}
assert n.nasa_why_not({"description": "Photo Credit: (NASA/Bill Ingalls)"}, ok) is None
assert "JPEG" in n.nasa_why_not({}, dict(ok, **{"File:MIMEType": "image/tiff"}))
assert "copyright" in n.nasa_why_not({}, dict(ok, **{"XMP:Credit": "© Getty Images"}))
assert "copyright" in n.nasa_why_not({"secondary_creator": "AP Photo/Someone"}, ok)
assert n.picture_kind(b"\xff\xd8\xff\xe0") == "jpg" and n.picture_kind(png) == "png"
assert n.clean("a\x1b]52;c;x\x07b") == "a ]52;c;x b"
for bad in ("../x", "a/b", "", "x" * 101):
    assert not n.ID_RE.match(bad), bad
real_fetch = n.fetch
n.fetch = lambda url, limit: b'["http://images-assets.nasa.gov/image/A/A~orig.jpg"]'
assert n.nasa_original("A") == "https://images-assets.nasa.gov/image/A/A~orig.jpg"
n.fetch = lambda url, limit: b'["https://evil.example/A~orig.jpg"]'
assert n.nasa_original("A") is None
# ESA's feeds: ESA's wallpaper cut on ESA's own CDN; another host's link is ignored
n.fetch = lambda url, limit: (b'<rss><item><title>Stars</title><link>https://esawebb.org/images/potm2610a/</link>'
    b'<enclosure url="https://cdn.esawebb.org/archives/images/screen/potm2610a.jpg"/></item>'
    b'<item><title>Bad</title><enclosure url="https://evil.example/archives/images/screen/x.jpg"/></item></rss>')
got = list(n.esa("webb"))
assert got == [("potm2610a", "https://cdn.esawebb.org/archives/images/wallpaper4/potm2610a.jpg", "Stars",
                "ESA/Webb (CC BY 4.0). https://esawebb.org/images/potm2610a/")], got
# Earth Observatory: only the large files on NASA's asset host; a credit
# naming another copyright holder skips the item
n.fetch = lambda url, limit: ('<item><title>Canyon</title><link>https://science.nasa.gov/x/</link>'
    '<span class="credits">NASA Earth Observatory/M. G.</span>'
    '<a href="https://assets.science.nasa.gov/content/dam/eo/canyon_oli_lrg.jpg">x</a>'
    '<img src="https://assets.science.nasa.gov/content/dam/eo/canyon_oli_lrg.jpg/jcr:content/renditions/t.png">'
    '<a href="https://evil.example/content/dam/x_lrg.jpg">y</a></item>'
    '<item><title>Theirs</title><span class="credits">© Someone</span>'
    '<a href="https://assets.science.nasa.gov/content/dam/eo/theirs_lrg.jpg">z</a></item>').encode()
got = list(n.earth())
assert [g[0] for g in got] == ["canyon_oli_lrg"], got
assert got[0][1] == "https://assets.science.nasa.gov/content/dam/eo/canyon_oli_lrg.jpg"
# Commons' wild animals: free licences only, no farm animals or artworks,
# landscape, links only to Wikimedia's hosts, each photographer credited
def info(lic="cc-by-sa-4.0", w=3840, h=2560, url="https://upload.wikimedia.org/a/Fox.jpg", artist="<a href='x'>Jo</a>"):
    return {"thumburl": url, "thumbwidth": w, "thumbheight": h, "mime": "image/jpeg",
            "extmetadata": {"License": {"value": lic}, "LicenseShortName": {"value": "CC BY-SA 4.0"},
                            "Artist": {"value": artist}}}
assert n.wild_why_not("File:Red fox in snow.jpg", info()) is None
assert n.wild_why_not("File:Fox.jpg", info(lic="cc0")) is None and n.wild_why_not("File:Fox.jpg", info(lic="pd")) is None
assert "licence" in n.wild_why_not("File:Fox.jpg", info(lic="cc-by-nc-4.0"))
assert "licence" in n.wild_why_not("File:Fox.jpg", info(lic=""))
for t in ("File:Cow on a hill.jpg", "File:Horse mosaic - Google Art Project.jpg", "File:Tiger skull.jpg", "File:Lion at the zoo.jpg"):
    assert "wild" in n.wild_why_not(t, info()), t
assert "landscape" in n.wild_why_not("File:Fox.jpg", info(w=2560, h=3840))
pages = {"1": {"title": "File:Red fox (Vulpes vulpes).jpg", "imageinfo": [info()]},
         "2": {"title": "File:Cow.jpg", "imageinfo": [info()]},
         "3": {"title": "File:Owl.jpg", "imageinfo": [info(url="https://evil.example/Owl.jpg")]}}
n.fetch = lambda url, limit: json.dumps({"query": {"pages": pages}}).encode()
n.WILD_GROUPS = ["birds"]
got = list(n.wild())
assert [g[0] for g in got] == ["Red_fox__Vulpes_vulpes"], got
assert got[0][1] == "https://upload.wikimedia.org/a/Fox.jpg" and got[0][3].startswith("Jo (CC BY-SA 4.0), Wikimedia Commons."), got
PY
check "the sources: only https, only their own hosts, also after a redirect; sizes, credits and feeds read right" \
    python3 -I -B "$T/rules.py" "$HERE/lib/wallpaper-sources.py"
check "the summary fits the list (52 characters)" bash -c '[ "$(sed -n "s/^# summary: //p" "$1" | wc -m)" -le 53 ]' _ "$HERE/extras/wallpapers.sh"

[ "$fails" -eq 0 ]
