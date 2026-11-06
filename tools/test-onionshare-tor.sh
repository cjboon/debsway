#!/bin/bash
# Checks OnionShare through a webtunnel bridge: what bin/onionshare-tor does with a pretend tor
# and OnionShare, above all that nothing runs before tor is connected, and that a bridge that
# doesn't work ends in saying so, not in connecting another way. A real tor refusing to go around
# a dead bridge, and OnionShare through a real private tor, were tried by hand: docs/extras/onionshare.md.
# Run by test.sh, or:  bash tools/test-onionshare-tor.sh
# shellcheck disable=SC2016  # the pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d /tmp/ost.XXXX) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
H=$T/h
D=$H/.local/state/wren/onionshare-tor
mkdir -p "$D" "$H/.local/bin" "$T/bin" "$T/real"
cp "$HERE/bin/onionshare-tor" "$H/.local/bin/onionshare-tor"
ln -s onionshare-tor "$H/.local/bin/onionshare-cli"
ln -s onionshare-tor "$H/.local/bin/onionshare"
: >"$D/torrc"
# tor: writes how it was started, then does what $T/tor-does says, and waits to be stopped
cat >"$T/bin/tor" <<PRETEND
#!/bin/sh
echo "tor \$*" >>"$T/calls"
echo \$\$ >"$T/tor-pid"
case \$(cat "$T/tor-does") in
    connect) echo 'Bootstrapped 100% (done): Done' >>"$D/log" ;;
    die) exit 1 ;;
esac
trap 'echo "tor stopped" >>"$T/calls"; exit 0' TERM
while :; do /bin/sleep 0.1; done
PRETEND
# the real one: writes how it was started; REAL_DOES says what it does then
for p in onionshare onionshare-cli; do
    cat >"$T/real/$p" <<PRETEND
#!/bin/sh
echo "real $p \$*" >>"$T/calls"
grep -q "Bootstrapped 100" "$D/log" 2>/dev/null && echo "was connected" >>"$T/calls"
case \${REAL_DOES:-} in
    read) read -r line; echo "it read: \$line" >>"$T/calls" ;;
    stay)
        trap 'echo "real stopped" >>"$T/calls"; exit 0' TERM
        trap 'echo "real saw Ctrl+C" >>"$T/calls"; exit 0' INT
        echo \$\$ >"$T/real-pid"
        while :; do /bin/sleep 0.1; done ;;
esac
exit \${REAL_RC:-0}
PRETEND
done
printf '#!/bin/sh\n' >"$T/bin/notify-send"
chmod +x "$T/bin/"* "$T/real/"*
run() { # WHAT-TOR-DOES COMMAND ARGS...
    echo "$1" >"$T/tor-does"; shift
    : >"$T/calls"
    local c=$1; shift
    HOME=$H PATH="$T/bin:$PATH" WREN_ONIONSHARE_REAL=$T/real WREN_ONIONSHARE_WAIT=${WAIT:-20} WREN_ONIONSHARE_POLL=0.1 sh "$H/.local/bin/$c" "$@"
}

out=$(run connect onionshare-cli report.pdf 2>&1); rc=$?
check "it starts tor, waits until connected, then runs the real one, with your arguments" bash -c '
    grep -q "^tor " "$1" && grep -qx "real onionshare-cli report.pdf" "$1" && grep -qx "was connected" "$1"' _ "$T/calls"
check "...tor with this torrc and nothing else: no defaults" grep -q "^tor --defaults-torrc /dev/null -f $D/torrc " "$T/calls"
check "...tor ends if this is killed (its owning process)" grep -q -- '--__OwningControllerProcess [0-9]' "$T/calls"
check "...and tor is stopped when OnionShare ends" grep -qx 'tor stopped' "$T/calls"
check "...its log, which can name the bridge, goes too" test ! -e "$D/log"
check "...it ends well, and said it was connecting" bash -c '[ "$1" = 0 ] && grep -q "through your webtunnel bridge" <<<"$2"' _ "$rc" "$out"
run connect onionshare >/dev/null 2>&1
check "the graphical app the same way" grep -qx 'real onionshare ' "$T/calls"
REAL_RC=3 run connect onionshare-cli x >/dev/null 2>&1; rc=$?
check "OnionShare's own result comes through" test "$rc" = 3

