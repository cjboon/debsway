#!/bin/bash
# Checks lib/tor.sh, the bridge chooser every Tor-related script uses
# (Tor Browser, Whonix, OnionShare, apt over Tor), with scripted answers
# instead of a keyboard. Changes nothing. Run by test.sh, or:
#   bash tools/test-bridges.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
set +e +o pipefail

T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}

OBFS4='obfs4 192.0.2.1:443 0123456789ABCDEF0123456789ABCDEF01234567 cert=AAAA iat-mode=0'
WEBT='webtunnel [2001:db8::1]:443 0123456789ABCDEF0123456789ABCDEF01234567 url=https://example.com/abc ver=0.0.1'

# run CONTEXT ANSWER...: what pick_bridges prints, then its result on the last line
run() {
    local context=$1
    shift
    printf '%s\n' "$@" >"$T/answers"
    (
        # shellcheck disable=SC2030
        export WREN_TEST_ANSWERS=$T/answers
        pick_bridges "$context"
        echo "RESULT $BRIDGE_TYPE ${#BRIDGES[@]} $BRIDGE_WANTED"
    ) 2>&1
}
result() { tail -1 <<<"$1"; }
has() { grep -q -- "$1" <<<"$2"; }
lacks() { ! grep -q -- "$1" <<<"$2"; }

echo "Asking first"
out=$(run tor-browser n)
check "no bridge needed: nothing else is asked" test "$(result "$out")" = "RESULT none 0 false"
check "the question is asked before any kind is shown" lacks 'Kinds of bridge' "$out"

echo "What each place offers"
out=$(run tor-browser y 1)
check "Tor Browser offers built-in obfs4" has 'own public list' "$out"
check "Tor Browser offers webtunnel" has 'webtunnel, bridge lines' "$out"
check "Tor Browser offers Snowflake" has 'Snowflake: no lines' "$out"
check "Tor Browser offers meek" has 'meek (Azure)' "$out"
check "choice 1 is built-in obfs4" test "$(result "$out")" = "RESULT obfs4-builtin 0 true"
out=$(run whonix y 2)
check "Whonix offers obfs4 lines" has 'obfs4, bridge lines' "$out"
check "Whonix offers Snowflake" has 'Snowflake: no lines' "$out"
check "Whonix offers webtunnel too (its lyrebird copied into the Gateway)" has 'webtunnel, bridge lines' "$out"
check "...and says why meek isn't offered" has 'Not offered here (meek: not offered for the Whonix Gateway' "$out"
check "choice 2 is Snowflake" test "$(result "$out")" = "RESULT snowflake 0 true"
out=$(run system-tor y 1 "$OBFS4" "")
check "the system Tor offers webtunnel (lyrebird)" has 'webtunnel, bridge lines' "$out"
check "...and says why meek is missing" has 'Not offered here (meek' "$out"
out=$(run system-tor y 2 "$WEBT" "$OBFS4" "")
check "the system Tor, choice 2: webtunnel, the webtunnel line kept" test "$(result "$out")" = "RESULT webtunnel 1 true"
out=$(run system-tor y 3)
check "...choice 3: Snowflake" test "$(result "$out")" = "RESULT snowflake 0 true"
out=$(run onionshare y 1)
check "OnionShare offers built-in obfs4" has 'own public list' "$out"
check "OnionShare offers Snowflake" has 'Snowflake: no lines' "$out"
check "OnionShare offers webtunnel (in a private tor)" has 'webtunnel, bridge lines' "$out"
check "...and says why meek is missing" has 'Not offered here (meek' "$out"
out=$(run onionshare y 4 "$WEBT" "")
check "...choice 4: webtunnel, with its line" test "$(result "$out")" = "RESULT webtunnel 1 true"

echo "Getting bridge lines"
out=$(run system-tor y 1 "$OBFS4" "Bridge $OBFS4" "not a bridge" "")
check "obfs4: both good lines are kept, the bad one skipped" test "$(result "$out")" = "RESULT obfs4 2 true"
check "obfs4: explains the website" has 'bridges.torproject.org/options' "$out"
check "obfs4: explains email" has 'bridges@torproject.org' "$out"
check "obfs4: explains Telegram" has '@GetBridgesBot' "$out"
out=$(run tor-browser y 3 "$WEBT" "$OBFS4" "")
check "webtunnel: the webtunnel line is kept, an obfs4 line is not" test "$(result "$out")" = "RESULT webtunnel 1 true"
check "webtunnel: explains the website" has 'choose webtunnel' "$out"
check "webtunnel: explains email" has 'get transport webtunnel' "$out"
out=$(run tor-browser y 3 "")
check "wanted but no lines: no bridge, and it remembers they wanted one" test "$(result "$out")" = "RESULT none 0 true"
out=$(run tor-browser y "" )
check "Enter at the menu: no bridge" test "$(result "$out")" = "RESULT none 0 true"
out=$(run tor-browser y 9 x 4)
check "a wrong choice asks again" test "$(result "$out")" = "RESULT snowflake 0 true"

echo "torrc lines"
conf=$(
    # shellcheck disable=SC2031
    export WREN_TEST_ANSWERS=$T/a
    printf '%s\n' y 1 "$OBFS4" "" >"$T/a"
    pick_bridges system-tor >/dev/null 2>&1
    tor_bridge_config
)
check "obfs4: the plugin line" has '^ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy' "$conf"
check "obfs4: the bridge line" has '^Bridge obfs4 192.0.2.1' "$conf"
check "obfs4: UseBridges" has '^UseBridges 1' "$conf"
check "obfs4 needs obfs4proxy" test "$(BRIDGE_TYPE=obfs4 bridge_packages)" = obfs4proxy
conf=$(BRIDGE_TYPE=webtunnel; BRIDGES=("$WEBT"); tor_bridge_config)
check "webtunnel: lyrebird runs it (the program Debian's AppArmor profile for tor allows)" has '^ClientTransportPlugin webtunnel exec /usr/bin/lyrebird$' "$conf"
# shellcheck disable=SC2016  # the inner shell expands them
check "webtunnel: the bridge line and UseBridges" bash -c 'grep -qxF "Bridge $2" <<<"$1" && grep -qx "UseBridges 1" <<<"$1"' _ "$conf" "$WEBT"
check "webtunnel needs lyrebird" test "$(BRIDGE_TYPE=webtunnel bridge_packages)" = lyrebird
check "...which Debian's AppArmor profile for tor lets it run" \
    bash -c '[ ! -e /etc/apparmor.d/abstractions/tor ] || grep -qx "  /usr/bin/lyrebird Pix," /etc/apparmor.d/abstractions/tor'
conf=$(BRIDGE_TYPE=snowflake tor_bridge_config)
check "Snowflake: both bridges" test "$(grep -c '^Bridge snowflake ' <<<"$conf")" = 2
check "Snowflake: the plugin line" has '^ClientTransportPlugin snowflake exec /usr/bin/snowflake-client' "$conf"
check "Snowflake lines use front=, which Debian's client knows" lacks 'fronts=' "$(grep -v '^#' "$WREN_DIR/data/snowflake-bridges.txt")"
check "built-in kinds write nothing to torrc" test -z "$(BRIDGE_TYPE=obfs4-builtin tor_bridge_config)"

[ "$fails" -eq 0 ]
