#!/bin/bash
# Checks the sandboxed wallets (extras/wallet-sandbox.sh, bin/wallet and its
# helpers) with pretend sudo, setfacl, wayland-restrict, id, cage and xclip; the
# firewall for real, with nft in a network namespace; and cage's X socket for
# real, with no screen. No wallet is opened, nothing is installed, and nothing
# outside temp folders changes (the session's folder in /dev/shm is removed).
# Run by test.sh, or:  bash tools/test-wallet-sandbox.sh
# shellcheck disable=SC2016,SC2329  # the inner shells and pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T" /dev/shm/wren-wallet-feather.test-* /dev/shm/wallet-feather.*; kill $(jobs -p) 2>/dev/null' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
command -v flock >/dev/null || { echo "  ok    skipped: flock isn't installed"; exit 0; }
mkdir -p "$T/fake" "$T/run" "$T/home" "$T/shm" "$T/conf"

# ---- the firewall, for real
NS_PATH=/usr/sbin:/sbin:/usr/bin:/bin
FW=$HERE/data/wallet-firewall.nft
if PATH=$NS_PATH command -v nft >/dev/null && unshare -rn true 2>/dev/null; then
    # A network namespace of its own, with the rule made to match its root user
    sed 's/meta skuid {[^}]*}/meta skuid 0/' "$FW" >"$T/fw.nft"
    # Everyone is the same user in there, Tor too. For real Tor's answers are its
    # own user's, so this one line stands in for that:
    sed 's/^\( *\)ip daddr 127.0.0.1 tcp dport 9050 accept$/&\n\1ip saddr 127.0.0.1 tcp sport 9050 accept/' "$T/fw.nft" >"$T/fw-tor.nft"
    cat >"$T/in-ns.sh" <<'EOF'
ip link set lo up && ip link add d0 type dummy && ip link set d0 up &&
ip addr add 192.168.5.2/24 dev d0 && ip route add default dev d0 &&
ip -6 addr add 2001:db8:5::2/64 dev d0 nodad || exit 9
[ "$FW" = none ] || nft -f "$FW" || exit 8
"$@"
EOF
    ns() { # RULE-FILE|none COMMAND...
        local f=$1
        shift
        FW=$f PATH=$NS_PATH unshare -rn bash "$T/in-ns.sh" "$@"
    }
    # how a connection from the wallet's user ends: errno's name, or "connected"
    cat >"$T/try.py" <<'EOF'
import errno, socket, sys
fam = socket.AF_INET6 if ":" in sys.argv[1] else socket.AF_INET
kind = socket.SOCK_DGRAM if len(sys.argv) > 3 else socket.SOCK_STREAM
s = socket.socket(fam, kind)
s.settimeout(0.5)
if kind == socket.SOCK_DGRAM:
    try:
        s.sendto(b"x", (sys.argv[1], int(sys.argv[2])))
        print("sent")
    except OSError as e:
        print(errno.errorcode[e.errno])
else:
    r = s.connect_ex((sys.argv[1], int(sys.argv[2])))
    print("connected" if r == 0 else errno.errorcode.get(r, r))
