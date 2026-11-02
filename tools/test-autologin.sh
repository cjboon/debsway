#!/bin/bash
# Checks extras/autologin.sh: it writes tty1's autologin rule for your user,
# asks first (default no) when the disk isn't encrypted, and --remove takes the
# rule out. Runs the extra with a pretend sudo that only records what it would
# write, and a pretend answer for whether the disk is encrypted, so nothing on
# this computer changes. Run by test.sh, or:  bash tools/test-autologin.sh
# shellcheck disable=SC2016  # the pretend programs expand their own variables
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

# sudo: logs, and keeps what "install ... /dev/stdin DEST" would write
mkdir -p "$T/bin"
cat >"$T/bin/sudo" <<EOF
#!/bin/sh
[ "\$1" = -v ] && exit 0
echo "\$*" >>"$T/calls"
case "\$*" in *"/dev/stdin "*) cat >"$T/written" ;; esac
exit 0
EOF
chmod +x "$T/bin/sudo"

R=$T/r
mkdir -p "$R/extras"
sed 's|^export PATH=.*|export PATH="$AUTOLOGIN_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q AUTOLOGIN_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
for f in pins.sh packages.sh lib data docs; do ln -s "$HERE/$f" "$R/$f"; done
cp "$HERE/extras/autologin.sh" "$R/extras/"
export AUTOLOGIN_TEST_PATH="$T/bin:$PATH"
[ "$(bash -c '. "$1/lib.sh"; command -v sudo' _ "$R")" = "$T/bin/sudo" ] || { echo "  FAIL  the real sudo would run; stopping"; exit 1; }

run() { # ROOT-DEVICE-TYPES ANSWER [ARGS]: the extra, with lsblk's answer and a typed answer
    : >"$T/calls"; rm -f "$T/written"
    printf '%s\n' "$2" >"$T/answers"
    DEBSWAY_LSBLK_ROOT=$1 DEBSWAY_TEST_ANSWERS=$T/answers bash "$R/extras/autologin.sh" "${@:3}" >"$T/out" 2>&1
}
me=$(id -un)
CONF=/etc/systemd/system/getty@tty1.service.d/50-debsway-autologin.conf

run "$(printf 'lvm\ncrypt\npart\ndisk')" ''
check "an encrypted disk: the rule is written without asking" grep -q "install -D -o root -g root -m 0644 /dev/stdin $CONF" "$T/calls"
check "...for your user, on tty1, with login -f" grep -qF -- "-o '-p -f -- \\\\u' --noreset --noclear --autologin $me - \${TERM}" "$T/written"
check "...replacing Debian's line, not adding a second" bash -c '[ "$(grep -c "^ExecStart=" "$1")" = 2 ] && grep -qx "ExecStart=" "$1"' _ "$T/written"
check "...and systemd reads it" grep -qx 'systemctl daemon-reload' "$T/calls"
check "...and it says the screen lock still asks" grep -q 'screen lock' "$T/out"
run "$(printf 'part\ndisk')" ''
check "a disk that isn't encrypted: it warns" grep -q 'NOT encrypted' "$T/out"
check "...and Enter (no) changes nothing" test ! -e "$T/written"
run "$(printf 'part\ndisk')" y
check "...yes writes the rule" test -s "$T/written"
run '' '' --remove
check "--remove takes the rule out" grep -qx "rm -f $CONF" "$T/calls"
run '' '' --manual
check "--manual runs nothing" test ! -s "$T/calls"

[ "$fails" -eq 0 ]
