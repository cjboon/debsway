#!/bin/bash
# Checks bin/debsway-menu (the menu behind "debsway" in the bar): the window
# it opens, and the menu itself, driven through a real pseudo-terminal with
# arrow keys, Enter, Esc and mouse clicks. The programs it would run are
# pretend ones that only write down how they were called. Changes nothing.
# Run by test.sh, or:  bash tools/test-debsway-menu.sh
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
command -v python3 >/dev/null || { echo "  ok    skipped: python3 isn't installed"; exit 0; }

mkdir -p "$T/fake" "$T/home/.local/bin" "$T/debsway"
# shellcheck disable=SC2016  # written into the pretend programs, expanded when they run
{
    # foot: write down its arguments, one per line
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"%s/foot"\n' "$T" >"$T/fake/foot"
    # bash (what the menu runs the debsway scripts with): write down the folder, the
    # arguments and whether it was asked to wait at the end
    printf '#!/bin/sh\necho "$PWD|$*|pause=$DEBSWAY_PAUSE" >>"%s/ran"\necho "printed by $*"\n' "$T" >"$T/fake/bash"
    printf '#!/bin/sh\ncat >/dev/null\n' >"$T/fake/less"
    # (keys --text prints the cheat sheet, as the real one does after filtering it)
    printf '#!/bin/sh\n[ "$1" = --text ] && exec cat "%s/home/.local/share/debsway/keys.txt"\necho "keys" >>"%s/ran"\n' "$T" "$T" >"$T/home/.local/bin/keys"
}
chmod +x "$T/fake/"* "$T/home/.local/bin/keys"
# radios: what it lists comes from $T/radios-list; state per name in $T/radio-NAME
# shellcheck disable=SC2016  # written into the pretend program, expanded when it runs
cat >"$T/radios.sh" <<FAKE
#!/bin/bash
case \$1 in
    list) [ -f "$T/radios-list" ] && cat "$T/radios-list" ;;
    *) case \${2:-status} in
        status) cat "$T/radio-\$1" ;;
        toggle) echo "radios \$1 toggle" >>"$T/ran"; if [ "\$(cat "$T/radio-\$1")" = on ]; then echo off >"$T/radio-\$1"; else echo on >"$T/radio-\$1"; fi ;;
       esac ;;
esac
FAKE
: >"$T/debsway/update.sh"
mkdir -p "$T/home/.local/share/debsway"
for i in $(seq 100); do echo "line $i"; done >"$T/home/.local/share/debsway/keys.txt"

# 1. The window: in grays, running the menu, and not fullscreen (the bar stays visible)
PATH="$T/fake:$PATH" HOME="$T/home" /bin/bash "$HERE/bin/debsway-menu"
check "a click opens a window named debsway-run" grep -qx -e --app-id=debsway-run "$T/foot"
check "...quietly: only errors are logged (no warning about the missing icon protocol)" grep -qx -e --log-level=error "$T/foot"
check "...not fullscreen, so the bar stays visible" not grep -qx -e --fullscreen "$T/foot"
check "...with a black background" grep -qx 'colors.background=000000' "$T/foot"
check "...where one step of the mouse wheel moves one line of a list, not three" grep -qx 'scrollback.multiplier=1.0' "$T/foot"
check "...and the menu as its program" test "$(tail -1 "$T/foot")" = --tui
# every color is a gray: red = green = blue in each
check "every color it sets is a gray" python3 -I -c '
import re, sys
vals = re.findall(r"colors\.\w[\w-]*=([0-9a-f]{6})$", open(sys.argv[1]).read(), re.M)
assert len(vals) >= 18, len(vals)
assert all(v[0:2] == v[2:4] == v[4:6] for v in vals), vals
' "$T/foot"

# 2. The menu in a terminal. run_menu "KEYS"... : one scenario; prints what
# was drawn and exit status on the first line, then what ran
cat >"$T/drive.py" <<'PY'
import fcntl, os, pty, re, select, struct, sys, termios, time