EOF
    try() { ns "$T/fw.nft" python3 -I "$T/try.py" "$@"; }
    check "nft takes the rule as written, the three users by name (root and nobody standing in)" bash -c '
        sed -e "s/\"wallet-feather\", \"wallet-sparrow\", \"wallet-electrum\"/\"root\", \"nobody\"/" "$1" >"$2/names.nft"
        PATH=$3 unshare -rn nft -f "$2/names.nft"' _ "$FW" "$T" "$NS_PATH"
    check "the rule names exactly the three wallets' users" \
        grep -qF 'meta skuid { "wallet-feather", "wallet-sparrow", "wallet-electrum" } jump wallet' "$FW"
    check "a closed port on this computer: refused by the rule" test "$(try 127.0.0.1 9)" = EHOSTUNREACH
    check "the internet directly: refused" test "$(try 1.1.1.1 443)" = EHOSTUNREACH
    check "your router: refused" test "$(try 192.168.5.1 80)" = EHOSTUNREACH
    check "this computer's own address on Tor's port: refused" test "$(try 192.168.5.2 9050)" = EHOSTUNREACH
    # IPv6 ends in silence, and an address out there does without the rule too, so
    # what counts is the rule's own count of what it turned away
    sed 's/^\( *\)reject with/\1counter reject with/' "$T/fw.nft" >"$T/fw-count.nft"
    hit() { ns "$T/fw-count.nft" bash -c 'python3 -I "$1" "$2" "$3" >/dev/null; nft list ruleset | grep -qE "counter packets [1-9]" && echo refused' _ "$T/try.py" "$@"; }
    check "IPv6, to this computer on Tor's port: refused" test "$(hit ::1 9050)" = refused
    check "...and out" test "$(hit 2001:db8:5::1 443)" = refused
    check "DNS over UDP: refused" not test "$(try 192.168.5.1 53 udp)" = sent
    check "UDP to Tor's port: refused" not test "$(try 127.0.0.1 9050 udp)" = sent
    check "no rule lets answers out, so a wallet can't pretend to be a service here" \
        not grep -qE '^[^#]*(established|related)' "$FW"
    # Tor's port, listening: the one thing that gets through. And wallet-net-check.
    cat >"$T/listen.sh" <<'EOF'
python3 -I -c 'import socket,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(("127.0.0.1",9050)); s.listen(); time.sleep(3)' &
/bin/sleep 0.3
"$@"
EOF
    try_tor() { ns "$T/fw-tor.nft" bash "$T/listen.sh" "$@"; }
    check "Tor's port on 127.0.0.1 gets through" test "$(try_tor python3 -I "$T/try.py" 127.0.0.1 9050)" = connected
    netrc() { "$@" >/dev/null 2>&1; echo $?; }
    check "wallet-net-check: the rule there, Tor answering: go" test "$(try_tor bash "$HERE/bin/wallet-net-check"; echo $?)" = 0
    check "...the rule there, no Tor: says so" test "$(netrc ns "$T/fw.nft" bash "$HERE/bin/wallet-net-check")" = 2
    check "...no rule: stop" test "$(netrc ns none bash "$HERE/bin/wallet-net-check")" = 1
    check "...no rule, even with something on Tor's port" bash -c '
        FW=none PATH=$1 unshare -rn bash "$2/in-ns.sh" bash "$2/listen.sh" bash "$3/bin/wallet-net-check"; [ $? = 1 ]' _ "$NS_PATH" "$T" "$HERE"
else
    echo "  skip  the firewall in a network namespace (needs nft and unshare -rn)"
fi

# ---- the wallet command
cat >"$T/fake/sudo" <<FAKE
#!/bin/bash
echo "sudo \$*" >>"$T/calls"
case " \$* " in
    *" -l "*) [ -z "\${FAKE_NOT_SET_UP:-}" ] ;;
    *" start "*) /bin/sleep "\${FAKE_UP:-0.1}" ;;
    *" clip-in "*) cat >"$T/into-wallet" ;;
    *" clip-out "*) printf '%s' "\$FAKE_WALLET_CLIP" ;;
esac
FAKE
printf '#!/bin/bash\necho "setfacl $*" >>"%s/calls"\n' "$T" >"$T/fake/setfacl"
printf '#!/bin/sh\necho ready\ncat >/dev/null\n' >"$T/fake/wayland-restrict"
printf '#!/bin/sh\nprintf "%%s" "$FAKE_HOST_CLIP"\n' >"$T/fake/wl-paste"
printf '#!/bin/sh\ncat >"%s/onto-host"\n' "$T" >"$T/fake/wl-copy"
chmod +x "$T/fake/"*
python3 -I -c 'import socket,sys,time; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); time.sleep(120)' "$T/run/wayland-1" >/dev/null 2>&1 &
/bin/sleep 0.3
w() { env PATH="$T/fake:$PATH" HOME="$T/home" XDG_RUNTIME_DIR="$T/run" WAYLAND_DISPLAY=wayland-1 WREN_SHARE_ROOT="$T/shm" WREN_WALLET_CONF="$T/conf" WREN_DEV="$T/dev" bash "$HERE/bin/wallet" "$@"; }

