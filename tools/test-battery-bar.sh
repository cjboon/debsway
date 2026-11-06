#!/bin/bash
# Checks the low battery warning in bin/sway-status: the real script, with a pretend battery
# and a pretend notify-send. Run by test.sh, or:
#   bash tools/test-battery-bar.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
S=$HERE/bin/sway-status
mkdir -p "$T/bin" "$T/power/BAT0" "$T/home" "$T/run"
printf '#!/bin/sh\necho "$*" >>"%s/notified"\n' "$T" >"$T/bin/notify-send"
chmod +x "$T/bin/notify-send"
: >"$T/notified"
battery() { echo "$1" >"$T/power/BAT0/capacity"; echo "$2" >"$T/power/BAT0/status"; }
run() { env HOME="$T/home" XDG_RUNTIME_DIR="$T/run" WREN_POWER_DIR="$T/power" PATH="$T/bin:$PATH" sh "$S" "$@"; }
bar_bat() { # the battery's block in one line the bar is sent, as JSON
    python3 -I -c '
import json, sys
line = sys.stdin.read().strip().rstrip(",")
for b in json.loads(line):
    if b.get("name") == "bat":
        print(json.dumps(b, sort_keys=True))'
}
# lines N: the first N lines the bar is sent, for a battery as it is now (after its 2 of header)
lines() {
    local p i=0 f=$T/out
    : >"$f"
    env HOME="$T/home" XDG_RUNTIME_DIR="$T/run" WREN_POWER_DIR="$T/power" PATH="$T/bin:$PATH" sh "$S" >"$f" 2>/dev/null </dev/null &
    while [ "$i" -lt 150 ] && [ "$(wc -l <"$f")" -lt $(($1 + 2)) ]; do /bin/sleep 0.1; i=$((i + 1)); done
    p=$(cat "$T/run/sway-status.pid" 2>/dev/null)
    [ -z "$p" ] || kill "$p" 2>/dev/null
    wait 2>/dev/null
    sed -n "3,$(($1 + 2))p" "$f"
}
one_line() { lines 1; }

battery 80 Discharging
out=$(one_line | bar_bat)
check "80%: an ordinary block" bash -c 'grep -q "bat 80%" <<<"$1" && ! grep -q "background" <<<"$1"' _ "$out"
battery 16 Discharging
out=$(one_line | bar_bat)
check "16%: still ordinary" not grep -q background <<<"$out"
battery 15 Discharging
out=$(one_line | bar_bat)
check "15%: yellow, black text, readable on either theme" bash -c 'grep -q "\"background\": \"#ffd000\"" <<<"$1" && grep -q "\"color\": \"#000000\"" <<<"$1"' _ "$out"
check "...it says how much" grep -q 'bat 15%' <<<"$out"
battery 6 Discharging
check "6%: still yellow" grep -q '#ffd000' <<<"$(one_line | bar_bat)"
battery 5 Discharging
out=$(one_line | bar_bat)
check "5%: red, white text" bash -c 'grep -q "\"background\": \"#d00000\"" <<<"$1" && grep -q "\"color\": \"#ffffff\"" <<<"$1"' _ "$out"
SECONDS=0
flash=$(lines 4)
took=$SECONDS
n=0
while IFS= read -r l; do if grep -q '#d00000' <<<"$(printf '%s\n' "$l" | bar_bat)"; then n=$((n + 1)); fi; done <<<"$flash"
check "...flashing: red, then not, then red, and so on" test "$n" = 2
check "...about once a second, not every 5" test "$took" -le 6
check "...the text stays there while it flashes" test "$(grep -c 'bat 5%' <<<"$flash")" = 4
battery 15 Discharging
check "15%: yellow doesn't flash" test "$(lines 2 | grep -c '#ffd000')" = 2
battery 5 Discharging
battery 5 Charging
out=$(one_line | bar_bat)
check "5% and charging: back to normal" not grep -q background <<<"$out"
check "...shown as charging" grep -q 'bat 5%+' <<<"$out"
battery 5 Full
check "plugged in and not going down (Full): normal" not grep -q background <<<"$(one_line | bar_bat)"
battery 5 'Not charging'
check "...Not charging: normal" not grep -q background <<<"$(one_line | bar_bat)"
rm -f "$T/power/BAT0/capacity" "$T/power/BAT0/status"
check "no battery: no block" test -z "$(one_line | bar_bat)"

# The text console's bar
battery 15 Discharging
check "the console bar: yellow and bold at 15%" grep -q 'bold,fg=yellow\]bat 15%' <<<"$(run --tmux)"
battery 5 Discharging
check "...red, bold and blinking at 5%" grep -q 'bold,blink,fg=red\]bat 5%' <<<"$(run --tmux)"
battery 80 Discharging
check "...plain otherwise" not grep -q 'fg=[a-z]*\]bat 80%' <<<"$(run --tmux)"

# One notification on reaching each level, in a running bar (SIGUSR1: draw again now)
battery 80 Discharging
: >"$T/notified"
env HOME="$T/home" XDG_RUNTIME_DIR="$T/run" WREN_POWER_DIR="$T/power" PATH="$T/bin:$PATH" sh "$S" >/dev/null 2>&1 </dev/null &
i=0
while [ "$i" -lt 50 ] && [ ! -s "$T/run/sway-status.pid" ]; do /bin/sleep 0.1; i=$((i + 1)); done
barpid=$(cat "$T/run/sway-status.pid")
redraw() { # (a redraw takes a moment: wait for the next one to end)
    kill -USR1 "$barpid" 2>/dev/null
    /bin/sleep 1.5
}
count() { grep -c "$1" "$T/notified"; }
/bin/sleep 1.5
check "80%: no notification" test "$(wc -l <"$T/notified")" = 0
battery 15 Discharging; redraw
check "reaching 15%: a notification" test "$(count 'Battery low')" = 1
battery 14 Discharging; redraw
battery 13 Discharging; redraw
check "...only one, as it goes on down" test "$(count 'Battery low')" = 1
battery 5 Discharging; redraw
check "reaching 5%: another, a critical one" bash -c 'grep -q "critical.*Battery very low" "$1"' _ "$T/notified"
battery 4 Discharging; redraw
check "...only one" test "$(count 'Battery very low')" = 1
battery 60 Charging; redraw
battery 15 Discharging; redraw
check "charged, then down to 15% again: it warns again" test "$(count 'Battery low')" = 2
kill "$barpid" 2>/dev/null
wait 2>/dev/null
rm -rf "$T"
[ "$fails" -eq 0 ]
