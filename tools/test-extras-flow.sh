#!/bin/bash
# Checks install-extras.sh --choose and --install (how install-base.sh asks for
# the extras right after you agree and installs them after the base), in a
# throwaway copy of debsway with pretend extras that only write down that they
# ran. Changes nothing outside a temp folder. Run by test.sh, or:
#   bash tools/test-extras-flow.sh
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
cp "$HERE/lib.sh" "$HERE/pins.sh" "$HERE/packages.sh" "$HERE/install-extras.sh" "$D/"
cp "$HERE"/lib/*.sh "$D/lib/"
for n in alpha beta gamma; do
    # shellcheck disable=SC2016  # written into the pretend extra, expanded when it runs
    printf '#!/bin/bash\n# summary: the %s extra\n# status: file:%s/nowhere-%s\necho "%s $DEBSWAY_SETUP_GH" >>"%s/ran"\n[ "%s" != "$FAIL_ON" ]\n' "$n" "$T" "$n" "$n" "$T" "$n" >"$D/extras/$n.sh"
done
export HOME="$T/home" XDG_STATE_HOME="$T/state"
mkdir -p "$HOME"
run() { env -u TERM bash "$D/install-extras.sh" "$@" 2>&1; }

# --list shows them, none checked or installed
out=$(run --list)
check "--list shows each extra with its summary" grep -q 'alpha  *the alpha extra' <<<"$out"
check "nothing is marked installed" not grep -q '\[installed\]' <<<"$out"

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
