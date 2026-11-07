#!/bin/bash
# Checks extras/pipewire-audio.sh: after it starts PipeWire it mutes the
# microphone, and it says the microphone is off only when it is. Runs the extra
# with a pretend sudo, dpkg-query (so apt has nothing to install), systemctl and
# wpctl. Changes nothing. Run by test.sh, or:  bash tools/test-pipewire-audio.sh
# shellcheck disable=SC2016  # the inner bash, and the copy of lib.sh, expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}

[ -f /etc/sway/config ] || { echo "  FAIL  needs sway installed (its stock config is what the extra builds on)"; exit 1; }

mkdir -p "$T/bin" "$T/home"
cat >"$T/bin/sudo" <<EOF
#!/bin/sh
[ "\$1" = -v ] && exit 0
echo "sudo \$*" >>"$T/calls"
exit 0
EOF
# Every package is installed, and the extra's marker already holds pipewire-audio
cat >"$T/bin/dpkg-query" <<'EOF'
#!/bin/sh
case "$*" in *Status*) echo "install ok installed" ;; *Depends*) echo "pipewire-audio" ;; esac
EOF
printf '#!/bin/sh\necho "systemctl $*" >>"%s/calls"\n' "$T" >"$T/bin/systemctl"
# (radios --wait waits a second at a time for the microphone)
printf '#!/bin/sh\nexit 0\n' >"$T/bin/sleep"
# wpctl: no $T/mic, no microphone; with $T/mic-stuck a mute changes nothing
cat >"$T/bin/wpctl" <<EOF
#!/bin/bash
[ -f "$T/mic" ] || exit 1
case \$1 in
    get-volume) echo "Volume: 1.00\$([ "\$(cat "$T/mic")" = muted ] && echo ' [MUTED]')" ;;
    set-mute) [ -e "$T/mic-stuck" ] && exit 0
        if [ "\$3" = 1 ]; then echo muted >"$T/mic"; else echo open >"$T/mic"; fi ;;
esac
EOF
chmod +x "$T/bin/"*

R=$T/r
mkdir -p "$R/extras"
sed 's|^export PATH=.*|export PATH="$PIPEWIRE_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q PIPEWIRE_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
for f in pins.sh packages.sh lib data docs bin; do ln -s "$HERE/$f" "$R/$f"; done
cp "$HERE/extras/pipewire-audio.sh" "$R/extras/"
export PIPEWIRE_TEST_PATH="$T/bin:$PATH"
[ "$(bash -c '. "$1/lib.sh"; command -v sudo' _ "$R")" = "$T/bin/sudo" ] || { echo "  FAIL  the real sudo would run; stopping"; exit 1; }

run() { : >"$T/calls"; env -u SWAYSOCK -u WAYLAND_DISPLAY HOME="$T/home" bash "$R/extras/pipewire-audio.sh" >"$T/out" 2>&1; }

echo open >"$T/mic"
run
check "it installs and runs" test $? -eq 0
check "a microphone there is muted" test "$(cat "$T/mic")" = muted
check "...and it says the microphone is off" grep -q 'The microphone is off until you switch it on' "$T/out"
check "...the user's audio services are started" grep -q 'systemctl --user enable --now pipewire.socket' "$T/calls"
check "...and the login line mutes it again, waiting for it" \
    grep -qx 'exec ~/.local/bin/radios mic off --wait' "$T/home/.config/sway/config.d/audio.conf"

rm -f "$T/mic"
run
check "no microphone (yet): it doesn't say the microphone is off" bash -c '! grep -q "microphone is off" "$1"' _ "$T/out"
check "...it says none showed up, and that the next login mutes it" grep -q 'No microphone showed up' "$T/out"

echo open >"$T/mic"
touch "$T/mic-stuck"
run
check "a mute that doesn't take: it doesn't say the microphone is off" bash -c '! grep -q "microphone is off" "$1"' _ "$T/out"
check "...it warns that it is still on, and how to switch it off" \
    bash -c 'grep -q "still on" "$1" && grep -q "wrenctl --mic off" "$1"' _ "$T/out"

[ "$fails" -eq 0 ]
