#!/bin/bash
# Checks bin/dim-warning (the slow fade before the screen locks) with a pretend
# brightnessctl that keeps the brightness in a file and a pretend notify-send.
# Changes nothing. Run by test.sh, or:  bash tools/test-dim.sh
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
DIM=$HERE/bin/dim-warning

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

mkdir -p "$T/fake" "$T/run"
# brightnessctl: -m prints "name,class,value,percent%,max"; "set N%" stores N; every set is logged
# shellcheck disable=SC2016  # written into the pretend program, expanded when it runs
cat >"$T/fake/brightnessctl" <<FAKE
#!/bin/bash
[ -f "$T/level" ] || exit 1
if [ "\$1" = -m ]; then echo "intel,backlight,100,\$(cat "$T/level")%,255"; exit 0; fi
[ "\$1" = -q ] && shift
if [ "\$1" = set ]; then v=\${2%\\%}; echo "\$v" >"$T/level"; echo "\$v" >>"$T/log"; fi
FAKE
# shellcheck disable=SC2016
printf '#!/bin/sh\necho "$*" >>"%s/notified"\n' "$T" >"$T/fake/notify-send"
chmod +x "$T/fake/"*
export PATH="$T/fake:$PATH" XDG_RUNTIME_DIR="$T/run" DEBSWAY_DIM_TICK=0.02 DEBSWAY_DIM_SECONDS=10 DEBSWAY_DIM_TO=10

level() { cat "$T/level"; }
dim() { bash "$DIM" "$@"; }

echo 80 >"$T/level"; : >"$T/log"; : >"$T/notified"
dim start
check "start tells you it is about to lock" grep -q 'Locking soon' "$T/notified"
sleep 0.15
check "the screen is dimmed part of the way while it fades" test "$(level)" -lt 80 -a "$(level)" -gt 10
sleep 0.6
check "it ends at the dim level" test "$(level)" -eq 10
check "it went down in steps, not in one jump" test "$(wc -l <"$T/log")" -ge 5
check "...and never below the dim level" test "$(sort -n "$T/log" | head -1)" -ge 10
dim stop
check "stop puts the brightness back exactly where it was" test "$(level)" -eq 80
check "...and leaves no state behind" test -z "$(ls "$T/run")"

# stopping in the middle of the fade
echo 63 >"$T/level"; : >"$T/log"
dim start
sleep 0.12
mid=$(level)
dim stop
sleep 0.3
check "stopping part way restores the brightness" test "$(level)" -eq 63
check "...and the fade does not carry on afterwards" test "$(level)" -eq 63 -a "$mid" -lt 63

# starting twice does not lose the original brightness
echo 70 >"$T/level"
dim start
sleep 0.1
dim start
sleep 0.1
dim stop
check "a second start keeps the original brightness" test "$(level)" -eq 70

# nothing to do
dim stop
check "stop with nothing started is harmless" test "$(level)" -eq 70
echo 8 >"$T/level"; : >"$T/log"
dim start; sleep 0.2
check "a screen already at or below the dim level is left alone" test "$(level)" -eq 8 -a ! -s "$T/log"
dim stop

# no backlight (a desktop monitor): only the notification
rm -f "$T/level"; : >"$T/notified"
dim start
check "without a backlight it still warns" grep -q 'Locking soon' "$T/notified"
check "...and changes nothing" test ! -e "$T/level"
dim stop

check "an unknown word is refused" not dim nonsense

# the idle setup
# shellcheck disable=SC2016  # the pattern names shell variables of the part, literally
check "swayidle starts the fade 30 seconds before the lock" python3 -I -c '
import re, sys
s = open(sys.argv[1]).read()
dim = int(re.search(r"timeout (\d+) .\$DIM start", s).group(1))
lock = int(re.search(r"timeout (\d+) .\$LOCK_CMD", s).group(1))
assert lock - dim == 30, (dim, lock)
assert "resume \x27$DIM stop\x27" in s
' "$HERE/parts/swayidle.sh"

[ "$fails" -eq 0 ]
