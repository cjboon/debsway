#!/bin/bash
# Checks set_bluetooth_autoenable (lib/net.sh, used by extras/bluetooth.sh) on
# pretend bluez main.conf files, and that the new extras fit the checklist.
# Changes nothing outside a temp folder. Run by test.sh, or:
#   bash tools/test-bluetooth-conf.sh
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$HERE/lib.sh"
set +e +o pipefail

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

# bluez's own file has the key commented out under [Policy]
printf '%s\n' '[General]' '#Name = BlueZ' '' '[Policy]' '#ReconnectAttempts=7' '#AutoEnable=true' >"$T/stock"
cp "$T/stock" "$T/c"
set_bluetooth_autoenable "$T/c" false
check "the commented AutoEnable line becomes false, in its place" grep -qx 'AutoEnable=false # debsway' "$T/c"
check "...once" test "$(grep -c AutoEnable "$T/c")" -eq 1
check "the rest of the file is unchanged" test "$(diff "$T/stock" "$T/c" | grep -c '^[<>]')" -eq 2
set_bluetooth_autoenable "$T/c" false
check "doing it twice changes nothing more" test "$(grep -c AutoEnable "$T/c")" -eq 1
set_bluetooth_autoenable "$T/c" true
check "undoing it puts bluez's own line back" cmp -s "$T/c" "$T/stock"

printf '%s\n' '[General]' 'Name = x' >"$T/nokey"
set_bluetooth_autoenable "$T/nokey" false
check "with no AutoEnable line, a [Policy] section is added" grep -qx '\[Policy\]' "$T/nokey"
check "...with the line in it" grep -qx 'AutoEnable=false # debsway' "$T/nokey"

printf '%s\n' '[Policy]' 'AutoEnable=true' >"$T/on"
set_bluetooth_autoenable "$T/on" false
check "an uncommented AutoEnable=true is switched too" grep -qx 'AutoEnable=false # debsway' "$T/on"
set_bluetooth_autoenable "$T/on" true
check "a line debsway did not write is not touched when undoing" not grep -q 'AutoEnable=false' "$T/on"

# the new extras fit the checklist
for n in bluetooth phone-tethering; do
    f="$HERE/extras/$n.sh"
    s=$(sed -n 's/^# summary: //p' "$f")
    check "$n has a summary of at most 52 characters" test -n "$s" -a "${#s}" -le 52
    check "$n has a status line" grep -q '^# status: ' "$f"
    check "$n has a --remove" grep -q -e '--remove' "$f"
done
check "bluetooth warns when there is no adapter, but goes on" grep -q 'has_bluetooth || warn' "$HERE/extras/bluetooth.sh"
# shellcheck disable=SC2016  # the pattern names a shell variable of the extra, literally
check "bluetooth starts the adapter off" grep -q 'set_bluetooth_autoenable "\$tmp" false' "$HERE/extras/bluetooth.sh"

[ "$fails" -eq 0 ]
