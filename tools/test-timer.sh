#!/bin/bash
# Checks bin/timer (timers, alarms, clock format) with pretend systemd, notify-send
# and sound player, so nothing is started and nothing rings. Run by test.sh, or:
#   bash tools/test-timer.sh
# shellcheck disable=SC2016  # the inner bash, and sway's own variables
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
check "with the alarm sound missing the notification says so" grep -q 'Timer done pasta (no sound: the alarm sound is missing' <<<"$(calls)"
check "...and nothing is played" bash -c "! grep -q '^pw-play' '$T/calls'"
check "ringing removes the timer" test "$(files)" = 0
check "ringing twice does nothing" t fire "$id"
mkdir -p "$T/sounds" && : >"$T/sounds/alarm.wav"
export DEBSWAY_SOUND_DIR="$T/sounds"
t 1m "tea" >/dev/null
id=$(find "$T/run/debsway-timers" -type f -printf '%f')
: >"$T/calls"
t fire "$id"
check "a timer rings the sound twice (about 20 seconds)" test "$(grep -c "^pw-play $T/sounds/alarm.wav" "$T/calls")" -eq 2
check "...and the notification has no apology" bash -c "! grep -q '(no sound' '$T/calls'"

# (the real /bin/sleep below: the pretend sleep above does not wait)
# 7b. an alarm rings long, and there are three ways to stop it. These use a player that
# really takes time and a notification program that supports --wait and --action.
mkdir -p "$T/ring"
# shellcheck disable=SC2016  # written into the pretend program, expanded when it runs
printf '#!/bin/sh\necho "pw-play $*" >>"%s/calls"\n/bin/sleep "${FAKE_PLAY:-0}"\n' "$T" >"$T/ring/pw-play"
cat >"$T/ring/notify-send" <<FAKE
#!/bin/bash
echo "notify-send \$*" >>"$T/calls"
case " \$* " in
    *" --help "*) echo "  -A, --action   --wait"; exit 0 ;;
    *" --wait "*) /bin/sleep "\${FAKE_NOTIFY_WAIT:-100}" ;;
esac
FAKE
chmod +x "$T/ring/"*
ringing() { local saved=$PATH rc; PATH="$T/ring:$PATH"; "$@"; rc=$?; PATH=$saved; return $rc; }
alarm_id() { t at 7:30 wake >/dev/null; find "$T/run/debsway-timers" -type f -name '[0-9]*' -printf '%f\n' | head -1; }

# how long: an alarm 30 plays by default (5 minutes), a timer 2 (about 20 seconds)
check "an alarm rings for 300 seconds, a timer for 20, unless told otherwise" bash -c "grep -q 'RING_ALARM=\${DEBSWAY_RING_ALARM:-300}' '$TIMER' && grep -q 'RING_TIMER=\${DEBSWAY_RING_TIMER:-20}' '$TIMER'"
id=$(alarm_id)
: >"$T/calls"
DEBSWAY_RING_ALARM=300 FAKE_PLAY=1 FAKE_NOTIFY_WAIT=4 ringing t fire "$id" &
fire_pid=$!
/bin/sleep 2.5
check "an alarm repeats the sound (30 times in all) until it is stopped" test "$(grep -c '^pw-play' "$T/calls")" -ge 2
check "the notification offers a Stop action and says how to stop it" grep -q 'notify-send --wait -A default=Stop -u critical -t 0 -a debsway Alarm wake. Click or dismiss this to stop the sound.' "$T/calls"
t stop >"$T/out" 2>&1
wait "$fire_pid"
check "timer stop ends the ringing" grep -q 'Stopped the sound' "$T/out"
check "...and the alarm stops repeating" test "$(grep -c '^pw-play' "$T/calls")" -lt 30
check "...and leaves no ring behind" test ! -e "$T/run/debsway-timers/ringing"
check "timer stop with nothing ringing and nothing pending says so" grep -q 'Nothing is running' <(t stop 2>&1)

# clicking or dismissing the notification ends it (the notify-send --wait returns)
id=$(alarm_id)
: >"$T/calls"
start=$SECONDS
DEBSWAY_RING_ALARM=300 FAKE_PLAY=3 FAKE_NOTIFY_WAIT=0.7 ringing t fire "$id"
took=$((SECONDS - start))
check "dismissing the notification stops the sound at once, not after the whole alarm" test "$took" -lt 6
check "...after one play" test "$(grep -c '^pw-play' "$T/calls")" -eq 1

