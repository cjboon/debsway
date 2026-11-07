#!/bin/bash
# Checks the sandboxes of Tor Browser and Mullvad Browser (lib/browser-sandbox.sh, bin/browser-sandbox,
# bin/browser-session, data/{tor,mullvad}-browser-firewall.nft): the firewall for real, with nft in a
# network namespace; what the session accepts from the user who calls it; the clipboard's check;
# what the installer takes from a file a hacked browser can write. The rest of what they do is with
# a pretend sudo. Nothing outside temp folders changes. Run by test.sh, or:
#   bash tools/test-browser-sandbox.sh
# shellcheck disable=SC2016  # the inner shells and pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
FW=$HERE/data/tor-browser-firewall.nft
SESSION=$HERE/bin/browser-session
CMD=$HERE/bin/browser-sandbox

# ---- the firewall, for real: root in a network namespace stands in for tor-browser
NS_PATH=/usr/sbin:/sbin:/usr/bin:/bin
cat >"$T/in-ns.sh" <<'EOF'
ip link set lo up && ip link add d0 type dummy && ip link set d0 up &&
ip addr add 192.168.5.2/24 dev d0 && ip route add default dev d0 || exit 9
nft -f "$1" || exit 8
shift
"$@"
EOF
# connect.py LISTEN-PORT CONNECT-HOST CONNECT-PORT: a listener of this user, if a port is given, and
# a connection to it: says what it got back
cat >"$T/connect.py" <<'EOF'
import errno, socket, sys
port, host, to = int(sys.argv[1]), sys.argv[2], int(sys.argv[3])
if port:
    srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", port)); srv.listen()
c = socket.socket(); c.settimeout(1)
try:
    c.connect((host, to))
    print("connected")
except socket.timeout:
    print("no answer")
except OSError as e:
    print(errno.errorcode.get(e.errno, e.errno))
EOF
ns() { local f=$1; shift; PATH=$NS_PATH unshare -rn bash "$T/in-ns.sh" "$f" "$@"; }
# (0 is the user here. "other": a rule for which this listener isn't the sandbox's user)
sed -E 's/meta skuid "tor-browser" jump/meta skuid 0 jump/; s/meta skuid != "tor-browser"/meta skuid != 0/' "$FW" >"$T/own.nft"
sed -E 's/meta skuid "tor-browser" jump/meta skuid 0 jump/; s/meta skuid != "tor-browser"/meta skuid != 12345/' "$FW" >"$T/other.nft"
if PATH=$NS_PATH command -v nft >/dev/null && unshare -rn true 2>/dev/null && ns "$T/own.nft" true 2>/dev/null; then
    say() { ns "$1" python3 -I "$T/connect.py" "$2" "$3" "$4"; }
    check "its Tor's own port: it reaches itself" test "$(say "$T/own.nft" 9150 127.0.0.1 9150)" = connected
    check "...and a bridge's program, on a port the system picked" test "$(say "$T/own.nft" 40000 127.0.0.1 40000)" = connected
    check "a listener that isn't this user, on such a port: nothing connects" test "$(say "$T/other.nft" 40000 127.0.0.1 40000)" = "no answer"
    check "...nor on Tor's port" test "$(say "$T/other.nft" 9150 127.0.0.1 9150)" = "no answer"
    check "a low port here, even of its own: no route, how the shared check sees the rule" test "$(say "$T/own.nft" 80 127.0.0.1 80)" = EHOSTUNREACH
    check "port 9 (the check itself): no route" test "$(say "$T/own.nft" 0 127.0.0.1 9)" = EHOSTUNREACH
    check "this computer's other loopback addresses: no route" test "$(say "$T/own.nft" 0 127.0.0.2 40000)" = EHOSTUNREACH
    check "this computer's own network address: no route" test "$(say "$T/own.nft" 0 192.168.5.2 40000)" = EHOSTUNREACH
    check "the shared check passes with this rule" ns "$T/own.nft" bash "$HERE/bin/sandbox-net-check"
    sed -E 's/meta skuid "mullvad-browser"/meta skuid 0/' "$HERE/data/mullvad-browser-firewall.nft" >"$T/mullvad.nft"
    check "Mullvad's: nothing on this computer, not even a listener of its own" test "$(say "$T/mullvad.nft" 40000 127.0.0.1 40000)" = EHOSTUNREACH
    check "...and the shared check passes with it" ns "$T/mullvad.nft" bash "$HERE/bin/sandbox-net-check"