out=$(w nosuch 2>&1); check "an unknown wallet: refused" grep -q usage <<<"$out"
: >"$T/calls"
w feather >/dev/null 2>&1
check "it opens as that wallet's own user" grep -qE "sudo -n -u wallet-feather /usr/local/libexec/wallet-session start feather $T/shm/wren-wallet-feather\.[A-Za-z0-9]+ wallet-feather-wayland" "$T/calls"
check "...passage to its own new folder and socket" bash -c 'grep -qE "setfacl -m u:wallet-feather:--x $1/shm/wren-wallet-feather\." "$1/calls" && grep -qE "setfacl -m u:wallet-feather:rw- $1/shm/wren-wallet-feather\.[^ ]+/wallet-feather-wayland" "$1/calls"' _ "$T"
check "...never through your home or your runtime folder" bash -c '! grep -E "setfacl.* ($1/home|$1/run)( |$)" "$1/calls"' _ "$T"
check "...and the folder goes when it closes" bash -c '[ -z "$(ls -A "$1/shm")" ]' _ "$T"
check "...no camera asked for without the option" not grep -q wallet-camera "$T/calls"

: >"$T/calls"
FAKE_UP=1 w electrum >/dev/null 2>&1 &
p=$!
/bin/sleep 0.4
out=$(w electrum 2>&1); rc=$?
check "the same wallet twice: refused" bash -c '[ "$1" != 0 ] && grep -q "already open" <<<"$2"' _ "$rc" "$out"
wait "$p"

out=$(FAKE_NOT_SET_UP=1 w sparrow 2>&1); rc=$?
check "a wallet you didn't choose: says so, nothing starts" bash -c '[ "$1" != 0 ] && grep -q "set up" <<<"$2"' _ "$rc" "$out"

: >"$T/calls"
printf 'enabled=yes\nhardware=no\ncamera=yes\n' >"$T/conf/sparrow.conf"
w sparrow >/dev/null 2>&1
check "with the camera option: given as it opens, before the session" bash -c 'grep -n "wallet-camera sparrow on" "$1" | head -1 | cut -d: -f1 >"$1.a"; grep -n " start sparrow " "$1" | head -1 | cut -d: -f1 >"$1.b"; [ "$(cat "$1.a")" -lt "$(cat "$1.b")" ]' _ "$T/calls"
check "...taken back as it closes" bash -c 'tail -1 "$1" | grep -q "wallet-camera sparrow off"' _ "$T/calls"
out=$(w sparrow 2>&1)
check "...no camera switched on: it says how" grep -q 'no camera is on' <<<"$out"

