#!/bin/bash
# Checks install-extras.sh --choose and --install (how install-base.sh asks for
# the extras right after you agree and installs them after the base), in a
# throwaway copy of debsway with pretend extras that only write down that they
# ran. Changes nothing outside a temp folder. Run by test.sh, or:
#   bash tools/test-extras-flow.sh
# shellcheck disable=SC2016  # sed and the inner shells expand their own variables
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

D=$T/debsway
mkdir -p "$D/extras" "$D/lib"
cp "$HERE/pins.sh" "$HERE/packages.sh" "$HERE/install-extras.sh" "$D/"
# (its lib.sh keeps the test's PATH, so pretend programs can be found)
sed 's|^export PATH=.*|export PATH="$FLOW_TEST_PATH"|' "$HERE/lib.sh" >"$D/lib.sh"
export FLOW_TEST_PATH="$T/fake:$PATH"
mkdir -p "$T/fake" "$D/data"
cp "$HERE"/lib/*.sh "$D/lib/"
for n in alpha beta gamma delta; do
    printf '#!/bin/bash\n# summary: the %s extra\n# status: file:%s/nowhere-%s\necho "%s${1:+ $1} $DEBSWAY_SETUP_GH" >>"%s/ran"\n[ "%s" != "$FAIL_ON" ]\n' "$n" "$T" "$n" "$n" "$T" "$n" >"$D/extras/$n.sh"
done
# their groups: gamma most secure, alpha least, beta somewhat, delta has no line (somewhat)
sed -i 's/^# summary: the gamma extra$/&\n# security: most/' "$D/extras/gamma.sh"
sed -i 's/^# summary: the alpha extra$/&\n# security: least/' "$D/extras/alpha.sh"
sed -i 's/^# summary: the beta extra$/&\n# security: some/' "$D/extras/beta.sh"
export HOME="$T/home" XDG_STATE_HOME="$T/state"
mkdir -p "$HOME"
run() { env -u TERM bash "$D/install-extras.sh" "$@" 2>&1; }

# --list shows them, none checked or installed
out=$(run --list)
check "--list shows each extra with its summary" grep -q 'alpha  *the alpha extra' <<<"$out"
check "nothing is marked installed" not grep -q '\[installed\]' <<<"$out"
check "--list: most secure first, then somewhat, then least, each under its heading" \
    test "$(grep -oE '^(MOST|SOMEWHAT|LEAST) SECURE|^  [a-z]+' <<<"$out" | tr -d ' ' | paste -sd,)" = 'MOSTSECURE,gamma,SOMEWHATSECURE,beta,delta,LEASTSECURE,alpha'
missing=()
for f in "$HERE"/extras/*.sh; do
    grep -qxE '# security: (most|some|least)' "$f" || missing+=("${f##*/}")