else
    echo "  ok    skipped the checks in a network namespace: no nft, no user namespaces, or no conntrack here"
fi
check "the rule for a new connection comes after none that would let it out unmarked" bash -c '
    ! grep -qE "^[[:space:]]*ip saddr 127.0.0.1 tcp sport" "$1"' _ "$FW"
check "answers are only that: a reply's direction" grep -q 'ct direction reply ip saddr 127.0.0.1 tcp sport' "$FW"
check "no answers to just anyone, in either" bash -c '! grep -qE "^[^#]*(established|related)" "$1" "$2"' _ "$FW" "$HERE/data/mullvad-browser-firewall.nft"
check "the firewall says plainly it doesn't force anything through Tor" grep -q "doesn't force anything through Tor" "$FW"

# ---- what the session accepts: run under a name, with a pretend wrapper and check
mkdir -p "$T/bin" "$T/shm"
printf '#!/bin/sh\necho "%s"\n' tor-browser >"$T/bin/id"
sed -e "s|^export PATH=.*|export PATH=$T/bin:/usr/bin:/bin|" \
    -e "s|^noabs=.*|noabs=$T/noabs|" -e "s|^netcheck=.*|netcheck=$T/netcheck|" "$SESSION" >"$T/session"
grep -q "$T/noabs" "$T/session" || { echo "  FAIL  the session's lines weren't found"; exit 1; }
# (it goes on past the wrapper only if told it is already inside it)
printf '#!/bin/sh\necho "wrapper $*" >>"%s/calls"\n' "$T" >"$T/noabs"
printf '#!/bin/sh\n[ -z "$1" ] || exit 0\n[ ! -e "%s/no-rule" ]\n' "$T" >"$T/netcheck"
cat >"$T/bin/getent" <<'EOF'
#!/bin/sh
echo "tor-browser:x:999:999::/home/tor-browser:/usr/sbin/nologin"
EOF
chmod +x "$T/bin/id" "$T/noabs" "$T/netcheck" "$T/bin/getent"
sess() { WREN_BROWSER_WRAPPED=1 bash "$T/session" "$@" 2>&1; }
printf '#!/bin/sh\necho someone\n' >"$T/bin/id"
check "a user that isn't one of the two: refused" grep -q 'this runs as the user' <<<"$(sess start)"
printf '#!/bin/sh\necho tor-browser\n' >"$T/bin/id"
: >"$T/calls"
env -u WREN_BROWSER_WRAPPED bash "$T/session" start x y z >/dev/null 2>&1
check "unwrapped, it goes through the wrapper first, with Tor Browser's --userns" grep -q -- 'wrapper --userns' "$T/calls"
printf '#!/bin/sh\necho mullvad-browser\n' >"$T/bin/id"
sed -i 's/^tor-browser:/mullvad-browser:/; s/tor-browser/mullvad-browser/g' "$T/bin/getent"
: >"$T/calls"
env -u WREN_BROWSER_WRAPPED bash "$T/session" start x y z >/dev/null 2>&1
check "...and Mullvad's without it (no_new_privs does no harm there)" bash -c '! grep -q -- --userns "$1" && grep -q wrapper "$1"' _ "$T/calls"
printf '#!/bin/sh\necho tor-browser\n' >"$T/bin/id"
sed -i 's/mullvad-browser/tor-browser/g' "$T/bin/getent"
: >"$T/no-rule"
check "no firewall: not started, and it says how to put it back" grep -q 'systemctl restart wren-tor-browser-firewall' <<<"$(sess start a b c)"
rm "$T/no-rule"
check "a socket folder that isn't one made for it: refused" grep -q 'unexpected socket folder' <<<"$(sess start /home/you/x wl -)"
check "...another browser's: refused" grep -q 'unexpected socket folder' <<<"$(sess start /dev/shm/wren-mullvad-browser.abc wl -)"
check "...with a way out of the folder: refused" grep -q 'unexpected socket folder' <<<"$(sess start '/dev/shm/wren-tor-browser.a/../../x' wl -)"
check "too few arguments: refused" grep -q usage <<<"$(sess start)"
check "an unknown command: refused" grep -q usage <<<"$(sess rm-everything)"
check "no command: refused" grep -q usage <<<"$(sess)"

