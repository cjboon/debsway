#!/bin/bash
# Checks extras/keepassxc.sh with a pretend sudo and apt, in a temp home: the
# on-lock program that locks KeePassXC's databases at every lock (only when it
# runs), the start on workspace 1 at login when you say so (and sway takes
# it), and --remove taking both out. Nothing outside a temp folder changes.
# Run by test.sh, or:  bash tools/test-keepassxc.sh
# shellcheck disable=SC2016  # the inner shells and pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
mkdir -p "$T/bin" "$T/home"
printf '#!/bin/sh\n[ "$1" = -v ] && exit 0\necho "sudo $*" >>"%s/calls"\n' "$T" >"$T/bin/sudo"
cat >"$T/bin/dpkg-query" <<'EOF'
#!/bin/sh
case "$*" in
    *Status*keepassxc-full* | *Status*webext-keepassxc-browser* | *Status*"keepassxc " ) exit 1 ;;
    *Status*) echo 'install ok installed' ;;
    *Depends*) echo 'keepassxc-minimal, qtwayland5' ;;
esac
EOF
chmod +x "$T/bin/"*
R=$T/r
mkdir -p "$R/extras" "$R/lib"
sed 's|^export PATH=.*|export PATH="$KP_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q KP_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
for f in pins.sh packages.sh data bin docs; do ln -s "$HERE/$f" "$R/$f"; done
for f in "$HERE"/lib/*; do ln -s "$f" "$R/lib/${f##*/}"; done
cp "$HERE/extras/keepassxc.sh" "$R/extras/"
export KP_TEST_PATH="$T/bin:$PATH"
kp() { printf '%s\n' "$1" >"$T/answers"; shift; env -u SWAYSOCK HOME="$T/home" XDG_CONFIG_HOME= WREN_TEST_ANSWERS="$T/answers" bash "$R/extras/keepassxc.sh" "$@" 2>&1; }
H=$T/home/.config/wren/on-lock.d/keepassxc
S=$T/home/.config/sway/config.d/keepassxc-start.conf

out=$(kp y)
check "the on-lock program: KeePassXC's databases lock at every lock" bash -c '[ -x "$1" ] && grep -qx "exec keepassxc --lock" "$1"' _ "$H"
check "...only when it runs (keepassxc --lock would start it otherwise)" grep -qx 'pgrep -x -u "$(id -u)" keepassxc >/dev/null || exit 0' "$H"
printf '#!/bin/sh\nexit 1\n' >"$T/bin/pgrep"
printf '#!/bin/sh\necho started >"%s/kp-ran"\n' "$T" >"$T/bin/keepassxc"
chmod +x "$T/bin/pgrep" "$T/bin/keepassxc"
PATH="$T/bin:$PATH" sh "$H"
check "...and with KeePassXC not running it does nothing" test ! -e "$T/kp-ran"
printf '#!/bin/sh\nexit 0\n' >"$T/bin/pgrep"
PATH="$T/bin:$PATH" sh "$H"
check "...with it running, it asks it to lock" test -e "$T/kp-ran"
check "yes: KeePassXC opens on workspace 1 at login" grep -qx "exec sh -c 'swaymsg -q \"workspace number 1\"; exec keepassxc'" "$S"
if command -v sway >/dev/null; then
    check "...and sway takes it" bash -c '! grep -q "rejected" <<<"$1"' _ "$out"
fi
kp n >/dev/null
check "no: it doesn't" test ! -e "$S"
kp y >/dev/null
kp y --remove >/dev/null
check "--remove takes the on-lock program and the start at login out" bash -c '[ ! -e "$1" ] && [ ! -e "$2" ]' _ "$H" "$S"

[ "$fails" -eq 0 ]