# without --wait support the notification is plain and the sound plays through
id=$(alarm_id)
: >"$T/calls"
DEBSWAY_RING_ALARM=30 env PATH="$T/fake:$PATH" bash "$TIMER" fire "$id"
check "a notify-send without --wait gets a plain notification" bash -c "grep -q '^notify-send -u critical -t 0 -a debsway Alarm' '$T/calls' && ! grep -q -e '--wait' '$T/calls'"
check "...and the alarm still rings its full length (3 plays for 30 seconds here)" test "$(grep -c '^pw-play' "$T/calls")" -eq 3

# with a pending timer, stop still cancels it as before
t 5m soon >/dev/null
check "timer stop with nothing ringing cancels a pending timer, as before" bash -c "bash '$TIMER' stop | grep -q -i 'cancel'"
unset DEBSWAY_SOUND_DIR

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
import re, datetime
print("date", bool(re.search(rb"\d{4}-\d{2}-\d{2}", out)))
PY
esc=$(python3 -I "$T/esc.py" "$TIMER" 2>&1)
check "Esc closes the timer menu" grep -qx 'esc 0' <<<"$esc"
check "an arrow key does not close it (it is history, not Esc)" grep -qx 'arrow None' <<<"$esc"
check "q and Enter still close it" grep -qx 'q 0' <<<"$esc"
check "Esc closes it after an arrow key too" grep -qx 'arrow-then-esc 0' <<<"$esc"
check "the menu says Esc closes it" grep -qx 'hint True' <<<"$esc"
check "the menu shows today's date" grep -qx 'date True' <<<"$esc"
# ...also when the bar has the date turned off
bash "$TIMER" clock date off >/dev/null
esc=$(python3 -I "$T/esc.py" "$TIMER" 2>&1)
check "...even with the date turned off in the bar" grep -qx 'date True' <<<"$esc"
bash "$TIMER" clock date on >/dev/null

# the sound debsway ships: a short, small, valid mono WAV, made by tools/make-alarm-sound.py
check "data/alarm.wav is a valid mono 16-bit sound of a few seconds, under 600 KB" python3 -I -c '
import os, sys, wave
f = sys.argv[1]
w = wave.open(f)
secs = w.getnframes() / w.getframerate()
assert w.getnchannels() == 1 and w.getsampwidth() == 2, "not mono 16-bit"
assert 3 < secs < 20, secs
assert os.path.getsize(f) < 600000
' "$HERE/data/alarm.wav"
check "the base part installs it" grep -q 'data/alarm.wav' "$HERE/parts/core-commands.sh"
check "the sound extra no longer needs a sound theme package" bash -c "! grep -q 'sound-theme' '$HERE/extras/pipewire-audio.sh'"

# How long before the screen locks: timer lock writes it, bin/debsway-idle runs
# swayidle with it. swayidle, swaymsg and pkill are pretend ones.
IDLE=$HERE/bin/debsway-idle
for c in swayidle swaymsg pkill; do
    printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\nexit 0\n' "$c" "$T" >"$T/fake/$c"
    chmod +x "$T/fake/$c"
done
export DEBSWAY_IDLE=$IDLE
check "with nothing set the screen locks after 30 minutes" test "$("$IDLE" --minutes)" = 30
check "timer lock alone says how long" grep -q 'after 30 minutes' <<<"$(t lock)"
: >"$T/calls"
out=$(SWAYSOCK=/pretend t lock 10 2>&1)
check "timer lock 10 says so" grep -q 'now locks after 10 minutes' <<<"$out"
check "...and debsway-idle reads 10" test "$("$IDLE" --minutes)" = 10
check "...and swayidle is started again with it (sway keeps the old timeouts otherwise)" \
    bash -c 'grep -q "^pkill -x swayidle" "$1" && grep -q "^swaymsg exec .*debsway-idle" "$1"' _ "$T/calls"
t lock 15m >/dev/null
check "timer lock 15m works too" test "$("$IDLE" --minutes)" = 15
for bad in 0 121 abc 5h -3; do
    check "timer lock $bad is refused" bash -c '! bash "$1" lock "$2"' _ "$TIMER" "$bad"
done
check "...and the time stays as it was" test "$("$IDLE" --minutes)" = 15
check "without the idle lock set up it says how to get it" \
    bash -c 'out=$(DEBSWAY_IDLE=/nonexistent bash "$1" lock 10 2>&1); [ $? -ne 0 ] && grep -q "parts/swayidle.sh" <<<"$out"' _ "$TIMER"
