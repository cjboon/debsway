#!/bin/bash
# Checks bin/radios (Wi-Fi, Bluetooth and microphone on/off) with a pretend
# rfkill, wpctl and bluetoothctl and a pretend /sys. Changes nothing. Run by
# test.sh, or:  bash tools/test-radios.sh
# shellcheck disable=SC2016  # the inner bash expands its own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
R=$HERE/bin/radios

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

mkdir -p "$T/fake" "$T/sys/class/net/wlan0/wireless" "$T/sys/class/bluetooth/hci0" "$T/rf"
# rfkill keeps "SOFT HARD" per type in a file; list prints it, block/unblock change the soft part
cat >"$T/fake/rfkill" <<FAKE
#!/bin/bash
f="$T/rf/\${@: -1}"
case \$1 in
    block) read -r s h <"$T/rf/\$2"; echo "blocked \$h" >"$T/rf/\$2" ;;
    unblock) read -r s h <"$T/rf/\$2"; echo "unblocked \$h" >"$T/rf/\$2" ;;
    -n) [ -f "\$f" ] && cat "\$f" ;;
esac
FAKE
# wpctl: the microphone is "Volume: 1.00" or "Volume: 1.00 [MUTED]"
cat >"$T/fake/wpctl" <<FAKE
#!/bin/bash
[ -f "$T/mic" ] || exit 1
case \$1 in
    get-volume) echo "Volume: 1.00\$([ "\$(cat "$T/mic")" = muted ] && echo ' [MUTED]')" ;;
    set-mute) if [ "\$3" = 1 ]; then echo muted >"$T/mic"; else echo open >"$T/mic"; fi ;;
esac
FAKE
cat >"$T/fake/bluetoothctl" <<FAKE
#!/bin/bash
echo "bluetoothctl \$*" >>"$T/calls"
case "\$1 \$2" in
    "power on") echo yes >"$T/powered" ;;
    "power off") echo no >"$T/powered" ;;
    show*) echo "Controller AA:BB"; echo "	Powered: \$(cat "$T/powered")" ;;
esac
FAKE
chmod +x "$T/fake/"*
echo "unblocked unblocked" >"$T/rf/wifi"; echo "unblocked unblocked" >"$T/rf/bluetooth"; echo open >"$T/mic"; echo yes >"$T/powered"
r() { env PATH="$T/fake:/usr/bin:/bin" DEBSWAY_SYS="$T/sys" XDG_RUNTIME_DIR="$T/run" bash "$R" "$@"; }

check "list shows each radio that exists, with its state" test "$(r list | paste -sd,)" = "wifi on,bluetooth on,mic on"
check "status says on" test "$(r wifi status)" = on
check "no word means status" test "$(r mic)" = on

r wifi off
check "wifi off blocks the radio" test "$(r wifi status)" = off
check "list shows it off" grep -qx 'wifi off' <(r list)
r wifi toggle
check "toggle turns it back on" test "$(r wifi status)" = on
r wifi on
check "on when it is on stays on" test "$(r wifi status)" = on

: >"$T/calls"
r bluetooth off
check "bluetooth off powers the adapter down and blocks the radio" test "$(r bluetooth status)" = off -a -n "$(grep 'power off' "$T/calls")"
r bluetooth on
check "bluetooth on unblocks it and powers the adapter up" test "$(r bluetooth status)" = on -a -n "$(grep 'power on' "$T/calls")"

r mic off
check "mic off mutes the default microphone" test "$(r mic status)" = off
check "...and nothing else changed" test "$(r wifi status)" = on
r mic toggle
check "mic toggle unmutes it" test "$(r mic status)" = on

echo "unblocked blocked" >"$T/rf/wifi"
check "a hardware switch is reported as blocked, not as off" test "$(r wifi status)" = blocked
echo "blocked blocked" >"$T/rf/wifi"
check "...also when the software one is on too" test "$(r wifi status)" = blocked
echo "unblocked unblocked" >"$T/rf/wifi"

# bluez starts the adapter powered down: free of rfkill, but still off
echo no >"$T/powered"
check "an unblocked but powered-down Bluetooth adapter counts as off" test "$(r bluetooth status)" = off
r bluetooth on
check "switching it on powers it up" test "$(r bluetooth status)" = on

# what a desktop does not have is not listed, and asking for it fails
rm -rf "$T/sys/class/bluetooth"; rm -f "$T/mic"
check "without Bluetooth or a microphone, only Wi-Fi is listed" test "$(r list)" = "wifi on"
r bluetooth on 2>"$T/err"; rc=$?
check "asking for Bluetooth there fails with status 1" test "$rc" -eq 1
check "...and says so" grep -q 'no bluetooth on this computer' "$T/err"
rm -rf "$T/sys/class/net"
check "with no Wi-Fi adapter nothing is listed" test -z "$(r list)"

# --wait: the microphone shows up a moment later (sound is still starting at login)
echo open >"$T/mic"
(sleep 1.5; echo open >"$T/mic") &
rm -f "$T/mic"
r mic off --wait
check "mic off --wait waits for the microphone, then mutes it" test "$(cat "$T/mic")" = muted
wait

check "a wrong word is refused with status 2" bash -c 'env PATH="$1/fake:/usr/bin:/bin" bash "$2" nonsense; [ $? -eq 2 ]' _ "$T" "$R"
check "so is a wrong action" bash -c 'echo open >"$1/mic"; env PATH="$1/fake:/usr/bin:/bin" DEBSWAY_SYS="$1/sys" bash "$2" mic sideways; [ $? -eq 2 ]' _ "$T" "$R"

[ "$fails" -eq 0 ]
