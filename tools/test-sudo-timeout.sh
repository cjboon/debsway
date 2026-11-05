#!/bin/bash
# Checks parts/sudo-timeout.sh with a pretend sudo and visudo: the rule says
# one minute, per terminal; it is checked by visudo and installed as root's,
# read-only; a rule visudo refuses isn't installed; --remove takes it out; and
# Wren Linux's scripts refresh sudo more often than that. Changes nothing
# outside a temp folder. Run by test.sh, or:  bash tools/test-sudo-timeout.sh
# shellcheck disable=SC2016  # the inner shells and pretend programs expand their own variables
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

mkdir -p "$T/bin" "$T/home"
cat >"$T/bin/sudo" <<EOF
#!/bin/bash
echo "sudo \$*" >>"$T/calls"
case \$1 in
    -v | -k) exit 0 ;;
    visudo) cp "\$3" "$T/checked"; [ ! -e "$T/visudo-refuses" ] ;;
    install) cp "\${@: -2:1}" "$T/installed" ;;
esac
EOF
chmod +x "$T/bin/sudo"
R=$T/r
mkdir -p "$R/parts" "$R/lib"
sed 's|^export PATH=.*|export PATH="$ST_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q ST_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
for f in pins.sh packages.sh data bin docs; do ln -s "$HERE/$f" "$R/$f"; done
for f in "$HERE"/lib/*; do ln -s "$f" "$R/lib/${f##*/}"; done
cp "$HERE/parts/sudo-timeout.sh" "$R/parts/"
export ST_TEST_PATH="$T/bin:$PATH"
st() { : >"$T/calls"; HOME=$T/home bash "$R/parts/sudo-timeout.sh" "$@" 2>&1; }

st >/dev/null
check "the rule: one minute, per terminal" bash -c '
    grep -qx "Defaults timestamp_timeout=1" "$1" && grep -qx "Defaults timestamp_type=tty" "$1" && [ "$(grep -vc "^#" "$1")" = 2 ]' _ "$T/installed"
check "...checked by visudo first, then installed as root's, read-only" bash -c '
    grep -q "sudo visudo -cf" "$1" && grep -q "sudo install -o root -g root -m 0440 .* /etc/sudoers.d/wren-sudo-timeout" "$1" && cmp "$2" "$3"' _ "$T/calls" "$T/checked" "$T/installed"
check "...and it says it is set up (a mark of yours)" test -f "$T/home/.config/wren/sudo-timeout"
if command -v visudo >/dev/null; then
    check "...and the real visudo takes it" visudo -cf "$T/installed"
fi
rm -f "$T/installed" "$T/home/.config/wren/sudo-timeout"
: >"$T/visudo-refuses"
st >/dev/null
check "a rule visudo refuses isn't installed" bash -c '[ ! -e "$1" ] && [ ! -e "$2" ]' _ "$T/installed" "$T/home/.config/wren/sudo-timeout"
rm -f "$T/visudo-refuses"
st >/dev/null
st --remove >/dev/null
check "--remove takes the rule and the mark out" bash -c 'grep -q "sudo rm -f /etc/sudoers.d/wren-sudo-timeout" "$1" && [ ! -e "$2" ]' _ "$T/calls" "$T/home/.config/wren/sudo-timeout"
check "Wren Linux's scripts refresh sudo more often than once a minute (sudo_keepalive)" bash -c '
    n=$(sed -n "/^sudo_keepalive() {/,/^}/p" "$1" | grep -oE "sleep [0-9]+" | grep -oE "[0-9]+"); [ -n "$n" ] && [ "$n" -lt 60 ]' _ "$HERE/lib/core.sh"
check "...and when a script ends, the refresher goes quietly (no \"Terminated\" after the last line)" bash -c '
    out=$(bash -c "SUDO=true; eval \"\$(sed -n \"/^sudo_keepalive() {/,/^}/p\" \"\$1\")\"; sudo_keepalive; /bin/sleep 0.3; echo last" _ "$1" 2>&1)
    [ "$out" = last ]' _ "$HERE/lib/core.sh"
check "it is in the base (packages.sh's PARTS)" grep -qE '(^|[ (])sudo-timeout( |$)' "$HERE/packages.sh"

[ "$fails" -eq 0 ]