def run(script, env, keys, rows=24, cols=80):
    """Start the menu in a pty, send each item of keys (a string, or a function
    of what has been drawn so far), return (drawn, exit status or None)."""
    pid, fd = pty.fork()
    if pid == 0:
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        os.execvpe("/bin/bash", ["bash", script, "--tui"], env)
    drawn = b""
    if keys and isinstance(keys[0], tuple) and keys[0][0] == "early":
        # the window is stretched just after the menu starts, before it has drawn anything
        time.sleep(0.08)
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", keys[0][1], keys[0][2], 0, 0))
        keys = keys[1:]
    def pump(wait=0.4):
        nonlocal drawn
        end = time.time() + wait
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.05)
            if r:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    return
                if not data:
                    return
                drawn += data
    # wait until the menu has drawn (a fixed delay is too short on a busy machine)
    deadline = time.time() + 6
    while b"Esc closes" not in drawn and time.time() < deadline:
        pump(0.1)
    for k in keys:
        if isinstance(k, tuple):      # ("resize", rows, cols): the window is stretched
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", k[1], k[2], 0, 0))
            pump(1.0)
            continue
        os.write(fd, (k(drawn) if callable(k) else k).encode())
        pump(0.5)
    status = None
    for _ in range(80):   # (up to 8 s: a busy machine can be slow to exit)
        done, st = os.waitpid(pid, os.WNOHANG)
        if done:
            status = os.waitstatus_to_exitcode(st)
            break
        time.sleep(0.1)
    if status is None:
        os.kill(pid, 9)
        os.waitpid(pid, 0)
    return drawn.decode(errors="replace"), status

def click_on(label):
    """A mouse click on the row where `label` was last drawn (SGR report)."""
    def f(drawn):
        m = None
        for m in re.finditer(r"\x1b\[(\d+);(\d+)H(?:\x1b\[[0-9;]*m)* ?" + re.escape(label), drawn.decode(errors="replace")):
            pass
        assert m, "never drew " + label
        return "\x1b[<0;%d;%dM\x1b[<0;%d;%dm" % (int(m.group(2)) + 3, int(m.group(1)), int(m.group(2)) + 3, int(m.group(1)))
    return f

if __name__ == "__main__":
    script, home, path, folder, ranfile = sys.argv[1:6]
    scenario = sys.argv[6]
    env = {"PATH": path, "HOME": home, "TERM": "xterm-256color", "DEBSWAY_DIR": folder, "LANG": "C.UTF-8", "DEBSWAY_ESC_WAIT": "1"}
    scenarios = {
        "enter": ["\r"],
        "down-enter": ["\x1b[B", "\r"],
        "j-enter": ["j", "j", "\r"],
        "up-wraps": ["\x1b[A", "\r"],
        "click-update": [click_on("Update")],
        "click-outside": ["\x1b[<0;1;1M\x1b[<0;1;1m", "q"],
        "esc": ["\x1b"],
        "help-esc": ["\r", "\x1b"],
        "help-q": ["\r", "q"],
        "help-space": ["\r", " ", "\x1b"],
        "help-pgdn": ["\r", "\x1b[6~", "\x1b"],
        "help-end": ["\r", "\x1b[F", "\x1b"],
        "help-wheel": ["\r", "\x1b[<65;5;5M", "\x1b[<65;5;5M", "\x1b[<65;5;5M", "\x1b[<65;5;5M", "\x1b[<65;5;5M", "\x1b[<65;5;5M", "\x1b[<65;5;5M", "\x1b[<65;5;5M", "\x1b"],
        "status-esc": ["\x1b[A", "\r", "\x1b"],
        "resize": [("resize", 40, 120), "q"],
        "toggle-wifi": ["j", "j", "j", "j", "\r", "\x1b"],
        "click-mic": [click_on("Microphone"), "\x1b"],
        "early-resize": [("early", 40, 120), "q"],
        "q": ["q"],
    }
    drawn, status = run(script, env, scenarios[scenario])
    if len(sys.argv) > 7:
        open(sys.argv[7], "w").write(re.sub(r"\x1b\[[0-9;?<]*[A-Za-z]", "\n", drawn))
    print("STATUS", status)
    print("DREW", "|".join(re.findall(r"(Help|Install apps|Update|Status)", drawn)[:4]))
    # where the title "debsway" was drawn each time: row;column
    print("TITLES", " ".join("%s;%s" % m for m in re.findall(r"\x1b\[(\d+);(\d+)H\x1b\[1mdebsway", drawn)))