done
check "every extra says how secure it is (# security: most, some or least)${missing:+: not ${missing[*]}}" test ${#missing[@]} -eq 0

# A renamed extra keeps its package marker's old name, or a computer that
# installed it before the rename would lose track of what it installed
check "mullvad-browser-regular.sh keeps the marker of mullvad-browser.sh" \
    test "$(cd "$HERE" && bash -c '. ./lib.sh; eval "$(grep -x "export DEBSWAY_OWNER=.*" extras/mullvad-browser-regular.sh)"; apt_marker')" = debsway-mullvad-browser

# The list itself (lib/checklist.sh), driven by keys and clicks in a
# pseudo-terminal: LIST MODE KEYS... runs install-extras.sh (--choose into
# $T/picked, or --remove) and sends the keys; what it drew is in $T/drawn
cat >"$T/drive.py" <<'PY'
import os, pty, re, select, struct, sys, termios, fcntl, time
script, mode, out, drawnfile, *keys = sys.argv[1:]
pid, fd = pty.fork()
if pid == 0:
    fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    args = ["bash", script, "--choose", out] if mode == "choose" else ["bash", script, "--remove"]
    os.execvpe("bash", args, dict(os.environ, TERM="xterm-256color", DEBSWAY_ESC_WAIT="0.2"))
drawn = b""
def pump(t):
    global drawn
    end = time.time() + t
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: d = os.read(fd, 65536)
            except OSError: return
            if not d: return
            drawn += d
def row_of(label):
    """The screen row where label was last drawn, after its check box"""
    m = None
    for m in re.finditer(rb"\x1b\[(\d+);3H(?:\x1b\[[0-9;]*m)*[ =]*(?:\[[ x]\] )?" + re.escape(label.encode()), drawn):
        pass
    assert m, "never drew " + label
    return int(m.group(1))
deadline = time.time() + 6
while b"Space or a click" not in drawn and time.time() < deadline:
    pump(0.1)
for k in keys:
    if k.startswith("click:"):
        what = k[6:]
        if what in ("Install", "Remove", "No extras", "Cancel"):
            m = None
            for m in re.finditer(rb"\x1b\[(\d+);(\d+)H(?:\x1b\[[0-9;]*m)*< " + re.escape(what.encode()) + rb" >", drawn):
                pass
            y, x = int(m.group(1)), int(m.group(2)) + 2
        else:
            y, x = row_of(what), 6
        k = "\x1b[<0;%d;%dM\x1b[<0;%d;%dm" % (x, y, x, y)
    os.write(fd, k.encode().decode("unicode_escape").encode() if "\\" in k else k.encode())
    pump(0.3)
pump(0.5)
for _ in range(40):
    done, st = os.waitpid(pid, os.WNOHANG)
    if done: break
    time.sleep(0.1)
else:
    os.kill(pid, 9); os.waitpid(pid, 0)
open(drawnfile, "wb").write(drawn)
PY
pick() { : >"$T/picked"; python3 -I "$T/drive.py" "$D/install-extras.sh" choose "$T/picked" "$T/drawn" "$@"; paste -sd, "$T/picked"; }
pick '\x1b' >/dev/null
check "the list: most secure first, each group under its heading" \
    bash -c 'grep -aoE "MOST SECURE|SOMEWHAT SECURE|LEAST SECURE|\] (alpha|beta|gamma|delta) " "$1" | head -7 | tr -d "] " | paste -sd, | grep -qx "MOSTSECURE,gamma,SOMEWHATSECURE,beta,delta,LEASTSECURE,alpha"' _ "$T/drawn"
check "Space checks, Down moves (over the headings), Enter installs what is checked" test "$(pick ' ' '\x1b[B' ' ' '\r')" = gamma,beta
check "Up from the first line goes round to the last" test "$(pick '\x1b[A' ' ' '\r')" = alpha
check "...and Down from the last back to the first" test "$(pick '\x1b[B' '\x1b[B' '\x1b[B' '\x1b[B' ' ' '\r')" = gamma
check "Space again unchecks" test "$(pick ' ' ' ' '\r')" = ""
check "Esc: nothing" test "$(pick ' ' '\x1b')" = ""
check "a click on a line checks it, a click on Install installs" test "$(pick click:delta click:Install)" = delta
check "a click on No extras: nothing" test "$(pick click:delta 'click:No extras')" = ""
check "the wheel moves down, and stops at the last line" test "$(pick '\x1b[<65;5;5M' '\x1b[<65;5;5M' '\x1b[<65;5;5M' '\x1b[<65;5;5M' '\x1b[<65;5;5M' ' ' '\r')" = alpha
check "...and up" test "$(pick '\x1b[<65;5;5M' '\x1b[<65;5;5M' '\x1b[<64;5;5M' ' ' '\r')" = beta
check "a click on a heading checks nothing" test "$(pick 'click:SOMEWHAT SECURE' '\r')" = ""
# ticked by the install stick (~/.config/debsway/preselect): in the first list only
mkdir -p "$HOME/.config/debsway"
echo beta >"$HOME/.config/debsway/preselect"
check "a name the stick left in preselect starts ticked" test "$(pick '\r')" = beta
check "...once: the list after starts empty" test "$(pick '\r')" = ""
echo beta >"$HOME/.config/debsway/preselect"
check "...and can be unticked" test "$(pick '\x1b[B' ' ' '\r')" = ""

# Remove apps (--remove): a list of only what is installed; what you check is
# removed with its own --remove, after a question (Enter is no)
rmlist() { : >"$T/ran"; printf '%s\n' "$1" >"$T/answers"; shift; DEBSWAY_TEST_ANSWERS=$T/answers python3 -I "$T/drive.py" "$D/install-extras.sh" remove - "$T/drawn" "$@"; }
rmlist '' '\x1b'
check "--remove with nothing installed: says so, removes nothing" bash -c 'grep -aq "nothing to remove" "$1" && [ ! -s "$2" ]' _ "$T/drawn" "$T/ran"
: >"$T/nowhere-beta"; : >"$T/nowhere-delta"
rmlist y ' ' '\r'
check "--remove lists only what is installed" bash -c 'grep -aq "\] beta " "$1" && grep -aq "\] delta " "$1" && ! grep -aq "\] gamma " "$1" && ! grep -aq "\] alpha " "$1"' _ "$T/drawn"
check "...with Remove and Cancel as its buttons" bash -c 'grep -aq "< Remove >" "$1" && grep -aq "< Cancel >" "$1"' _ "$T/drawn"
check "...and after yes, removes the checked one with its own --remove" test "$(cat "$T/ran")" = "beta --remove "
rmlist '' ' ' '\r'
check "...Enter at the question removes nothing" test ! -s "$T/ran"
rm "$T/nowhere-beta" "$T/nowhere-delta"

# --choose with no terminal to ask on: writes an empty file, installs nothing
: >"$T/ran"
setsid bash "$D/install-extras.sh" --choose "$T/picked" </dev/null >"$T/out" 2>&1
check "--choose with no terminal writes an empty file" test -e "$T/picked" -a ! -s "$T/picked"
check "...and installs nothing" test ! -s "$T/ran"

# --install installs exactly the names in the file, in order, and nothing else
printf 'gamma\nalpha\n' >"$T/picked"
: >"$T/ran"
DEBSWAY_SETUP_GH=1 run --install "$T/picked" >/dev/null
check "--install runs the picked extras in the order picked" test "$(paste -sd, "$T/ran")" = "gamma 1,alpha 1"
check "...and not the others" not grep -q beta "$T/ran"
check "...passing the environment on (git's setup flag)" grep -q 'alpha 1' "$T/ran"

# an empty file or a blank line installs nothing
: >"$T/ran"; : >"$T/picked"
out=$(run --install "$T/picked")
check "an empty list installs nothing" test ! -s "$T/ran"
check "...and says how to add some later" grep -q 'debsway --apps' <<<"$out"
printf '\n\n' >"$T/picked"; : >"$T/ran"
run --install "$T/picked" >/dev/null
check "blank lines are ignored" test ! -s "$T/ran"

# a name that is not an extra is skipped, the rest still run
printf 'nonsense\nbeta\n' >"$T/picked"; : >"$T/ran"
run --install "$T/picked" >/dev/null
check "an unknown name is skipped and the rest run" test "$(cat "$T/ran")" = "beta "

# one failing extra does not stop the others, and the exit status says so
printf 'alpha\nbeta\n' >"$T/picked"; : >"$T/ran"
FAIL_ON=alpha run --install "$T/picked" >"$T/out"; rc=$?
check "a failing extra does not stop the next" grep -q '^beta' "$T/ran"
check "...it is named in the message" grep -q 'These failed: alpha' "$T/out"
rc=$(FAIL_ON=alpha env -u TERM bash "$D/install-extras.sh" --install "$T/picked" >/dev/null 2>&1; echo $?)
check "...and the exit status is a failure" test "$rc" -ne 0

# install-base.sh asks first, installs last
# shellcheck disable=SC2016  # Python code, with a literal ${PKGS[@]} to look for
check "install-base.sh asks for the extras before it installs anything" python3 -I -c '
import sys
s = open(sys.argv[1]).read()
ask = s.index("--choose")
pkgs = s.index("apt_install \"${PKGS[@]}\"")
install = s.index("--install")
assert ask < pkgs < install, (ask, pkgs, install)
' "$HERE/install-base.sh"
check "...right after the intro and the sudo check" python3 -I -c '
import sys
s = open(sys.argv[1]).read()
assert s.index("prep/intro.sh") < s.index("need_user") < s.index("--choose")
' "$HERE/install-base.sh"
check "install-base.sh no longer installs Firefox, git or KeePassXC by itself" not grep -q 'for app in firefox keepassxc' "$HERE/install-base.sh"

# KeePassXC: the minimal build, never the full build or the Firefox add-on
k=$HERE/extras/keepassxc.sh
check "keepassxc installs the minimal build" grep -q '^apt_install keepassxc-minimal' "$k"
check "...and no apt_install line names the full build or the add-on" not grep -E '^[[:space:]]*(apt_install|pkgs=)' "$k" | grep -qE 'keepassxc-full|webext-keepassxc-browser'
check "...it takes the full build and the add-on out of its marker" grep -q '^apt_drop keepassxc-full keepassxc webext-keepassxc-browser' "$k"
check "...and no longer asks about the add-on" not grep -q 'auto_or_ask' "$k"
check "nothing else installs the add-on" not grep -rq 'apt_install.*webext-keepassxc-browser' "$HERE/extras" "$HERE/parts" "$HERE/install-base.sh"

[ "$fails" -eq 0 ]
