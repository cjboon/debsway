#!/bin/bash
# Checks the policies.json that bin/ublock-allow writes for every Firefox
# (parts/firefox-hardening.sh): it is valid JSON, keeps uBlock's medium mode and
# the allowed sites, and sets no DNS (each Firefox sets its own at its start,
# tools/test-wifi-signin.sh checks that). Uses a
# temp folder for /etc/firefox-esr and Firefox's distribution folder, so it
# changes nothing. Run by test.sh, or:  bash tools/test-firefox-policy.sh
# shellcheck disable=SC2016  # the inner shells and Python expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
not() { ! "$@"; }
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}

export WREN_FIREFOX_ETC=$T/etc WREN_FIREFOX_DIST=$T/dist
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
check "no DNS in it: a locked policy would hold every Firefox, the Wi-Fi sign-in window too" not grep -q DNSOverHTTPS "$POLICY"
check "uBlock's medium mode is still set" \
    bash -c "grep -q '3p-script block' <<<\"\$1\"" _ "$(policy 3rdparty Extensions uBlock0@raymondhill.net adminSettings)"
check "DuckDuckGo is still the search engine" test "$(policy SearchEngines Default)" = '"DuckDuckGo"'
check "Firefox never offers to save a password (KeePassXC keeps them)" test "$(policy OfferToSaveLogins)" = false
check "...and makes none up, nor offers Relay addresses (every profile's defaults)" \
    bash -c 'grep -qx "pref(\"signon.rememberSignons\", false);" "$1" && grep -qx "pref(\"signon.generation.enabled\", false);" "$1" && grep -qx "pref(\"signon.firefoxRelay.feature\", \"disabled\");" "$1"' _ "$HERE/data/firefox-hardening.js"
check "without the bookmarks file: an empty bookmarks policy, still valid" test "$(policy ManagedBookmarks)" = '[]'
cp "$HERE/data/firefox-bookmarks.json" "$T/etc/wren-bookmarks.json"
allow --refresh
check "with it: the \"Learn (Wren Linux)\" folder, as data/firefox-bookmarks.json has it" python3 -I -c '
import json, sys
p = json.load(open(sys.argv[1]))["policies"]["ManagedBookmarks"]
assert p == json.load(open(sys.argv[2]))
assert p[0] == {"toplevel_name": "Learn (Wren Linux)"}
' "$POLICY" "$HERE/data/firefox-bookmarks.json"
check "...every bookmark a name and an https address, in a folder" python3 -I -c '
import json, re, sys
for folder in json.load(open(sys.argv[1]))[1:]:
    assert folder["name"] and folder["children"]
    for b in folder["children"]:
        assert b["name"] and re.fullmatch(r"https://[a-z0-9.-]+(/[^\s\"<>]*)?", b["url"]), b
' "$HERE/data/firefox-bookmarks.json"
check "...installed by the hardening, and taken out with it" \
    bash -c 'grep -q "install -m 0644 \"\$WREN_DIR/data/firefox-bookmarks.json\" \"\$ETC/wren-bookmarks.json\"" "$1" && grep -q "\"\$ETC/wren-bookmarks.json\" \"\$ALLOW\"" "$1"' _ "$HERE/parts/firefox-hardening.sh"

allow example.com >/dev/null
check "an allowed site lands in the policy" \
    bash -c "grep -q 'example.com \* 3p-script noop' <<<\"\$1\"" _ "$(policy 3rdparty Extensions uBlock0@raymondhill.net adminSettings)"

check "the sandboxed Firefox asks strict or fallback (default strict), explained, and saves it" python3 -I -c '
import sys; s = open(sys.argv[1]).read()
assert "choose dns \"Firefox\x27s own encrypted DNS?\" \"$dns\" strict fallback" in s and "dns=strict" in s
assert "  strict    always" in s and "  fallback  if encrypted DNS fails" in s and "\"dns=$dns\"" in s
assert s.index("\"dns=$dns\"") < s.index("ublock-allow --mode")
' "$HERE/extras/firefox-sandbox.sh"

# A policies.json someone else wrote is left alone
printf '{"policies": {}}\n' >"$POLICY"
rm -f "$T/dist/.wren-written"
check "someone else's policies.json is refused" bash -c "! bash '$HERE/bin/ublock-allow' --refresh"
check "and not changed" grep -qx '{"policies": {}}' "$POLICY"

# uBlock's mode, chosen at the sandboxed Firefox's install: standard or medium
# (from a clean folder: the check above left someone else's policies.json)
rm -rf "${T:?}/dist" "${T:?}/etc"
mkdir -p "$T/etc"
rules() { python3 -I -c 'import json,sys; p=json.load(open(sys.argv[1]))["policies"]["3rdparty"]["Extensions"]["uBlock0@raymondhill.net"]["adminSettings"]; print(json.loads(p)["dynamicFilteringString"])' "$POLICY"; }
rm -f "$T/etc/wren-ublock-mode"
allow --refresh
check "no mode chosen (Wren Linux before the choice): medium, other sites' scripts blocked" grep -qx '\* \* 3p-script block' <<<"$(rules)"
allow --mode standard >/dev/null
check "--mode standard: other sites' scripts and frames are no longer blocked" bash -c '! grep -q "3p-script block\|3p-frame block" <<<"$1"' _ "$(rules)"
check "...the filter lists still work (only the blocking rules go)" grep -q 'behind-the-scene \* \* noop' <<<"$(rules)"
check "...and --list says so" grep -qx 'uBlock Origin: standard mode' <<<"$(allow --list)"
allow example.org >/dev/null
check "...a site allowed then stays allowed (it counts once medium mode is back)" grep -qx 'example.org \* 3p-script noop' <<<"$(rules)"
allow --mode medium >/dev/null
check "--mode medium: blocked again, the allowed site still let through" bash -c 'grep -qx "\* \* 3p-script block" <<<"$1" && grep -qx "example.org \* 3p-script noop" <<<"$1"' _ "$(rules)"
check "a mode that isn't standard or medium is refused" bash -c '! "$@"' _ bash "$HERE/bin/ublock-allow" --mode loose
check "the sandboxed Firefox explains both modes and asks which (default medium), set after the hardening put ublock-allow in place" python3 -I -c '
import sys; s = open(sys.argv[1]).read()
q = "choose ublock \"Which way should uBlock Origin work?\" \"$ublock\" medium standard"
assert q in s and "ublock=medium" in s
assert "  medium    blocks ads" in s and "  standard  blocks ads" in s and "Wren Linux\x27s default" in s
assert s.index("parts/firefox-hardening.sh\"") < s.index("ublock-allow --mode \"$ublock\"")
assert s.index(q) < s.index("ublock-allow --mode \"$ublock\"")
' "$HERE/extras/firefox-sandbox.sh"

# choose (lib/core.sh): one of the options, by its first letter or whole word
# (the answer is the last line: a wrong one first prints a hint)
pick() { printf '%s\n' "$@" >"$T/answers"; WREN_TEST_ANSWERS="$T/answers" bash -c '. "$1/lib.sh"; choose v "Which?" standard standard medium; echo "$v"' _ "$HERE" 2>/dev/null | tail -1; }
check "choose: m is medium, a whole word too, Enter the default" \
    bash -c '[ "$1" = medium ] && [ "$2" = medium ] && [ "$3" = standard ]' _ "$(pick m)" "$(pick Medium)" "$(pick "")"
check "...something else asks again" test "$(pick x s)" = standard
check "...and with no answer at all, the default" test "$(pick)" = standard

[ "$fails" -eq 0 ]