PY
menu() { # SCENARIO [FOLDER]: runs it, leaves the output in $out and what ran in $T/ran
    : >"$T/ran"
    out=$(python3 -I "$T/drive.py" "$HERE/bin/debsway-menu" "$T/home" "$T/fake:/usr/bin:/bin" "${2-$T/debsway}" "$T/ran" "$1" "$T/screen" 2>&1)
}

menu enter
check "the four entries are drawn" grep -q 'DREW Help|Install apps|Update|Status' <<<"$out"
check "Enter on the first entry opens Help in the pager, not less" grep -qx 'line 1' "$T/screen"
check "...which says how to close it" grep -q 'Esc closes' "$T/screen"

menu help-esc
check "Esc closes the Help page and the window" grep -q 'STATUS 0' <<<"$out"
menu help-q
check "q does too" grep -q 'STATUS 0' <<<"$out"
menu help-space
check "Space scrolls a page" grep -qx 'line 24' "$T/screen"
check "...and Esc then closes" grep -q 'STATUS 0' <<<"$out"
menu help-pgdn
check "Page Down scrolls a page" grep -qx 'line 24' "$T/screen"
menu help-end
check "End shows the last page" grep -qx 'line 100' "$T/screen"
menu help-wheel
check "the mouse wheel scrolls" grep -qx 'line 26' "$T/screen"
menu status-esc
check "Status is shown in the pager too" grep -qxF "$T/debsway|status.sh|pause=" "$T/ran"
check "...and Esc closes it" grep -q 'STATUS 0' <<<"$out"

menu down-enter
check "Down then Enter runs install-extras.sh in the debsway folder" grep -qxF "$T/debsway|install-extras.sh|pause=1" "$T/ran"

menu j-enter
check "j moves down too (Update)" grep -qxF "$T/debsway|update.sh|pause=1" "$T/ran"
check "what Update prints is also kept in a log" grep -qx 'printed by update.sh' "$T/home/.local/state/debsway/menu-update.log"

menu up-wraps
check "Up from the first entry goes to the last (Status)" grep -qxF "$T/debsway|status.sh|pause=" "$T/ran"

menu click-update
check "a click on Update runs update.sh" grep -qxF "$T/debsway|update.sh|pause=1" "$T/ran"

menu click-outside
check "a click outside the entries runs nothing" test ! -s "$T/ran"

menu esc
check "Esc closes the menu" grep -q 'STATUS 0' <<<"$out"
check "...and runs nothing" test ! -s "$T/ran"

menu q
check "q closes the menu" grep -q 'STATUS 0' <<<"$out"

menu resize
check "the menu starts centered for the window's first size (24x80)" grep -q 'TITLES 9;22' <<<"$out"
check "and centers itself again, with no key pressed, when sway stretches the window" grep -q 'TITLES 9;22 17;42' <<<"$out"
check "...without leaving the menu" grep -q 'STATUS 0' <<<"$out"

menu early-resize
check "a window stretched before the first draw is drawn centered at once, with no jump" grep -qx 'TITLES 17;42' <<<"$(grep TITLES <<<"$out")"

