#!/bin/bash
# Checks bin/timer (timers, alarms, clock format) with pretend systemd, notify-send
# and sound player, so nothing is started and nothing rings. Run by test.sh, or:
#   bash tools/test-timer.sh
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TIMER=$HERE/bin/timer

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}

# pretend programs that only write down how they were called
mkdir -p "$T/fake" "$T/run" "$T/config" "$T/home"
for c in systemd-run systemctl notify-send pw-play; do
    printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\nexit 0\n' "$c" "$T" >"$T/fake/$c"
done
printf '#!/bin/sh\nexit 0\n' >"$T/fake/sleep"
chmod +x "$T/fake/"*
export PATH="$T/fake:$PATH" HOME="$T/home" XDG_RUNTIME_DIR="$T/run" XDG_CONFIG_HOME="$T/config"

t() { bash "$TIMER" "$@"; }
calls() { cat "$T/calls" 2>/dev/null; }
files() { find "$T/run/debsway-timers" -type f 2>/dev/null | wc -l; }

# 1. how long a person may say it takes
for pair in 90s=90 10m=600 1h30m=5400 1h30=5400 5m30=330 90=5400 1.5h=5400 45S=45; do
    check "duration ${pair%=*} is ${pair#*=} seconds" test "$(t seconds "${pair%=*}")" = "${pair#*=}"
done
for bad in 0 abc 5x 5m5x 1000h -3; do
    check "'$bad' is not a duration" bash -c "! bash '$TIMER' seconds '$bad'"
done

# 2. a timer
out=$(t 10m tea 2>&1)
check "timer says it is set" grep -q 'Timer set (tea)' <<<"$out"
check "timer made one file" test "$(files)" = 1
check "timer asked systemd for a user timer at a clock time" grep -q -- 'systemd-run --user .*--on-calendar=20' <<<"$(calls)"
check "list shows its name" grep -q 'tea' <<<"$(t list)"
check "the bar text counts down in minutes" test "$(t next)" = "tea 10m"

# 3. a second one, sorted soonest first, and a count in the bar
t 2h bake >/dev/null
check "bar shows the soonest and how many more" test "$(t next)" = "tea 10m +1"
check "list has both" test "$(t list | wc -l)" = 2

# 4. cancel one, then all
t cancel 1 >/dev/null
check "cancel 1 stops that timer's unit" grep -q 'systemctl --user stop debsway-timer-' <<<"$(calls)"
check "one is left" test "$(files)" = 1
check "the one left is the other" bash -c "[[ \$(bash '$TIMER' next) == bake\ [12]h* ]]"
t cancel all >/dev/null
check "cancel all leaves nothing" test "$(files)" = 0
check "nothing running says so" grep -q 'Nothing is running' <<<"$(t list)"
check "next is empty when nothing runs" test -z "$(t next)"
check "cancel of a missing number fails" bash -c "t() { bash '$TIMER' \"\$@\"; }; t 5m x >/dev/null; ! bash '$TIMER' cancel 9"
t cancel all >/dev/null

# 5. an alarm: the next such time, never in the past, within a day and a bit
for when in "7am" "7:30 pm" "19:30" "at 6:15 wake up" "tomorrow 8am"; do
    # shellcheck disable=SC2086  # "at 6:15 wake up" is meant to be several words
    t $when >/dev/null 2>&1
done
now=$(date +%s)
ok=1
for f in "$T/run/debsway-timers/"*; do
    due=$(sed -n 's/^due=//p' "$f")
    [ "$due" -gt "$now" ] && [ "$due" -le $((now + 2 * 86400)) ] || ok=0
done
check "five alarms made five files" test "$(files)" = 5
check "every alarm is in the future, within two days" test "$ok" = 1
check "alarm keeps its name" grep -q 'label=wake up' "$T/run/debsway-timers/"*
check "an alarm shows in the bar as alarm text" bash -c "[[ \$(bash '$TIMER' next) == *' +4' ]]"
t cancel all >/dev/null

