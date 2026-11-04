#!/bin/bash
# Checks bin/wren-lock with a pretend swaylock and pgrep: the screen locks
# first, then the on-lock programs run (each with a 10-second limit, only the
# executable ones); a screen locked already isn't locked again; and Super+Escape,
# the power menu and the lid lock through it. Changes nothing outside a temp
# folder. Run by test.sh, or:  bash tools/test-wren-lock.sh
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
mkdir -p "$T/bin" "$T/conf/wren/on-lock.d"
printf '#!/bin/sh\necho "swaylock $*" >>"%s/order"\n' "$T" >"$T/bin/swaylock"
printf '#!/bin/sh\n[ -e "%s/locked" ]\n' "$T" >"$T/bin/pgrep"
printf '#!/bin/sh\necho "timeout $1" >>"%s/order"\nshift; exec "$@"\n' "$T" >"$T/bin/timeout"
printf '#!/bin/sh\necho "vault closes" >>"%s/order"\n' "$T" >"$T/conf/wren/on-lock.d/vault"
printf '#!/bin/sh\necho "keepassxc locks" >>"%s/order"\n' "$T" >"$T/conf/wren/on-lock.d/keepassxc"
printf '#!/bin/sh\necho "not a program" >>"%s/order"\n' "$T" >"$T/conf/wren/on-lock.d/notes.txt"
chmod +x "$T/bin/"* "$T/conf/wren/on-lock.d/vault" "$T/conf/wren/on-lock.d/keepassxc"
lk() { : >"$T/order"; PATH="$T/bin:$PATH" XDG_CONFIG_HOME=$T/conf HOME=$T bash "$HERE/bin/wren-lock"; }

lk
check "it locks first, then runs the on-lock programs, each with a 10-second limit" \
    test "$(paste -sd'|' "$T/order")" = "swaylock -f -c 000000|timeout 10|keepassxc locks|timeout 10|vault closes"
check "...only the executable ones" bash -c '! grep -q "not a program" "$1"' _ "$T/order"
: >"$T/locked"
lk
check "a screen locked already isn't locked again; the programs still run" \
    test "$(paste -sd'|' "$T/order")" = "timeout 10|keepassxc locks|timeout 10|vault closes"
check "Super+Escape locks through it" grep -q 'bindsym \\$mod+Escape exec ~/.local/bin/wren-lock' "$HERE/parts/swaylock.sh"
check "...and so do the power menu's Lock and the lid" bash -c '
    grep -q "exec \"\$HOME/.local/bin/wren-lock\"" "$1" && grep -q "\"\$HOME/.local/bin/wren-lock\"" "$2"' _ "$HERE/bin/powermenu" "$HERE/bin/lid"
check "the swaylock part installs it" grep -qx 'install_bin wren-lock' "$HERE/parts/swaylock.sh"

[ "$fails" -eq 0 ]