# Wi-Fi, Bluetooth and the microphone: listed only when the computer has them
printf 'wifi on\nmic off\n' >"$T/radios-list"; echo on >"$T/radio-wifi"; echo off >"$T/radio-mic"
cp "$T/radios.sh" "$T/home/.local/bin/radios"; chmod +x "$T/home/.local/bin/radios"
menu toggle-wifi
check "Wi-Fi and the microphone are listed, with their state" grep -q 'Wi-Fi: on' "$T/screen" && grep -q 'Microphone: off' "$T/screen"
check "choosing Wi-Fi flips it" grep -qx 'radios wifi toggle' "$T/ran"
check "...the entry shows the new state" grep -q 'Wi-Fi: off' "$T/screen"
check "...and the menu stays open until Esc" grep -q 'STATUS 0' <<<"$out"
check "Bluetooth is not listed when the computer has none" not grep -q 'Bluetooth' "$T/screen"
echo off >"$T/radio-mic"
menu click-mic
check "a click on Microphone flips it too" grep -qx 'radios mic toggle' "$T/ran"
printf 'bluetooth blocked\n' >"$T/radios-list"; echo blocked >"$T/radio-bluetooth"
menu enter
check "a Bluetooth held off by a hardware switch says so" grep -q 'Bluetooth: off (hardware switch)' "$T/screen"
: >"$T/radios-list"
menu enter
check "with nothing to switch only the usual entries show" test "$(grep -c -E 'Wi-Fi|Bluetooth|Microphone' "$T/screen")" -eq 0
rm -f "$T/home/.local/bin/radios"

menu enter "$T/nowhere"
check "without the debsway folder only Help is drawn" grep -q 'DREW Help$' <<<"$out"

# 3. The prompt at the end of the install and update screens: Esc, Enter or q
cat >"$T/pause.py" <<'PY'
import os, pty, select, sys, time
def run(keys, pause=True):
    pid, fd = pty.fork()
    if pid == 0:
        env = dict(os.environ, TERM="xterm", DEBSWAY_ESC_WAIT="1")
        if pause: env["DEBSWAY_PAUSE"] = "1"
        else: env.pop("DEBSWAY_PAUSE", None)
        os.execvpe("/bin/bash", ["bash", "-c", ". " + sys.argv[1] + "; pause_if_asked; echo AFTER-IT"], env)
    out = b""
    def pump(w):
        nonlocal out
        end = time.time() + w
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.05)
            if r:
                try: d = os.read(fd, 4096)
                except OSError: return
                if not d: return
                out += d
    pump(0.5)
    waiting = b"AFTER-IT" not in out
    for k in keys:
        os.write(fd, k.encode()); pump(1.5)   # (a plain Esc is confirmed after DEBSWAY_ESC_WAIT)
    os.kill(pid, 9); os.waitpid(pid, 0)
    return waiting, b"AFTER-IT" in out, b"Press Esc to close" in out
for name, keys, pause in [("none", [], False), ("x-then-esc", ["x", "\x1b"], True), ("enter", ["\r"], True),
                          ("q", ["q"], True), ("arrow", ["\x1b[A"], True), ("nothing", [], True)]:
    waiting, closed, prompted = run(keys, pause)
    print(name, "waiting=%s closed=%s prompted=%s" % (waiting, closed, prompted))
PY
pausetest=$(python3 -I "$T/pause.py" "$HERE/lib/core.sh" 2>&1)
check "with no menu, nothing waits" grep -qx 'none waiting=False closed=True prompted=False' <<<"$pausetest"
check "the prompt asks for Esc" grep -q 'prompted=True' <<<"$pausetest"
check "a stray key does not close it, Esc does" grep -qx 'x-then-esc waiting=True closed=True prompted=True' <<<"$pausetest"
check "Enter closes it" grep -qx 'enter waiting=True closed=True prompted=True' <<<"$pausetest"
check "q closes it" grep -qx 'q waiting=True closed=True prompted=True' <<<"$pausetest"
check "an arrow key does not close it" grep -qx 'arrow waiting=True closed=False prompted=True' <<<"$pausetest"
check "without a key it keeps waiting" grep -qx 'nothing waiting=True closed=False prompted=True' <<<"$pausetest"

