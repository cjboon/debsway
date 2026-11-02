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
# (its lib.sh keeps the test's PATH, so a pretend dialog can be found)
sed 's|^export PATH=.*|export PATH="$FLOW_TEST_PATH"|' "$HERE/lib.sh" >"$D/lib.sh"
export FLOW_TEST_PATH="$T/fake:$PATH"
mkdir -p "$T/fake" "$D/data"
cp "$HERE/data/dialogrc" "$D/data/"
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

# The list drawn by dialog: what it answers (one name per line) is what gets
# picked, a heading line checked by mistake is not an extra, and its colours are debsway's
cat >"$T/fake/dialog" <<EOF
#!/bin/sh
echo "\$DIALOGRC" >"$T/dialogrc-used"
printf '%s\n' "\$*" >"$T/dialog-args"
printf '~most\ngamma\nalpha\n' >&2
EOF
chmod +x "$T/fake/dialog"
script -qec "bash $D/install-extras.sh --choose $T/picked" /dev/null </dev/null >/dev/null 2>&1
check "with dialog: the checked extras are picked, a checked heading isn't" test "$(paste -sd, "$T/picked")" = "gamma,alpha"
check "...with Install and No extras as its buttons" bash -c 'grep -q -- "--ok-label Install --cancel-label No extras" "$1"' _ "$T/dialog-args"
check "...in debsway's colours" test "$(cat "$T/dialogrc-used")" = "$D/data/dialogrc"
check "...the headings in the list, in order" bash -c 'grep -o "~[a-z]*" "$1" | paste -sd, | grep -qx "~most,~some,~least"' _ "$T/dialog-args"
rm "$T/fake/dialog"

# Remove apps (--remove): a list of only what is installed; what you check is
# removed with its own --remove, after a question (Enter is no)
cat >"$T/fake/dialog" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >"$T/dialog-args"
cat "$T/dialog-answer" >&2
EOF
chmod +x "$T/fake/dialog"
rmlist() { : >"$T/ran"; printf '%s\n' "$@" >"$T/answers"; DEBSWAY_TEST_ANSWERS=$T/answers script -qec "bash $D/install-extras.sh --remove" /dev/null </dev/null >"$T/out" 2>&1; }
rmlist ''
check "--remove with nothing installed: says so, removes nothing" bash -c 'grep -q "nothing to remove" "$1" && [ ! -s "$2" ]' _ "$T/out" "$T/ran"
: >"$T/nowhere-beta"; : >"$T/nowhere-delta"
printf 'beta\ngamma\n' >"$T/dialog-answer"
rmlist y
check "--remove lists only what is installed" bash -c 'grep -q " beta " "$1" && grep -q " delta " "$1" && ! grep -q " gamma " "$1" && ! grep -q " alpha " "$1"' _ "$T/dialog-args"
check "...with Remove and Cancel as its buttons" grep -q -- '--ok-label Remove --cancel-label Cancel' "$T/dialog-args"
check "...and after yes, removes the checked one with its own --remove (not one that isn't installed)" test "$(cat "$T/ran")" = "beta --remove "
rmlist ''
check "...Enter at the question removes nothing" test ! -s "$T/ran"
rm "$T/fake/dialog" "$T/nowhere-beta" "$T/nowhere-delta"

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