out=$(WAIT=1 run hang onionshare-cli secret.pdf 2>&1); rc=$?
check "the bridge doesn't connect: OnionShare never runs" not grep -q '^real ' "$T/calls"
check "...it fails, and says nothing connected any other way" bash -c '[ "$1" -ne 0 ] && grep -q "nothing connected any other way" <<<"$2" && grep -q "Nothing was shared" <<<"$2"' _ "$rc" "$out"
check "...and its tor is stopped" grep -qx 'tor stopped' "$T/calls"
out=$(run die onionshare-cli secret.pdf 2>&1); rc=$?
check "tor won't start: it fails, and OnionShare never runs" bash -c '[ "$1" -ne 0 ] && ! grep -q "^real " "$2" && grep -q "stopped before it connected" <<<"$3"' _ "$rc" "$T/calls" "$out"

out=$(run connect onionshare-cli --help 2>&1)
check "--help: no tor for that" bash -c '! grep -q "^tor " "$1" && grep -qx "real onionshare-cli --help" "$1"' _ "$T/calls"

echo hang >"$T/tor-does"
HOME=$H PATH="$T/bin:$PATH" WREN_ONIONSHARE_REAL=$T/real WREN_ONIONSHARE_WAIT=8 WREN_ONIONSHARE_POLL=0.1 sh "$H/.local/bin/onionshare-cli" a >/dev/null 2>&1 &
first=$!
i=0; while [ "$i" -lt 50 ] && [ ! -s "$T/tor-pid" ]; do /bin/sleep 0.1; i=$((i + 1)); done
: >"$T/calls2"
out=$(HOME=$H PATH="$T/bin:$PATH" WREN_ONIONSHARE_REAL=$T/real sh "$H/.local/bin/onionshare-cli" b 2>&1); rc=$?
check "one at a time: a second is refused, and says why" bash -c '[ "$1" -ne 0 ] && grep -q "running already" <<<"$2"' _ "$rc" "$out"
kill "$first" 2>/dev/null; wait "$first" 2>/dev/null
i=0; while [ "$i" -lt 50 ] && ! grep -qx 'tor stopped' "$T/calls"; do /bin/sleep 0.1; i=$((i + 1)); done
check "...killed while connecting: its tor stops too" grep -qx 'tor stopped' "$T/calls"

out=$(echo typed | REAL_DOES='read' run connect onionshare-cli x 2>&1)
check "what you type reaches OnionShare" grep -qx 'it read: typed' "$T/calls"

# sharing_started: the wrapper running, in its own group (as a terminal has it), and sharing
sharing_started() {
    rm -f "$T/real-pid"
    echo connect >"$T/tor-does"
    : >"$T/calls"
    REAL_DOES=stay HOME=$H PATH="$T/bin:$PATH" WREN_ONIONSHARE_REAL=$T/real WREN_ONIONSHARE_POLL=0.1 \
        env --default-signal=INT setsid sh "$H/.local/bin/onionshare-cli" a >/dev/null 2>&1 &
    wrapper=$!
    i=0; while [ "$i" -lt 100 ] && [ ! -s "$T/real-pid" ]; do /bin/sleep 0.1; i=$((i + 1)); done
}
# gone_soon PID: it ended, or it is stopped by force so the test goes on
gone_soon() {
    local i=0
    while [ "$i" -lt 50 ] && kill -0 "$1" 2>/dev/null; do /bin/sleep 0.1; i=$((i + 1)); done
    if kill -0 "$1" 2>/dev/null; then kill -9 "$1" 2>/dev/null; return 1; fi
}
sharing_started
kill "$wrapper" 2>/dev/null
check "killed while sharing: the share ends, it doesn't stay online" gone_soon "$(cat "$T/real-pid")"
check "...told to stop" grep -qx 'real stopped' "$T/calls"
gone_soon "$wrapper"; wait "$wrapper" 2>/dev/null
check "...and its tor is stopped" grep -qx 'tor stopped' "$T/calls"
sharing_started
kill -INT -- "-$wrapper" 2>/dev/null
check "Ctrl+C while sharing: OnionShare gets it, and ends" gone_soon "$(cat "$T/real-pid")"
check "...in its own way" grep -qx 'real saw Ctrl+C' "$T/calls"
gone_soon "$wrapper"; wait "$wrapper" 2>/dev/null
check "...and its tor is stopped" grep -qx 'tor stopped' "$T/calls"

