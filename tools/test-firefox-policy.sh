#!/bin/bash
# Checks the policies.json that bin/ublock-allow writes for every Firefox
# (parts/firefox-hardening.sh): it is valid JSON, keeps uBlock's medium mode and
# the allowed sites, and turns Firefox's own DNS-over-HTTPS off for good. Uses a
# temp folder for /etc/firefox-esr and Firefox's distribution folder, so it
# changes nothing. Run by test.sh, or:  bash tools/test-firefox-policy.sh
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}

export DEBSWAY_FIREFOX_ETC=$T/etc DEBSWAY_FIREFOX_DIST=$T/dist
mkdir -p "$T/etc"
POLICY=$T/dist/policies.json
allow() { bash "$HERE/bin/ublock-allow" "$@"; }

# policy KEY...: the value at that path in policies.json, as JSON
policy() {
    python3 -I - "$POLICY" "$@" <<'PY'
import json, sys
v = json.load(open(sys.argv[1]))["policies"]
for k in sys.argv[2:]:
    v = v[k]
print(json.dumps(v, sort_keys=True))
PY
}

allow --refresh
check "it writes a policies.json" test -s "$POLICY"
if ! command -v python3 >/dev/null; then
    echo "  skip  python3 isn't installed, so the JSON can't be read"
    [ "$fails" -eq 0 ]
    exit
fi
check "the file is valid JSON" python3 -I -m json.tool "$POLICY"
check "Firefox's own DNS-over-HTTPS is off" test "$(policy DNSOverHTTPS Enabled)" = false
check "and locked, so a profile can't turn it back on" test "$(policy DNSOverHTTPS Locked)" = true
check "uBlock's medium mode is still set" \
    bash -c "grep -q '3p-script block' <<<\"\$1\"" _ "$(policy 3rdparty Extensions uBlock0@raymondhill.net adminSettings)"
check "DuckDuckGo is still the search engine" test "$(policy SearchEngines Default)" = '"DuckDuckGo"'

allow example.com >/dev/null
check "an allowed site lands in the policy" \
    bash -c "grep -q 'example.com \* 3p-script noop' <<<\"\$1\"" _ "$(policy 3rdparty Extensions uBlock0@raymondhill.net adminSettings)"
check "and the DNS setting stays" test "$(policy DNSOverHTTPS Enabled)" = false

# A policies.json someone else wrote is left alone
printf '{"policies": {}}\n' >"$POLICY"
rm -f "$T/dist/.debsway-written"
check "someone else's policies.json is refused" bash -c "! bash '$HERE/bin/ublock-allow' --refresh"
check "and not changed" grep -qx '{"policies": {}}' "$POLICY"

[ "$fails" -eq 0 ]