# ---- the command
fake_home=$T/h
mkdir -p "$fake_home/.local/bin" "$T/rt" "$T/cmd"
ln -s "$CMD" "$T/cmd/tor-browser"
ln -s "$CMD" "$T/cmd/browser-sandbox"
run_cmd() { HOME=$fake_home XDG_RUNTIME_DIR=$T/rt WAYLAND_DISPLAY=wl bash "$T/cmd/$1" "${@:2}" 2>&1; }
check "only web addresses open: a file isn't" grep -q 'only http://' <<<"$(run_cmd tor-browser file:///etc/passwd)"
check "...nor an option in disguise" grep -q 'only http://' <<<"$(run_cmd tor-browser --new-instance)"
check "...nor an address with a space in it" grep -q 'only http://' <<<"$(run_cmd tor-browser 'http://a b')"
check "a Wayland name with a folder in it: refused" grep -q 'plain name' <<<"$(HOME=$fake_home XDG_RUNTIME_DIR=$T/rt WAYLAND_DISPLAY=a/b bash "$T/cmd/tor-browser" 2>&1)"
check "the shared folder is new for each start, and passage is to it alone" bash -c '
    grep -q "mktemp -d \"\$SHARE_ROOT/wren-\$name\." "$1" && grep -q "setfacl -m \"u:\$name:--x\" \"\$share\"" "$1" && ! grep -qE "setfacl.*(\\\$rt|\\\$HOME)" "$1"' _ "$CMD"
check "any other name of it: only the clipboard" grep -q usage <<<"$(run_cmd browser-sandbox whatever)"

# clip_ok: one line of plain text, of a limited length
eval "$(sed -n '/^CLIP_MAX=/p; /^clip_ok() {/,/^}/p' "$CMD")"
check "the clipboard takes an address" clip_ok 'bc1qar0srrr7xfkvy5l643lydnw9re59gtzzwf5mdq'
check "...spaces and punctuation too" clip_ok 'one two: https://example.org/?a=1&b=2'
check "...but no line break" not clip_ok $'one\ntwo'
check "...no escape sequence" not clip_ok $'a\e[2Jb'
check "...no carriage return" not clip_ok $'pay here\rpay there'
check "...no look-alike letters" not clip_ok 'gооgle.com'
check "...no right-to-left mark" not clip_ok $'abc\u202edef'
check "...nothing longer than its limit" not clip_ok "$(head -c 4097 /dev/zero | tr '\0' a)"
check "...up to its limit" clip_ok "$(head -c 4096 /dev/zero | tr '\0' a)"
check "...and nothing at all isn't text" not clip_ok ''
check "it is checked before it is shown, from both sides" bash -c '
    sed -n "/^clip() {/,/^}/p" "$1" | grep -n . | grep -E "clip_ok|Into %s:|Out of %s:" | head -1 | grep -q clip_ok' _ "$CMD"

# ---- the installer: what comes from a file a hacked browser can write
eval "$(sed -n '/^JS_BEGIN=/p; /^JS_END=/p; /^current_bridges() {/,/^}/p; /^current_builtin() {/,/^}/p' "$HERE/extras/tor-browser.sh")"
our_block() { cat "$T/block"; }
printf '%s\n' 'user_pref("torbrowser.settings.bridges.bridge_strings.0", "obfs4 1.2.3.4:443 ABC cert=x iat-mode=0");' \
    'user_pref("torbrowser.settings.bridges.bridge_strings.1", "webtunnel 1.2.3.4:443 ABC url=https://a.example/x");' \
    "user_pref(\"torbrowser.settings.bridges.bridge_strings.2\", \"obfs4 $(printf '\033')[2J hello\");" \
    'user_pref("torbrowser.settings.bridges.bridge_strings.3", "something else");' \
    'user_pref("torbrowser.settings.bridges.bridge_strings.4", "obfs4 x\"); evil(\"");' >"$T/block"
kept=$(current_bridges)
check "bridge lines from last time: good ones are kept" test "$(wc -l <<<"$kept")" = 2
check "...one with control characters isn't" not grep -q "$(printf '\033')" <<<"$kept"
check "...nor one that isn't a bridge line" not grep -q 'something else' <<<"$kept"
check "...nor one that breaks out of its quotes" not grep -q evil <<<"$kept"
printf 'user_pref("torbrowser.settings.bridges.builtin_type", "snowflake");\n' >"$T/block"
check "a built-in kind from last time is kept" test "$(current_builtin)" = snowflake
printf 'user_pref("torbrowser.settings.bridges.builtin_type", "x%s[2J");\n' "$(printf '\033')" >"$T/block"
check "...anything else named there isn't, and doesn't reach your terminal" test -z "$(current_builtin)"

