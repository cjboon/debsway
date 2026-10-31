#!/bin/bash
# Checks the hardware tests (lib/core.sh: has_backlight, has_battery, has_wifi...)
# and skip_unless, on a pretend /sys. Changes nothing. Run by test.sh, or:
#   bash tools/test-hardware.sh
# shellcheck disable=SC2016  # the inner bash expands its own variables
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
# sys_has SYSDIR CHECK: the check, run with SYSDIR as /sys
sys_has() { env DEBSWAY_SYS="$1" bash -c '. "$1/lib/core.sh"; "$2"' _ "$HERE" "$2"; }

mkdir -p "$T/desktop/class/net/eth0" "$T/desktop/class/power_supply/AC"
mkdir -p "$T/laptop/class/backlight/intel_backlight" "$T/laptop/class/power_supply/BAT0" \
    "$T/laptop/class/net/wlan0/wireless" "$T/laptop/class/bluetooth/hci0"
mkdir -p "$T/amd/firmware/acpi" && : >"$T/amd/firmware/acpi/platform_profile"

check "a desktop has no backlight" not sys_has "$T/desktop" has_backlight
check "a laptop has one" sys_has "$T/laptop" has_backlight
check "a desktop has no battery (the mains adapter is not one)" not sys_has "$T/desktop" has_battery
check "a laptop has a battery" sys_has "$T/laptop" has_battery
check "a desktop has no power profiles" not sys_has "$T/desktop" has_power_profiles
check "a laptop has them (it has a battery)" sys_has "$T/laptop" has_power_profiles
check "a desktop with a platform profile has them" sys_has "$T/amd" has_power_profiles
check "a wired-only desktop has no Wi-Fi" not sys_has "$T/desktop" has_wifi
check "a laptop has Wi-Fi" sys_has "$T/laptop" has_wifi
check "a desktop has no Bluetooth adapter" not sys_has "$T/desktop" has_bluetooth
check "a laptop has one" sys_has "$T/laptop" has_bluetooth
check "an empty /sys has none of it" not sys_has "$T/nowhere" has_wifi

# skip_unless: stops a part cleanly under install-base.sh, never when run by hand
run() { # SYSDIR FROM_BASE: prints RAN if the part would go on
    env DEBSWAY_SYS="$1" ${2:+DEBSWAY_FROM_BASE=1} bash -c '. "$1/lib/core.sh"; skip_unless has_wifi "no Wi-Fi."; echo RAN' parts/x.sh "$HERE"
}
check "from install-base.sh, with the hardware, the part goes on" grep -q RAN <(run "$T/laptop" 1)
check "from install-base.sh, without it, the part stops" not grep -q RAN <(run "$T/desktop" 1)
check "...and says why" grep -q 'Skipped: no Wi-Fi' <(run "$T/desktop" 1)
check "...and how to install it later" grep -q 'bash parts/' <(run "$T/desktop" 1)
check "run by hand, the part always goes on" grep -q RAN <(run "$T/desktop" "")
check "the stop is a success (install-base.sh does not count it as failed)" bash -c '
    DEBSWAY_SYS="$2" DEBSWAY_FROM_BASE=1 bash -c ". \"$1/lib/core.sh\"; skip_unless has_wifi x" parts/x.sh "$1" >/dev/null' _ "$HERE" "$T/desktop"

# each laptop part asks for the right hardware, and install-base.sh sets the flag
check "brightnessctl asks for a backlight" grep -q 'skip_unless has_backlight' "$HERE/parts/brightnessctl.sh"
check "power-profiles-daemon asks for a battery or profiles" grep -q 'skip_unless has_power_profiles' "$HERE/parts/power-profiles-daemon.sh"
check "network-manager asks for Wi-Fi" grep -q 'skip_unless has_wifi' "$HERE/parts/network-manager.sh"
check "random-mac asks for Wi-Fi" grep -q 'skip_unless has_wifi' "$HERE/parts/random-mac.sh"
check "install-base.sh runs the parts with the flag" grep -q 'DEBSWAY_FROM_BASE=1 bash' "$HERE/install-base.sh"

[ "$fails" -eq 0 ]
