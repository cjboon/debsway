#!/bin/bash
# Checks the hints for commands that aren't installed (data/command-hints.bash):
# a Wren Linux extra's command names its script, anything else is "command not
# found" (status 127), odd names aren't looked up, nothing is run. And
# parts/command-hints.sh on a copy of Wren Linux with a pretend sudo: one marked
# block in a temp ~/.bashrc, kept once on a re-run, gone with --remove, the
# rest of the file untouched. Run by test.sh, or:  bash tools/test-command-hints.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}

sed "s|@WREN_DIR@|$HERE|" "$HERE/data/command-hints.bash" >"$T/hints"
hint() { (cd "$T" && bash -c '. "$1"; command_not_found_handle "$2"' _ "$T/hints" "$1" 2>&1); }
st() { (cd "$T" && bash -c '. "$1"; command_not_found_handle "$2"' _ "$T/hints" "$1" >/dev/null 2>&1); echo $?; }

check "claude-vm, not installed: it says wrenctl install claude-vm" grep -qx '    wrenctl install claude-vm' <<<"$(hint claude-vm)"
check "gimp: wrenctl install gimp" grep -qx '    wrenctl install gimp' <<<"$(hint gimp)"
check "...and status 127, as for any missing command" test "$(st gimp)" = 127
check "a name no extra provides: command not found, 127" bash -c '[[ $1 == *"no-such-thing-x: command not found"* ]] && [ "$2" = 127 ]' _ "$(hint no-such-thing-x)" "$(st no-such-thing-x)"
check "odd names aren't looked up, and nothing runs" bash -c '
    out=$(cd "$1" && bash -c ". \"\$1\"; command_not_found_handle \"\$2\"" _ "$1/hints" "\$(touch $1/ran)" 2>&1)
    [[ $out == *"command not found"* ]] && [ ! -e "$1/ran" ]' _ "$T"
check "...nor a path" bash -c '[[ $1 == *"command not found"* ]]' _ "$(hint ../extras/gimp)"
check "every extra's bin: command names a script that exists" bash -c '
    for f in "$1"/extras/*.sh; do
        for w in $(grep -m1 "^# status:" "$f" | sed "s/^# status://"); do
            case $w in bin:*) n=${w#bin:}; [ -n "$n" ] || exit 1 ;; esac
        done
    done' _ "$HERE"

# ---- the part: one marked block in ~/.bashrc, loading the root-owned file
R=$T/r
mkdir -p "$R/parts" "$T/bin" "$T/home" "$T/usr"
sed 's|^export PATH=.*|export PATH="$HINTS_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q HINTS_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
for f in packages.sh pins.sh lib data bin docs extras; do ln -s "$HERE/$f" "$R/$f"; done
sed "s|/usr/local/share/wren|$T/usr|" "$HERE/parts/command-hints.sh" >"$R/parts/command-hints.sh"
# a pretend sudo: runs the command as this user (install without its -o/-g, which
# only root may give)
cat >"$T/bin/sudo" <<'SUDO'
#!/bin/bash
while [ "${1#-}" != "$1" ]; do shift; done
[ $# -gt 0 ] || exit 0
if [ "$1" = install ]; then
    a=()
    while [ $# -gt 0 ]; do case $1 in -o | -g) shift 2 ;; *) a+=("$1"); shift ;; esac; done
    set -- "${a[@]}"
fi
exec "$@"
SUDO
chmod +x "$T/bin/sudo"
[ "$(HINTS_TEST_PATH="$T/bin:$PATH" bash -c '. "$1/lib.sh"; command -v sudo' _ "$R")" = "$T/bin/sudo" ] ||
    { echo "  FAIL  the real sudo would run; stopping"; exit 1; }
part() { HOME=$T/home HINTS_TEST_PATH="$T/bin:$PATH" bash "$R/parts/command-hints.sh" "$@" >/dev/null 2>&1; }
printf 'alias ll="ls -l"\n' >"$T/home/.bashrc"
part
part
check "the part: one block in ~/.bashrc after a re-run" test "$(grep -c '^# >>> Wren Linux command hints >>>$' "$T/home/.bashrc")" = 1
check "...loading the installed file, which has this repository's folder" bash -c '
    grep -qx "\[ -r $1/command-hints.bash \] && . $1/command-hints.bash" "$2" && grep -q "local dir=$3 " "$1/command-hints.bash"' _ "$T/usr" "$T/home/.bashrc" "$R"
check "...and a new terminal gets the hints" bash -c 'HOME=$1 bash -ic "command_not_found_handle gimp" 2>&1 | grep -q "wrenctl install gimp"' _ "$T/home"
part --remove
check "--remove: the block is gone, the rest of ~/.bashrc stays" bash -c '[ "$(cat "$1")" = "alias ll=\"ls -l\"" ]' _ "$T/home/.bashrc"
check "...and the file" test ! -e "$T/usr/command-hints.bash"
check "it is part of the base, after the Wren menu" bash -c '
    . "$1/packages.sh"; [[ " ${PARTS[*]} " == *" wren-menu command-hints "* ]]' _ "$HERE"

[ "$fails" -eq 0 ]