TB=$HERE/extras/tor-browser.sh
check "it writes nothing in the browser's home as root" bash -c '! grep -nE "sudo[^|]*(\\\$(TBB|PROFILE|USERJS|TB_BASE)|/home/)" "$1"' _ "$TB"
check "the download is checked against the key before it is unpacked" bash -c '
    sed -n "/^install_browser() {/,/^}/p" "$1" | grep -E "verify_detached|tar -xJ" | head -1 | grep -q verify_detached' _ "$TB"
check "...it is unpacked by its user" grep -qx '    as_browser "$NAME" tar -xJ -C "$TB_BASE" <"$tarball" || die "Couldn'"'"'t unpack $tarball."' "$TB"
for x in extras/tor-browser.sh extras/mullvad-browser-sandbox.sh; do
    check "$x: says what it runs on, and removes it" bash -c '
        for w in "install_bin wayland-restrict" install_no_abstract install_net_check remove_wayland_restrict remove_no_abstract remove_net_check browser_remove; do
            grep -q "^ *$w" "$1" || exit 1
        done' _ "$HERE/$x"
    check "...and an update notices its files" bash -c 'for f in lib/browser-sandbox.sh bin/browser-sandbox bin/browser-session bin/no-abstract-sockets bin/wayland-restrict bin/sandbox-net-check; do grep -q "^# files:.* $f\| $f " "$1" || grep -q "^# files: $f" "$1" || exit 1; done' _ "$HERE/$x"
done
check "the session keeps its shared helpers from being taken away" bash -c '
    f=$(sed -n "/^remove_no_abstract() {/,/^}/p; /^remove_net_check() {/,/^}/p" "$1/lib/core.sh")
    [ "$(grep -c "browser-session" <<<"$f")" = 2 ] && grep -q browser-sandbox <<<"$(sed -n "/^remove_wayland_restrict() {/,/^}/p" "$1/lib/core.sh")"' _ "$HERE"
check "the DNS sets of both firewalls are filled" bash -c 'grep -q wren-tor-browser-firewall "$1" && grep -q wren-mullvad-browser-firewall "$1"' _ "$HERE/parts/sandbox-dns.sh"

# ---- the sudo rule: the session script, as that user, and nothing else (pretend sudo, real visudo)
mkdir -p "$T/sudo-etc"
cat >"$T/fakesudo" <<'EOF'
#!/bin/bash
case $1 in
    visudo) shift; PATH=/usr/sbin:$PATH exec visudo "$@" ;;
    install) cp "${@: -2:1}" "$SUDO_OUT" ;;
    tee) cat >/dev/null ;;
esac
EOF
chmod +x "$T/fakesudo"
# shellcheck disable=SC2317,SC2329  # called by the function the eval below brings in
(
    die() { echo "died: $*"; exit 1; }
    sudo() { SUDO_OUT=$T/sudo-etc/rule "$T/fakesudo" "$@"; }
    eval "$(sed -n '/^BROWSER_SESSION=/p; /^browser_allow() {/,/^}/p' "$HERE/lib/browser-sandbox.sh")"
    browser_allow tor-browser
) >/dev/null 2>&1
rule=$(grep -v '^#' "$T/sudo-etc/rule" 2>/dev/null)
check "your user may run the session script as that user" test "$rule" = "$(id -un) ALL=(tor-browser) NOPASSWD: /usr/local/libexec/browser-session"
if PATH=/usr/sbin:$PATH command -v visudo >/dev/null; then
    check "...and the real visudo takes it" env PATH="/usr/sbin:$PATH" visudo -cf "$T/sudo-etc/rule"
fi

# ---- nothing outside the sandbox is called what it isn't
check "a session has a clean environment" grep -q 'setsid env -i' "$SESSION"
check "...and the browser's X server is its own: sway's Wayland socket is the restricted one" grep -q 'WAYLAND_DISPLAY="$host_dir/$host_wl"' "$SESSION"
check "what it saves is shared with you only as it lands" grep -q 'g::-,o::-,m::rw' "$SESSION"
[ "$fails" -eq 0 ]