# ---- wallet clip
# Holds a wallet's lock, as an open wallet does
hold() { flock -n "$T/run/wallet-$1.lock" /bin/sleep "${2:-5}" >/dev/null 2>&1 & /bin/sleep 0.2; }
clip() { w clip "$@" 2>&1; }
out=$(FAKE_HOST_CLIP=addr clip in </dev/null); check "no wallet open: nothing to do" grep -q 'no wallet is open' <<<"$out"
hold feather 8
rm -f "$T/into-wallet" "$T/onto-host"
out=$(FAKE_HOST_CLIP='4AddrOne' clip in <<<y)
check "in: it shows the text first" grep -q '  4AddrOne' <<<"$out"
check "...and sends it when you say yes" test "$(cat "$T/into-wallet")" = 4AddrOne
rm -f "$T/into-wallet"
out=$(FAKE_HOST_CLIP='4AddrOne' clip in <<<n)
check "...no: nothing goes" test ! -e "$T/into-wallet"
out=$(FAKE_HOST_CLIP='4AddrOne' clip in </dev/null)
check "...just Enter, or nothing: nothing goes" test ! -e "$T/into-wallet"
out=$(FAKE_WALLET_CLIP='bc1qAddr' clip out <<<y)
check "out: it shows the text, and says to compare it" bash -c 'grep -q "  bc1qAddr" <<<"$1" && grep -q compare <<<"$1"' _ "$out"
check "...and copies it when you say yes" test "$(cat "$T/onto-host")" = bc1qAddr
rm -f "$T/onto-host"
out=$(FAKE_WALLET_CLIP='bc1qAddr' clip out <<<n)
check "...no: your clipboard is left alone" test ! -e "$T/onto-host"
bad() { # DESCRIPTION TEXT
    rm -f "$T/onto-host"
    out=$(FAKE_WALLET_CLIP=$2 clip out <<<y)
    check "from a wallet, $1: refused, not even shown" bash -c '[ ! -e "$1" ] && grep -q "nothing was moved" <<<"$2" && ! grep -qF "$3" <<<"$2"' _ "$T/onto-host" "$out" "${2:0:5}"
}
bad "a terminal escape" $'abc\e]52;c;evil\a'
bad "two lines" $'first\nsecond'
bad "a look-alike letter" 'bc1qаddr'
bad "a tab" $'abcdef\tghi'
long=$(printf 'x%.0s' {1..1025})
bad "too long" "$long"
ok=$(printf 'x%.0s' {1..1024})
rm -f "$T/onto-host"
out=$(FAKE_WALLET_CLIP=$ok clip out <<<y)
check "...the longest allowed gets through" test "$(cat "$T/onto-host")" = "$ok"
out=$(FAKE_WALLET_CLIP='' clip out <<<y)
check "an empty clipboard: says so" grep -q 'empty' <<<"$out"
rm -f "$T/into-wallet"
out=$(FAKE_HOST_CLIP=$'one\ntwo' clip in <<<y)
check "from your clipboard, two lines (a password list, say): refused too" test ! -e "$T/into-wallet"
out=$(FAKE_HOST_CLIP=x clip out sparrow </dev/null)
check "a named wallet that isn't open: says so" grep -q "sparrow isn't open" <<<"$out"
hold electrum 4
out=$(FAKE_HOST_CLIP=x clip in </dev/null)
check "two open: it asks you to name one, and moves nothing" grep -q 'name one' <<<"$out"
/bin/sleep 4

# ---- the session, in a copy with its fixed places made pretend
mkdir -p "$T/sfake" "$T/homes/feather" "$T/lib/feather/usr/bin" "$T/sfake-ok"
printf '#!/bin/sh\ncase "$1" in -un) echo wallet-feather ;; *) exec /usr/bin/id "$@" ;; esac\n' >"$T/sfake/id"
printf '#!/bin/bash\nexec "$@"\n' >"$T/noabs"
printf '#!/bin/sh\necho feather-ran\n' >"$T/lib/feather/usr/bin/feather"
cat >"$T/sfake/cage" <<EOF
#!/bin/bash
echo "cage \$*" >>"$T/scalls"
env >"$T/cage-env"
[ -z "\${FAKE_CAGE_STAYS:-}" ] || /bin/sleep 5
EOF
cat >"$T/sfake/xclip" <<EOF
#!/bin/bash
echo "xclip DISPLAY=\$DISPLAY \$*" >>"$T/scalls"
case " \$* " in *" -in "*) cat >"$T/x-clip" ;; *" -out "*) cat "$T/x-clip" ;; esac
EOF
printf '#!/bin/sh\nexit "${FAKE_NET:-0}"\n' >"$T/netcheck"
chmod +x "$T/sfake/"* "$T/noabs" "$T/netcheck" "$T/lib/feather/usr/bin/feather"
sed -e "s|^export PATH=.*|export PATH=$T/sfake:\$PATH|" -e "s|^noabs=.*|noabs=$T/noabs|" -e "s|^netcheck=.*|netcheck=$T/netcheck|" \
    -e "s|^homes=.*|homes=$T/homes|" -e "s|^lib=.*|lib=$T/lib|" "$HERE/bin/wallet-session" >"$T/session"
chmod +x "$T/session"
SD=$(mktemp -d /dev/shm/wren-wallet-feather.testXXXXXXX)
SN=wayland-test
python3 -I -c 'import socket,sys,time; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); time.sleep(60)' "$SD/$SN" >/dev/null 2>&1 &
/bin/sleep 0.3
# (PATH and the rest come from the copy's own lines)
s() { env -u WALLET_WRAPPED "$T/session" "$@" 2>&1; }

