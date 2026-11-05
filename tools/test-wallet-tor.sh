#!/bin/bash
# Checks lib/wallet-tor.sh, the Tor offered to Feather, Sparrow and Electrum
# when they are installed: the network keys are merged into the wallet's own
# settings file and nothing else in it changes, only before the wallet's first
# run, and what each installer writes. Changes nothing outside a temp folder.
# Run by test.sh, or:  bash tools/test-wallet-tor.sh
# shellcheck disable=SC2016  # the inner bash expands its own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh"
. "$HERE/lib/wallet-tor.sh"
set +e +o pipefail

T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
key() { python3 -I -c 'import json, sys; print(json.dumps(json.load(open(sys.argv[1])).get(sys.argv[2])))' "$1" "$2"; }
export -f key

# ---- merging into a settings file ----
F=$T/a/settings.json
wallet_json_set "$F" '{"proxy": 1, "torPrivacyLevel": 2}'
check "a settings file that isn't there is made, with the keys" bash -c '[ "$(key "$1" proxy)" = 1 ] && [ "$(key "$1" torPrivacyLevel)" = 2 ]' _ "$F"
check "...only you can read it" test "$(stat -c %a "$F")" = 600
printf '{"preferredFiatCurrency": "EUR", "torPrivacyLevel": 1}\n' >"$F"
wallet_json_set "$F" '{"torPrivacyLevel": 2}'
check "a file there already keeps everything else in it" bash -c '[ "$(key "$1" preferredFiatCurrency)" = "\"EUR\"" ] && [ "$(key "$1" torPrivacyLevel)" = 2 ]' _ "$F"
echo '[1, 2]' >"$F"
check "a file that isn't a JSON object is left alone, and it says so" bash -c '! wallet_json_set "$1" "{\"x\": 1}" && [ "$(cat "$1")" = "[1, 2]" ]' _ "$F"

# ---- asked only before the first run ----
offer() { # ANSWER FILE: wallet_offer_tor for a pretend wallet, answering ANSWER
    printf '%s\n' "$1" >"$T/answers"
    WREN_TEST_ANSWERS=$T/answers wallet_offer_tor Pretend no-such-program-here "$2" '{"tor": true}' "what" "where in Pretend" 2>&1
}
G=$T/fresh/settings.json
out=$(offer y "$G")
check "before the first run: asked, and yes writes the setting" bash -c 'grep -q "Send Pretend through Tor" <<<"$1" && [ "$(key "$2" tor)" = true ]' _ "$out" "$G"
H=$T/fresh2/settings.json
out=$(offer n "$H")
check "...no leaves no settings file, and says where it is" bash -c '[ ! -e "$2" ] && grep -q "Later: where in Pretend" <<<"$1"' _ "$out" "$H"
printf '{"tor": false}\n' >"$G"
out=$(offer y "$G")
check "once the wallet has settings of its own: not asked, not changed, only told where" \
    bash -c '! grep -q "Send Pretend" <<<"$1" && [ "$(key "$2" tor)" = false ] && grep -q "where in Pretend" <<<"$1"' _ "$out" "$G"
out=$(printf 'y\n' >"$T/answers"; WREN_TEST_ANSWERS=$T/answers wallet_offer_tor Pretend bash "$T/run/settings.json" '{"tor": true}' what where 2>&1)
check "...nor while it runs (it would write over the setting when it closes)" bash -c '[ ! -e "$1" ]' _ "$T/run/settings.json"

# ---- what each installer writes ----
check "Feather: everything over its own Tor (proxy 1 = Tor, torPrivacyLevel 2 = all), in ~/.config/feather/settings.json" \
    bash -c 'grep -q "^wallet_offer_tor Feather feather \"\${XDG_CONFIG_HOME:-\$HOME/.config}/feather/settings.json\"" "$1" && grep -qF "'"'"'{\"proxy\": 1, \"torPrivacyLevel\": 2}'"'"'" "$1"' _ "$HERE/extras/feather-wallet.sh"
check "Sparrow: this computer's Tor as its proxy, offered only when that Tor runs" \
    bash -c 'grep -A2 "^if system_tor_runs; then" "$1" | grep -q "wallet_offer_tor Sparrow Sparrow \"\$HOME/.sparrow/config\"" && grep -qF "useProxy\\\": true, \\\"proxyServer" "$1"' _ "$HERE/extras/sparrow-wallet.sh"
check "Electrum: this computer's Tor as its proxy (socks5), config_version 3, offered only when that Tor runs" \
    bash -c 'grep -A2 "^if system_tor_runs; then" "$1" | grep -q "wallet_offer_tor Electrum electrum \"\$HOME/.electrum/config\"" && grep -qF "config_version\\\": 3, \\\"proxy\\\": \\\"socks5:" "$1"' _ "$HERE/extras/electrum.sh"
check "the Tor port is the system tor service's SOCKS port" test "$WALLET_TOR_SOCKS" = 127.0.0.1:9050

[ "$fails" -eq 0 ]