# 4. The screens it opens
check "the install screen waits for Enter only when asked to" grep -q 'pause_if_asked' "$HERE/install-extras.sh"
check "choosing nothing in the checklist leaves before that wait" python3 -I -c '
import re, sys
s = open(sys.argv[1]).read()
none = s.index("No extras chosen")
wait = s.index("pause_if_asked")
assert none < wait and "exit 0" in s[none:wait], "the no-choice exit must come first"
' "$HERE/install-extras.sh"
# shellcheck disable=SC2016  # the inner shells expand their own variables
check "the install list and nmtui have the same color block" \
    bash -c 'b() { sed -n "/^# newt (whiptail/,/^export NEWT_COLORS$/p" "$1"; }; [ -n "$(b "$1")" ] && [ "$(b "$1")" = "$(b "$2")" ]' _ "$HERE/install-extras.sh" "$HERE/bin/nmtui"

# the nmtui wrapper: runs the real program with debsway's colors, unless you set your own
# shellcheck disable=SC2016  # written into the pretend program, expanded when it runs
printf '#!/bin/sh\necho "colors=$NEWT_COLORS"\necho "colorterm=${COLORTERM:-}"\necho "args=$*"\n' >"$T/fake/nmtui"
chmod +x "$T/fake/nmtui"
nm=$(env -u NEWT_COLORS -u COLORTERM TERM=foot DEBSWAY_NMTUI="$T/fake/nmtui" bash "$HERE/bin/nmtui" connect X)
check "the nmtui wrapper sets debsway's colors: in foot, exact white on black" grep -q 'colors=root=#ffffff,#000000' <<<"$nm"
check "...telling newt the terminal has 24-bit color, or it ignores them (and draws blue and red)" grep -qx 'colorterm=truecolor' <<<"$nm"
check "...and passes its arguments on" grep -qx 'args=connect X' <<<"$nm"
nm=$(env -u NEWT_COLORS -u COLORTERM TERM=linux DEBSWAY_NMTUI="$T/fake/nmtui" bash "$HERE/bin/nmtui")
# shellcheck disable=SC2016
check "at the console (no 24-bit color): color names" bash -c 'grep -q "colors=root=white,black" <<<"$1" && grep -qx "colorterm=" <<<"$1"' _ "$nm"
# shellcheck disable=SC2016
check "every one of newt's color sets is given (one left out stays red)" bash -c '
for c in root border window shadow title button actbutton compactbutton checkbox actcheckbox entry disentry label listbox actlistbox sellistbox actsellistbox textbox acttextbox helpline roottext emptyscale fullscale; do
    grep -qE "(^| )$c=" <<<"${1#colors=}" || exit 1
done' _ "$(grep '^colors=' <<<"$nm")"

# the real whiptail, as the install list starts it: only black and white come out,
# the chosen line reversed (white behind it)
if command -v whiptail >/dev/null; then
    cat >"$T/wt.py" <<'PY'