out=$(s start feather "$SD" "$SN"); rc=$?
check "the session opens the wallet in cage, with the private X server's address written down" bash -c 'grep -q "cage -d -- bash -c .*DISPLAY.*wallet-start .*feather" "$1"' _ "$T/scalls"
check "...told to use X and the restricted socket, in an emptied environment" bash -c 'grep -qx "QT_QPA_PLATFORM=xcb" "$1" && grep -qx "WLR_BACKENDS=wayland" "$1" && grep -qx "WAYLAND_DISPLAY=$2/$3" "$1" && ! grep -q "^SWAYSOCK=" "$1"' _ "$T/cage-env" "$SD" "$SN"
check "...its home where its files are" grep -qx "HOME=$T/homes/feather" "$T/cage-env"
check "...and the folder you share, at transfer" test "$(readlink "$T/homes/feather/transfer")" = "$T/homes/files/feather"
check "...and its memory folder goes" bash -c '! ls -d /dev/shm/wallet-feather.* 2>/dev/null'

: >"$T/scalls"
out=$(FAKE_NET=1 s start feather "$SD" "$SN")
check "the firewall missing, seen from the wallet: it doesn't open" bash -c '! grep -q cage "$1" && grep -q "firewall" <<<"$2"' _ "$T/scalls" "$out"
out=$(FAKE_NET=2 s start feather "$SD" "$SN")
check "Tor not answering: it doesn't open" bash -c '! grep -q cage "$1" && grep -q "Tor" <<<"$2"' _ "$T/scalls" "$out"

cat >"$T/netcheck" <<EOF
#!/bin/sh
n=\$(cat "$T/netn" 2>/dev/null || echo 0)
echo \$((n + 1)) >"$T/netn"
[ "\$n" = 0 ]
EOF
: >"$T/scalls"
cat >"$T/sfake/cage" <<EOF
#!/bin/bash
trap 'echo closed >"$T/cage-closed"; exit 0' TERM
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do /bin/sleep 0.2; done
EOF
out=$(WALLET_RECHECK=0.2 s start feather "$SD" "$SN")
check "the firewall going while it is open: the wallet is closed" bash -c '[ -e "$1" ] && grep -q "went away" <<<"$2"' _ "$T/cage-closed" "$out"
printf '#!/bin/sh\nexit 0\n' >"$T/netcheck"

for a in "/tmp/evil" "/dev/shm/wren-wallet-sparrow.abc" "/dev/shm/wren-wallet-feather.a/../b"; do
    out=$(s start feather "$a" "$SN")
    check "another socket folder is refused: $a" grep -q 'unexpected socket folder' <<<"$out"
done
out=$(s start feather "$SD" "../x")
check "a Wayland name with a path in it is refused" grep -q 'unexpected Wayland' <<<"$out"
out=$(s start sparrow "$SD" "$SN")
check "the user wallet-feather can't run another wallet" grep -q 'runs as the user wallet-sparrow' <<<"$out"
out=$(s clip-out nosuch)
check "an unknown wallet name is refused" grep -q 'unknown wallet' <<<"$out"

out=$(s clip-in feather </dev/null)
check "the clipboard with no wallet open: says so" grep -q "isn't open" <<<"$out"
B=$(mktemp -d /dev/shm/wallet-feather.XXXXXXX)
mkdir "$B/run"
printf ':7' >"$B/run/display"
printf 'text' | s clip-in feather
check "clip-in goes to that wallet's own X server's clipboard" bash -c 'grep -q "xclip DISPLAY=:7 -selection clipboard -in" "$1" && [ "$(cat "$2")" = text ]' _ "$T/scalls" "$T/x-clip"
check "clip-out gives it back" test "$(s clip-out feather)" = text
printf 'x; evil' >"$B/run/display"
out=$(printf z | s clip-in feather)
check "a display name a wallet has changed into something else: refused" grep -q "isn't ready" <<<"$out"
rm -rf "$B" "$SD"

