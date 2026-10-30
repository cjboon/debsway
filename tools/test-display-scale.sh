#!/bin/bash
# Checks bin/display-scale's sharp-screen notice and list with a pretend sway
# and pretend screen data (EDID) in a temp folder: a 13-inch 1920x1080 laptop
# panel is sharp (166 pixels per inch), a VM's Virtual-1 screen is not judged
# (QEMU makes its size up; it came out at 328). Run by test.sh, or:
#   bash tools/test-display-scale.sh
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DS=$HERE/bin/display-scale
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

# edid FILE WIDTH-MM HEIGHT-MM: the first 128 bytes of a screen's EDID, with that
# image size in its first detailed timing
edid() {
    python3 -I -c '
import sys
w, h = int(sys.argv[2]), int(sys.argv[3])
b = bytearray(128)
b[0:8] = bytes([0, 255, 255, 255, 255, 255, 255, 0])
b[21], b[22] = w // 10, h // 10
b[54], b[55] = 0x3a, 0x02            # a pixel clock: a real timing
b[66], b[67], b[68] = w & 255, h & 255, ((w >> 8) << 4) | (h >> 8)
open(sys.argv[1], "wb").write(b)' "$1" "$2" "$3"
}
mkdir -p "$T/drm/card0-eDP-1" "$T/drm/card0-Virtual-1" "$T/fake" "$T/home"
edid "$T/drm/card0-eDP-1/edid" 294 165
edid "$T/drm/card0-Virtual-1/edid" 99 62
# outputs FILE: the screens the pretend sway has
cat >"$T/fake/swaymsg" <<SH
#!/bin/sh
case "\$*" in
    *get_version*) exit 0 ;;
    *get_outputs*) cat "$T/outputs" ;;
    *subscribe*) exit 0 ;;
esac
SH
printf '#!/bin/sh\necho "$*" >>"%s/notified"\n' "$T" >"$T/fake/notify-send"
printf '#!/bin/sh\nexit 0\n' >"$T/fake/sleep"
chmod +x "$T/fake/"*
run() { env PATH="$T/fake:$PATH" HOME="$T/home" XDG_STATE_HOME="$T/state" DEBSWAY_DRM_DIR="$T/drm" sh "$DS" "$@"; }
screen() { printf "Output %s '%s'\n  Current mode: %s @ 60.000 Hz\n  Scale factor: 1.000000\n" "$@"; }

screen eDP-1 'Some Panel 0x1234' 1920x1080 >"$T/outputs"
: >"$T/notified"
run watch
check "a sharp laptop screen at scale 1 gets the notice (166 pixels per inch)" grep -q '166 pixels per inch' "$T/notified"
: >"$T/notified"
run watch
check "...once" test ! -s "$T/notified"
check "its list shows the size and sharpness" grep -q '294x165 mm, 166 pixels per inch' <<<"$(run list)"
# a screen wider than 255 mm keeps the top bits of its width (read as x16, a 294 mm
# panel came out 54 mm wide and 903 pixels per inch); and a big one, 527x296 mm
edid "$T/drm/card0-eDP-1/edid" 527 296
screen eDP-1 'Big Screen 0x1' 1920x1080 >"$T/outputs"
check "a 24-inch screen is 527x296 mm, 93 pixels per inch, not sharp" grep -q '527x296 mm, 93 pixels per inch, scale 1, suggested 1$' <<<"$(run list)"
edid "$T/drm/card0-eDP-1/edid" 294 165

rm -rf "$T/state"
screen Virtual-1 'Unknown Unknown Unknown' 1280x800 >"$T/outputs"
: >"$T/notified"
run watch
check "a VM's screen gets no notice (QEMU's made-up size gave 328 pixels per inch)" test ! -s "$T/notified"
check "...and its list says why the sharpness is unknown" grep -q "a VM's screen, no real size" <<<"$(run list)"

[ "$fails" -eq 0 ]