: >"$T/calls"
t lock 10 >/dev/null
"$IDLE"
run=$(grep '^swayidle ' "$T/calls")
check "swayidle fades 30 seconds before the lock (570 s)" grep -q 'timeout 570 .*dim-warning start' <<<"$run"
check "...locks at 600 s" grep -q "timeout 600 swaylock -f -c 000000" <<<"$run"
check "...turns the screen off 5 minutes later (900 s)" grep -q 'timeout 900 swaymsg "output \* power off"' <<<"$run"
check "...and locks before sleep" grep -q 'before-sleep swaylock' <<<"$run"
printf 'minutes=500\n' >"$T/config/debsway/lock"
check "a time out of range in the file falls back to 30" test "$("$IDLE" --minutes)" = 30
check "the timer menu offers it" grep -q 'lock after $("$IDLE" --minutes) min idle' "$TIMER"
check "parts/swayidle.sh starts swayidle through debsway-idle" grep -qx 'IDLE_CMD="$HOME/.local/bin/debsway-idle"' "$HERE/parts/swayidle.sh"

# the menu's screen: one box with this month (ncal's cal) and the timers, centred
mkdir -p "$T/calbin"
cat >"$T/calbin/cal" <<'EOF'
#!/bin/sh
printf '%s\n' '    October 2026      ' 'Su Mo Tu We Th Fr Sa  ' '             1  2  3  ' ' 4  5  6  7  8  9 10  ' \
    '11 12 13 14 15 16 17  ' '18 19 20 21 22 23 24  ' '25 26 27 28 29 30 31  ' '                      '
EOF
chmod +x "$T/calbin/cal"
bash "$TIMER" cancel all >/dev/null 2>&1
bash "$TIMER" 10m tea >/dev/null
scr() { env PATH="$T/calbin:$PATH" COLUMNS="${C:-100}" LINES="${R:-30}" bash "$TIMER" screen; }
plain() { sed 's/\x1b\[[0-9;]*m//g'; }
widths() { python3 -I -c 'import sys; print(" ".join(sorted({str(len(l)) for l in sys.stdin.read().split("\n") if l})))'; }
# shape TEXT: "ROWS WIDTHS LEFT-MARGIN" of the screen, without colours
shape() { local p; p=$(plain <<<"$1"); printf '%s %s %s' "$(grep -c . <<<"$p")" "$(LANG=C.UTF-8 widths <<<"$p")" "$(grep -m1 . <<<"$p" | grep -o '^ *' | tr -d '\n' | wc -c)"; }
out=$(LANG=C.UTF-8 scr)
check "the screen is one box of 19 rows, every row the same width, centred (14 + 72 + 14)" test "$(shape "$out")" = "19 86 14"
check "...and centred in the window's height too (30 rows: 4 above it)" bash -c '[ "$(sed -n "1,4p" <<<"$1" | grep -c .)" = 0 ] && sed -n 5p <<<"$1" | grep -q "╭"' _ "$out"
check "it shows this month from cal" grep -q 'October 2026' <<<"$(plain <<<"$out")"
today=$(date +%-d)
check "...with today highlighted" grep -qF "$(printf '\033[7m%2s\033[0m' "$today")" <<<"$out"
check "...and the running timer, by name" grep -qE '1\) tea +(10|9) min' <<<"$(plain <<<"$out")"
check "the date and time are at the top, beside the title" grep -qE 'TIMER AND ALARM +[A-Z][a-z]{2} [0-9]{4}-[0-9]{2}-[0-9]{2} ' <<<"$(plain <<<"$out")"
bash "$TIMER" cancel all >/dev/null 2>&1
out=$(LANG=C.UTF-8 scr)
check "with nothing set it says so" grep -q 'Nothing set yet' <<<"$(plain <<<"$out")"
check "...and the box keeps its shape" test "$(shape "$out")" = "19 86 14"
out=$(LANG=C.UTF-8 env PATH="$T/fake:/usr/bin:/bin" COLUMNS=100 LINES=30 bash "$TIMER" screen 2>&1)
if ! command -v cal >/dev/null; then
    check "without cal it says how to get it" grep -q 'debsway --update' <<<"$out"
    check "...in the same shape" test "$(shape "$out")" = "19 86 14"
fi
out=$(LANG=C scr)
check "without UTF-8 the box is drawn with plain + - |" bash -c '! grep -q "╭" <<<"$1" && grep -q "^ *+---" <<<"$1"' _ "$out"
check "...in the same shape" test "$(shape "$out")" = "19 86 14"
out=$(LANG=C.UTF-8 C=60 R=10 scr)
check "a window smaller than the box still shows all of it (no margin)" test "$(shape "$out")" = "19 72 0"
check "parts/core-commands.sh installs ncal (cal) and --remove takes it out" \
    bash -c 'grep -qx "apt_install ncal" "$1" && grep -qx "    apt_purge ncal" "$1"' _ "$HERE/parts/core-commands.sh"

[ "$fails" -eq 0 ]