import os, pty, select, sys, time, fcntl, termios, struct, re
def run(term):
    pid, fd = pty.fork()
    if pid == 0:
        env = dict(os.environ, TERM=term); env.pop("COLORTERM", None); env.pop("NEWT_COLORS", None)
        os.execvpe("bash", ["bash", "-c", 'eval "$(sed -n "/^# newt (whiptail/,/^export NEWT_COLORS$/p" "$1")"; exec whiptail --checklist pick 15 60 4 a one OFF b two OFF', "_", sys.argv[1]], env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    out = b""; end = time.time() + 1.0
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: d = os.read(fd, 65536)
            except OSError: break
            if not d: break
            out += d
    os.kill(pid, 9); os.waitpid(pid, 0)
    return set(re.findall(rb"\x1b\[([0-9;]*)m", out))
bw = {b"", b"1", b"30", b"37", b"40", b"47", b"38;2;0;0;0", b"38;2;255;255;255", b"48;2;0;0;0", b"48;2;255;255;255"}
for term, white_bg in (("foot", b"48;2;255;255;255"), ("linux", b"47")):
    c = run(term)
    print(term, "bw" if c and c <= bw else sorted(c - bw), "reversed" if white_bg in c else "flat")
PY
    wt=$(python3 -I "$T/wt.py" "$HERE/install-extras.sh" 2>&1)
    check "the real whiptail in foot: only black and white, the chosen line reversed" grep -qx 'foot bw reversed' <<<"$wt"
    check "...and at the console" grep -qx 'linux bw reversed' <<<"$wt"
fi

# the introduction (prep/intro.sh, start.sh's first screen) says what to press
if command -v less >/dev/null; then
    cat >"$T/intro.py" <<'PY'
import os, pty, select, sys, time, fcntl, termios, struct, re
pid, fd = pty.fork()
if pid == 0:
    os.execvpe("bash", ["bash", sys.argv[1]], dict(os.environ, TERM="xterm", DEBSWAY_ASSUME_YES="1"))
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 20, 80, 0, 0))
def pump(w):
    out = b""; end = time.time() + w
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: d = os.read(fd, 65536)
            except OSError: break
            if not d: break
            out += d
    return re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]|\x1b[=>]|\r|\x07", b"", out).decode(errors="replace")
print("first", "Space for more, b to go back, q to go on" in pump(1.0))
for _ in range(12):
    os.write(fd, b" "); time.sleep(0.1)
print("end", "The end. Press q to go on to the question" in pump(1.0))
os.write(fd, b"q"); time.sleep(0.5)
done, st = os.waitpid(pid, os.WNOHANG)
if not done:
    os.kill(pid, 9); os.waitpid(pid, 0)
print("q", bool(done) and os.waitstatus_to_exitcode(st) == 0)
PY
    intro=$(python3 -I "$T/intro.py" "$HERE/prep/intro.sh" 2>&1)
    check "the introduction says what to press while you read (Space, b, q)" grep -qx 'first True' <<<"$intro"
    check "...and on its last page that q goes on" grep -qx 'end True' <<<"$intro"
    check "...and q does go on" grep -qx 'q True' <<<"$intro"
fi
nm=$(NEWT_COLORS='root=red,blue' DEBSWAY_NMTUI="$T/fake/nmtui" bash "$HERE/bin/nmtui")
check "colors you set yourself win" grep -qx 'colors=root=red,blue' <<<"$nm"
# shellcheck disable=SC2016  # a literal $HOME in the bar's script
check "the Wi-Fi name in the bar opens the wrapper" grep -q 'exec "\$HOME/.local/bin/nmtui"' "$HERE/bin/sway-status"

# the bar
check "the bar shows debsway" grep -q '"full_text":"debsway"' "$HERE/bin/sway-status"
check "the bar has no separate Help any more" not grep -q '"name":"help"' "$HERE/bin/sway-status"
check "a click on debsway starts the menu" grep -q 'debsway-menu' "$HERE/bin/sway-status"

# shellcheck disable=SC2016  # the inner bash, and the menu's own text
# A script that waits at its end marks it, so the menu doesn't ask a second time;
# one that stops on an error before that leaves no mark, and the menu waits
check "pause_if_asked marks that the window waited" bash -c '. "$1/lib.sh"; DEBSWAY_PAUSE=1 DEBSWAY_PAUSED_FILE="$2/paused" pause_if_asked </dev/null >/dev/null 2>&1; [ -e "$2/paused" ]' _ "$HERE" "$T"
# shellcheck disable=SC2016  # the menu's own text, $ included
check "the menu waits after an error only without that mark" grep -q '"$rc" -ne 0 \] && \[ ! -e "$DEBSWAY_PAUSED_FILE" \]' "$HERE/bin/debsway-menu"

[ "$fails" -eq 0 ]
