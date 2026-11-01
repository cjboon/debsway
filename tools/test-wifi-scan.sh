#!/bin/bash
# Checks wifi.sh's network scan: a scan that never finishes (a driver that
# starts one and never reports it done, as right after a boot) is cut off,
# so wifi.sh goes on to ask for the network name instead of hanging at
# "Scanning for networks". Runs scan_ssids with a pretend iw. Run by test.sh, or:
#   bash tools/test-wifi-scan.sh
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

mkdir -p "$T/bin"
# iw that hangs (TEST_IW=hang) or lists two networks
cat >"$T/bin/iw" <<'EOF'
#!/bin/sh
if [ "$TEST_IW" = hang ]; then exec /bin/sleep 60; fi
printf '\tsignal: -70.00 dBm\n\tSSID: far\n\tsignal: -40.00 dBm\n\tSSID: near\n'
EOF
chmod +x "$T/bin/iw"

fn=$(sed -n '/^SCAN_TIMEOUT=/p; /^scan_ssids() {/,/^}/p' "$HERE/wifi.sh")
scan() { # MODE: scan_ssids with the wpa backend (iw)
    TEST_IW=$1 PATH="$T/bin:$PATH" DEBSWAY_SCAN_TIMEOUT=1 bash -c "$fn"'
        BACKEND=wpa IF=wlan0; scan_ssids'
}

check "the scan is in a function wifi.sh has" test -n "$fn"
start=$(date +%s)
out=$(scan hang)
took=$(($(date +%s) - start))
check "a scan that never finishes is cut off (took ${took}s)" test "$took" -lt 10
check "...and gives no networks, so wifi.sh asks for the name" test -z "$out"
check "a scan that works lists the networks, strongest first" test "$(scan ok | paste -sd' ')" = "near far"
check "nmcli and iwctl scans have a time limit too" \
    bash -c 'grep -q "timeout \"\$SCAN_TIMEOUT\" nmcli" "$1" && grep -q "timeout \"\$SCAN_TIMEOUT\" iwctl station \"\$IF\" get-networks" "$1"' _ "$HERE/wifi.sh"

[ "$fails" -eq 0 ]