check "the session goes under the wrapper before anything else it does" bash -c '
    a=$(grep -n "exec \"\$noabs\" \"\$0\"" "$1" | cut -d: -f1); b=$(grep -nE "^(cmd=|case |rc=0)" "$1" | head -1 | cut -d: -f1); [ -n "$a" ] && [ "$a" -lt "$b" ]' _ "$HERE/bin/wallet-session"
check "...and keeps X's socket private (umask 077)" grep -qx 'umask 077' "$HERE/bin/wallet-session"

# ---- cage's X socket, for real and with no screen
if command -v cage >/dev/null && command -v Xwayland >/dev/null && [ -w /tmp/.X11-unix ]; then
    cat >"$T/x.sh" <<EOF
#!/bin/bash
stat -c %a "/tmp/.X11-unix/X\${DISPLAY#:}" >"$T/x-mode"
EOF
    chmod +x "$T/x.sh"
    mkdir -p "$T/xrun"
    chmod 700 "$T/xrun"
    ( umask 077; env -i PATH=/usr/bin:/bin HOME="$T" XDG_RUNTIME_DIR="$T/xrun" WLR_BACKENDS=headless WLR_RENDERER=pixman timeout 20 cage -d -- "$T/x.sh" >/dev/null 2>&1 )
    check "the wallet's X socket in /tmp is its user's alone" test "$(cat "$T/x-mode" 2>/dev/null)" = 700
else
    echo "  skip  cage's X socket (needs cage, Xwayland and /tmp/.X11-unix)"
fi

# ---- the camera helper
mkdir -p "$T/dev" "$T/cfake"
printf '#!/bin/bash\necho "setfacl $*" >>"%s/ccalls"\n' "$T" >"$T/cfake/setfacl"
chmod +x "$T/cfake/setfacl"
cam() { env PATH="$T/cfake:$PATH" WREN_DEV="$T/dev" WREN_WALLET_CONF="$T/conf" "$HERE/bin/wallet-camera" "$@" 2>&1; }
printf 'enabled=yes\ncamera=no\n' >"$T/conf/electrum.conf"
printf 'enabled=yes\ncamera=yes\n' >"$T/conf/feather.conf"
check "the camera helper: an unknown wallet is refused" not cam 'x; rm' on
check "...anything but on or off is refused" not cam feather 'status'
check "...a wallet not set up with the camera is refused" not cam electrum on
check "...a wallet with it, and no camera there: nothing happens" cam feather on
check "...a test that runs as root would not use these places" grep -qE 'DEV=/dev CONF=/etc/wren/wallets' "$HERE/bin/wallet-camera"

