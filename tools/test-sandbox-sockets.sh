#!/bin/bash
# Checks that the sandboxed browsers (bin/firefox, its profiles, bin/incognito
# and its Wi-Fi sign-in window) get no way into your runtime folder. Passage
# through that folder also leads to every socket in it, and your audio server's
# (pipewire-0, pulse/native) are open to anyone who reaches them, with your
# microphones and camera behind them. What a browser is handed lives in a new
# private folder instead. With pretend sudo, setfacl and wayland-restrict, in a
# temp folder; nothing is started. Run by test.sh, or:
#   bash tools/test-sandbox-sockets.sh
# shellcheck disable=SC2016  # the pretend programs and bash -c lines expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
command -v flock >/dev/null || { echo "  ok    skipped: flock isn't installed"; exit 0; }

mkdir -p "$T/fake" "$T/run" "$T/home" "$T/shm"
# sudo: -l says yes; the session writes down the folder it was given, that
# folder's mode and what is in it, while the browser "runs"
cat >"$T/fake/sudo" <<FAKE
#!/bin/bash
echo "sudo \$*" >>"$T/calls"
case " \$* " in *" -l "*) exit 0 ;; esac
for a; do
    case \$a in
        "$T"/*) if [ -d "\$a" ] && [ "\${a%/Downloads*}" = "\$a" ]; then
            echo "\$a" >"$T/given"
            stat -c %a "\$a" >"$T/given-mode"
            ls -A "\$a" >"$T/given-files"
            break
        fi ;;
    esac
done
FAKE
printf '#!/bin/bash\necho "setfacl $*" >>"%s/calls"\n' "$T" >"$T/fake/setfacl"
printf '#!/bin/sh\n: >"$1"\necho ready\ncat >/dev/null\n' >"$T/fake/wayland-restrict"
printf '#!/bin/sh\ncat >/dev/null\n' >"$T/fake/pw-cat"
chmod +x "$T/fake/"*
for s in wayland-1 pipewire-0; do
    python3 -I -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); import time; time.sleep(60)' "$T/run/$s" &
done
sleep 0.3

# run COMMAND ARGS...: the command as it would start from sway
run() {
    local cmd=$1
    shift
    : >"$T/calls"
    rm -f "$T/given" "$T/given-mode" "$T/given-files"
    env PATH="$T/fake:$PATH" HOME="$T/home" XDG_RUNTIME_DIR="$T/run" WAYLAND_DISPLAY=wayland-1 \
        WREN_SHARE_ROOT="$T/shm" WREN_FX_PROFILE_DIR="$T/prof" bash "$HERE/bin/$cmd" "$@" >/dev/null 2>&1
}
# no_way_in: nothing gave the sandbox user any right on the runtime folder
no_way_in() { ! grep -qE "^setfacl -m .*u:[a-z-]+:[^ ]* ([^ ]+ )*$T/run( |\$)" "$T/calls"; }
given() { cat "$T/given" 2>/dev/null; }
private_folder() { # NAME: the folder given is new, private, and named for NAME
    [[ $(given) =~ ^$T/shm/wren-$1\.[A-Za-z0-9]{8}$ ]] && [ "$(cat "$T/given-mode")" = 700 ]
}
passage() { grep -qE "^setfacl -m u:$1:--x $(given)( |\$)" "$T/calls"; } # USER

# --- the main Firefox (its sound follows /etc/wren/firefox.conf, so sound is
# checked below with a profile, whose choice is in a folder of the test's)
run firefox https://example.org/
check "the main Firefox gets no right on your runtime folder" no_way_in
check "...it is given a new private folder, not the runtime folder" private_folder firefox
check "...with passage to that folder" passage firefox
check "...the restricted socket is in it" grep -qx firefox-wayland "$T/given-files"
check "...the session is told that folder" grep -qF "firefox-session start $(given) firefox-wayland " "$T/calls"
check "...and it is gone when Firefox closes" test ! -e "$(given)"
check "...nothing of it is left in the runtime folder" bash -c 'ls -A "$1" | grep -qE "wayland$|fifo$" && exit 1; [ "$(ls -A "$1" | grep -c firefox-)" = 0 ]' _ "$T/run"

# --- with sound off: the same, without a pipe
run firefox --no-audio
check "sound off makes no difference to it: no right on the runtime folder" no_way_in
check "...a private folder all the same" private_folder firefox

# --- a profile, with sound
run firefox --profile bank
check "a profile gets no right on your runtime folder" no_way_in
check "...a private folder of its own" private_folder firefox-bank
check "...with passage for its own user" passage fx-bank
check "...the restricted socket and the sound pipe are in it" bash -c 'grep -qx firefox-bank-wayland "$1" && grep -qx firefox-bank-audio.fifo "$1"' _ "$T/given-files"
check "...the session is told that folder and that pipe" grep -qF "firefox-session start $(given) firefox-bank-wayland firefox-bank-audio.fifo" "$T/calls"
check "...which only that user may use" grep -qF "setfacl -m u:fx-bank:rw- $(given)/firefox-bank-audio.fifo" "$T/calls"

# --- your New Tab picture goes in there too
mkdir -p "$T/home/Pictures/wren/firefox"
printf '\xff\xd8\xff\xe0 a photo' >"$T/home/Pictures/wren/firefox/p.jpg"
run firefox --no-audio
check "your New Tab picture is handed over in the private folder" grep -qx firefox-newtab.jpg "$T/given-files"
check "...readable by firefox alone" grep -qF "setfacl -m u:firefox:r-- $(given)/firefox-newtab.jpg" "$T/calls"
rm -rf "$T/home/Pictures"

# --- what a crash leaves
mkdir "$T/shm/wren-firefox.OldOld11" "$T/shm/wren-firefox-shop.Other111"
run firefox --no-audio
check "a folder a crash left is cleared at the next start" test ! -e "$T/shm/wren-firefox.OldOld11"
check "...another profile's stays: it may be running" test -d "$T/shm/wren-firefox-shop.Other111"
rm -rf "$T/shm/wren-firefox-shop.Other111"
# an older version may have ended without taking back its passage
check "...and an older version's passage through the runtime folder is taken back" grep -qE "^setfacl -x u:firefox $T/run\$" "$T/calls"

# --- incognito, and the Wi-Fi sign-in window
run incognito https://example.org/
check "incognito gets no right on your runtime folder" no_way_in
check "...a private folder" private_folder incognito
check "...with passage to it" passage incognito
check "...the restricted socket and the sound pipe are in it" bash -c 'grep -qx incognito-wayland "$1" && grep -qx incognito-audio.fifo "$1"' _ "$T/given-files"
check "...and it is gone when the window closes" test ! -e "$(given)"
run incognito --no-audio --signin http://example.org/
check "the Wi-Fi sign-in window gets no right on your runtime folder" no_way_in
check "...a private folder of its own" private_folder wifi-signin
check "...with passage for its own user" passage wifi-signin

# --- the sessions take only such a folder (they run as the sandbox user, and
# what comes from the caller is checked)
line() { grep -F 'unexpected socket folder' "$HERE/bin/$1"; }
takes() { # SESSION VALUE [VAR=VALUE]: does its check accept VALUE?
    local out
    out=$(bash -c 'die() { exit 1; }; host_dir=$2; tag=$3; me=$4; eval "$1"' _ "$(line "$1")" "$2" "${3:-}" "${4:-}" 2>/dev/null && echo yes)
    [ "$out" = yes ]
}
check "firefox-session checks the folder it is given" test -n "$(line firefox-session)"
check "...takes its own" takes firefox-session /dev/shm/wren-firefox.AbCd1234
check "...not your runtime folder" not takes firefox-session /run/user/1000
check "...not a profile's" not takes firefox-session /dev/shm/wren-firefox-bank.AbCd1234
check "...not one that climbs out" not takes firefox-session /dev/shm/wren-firefox.x/../../../run/user/1000
check "...a profile takes its own" takes firefox-session /dev/shm/wren-firefox-bank.AbCd1234 bank
check "...not the main Firefox's" not takes firefox-session /dev/shm/wren-firefox.AbCd1234 bank
check "incognito-session checks the folder it is given" test -n "$(line incognito-session)"
check "...takes its own user's" takes incognito-session /dev/shm/wren-incognito.AbCd1234 '' incognito
check "...not your runtime folder" not takes incognito-session /run/user/1000 '' incognito
check "...not the other user's" not takes incognito-session /dev/shm/wren-wifi-signin.AbCd1234 '' incognito

[ "$fails" -eq 0 ]