# 6. things it should refuse
for bad in banana "at" "tomorrow" "25:00" "now" "friday"; do
    check "refuses '$bad'" bash -c "! bash '$TIMER' $bad"
done
check "refused things leave no files" test "$(files)" = 0

# 7. ringing: a notification, then the file is gone
t 1m "pasta" >/dev/null
id=$(find "$T/run/debsway-timers" -type f -printf '%f')
: >"$T/calls"
t fire "$id"
check "ringing sends a notification with the name" grep -q 'notify-send -u critical -t 0 -a debsway Timer done pasta' <<<"$(calls)"
check "ringing plays a sound when the system has one" bash -c "[ ! -r /usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga ] || grep -q pw-play '$T/calls'"
check "ringing removes the timer" test "$(files)" = 0
check "ringing twice does nothing" t fire "$id"

# 8. the clock setting
t clock date off >/dev/null
check "date off is remembered" grep -qx 'date=no' "$T/config/debsway/clock"
check "no date looks like a weekday and the time with am or pm" bash -c "[[ \$(bash '$TIMER' clock date off) =~ ^The\ bar\ shows:\ [A-Z][a-z]{2}\ [0-9]{1,2}:[0-9]{2}\ [AP]M\$ ]]"
check "date on looks like the usual bar" bash -c "[[ \$(bash '$TIMER' clock date on) =~ ^The\ bar\ shows:\ [A-Z][a-z]{2}\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{1,2}:[0-9]{2}\ [AP]M\$ ]]"
check "24 hour is not an option" bash -c "! bash '$TIMER' clock 24h"
check "the clock file never has an hours setting" bash -c "! grep -q hours '$T/config/debsway/clock'"
check "a wrong clock option fails" bash -c "! bash '$TIMER' clock sideways"
check "the clock file keeps one line per setting" test "$(sort "$T/config/debsway/clock" | uniq -d | wc -l)" = 0

# 9. an old file with nothing behind it is dropped
mkdir -p "$T/run/debsway-timers"
printf 'kind=timer\ndue=%s\nlabel=old\n' $(($(date +%s) - 1000)) >"$T/run/debsway-timers/old"
t list >/dev/null
check "a timer long past is forgotten" test "$(files)" = 0

# 10. Esc closes the menu (it runs in a window of its own, from the bar or Super+t)
cat >"$T/esc.py" <<'PY'
import os, pty, select, sys, time
def run(keys, wait=0.5):
    pid, fd = pty.fork()
    if pid == 0:
        os.execvpe("/bin/bash", ["bash", sys.argv[1]], dict(os.environ, TERM="xterm"))
    out = b""
    def pump(w):
        nonlocal out
        end = time.time() + w
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.05)
            if r:
                try: d = os.read(fd, 65536)
                except OSError: return
                if not d: return
                out += d
    pump(0.8)
    for k in keys:
        os.write(fd, k.encode()); pump(wait)
    for _ in range(40):
        done, st = os.waitpid(pid, os.WNOHANG)
        if done:
            return os.waitstatus_to_exitcode(st), out
        time.sleep(0.05)
    os.kill(pid, 9); os.waitpid(pid, 0)
    return None, out
print("esc", run(["\x1b"])[0])
print("arrow", run(["\x1b[A"])[0])
print("q", run(["q\r"])[0])
status, out = run(["\x1b[A", "\x1b"])
print("arrow-then-esc", status)
print("hint", b"Esc or q" in out)
PY
esc=$(python3 -I "$T/esc.py" "$TIMER" 2>&1)
check "Esc closes the timer menu" grep -qx 'esc 0' <<<"$esc"
check "an arrow key does not close it (it is history, not Esc)" grep -qx 'arrow None' <<<"$esc"
check "q and Enter still close it" grep -qx 'q 0' <<<"$esc"
check "Esc closes it after an arrow key too" grep -qx 'arrow-then-esc 0' <<<"$esc"
check "the menu says Esc closes it" grep -qx 'hint True' <<<"$esc"

[ "$fails" -eq 0 ]