# ---- the extra, with pretend sudo
mkdir -p "$T/xf" "$T/xh/.local/opt/feather/usr/bin" "$T/xh/.config/sway/config.d"
cat >"$T/xf/sudo" <<EOF
#!/bin/bash
echo "sudo \$*" >>"$T/xcalls"
case \$1 in
    tee) f=\$2; case \$f in $T/*) ;; *) f=$T/root\$f ;; esac; mkdir -p "\${f%/*}"; cat >"\$f" ;;
    install) a=("\$@"); n=\${#a[@]}; case " \$* " in *" -d "*) case "\${a[n-1]}" in $T/*) mkdir -p "\${a[n-1]}" ;; esac ;; *) d=$T/root\${a[n-1]}; mkdir -p "\${d%/*}"; cp "\${a[n-2]}" "\$d" ;; esac ;;
    test) exit 1 ;;
    visudo) /bin/true ;;
esac
exit 0
EOF
for c in systemctl getent; do printf '#!/bin/sh\nexit 0\n' >"$T/xf/$c"; done
printf '#!/bin/sh\nexit 0\n' >"$T/xf/swaymsg"
printf '#!/bin/sh\nexit 0\n' >"$T/xf/sway"
# id: the wallets' users exist only when a test says so, with that number
cat >"$T/xf/id" <<'EOF'
#!/bin/bash
case "$*" in
    *wallet-*) [ -n "${XT_USER_ID:-}" ] || exit 1; echo "$XT_USER_ID" ;;
    *) exec /usr/bin/id "$@" ;;
esac
EOF
cat >"$T/xf/dpkg-query" <<'EOF'
#!/bin/sh
# Everything is here, but not Wren Linux's own record of what this script installed
case "$*" in *wren-*) exit 1 ;; esac
printf 'install ok installed'
EOF
chmod +x "$T/xf/"*
xt() { # ANSWERS ARGS...: the extra, as a person with /dev/kvm or not
    local a=$1
    shift
    printf '%b' "$a" >"$T/answers"
    # lib.sh sets its own PATH, so these are functions, found before any PATH: never
    # the real sudo, or anything that could reach the real system or your sway
    (
        for c in sudo systemctl getent swaymsg sway dpkg-query id; do
            eval "$c() { \"$T/xf/$c\" \"\$@\"; }"
            export -f "${c?}"
        done
        env HOME="$T/xh" WREN_TEST_ANSWERS="$T/answers" WREN_KVM="${XT_KVM:-$T/no-kvm}" WREN_WALLET_CONF="$T/xc" \
            SWAYSOCK= WAYLAND_DISPLAY= bash "$HERE/extras/wallet-sandbox.sh" "$@" 2>&1
    )
}
touch "$T/xh/.local/opt/feather/usr/bin/feather"
chmod +x "$T/xh/.local/opt/feather/usr/bin/feather"
XS=$HERE/extras/wallet-sandbox.sh
R=$T/root
touch "$T/kvm"
out=$(XT_KVM=$T/kvm xt 'n\n')
check "a computer that can run VMs: Whonix is offered first, and no stops here" bash -c 'grep -q "wrenctl install whonix" <<<"$1" && grep -q "Nothing was changed" <<<"$1" && ! grep -q apt-get "$2" 2>/dev/null && [ ! -e "$3/feather.conf" ]' _ "$out" "$T/xcalls" "$T/xc"
rm -rf "$T/xc"; : >"$T/xcalls"
# Yes to Electrum alone, with the camera but no hardware wallet; no to the others
out=$(xt 'n\nn\ny\nn\ny\n')
check "a computer that can't: no such question" not grep -q 'wrenctl install whonix' <<<"$out"
check "the install runs through" grep -q 'Open it with: wallet electrum' <<<"$out"
check "...and never reached the real sudo" not grep -q 'a password is required' <<<"$out"
check "...your answers kept, in root's file" bash -c 'grep -qx enabled=yes "$1/electrum.conf" && grep -qx camera=yes "$1/electrum.conf" && grep -qx hardware=no "$1/electrum.conf" && grep -qx enabled=no "$1/feather.conf"' _ "$T/xc"
check "...sudoers: the session, as the wallet chosen and no other" bash -c 'grep -qE "ALL=\(wallet-electrum\) NOPASSWD: /usr/local/libexec/wallet-session$" "$1" && ! grep -qE "wallet-(feather|sparrow)" "$1"' _ "$R/etc/sudoers.d/wren-wallet"
check "...the camera helper as root only because a wallet has the camera" grep -qE 'ALL=\(root\) NOPASSWD: /usr/local/libexec/wallet-camera$' "$R/etc/sudoers.d/wren-wallet"
check "...all three users exist, for the firewall to load" bash -c 'for u in feather sparrow electrum; do grep -q "sudo useradd .* wallet-$u$" "$1" || exit 1; done' _ "$T/xcalls"
check "...no password and no login for them" grep -q 'sudo usermod --lock --shell /usr/sbin/nologin wallet-electrum' "$T/xcalls"
check "...the folder you share: you and that wallet" grep -q "sudo setfacl -P -d -m u:$(id -un):rwx,u:wallet-electrum:rwx /var/lib/wren-wallet/files/electrum" "$T/xcalls"
check "...no core files, which could hold keys" grep -qx 'wallet-electrum hard core 0' "$R/etc/security/limits.d/50-wren-wallet.conf"
check "...the firewall at every boot, before the network" bash -c 'grep -qx "Before=network-pre.target" "$1" && grep -qx "ExecStart=/usr/sbin/nft -f /etc/wren/wallet.nft" "$1"' _ "$R/etc/systemd/system/wren-wallet-firewall.service"
check "...it is loaded now" grep -q 'sudo systemctl restart wren-wallet-firewall.service' "$T/xcalls"
check "...Tor is marked as in use" test -f "$R/etc/tor/.wren-wallet-sandbox"
check "...~/Wallets, outside your home" test "$(readlink "$T/xh/Wallets")" = /var/lib/wren-wallet/files
check "...no hardware rule without the choice" not test -f "$R/etc/udev/rules.d/71-wren-wallet-electrum.rules"
check "...it warns that your backup doesn't cover them" grep -q "backup doesn't cover" <<<"$out"
: >"$T/xcalls"
out=$(xt '')
check "run again (an update): it asks nothing" not grep -qE 'Set up|hardware wallet over|camera for QR' <<<"$out"
sed -i 's/^enabled=no/enabled=yes/; s/^hardware=no/hardware=yes/' "$T/xc/feather.conf"
out=$(xt '')
check "a wallet turned on in its file: its hardware rule, for that user alone" bash -c 'grep -q "RUN+=\"/usr/bin/setfacl -m u:wallet-feather:rw- \$devnode\"" "$1" && ! grep -q uaccess "$1"' _ "$R/etc/udev/rules.d/71-wren-wallet-feather.rules"
check "...its files copied where its user can read them, root's" bash -c 'grep -q "sudo cp -r --no-preserve=all $1/.local/opt/feather /usr/local/lib/wren-wallet/feather.new" "$2" && grep -q "sudo chown -R root:root /usr/local/lib/wren-wallet/feather.new" "$2"' _ "$T/xh" "$T/xcalls"
: >"$T/xcalls"
out=$(XT_USER_ID=1001 xt '')
check "a regular account with such a name: it stops, and leaves it alone" bash -c 'grep -q "regular user account called wallet-" <<<"$1" && ! grep -q "usermod.*wallet-" "$2"' _ "$out" "$T/xcalls"
: >"$T/xcalls"
out=$(XT_USER_ID=999 xt '' --remove)
check "--remove: the firewall and the users go" bash -c 'grep -q "sudo nft delete table inet wren_wallet" "$1" && grep -q "sudo userdel wallet-electrum" "$1"' _ "$T/xcalls"
check "...it keeps the wallets" bash -c '! grep -E "^sudo rm .*/var/lib/wren-wallet" "$1" && grep -q "Your wallets are kept" <<<"$2"' _ "$T/xcalls" "$out"
check "...~/Wallets goes" not test -L "$T/xh/Wallets"
check "the summary fits the checklist" bash -c 'l=$(sed -n "s/^# summary: //p" "$1"); [ ${#l} -le 52 ] && [ -n "$l" ]' _ "$XS"
check "...and the Whonix question's default is no" grep -q 'Set up the sandbox anyway?" n' "$XS"
check "Tor's mark is on the list of the tor service's users" bash -c 'grep -qx "MARK=/etc/tor/.wren-wallet-sandbox" "$1" && grep -q ".wren-wallet-sandbox" "$2"' _ "$XS" "$HERE/lib/tor.sh"
check "removing another sandbox leaves the shared helpers while this one is here" bash -c 'grep -q "wallet-session" <<<"$(sed -n "/^remove_no_abstract/,/^}/p" "$1")" && grep -q "/usr/local/bin/wallet" <<<"$(sed -n "/^remove_wayland_restrict/,/^}/p" "$1")"' _ "$HERE/lib/core.sh"
check "--remove never deletes the wallets" bash -c '! sed -n "/--remove \]; then/,/^fi/p" "$1" | grep -qE "rm .*(\\\$HOMES|wren-wallet)($|[^.])|rm -rf \"\\\$HOMES"' _ "$XS"
check "...and says where they are" grep -q 'Your wallets are kept in' "$XS"
check "the sudoers rule is checked before it goes in" bash -c 'grep -q "visudo -cf" "$1"' _ "$XS"
check "the Super+Ctrl+w key isn't taken" bash -c '! grep -rnE "\\\$mod\+Ctrl\+w\b" "$1/data" "$1/parts" "$1/lib" | grep -v wallet' _ "$HERE"

[ "$fails" -eq 0 ]
