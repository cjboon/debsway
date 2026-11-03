#!/bin/bash
# Checks bin/media-sandbox with a pretend bubblewrap and a pretend
# wayland-restrict that only write down how they were called: what the
# program is shown, and which kinds of address switch the network on.
# Changes nothing. Run by test.sh, or:  bash tools/test-media-sandbox.sh
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

mkdir -p "$T/fake" "$T/run" "$T/home"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"%s/bwrap.args"\n' "$T" >"$T/fake/bwrap"
# wayland-restrict: say it is ready, then wait until its input closes
printf '#!/bin/sh\necho ready\ncat >/dev/null\n' >"$T/fake/wayland-restrict"
chmod +x "$T/fake/"*
echo x >"$T/video.mp4"
export PATH="$T/fake:$PATH" HOME="$T/home" XDG_RUNTIME_DIR="$T/run" WAYLAND_DISPLAY=wayland-1
: >"$T/run/wayland-1"

# (a copy that uses a pretend no-abstract-sockets wrapper, which writes down that it ran)
printf '#!/bin/sh\necho wrapped >"%s/noabs.ran"\nexec "$@"\n' "$T" >"$T/fake/noabs"
chmod +x "$T/fake/noabs"
sed "s|/usr/local/libexec/wren-no-abstract-sockets|$T/fake/noabs|" "$HERE/bin/media-sandbox" >"$T/media-sandbox"
run() { rm -f "$T/bwrap.args" "$T/noabs.ran"; bash "$T/media-sandbox" "$@"; }
args() { cat "$T/bwrap.args"; }

run mpv "$T/video.mp4"
check "a file on the command line is shown to the program" grep -qxF "$T/video.mp4" "$T/bwrap.args"
check "a file alone gives no network" not grep -qx -e --share-net "$T/bwrap.args"
check "the program gets the restricted socket, not the real one" not grep -qxF "$T/run/wayland-1" <(grep -A1 -x -e --ro-bind "$T/bwrap.args" | grep -v -e '^--')

run mpv https://example.org/v.mp4
check "an https address turns the network on" grep -qx -e --share-net "$T/bwrap.args"
check "...and then the program can't reach X11's abstract socket (the wrapper runs bubblewrap)" test -e "$T/noabs.ran"
sed "s|/usr/local/libexec/wren-no-abstract-sockets|$T/nothing|" "$HERE/bin/media-sandbox" >"$T/media-sandbox-nowrap"
rm -f "$T/bwrap.args"
out=$(bash "$T/media-sandbox-nowrap" mpv https://example.org/v.mp4 2>&1)
check "...without the wrapper a web address is refused, saying how to fix it, and nothing starts" \
    bash -c '[[ $1 == *"wrenctl install media"* ]] && [ ! -e "$2" ]' _ "$out" "$T/bwrap.args"
bash "$T/media-sandbox-nowrap" mpv "$T/video.mp4"
check "...a file needs no wrapper (no network, so no way to that socket)" test -e "$T/bwrap.args"

run mpv "file://$T/video.mp4"
check "a file:// address is shown as the file" grep -qxF "$T/video.mp4" "$T/bwrap.args"
check "a file:// address gives no network" not grep -qx -e --share-net "$T/bwrap.args"

run mpv "--sub-file=file://$T/video.mp4"
check "an option with a file:// address gives no network" not grep -qx -e --share-net "$T/bwrap.args"

run mpv "--sub-file=https://example.org/s.srt"
check "an option with an https address turns the network on" grep -qx -e --share-net "$T/bwrap.args"

# GIMP: ~/Pictures to open and save in, its settings, ~/Downloads read-only, never the network
# (bind SRC DEST: the pair in bwrap's arguments, after OPTION)
pair() { python3 -I -c 'import sys; a = open(sys.argv[1]).read().split("\n"); o, src = sys.argv[2], sys.argv[3]
sys.exit(0 if any(a[i] == o and a[i + 1] == src and a[i + 2] == src for i in range(len(a) - 2)) else 1)' "$T/bwrap.args" "$@"; }
mkdir -p "$T/home/Downloads"
echo x >"$T/home/Downloads/photo.jpg"
mkdir -p "$T/elsewhere"; echo x >"$T/elsewhere/other.png"
run gimp-3.0 "$T/home/Downloads/photo.jpg" "$T/elsewhere/other.png"
check "gimp: ~/Pictures read and write, to open and save in" pair --bind "$T/home/Pictures"
check "...its own settings read and write" pair --bind "$T/home/.config/GIMP"
check "...~/Downloads read-only" pair --ro-bind "$T/home/Downloads"
check "...a picture from elsewhere read-only" pair --ro-bind "$T/elsewhere/other.png"
check "...no network" not grep -qx -e --share-net "$T/bwrap.args"
run gimp-3.0 https://example.org/evil.png
check "...not even for a web address" not grep -qx -e --share-net "$T/bwrap.args"
run mpv "$T/video.mp4"
check "mpv, zathura, imv: no ~/Pictures" not grep -qxF "$T/home/Pictures" "$T/bwrap.args"
check "the gimp command runs GIMP through the sandbox, as the menu entry does" bash -c '
    grep -qx "exec \"\$HOME/.local/bin/media-sandbox\" /usr/bin/gimp-3.0 \"\$@\"" "$1" &&
    grep -q "s|^Exec=gimp-3.0|Exec=\$BIN/gimp|" "$2"' _ "$HERE/bin/gimp" "$HERE/extras/gimp.sh"
for e in media pdf-viewer gimp; do
    check "extras/$e.sh installs the wrapper, as root's, and update.sh knows it uses it" \
        bash -c 'grep -qx "install_no_abstract" "$1" && grep -q "^# files:.*bin/no-abstract-sockets" "$1" && grep -q "remove_no_abstract" "$1"' _ "$HERE/extras/$e.sh"
    check "...its manual steps too" grep -q 'wren-no-abstract-sockets' "$HERE/docs/extras/$e.md"
done
check "the media and PDF extras keep the sandbox while GIMP uses it" bash -c 'grep -q "BIN/gimp" "$1" && grep -q "BIN/gimp" "$2"' _ "$HERE/extras/media.sh" "$HERE/extras/pdf-viewer.sh"

[ "$fails" -eq 0 ]