rm -f "$D/torrc"
out=$(run connect onionshare-cli x 2>&1); rc=$?
check "no private tor set up: it says what to do, and OnionShare never runs" bash -c '[ "$1" -ne 0 ] && grep -q "wrenctl install onionshare" <<<"$2" && ! grep -q "^real " "$3"' _ "$rc" "$out" "$T/calls"
: >"$D/torrc"
check "run under another name: refused" bash -c 'HOME=$1 sh "$2"; [ $? = 2 ]' _ "$H" "$H/.local/bin/onionshare-tor"

# What extras/onionshare.sh writes, with the real tor reading it where there is one
X=$HERE/extras/onionshare.sh
check "webtunnel: lyrebird from the Tor Project's pinned repository, before the install" bash -c '
    grep -q "add_torproject_repo" "$1" && grep -q "pkgs+=(lyrebird)" "$1"' _ "$X"
(
    set +e
    . "$HERE/lib.sh"
    set +e +u +o pipefail
    # shellcheck disable=SC2317,SC2329  # what the install would call
    apt_install() { :; }
    PRIVATE_TOR=$T/w/state
    BIN=$T/w/bin
    mkdir -p "$BIN"
    BRIDGE_TYPE=webtunnel
    BRIDGES=("webtunnel [2001:db8::1]:443 0123456789ABCDEF0123456789ABCDEF01234567 url=https://example.invalid/x ver=0.0.1")
    eval "$(sed -n '/^private_tor_off() {/,/^}/p; /^private_tor_on() {/,/^}/p' "$X")"
    # shellcheck disable=SC2317,SC2329  # what private_tor_on calls
    tor() { if command -v /usr/bin/tor >/dev/null; then /usr/bin/tor "$@"; else :; fi; }
    private_tor_on >/dev/null 2>&1
    echo "on=$?" >"$T/w.out"
    { stat -c 'dir=%a' "$PRIVATE_TOR"; stat -c 'torrc=%a' "$PRIVATE_TOR/torrc"; readlink "$BIN/onionshare-cli"; readlink "$BIN/onionshare"; cat "$PRIVATE_TOR/torrc"; } >>"$T/w.out"
    private_tor_off >/dev/null 2>&1
    { [ -e "$PRIVATE_TOR" ] && echo "state left"; [ -e "$BIN/onionshare" ] && echo "link left"; [ -e "$BIN/onionshare-tor" ] && echo "command left"; } >"$T/w.off"
) >/dev/null 2>&1
check "the private tor: tor accepts its settings" grep -qx 'on=0' "$T/w.out"
check "...its folder and settings are yours alone (bridge lines are private)" bash -c 'grep -qx "dir=700" "$1" && grep -qx "torrc=600" "$1"' _ "$T/w.out"
for l in 'UseBridges 1' 'SocksPort 0' 'ClientTransportPlugin webtunnel exec /usr/bin/lyrebird'; do
    check "...$l" grep -qx "$l" "$T/w.out"
done
check "...your bridge line" grep -q '^Bridge webtunnel \[2001:db8::1\]:443' "$T/w.out"
check "...no port of its own to control it" not grep -q '^ControlPort' "$T/w.out"
check "...both commands lead to it" test "$(grep -c '^onionshare-tor$' "$T/w.out")" = 2
check "another bridge chosen, or removed: the private tor, its bridge lines and the links go" test ! -s "$T/w.off"
check "...and --remove does that" bash -c 'sed -n "/= --remove \]; then/,/^fi/p" "$1" | grep -q "private_tor_off"' _ "$X"
check "the settings: the private socket, and no way to OnionShare's own tor" bash -c '
    sed -n "/kind == \"webtunnel\"/,/elif/p" "$1" | grep -q "socket_file" && sed -n "/kind == \"webtunnel\"/,/elif/p" "$1" | grep -q "no_auth"' _ "$X"
check "...written after the private tor is in place" bash -c '
    a=$(grep -n "then private_tor_on; else private_tor_off" "$1" | cut -d: -f1); b=$(grep -n "connection_type\"\] = \"socket_file\"" "$1" | cut -d: -f1); [ "$a" -lt "$b" ]' _ "$X"

[ "$fails" -eq 0 ]
