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
    printf '#!/bin/sh\necho "$PWD|$*|pause=$DEBSWAY_PAUSE" >>"%s/ran"\n' "$T" >"$T/fake/bash"
    printf '#!/bin/sh\ncat >/dev/null\n' >"$T/fake/less"
    printf '#!/bin/sh\necho "keys" >>"%s/ran"\n' "$T" >"$T/home/.local/bin/keys"
}
chmod +x "$T/fake/"* "$T/home/.local/bin/keys"
: >"$T/debsway/update.sh"

# 1. The window: in grays, running the menu, and not fullscreen (the bar stays visible)
PATH="$T/fake:$PATH" HOME="$T/home" /bin/bash "$HERE/bin/debsway-menu"
check "a click opens a window named debsway-run" grep -qx -e --app-id=debsway-run "$T/foot"
check "...not fullscreen, so the bar stays visible" not grep -qx -e --fullscreen "$T/foot"
check "...with a black background" grep -qx 'colors.background=000000' "$T/foot"
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
    pump(0.6)
    for k in keys:
        if isinstance(k, tuple):      # ("resize", rows, cols): the window is stretched
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", k[1], k[2], 0, 0))
            pump(1.0)
            continue
        os.write(fd, (k(drawn) if callable(k) else k).encode())
        pump(0.5)
    status = None
    for _ in range(30):
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
    env = {"PATH": path, "HOME": home, "TERM": "xterm-256color", "DEBSWAY_DIR": folder, "LANG": "C.UTF-8"}
    scenarios = {
        "enter": ["\r"],
        "down-enter": ["\x1b[B", "\r"],
        "j-enter": ["j", "j", "\r"],
        "up-wraps": ["\x1b[A", "\r"],
        "click-update": [click_on("Update")],
        "click-outside": ["\x1b[<0;1;1M\x1b[<0;1;1m", "q"],
        "esc": ["\x1b"],
        "resize": [("resize", 40, 120), "q"],
        "q": ["q"],
    }
    drawn, status = run(script, env, scenarios[scenario])
    print("STATUS", status)
    print("DREW", "|".join(re.findall(r"(Help|Install apps|Update|Status)", drawn)[:4]))
    # where the title "debsway" was drawn each time: row;column
    print("TITLES", " ".join("%s;%s" % m for m in re.findall(r"\x1b\[(\d+);(\d+)H\x1b\[1mdebsway", drawn)))
PY
menu() { # SCENARIO [FOLDER]: runs it, leaves the output in $out and what ran in $T/ran
    : >"$T/ran"
    out=$(python3 -I "$T/drive.py" "$HERE/bin/debsway-menu" "$T/home" "$T/fake:/usr/bin:/bin" "${2-$T/debsway}" "$T/ran" "$1" 2>&1)
}

menu enter
check "Enter on the first entry opens Help" grep -qx keys "$T/ran"
check "the four entries are drawn" grep -q 'DREW Help|Install apps|Update|Status' <<<"$out"

menu down-enter
check "Down then Enter runs install-extras.sh in the debsway folder" grep -qxF "$T/debsway|install-extras.sh|pause=1" "$T/ran"

menu j-enter
check "j moves down too (Update)" grep -qxF "$T/debsway|update.sh|pause=1" "$T/ran"

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
check "the menu starts centered for the window's first size (24x80)" grep -q 'TITLES 9;28' <<<"$out"
check "and centers itself again, with no key pressed, when sway stretches the window" grep -q 'TITLES 9;28 17;48' <<<"$out"
check "...without leaving the menu" grep -q 'STATUS 0' <<<"$out"

menu enter "$T/nowhere"
check "without the debsway folder only Help is drawn" grep -q 'DREW Help$' <<<"$out"

# 3. The screens it opens
check "the install screen waits for Enter only when asked to" grep -q 'pause_if_asked' "$HERE/install-extras.sh"
check "choosing nothing in the checklist leaves before that wait" python3 -I -c '
import re, sys
s = open(sys.argv[1]).read()
none = s.index("No extras chosen")
wait = s.index("pause_if_asked")
assert none < wait and "exit 0" in s[none:wait], "the no-choice exit must come first"
' "$HERE/install-extras.sh"
check "the checklist colors are all grays" python3 -I -c '
import re, sys
s = open(sys.argv[1]).read()
block = s[s.index("NEWT_COLORS"):]
block = block[:block.index("}\n")]
cols = set(re.findall(r"=(\w+),(\w+)", block))
names = {c for pair in cols for c in pair}
assert names <= {"black", "lightgray", "gray", "white"}, names
' "$HERE/install-extras.sh"

# the bar
check "the bar shows debsway" grep -q '"full_text":"debsway"' "$HERE/bin/sway-status"
check "the bar has no separate Help any more" not grep -q '"name":"help"' "$HERE/bin/sway-status"
check "a click on debsway starts the menu" grep -q 'debsway-menu' "$HERE/bin/sway-status"

[ "$fails" -eq 0 ]
