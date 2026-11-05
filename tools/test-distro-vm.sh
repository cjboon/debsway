#!/bin/bash
# Checks the distribution VMs (extras/distro-vm.sh, bin/distro-vm-session,
# bin/distro-vm-net-check, data/distro-vm-firewall.nft): the firewall and the
# net check for real, with nft in a network namespace; the release lists and the
# signature checks with a key made here and pretend downloads. No VM is started,
# nothing is downloaded or installed, and nothing outside temp folders changes.
# Run by test.sh, or:  bash tools/test-distro-vm.sh
# shellcheck disable=SC2016,SC2329  # the inner shells and pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'gpgconf --homedir "$T/gpg" --kill all 2>/dev/null; gpgconf --homedir "$T/other" --kill all 2>/dev/null; rm -rf "$T"; kill $(jobs -p) 2>/dev/null' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
SESSION=$HERE/bin/distro-vm-session
NETCHECK=$HERE/bin/distro-vm-net-check
FW=$HERE/data/distro-vm-firewall.nft
EXTRA=$HERE/extras/distro-vm.sh

# ---- the firewall and the net check, for real
NS_PATH=/usr/sbin:/sbin:/usr/bin:/bin
if PATH=$NS_PATH command -v nft >/dev/null && unshare -rn true 2>/dev/null; then
    # In a namespace of its own everyone is root, so root stands in for the VM's
    # user, in one set or the other
    { cat "$FW"; echo 'add element inet wren_distro_vm direct { "root" }'
      echo 'add element inet wren_distro_vm resolvers { 192.168.5.1 }'; } >"$T/direct.nft"
    { cat "$FW"; echo 'add element inet wren_distro_vm tor { "root" }'; } >"$T/tor.nft"
    # For real Tor's answers are its own user's; here they are root's too, so this
    # one line stands in for that
    sed -e 's/^\( *\)ip daddr 127.0.0.1 tcp dport 9041 accept$/&\n\1ip saddr 127.0.0.1 tcp sport 9041 accept/' \
        -e 's/^\( *\)ip daddr 127.0.0.1 udp dport 9054 accept$/&\n\1ip saddr 127.0.0.1 udp sport 9054 accept/' "$T/tor.nft" >"$T/tor-real.nft"
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
    # how a connection ends: errno's name, "connected", or for UDP "sent"
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
    # a pretend Tor: TransPort 9041 takes connections, DNSPort 9054 echoes what it gets
    cat >"$T/tor.py" <<'EOF'
import socket, sys, threading
t = socket.socket(); t.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
t.bind(("127.0.0.1", 9041)); t.listen()
d = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); d.bind(("127.0.0.1", 9054))
def dns():
    while True:
        m, a = d.recvfrom(512); d.sendto(b"tor-dns:" + m, a)
threading.Thread(target=dns, daemon=True).start()
while True:
    c, _ = t.accept(); c.close()
EOF
    cat >"$T/dns.py" <<'EOF'
import socket, sys
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(1)
s.sendto(b"q", (sys.argv[1], 53))
try: print(s.recvfrom(64)[0].decode())
except OSError: print("none")
EOF
    # (the pretend Tor is stopped after, or the namespace's output never ends)
    with_tor() { local p r=0; python3 -I "$T/tor.py" >/dev/null 2>&1 & p=$!; /bin/sleep 0.3; "$@" || r=$?; kill "$p"; return "$r"; }
    try() { ns "$1" python3 -I "$T/try.py" "${@:2}"; }
    export -f with_tor
    export T

    check "nft takes the rule, with users by name in both sets" \
        ns none bash -c 'nft -f "$1" && nft -f "$2"' _ "$T/direct.nft" "$T/tor.nft"
    check "nft takes the rule as extras/distro-vm.sh writes it (three users, both sets)" bash -c '
        { cat "$1"; echo "add element inet wren_distro_vm direct { \"root\", \"nobody\" }"
          echo "add element inet wren_distro_vm tor { \"daemon\" }"; } >"$2/three.nft"
        PATH=$3 unshare -rn nft -c -f "$2/three.nft"' _ "$FW" "$T" "$NS_PATH"

    # internet only
    check "direct: a closed port on this computer: refused by the rule" test "$(try "$T/direct.nft" 127.0.0.1 9)" = EHOSTUNREACH
    check "direct: this computer's own LAN address: refused" test "$(try "$T/direct.nft" 192.168.5.2 22)" = EHOSTUNREACH
    check "direct: your router: refused" test "$(try "$T/direct.nft" 192.168.5.1 80)" = EHOSTUNREACH
    check "direct: 10.x, 172.16.x, link-local: refused" bash -c '
        for a in 10.0.0.1 172.16.0.1 169.254.1.1 100.64.0.1; do
            [ "$(FW=$1 PATH=$3 unshare -rn bash "$2/in-ns.sh" python3 -I "$2/try.py" $a 80)" = EHOSTUNREACH ] || exit 1
        done' _ "$T/direct.nft" "$T" "$NS_PATH"
    check "direct: the internet isn't refused (it times out here, with nowhere to go)" \
        not test "$(try "$T/direct.nft" 1.1.1.1 443)" = EHOSTUNREACH
    check "direct: DNS to the resolver in the set: sent" test "$(try "$T/direct.nft" 192.168.5.1 53 udp)" = sent
    check "direct: DNS to another address: refused" not test "$(try "$T/direct.nft" 192.168.5.9 53 udp)" = sent
    check "direct: IPv6: refused" not test "$(try "$T/direct.nft" 2001:db8:5::1 443)" = connected

    # Tor only
    check "tor: TCP to the internet lands in Tor's TransPort" \
        test "$(ns "$T/tor-real.nft" bash -c 'with_tor python3 -I "$T/try.py" 1.1.1.1 443')" = connected
    check "tor: TCP to your router lands in Tor too (and Tor refuses private addresses)" \
        test "$(ns "$T/tor-real.nft" bash -c 'with_tor python3 -I "$T/try.py" 192.168.5.1 80')" = connected
    check "tor: DNS to any address goes to Tor's DNSPort" \
        test "$(ns "$T/tor-real.nft" bash -c 'with_tor python3 -I "$T/dns.py" 192.168.5.1')" = tor-dns:q
    check "tor: other UDP: refused" test "$(try "$T/tor.nft" 1.1.1.1 443 udp)" = EPERM
    check "tor: with Tor down, TCP gets nowhere" not test "$(try "$T/tor.nft" 1.1.1.1 443)" = connected
    check "tor: IPv6: refused" not test "$(try "$T/tor.nft" 2001:db8:5::1 443)" = connected

    check "no rule lets answers out, so a VM's user can't stand in for a service here" \
        not grep -qE '^[^#]*(established|related)' "$FW"
    check "Tails is never in the Tor set: extras/distro-vm.sh asks only for Kali and Arch" \
        grep -q 'if \[ "$d" = tails \]; then' "$EXTRA"

    # the net check, as the session runs it
    check "net check, direct, rule loaded: passes" ns "$T/direct.nft" bash "$NETCHECK" direct
    check "...no rule (flushed): fails, so no VM starts" not ns none bash "$NETCHECK" direct
    check "...only the Tor rule loaded: fails for a direct VM" not ns "$T/tor-real.nft" bash "$NETCHECK" direct
    check "net check, tor, rule loaded and Tor up: passes" ns "$T/tor-real.nft" bash -c 'with_tor bash "$1" tor' _ "$NETCHECK"
    rc=0; ns "$T/tor-real.nft" bash "$NETCHECK" tor || rc=$?
    check "...Tor down: exit 2 (Tor doesn't answer)" test "$rc" = 2
    rc=0; ns none bash -c 'with_tor bash "$1" tor' _ "$NETCHECK" || rc=$?
    check "...no rule, even with Tor up: exit 1" test "$rc" = 1
    rc=0; ns "$T/direct.nft" bash -c 'with_tor bash "$1" tor' _ "$NETCHECK" || rc=$?
    check "...only the direct rule loaded: fails for a Tor VM" test "$rc" != 0
else
    echo "  ok    skipped the firewall checks: no nft or no user namespaces here"
fi

# ---- the release lists and signatures, with pretend downloads
if command -v gpg >/dev/null && command -v python3 >/dev/null; then
    mkdir -p "$T/gpg" "$T/other" "$T/keys" "$T/www" && chmod 700 "$T/gpg" "$T/other"
    for h in gpg other; do
        gpg --homedir "$T/$h" --batch --passphrase '' --quick-gen-key "test-$h <t@example.org>" ed25519 sign never 2>/dev/null
    done
    fpr=$(gpg --homedir "$T/gpg" --batch --with-colons --list-keys | awk -F: '/^fpr/ { print $10; exit }')
    for n in kali tails arch; do
        gpg --homedir "$T/gpg" --batch --export "$fpr" >"$T/keys/$n.gpg"
        echo "$fpr" >"$T/keys/$n.fpr"
    done
    sign() { gpg --homedir "$T/${3:-gpg}" --batch --yes --detach-sign -o "$2" "$1" 2>/dev/null; }

    # The session's functions, run outside it: wget hands out the pretend files
    # (www/ by the last part of the address), die returns instead of ending
    cat >"$T/harness.sh" <<'EOF'
set -uo pipefail
die() { echo "DIE: $*"; exit 1; }
say() { :; }
wget() {
    local out= url
    while [ $# -gt 0 ]; do case $1 in -O) out=$2; shift 2 ;; -q|-c|--show-progress) shift ;; -qO) out=$2; shift 2 ;; *) url=$1; shift ;; esac; done
    echo "$url" >>"$T/urls"
    local f=$T/www/${url##*/}
    [ -n "${url##*/}" ] || f=$T/www/releases.json
    [ -f "$f" ] || return 8
    cp "$f" "$out"
}
eval "$(sed -n '/^release_info() {/,/^}/p; /^sig_url() {/,/^}/p; /^good_sig() {/,/^}/p; /^image_ok() {/,/^}/p; /^current_image() /p; /^tidy() /p; /^fetch() {/,/^}/p' "$SESSION")"
netcheck_or_die() { :; }
KEYS=$T/keys
EOF
    run() { # NAME BASH-CODE: in a fresh folder, as that distribution
        local d
        d=$(mktemp -d "$T/run.XXXX")
        T=$T SESSION=$SESSION NAME=$1 HOME=$d IMAGES=$d/images bash -c '. "$T/harness.sh"; eval "$1"' _ "$2"
    }

    # Tails: latest.json names the ISO, its SHA-256 and size; the ISO's own signature
    printf 'tails iso\n' >"$T/www/tails-amd64-7.16.iso"
    sha=$(sha256sum "$T/www/tails-amd64-7.16.iso" | cut -d' ' -f1)
    size=$(stat -c %s "$T/www/tails-amd64-7.16.iso")
    tails_json() { # SHA SIZE URL-VERSION
        printf '{"installations":[{"version":"7.16","installation-paths":[{"type":"img","target-files":[{"url":"x","sha256":"%s","size":1}]},{"type":"iso","target-files":[{"url":"https://download.tails.net/tails/stable/tails-amd64-%s/tails-amd64-%s.iso","sha256":"%s","size":%s}]}]}]}' \
            "$1" "$3" "$3" "$1" "$2" >"$T/www/latest.json"
    }
    # (the size limits are Tails' real ones; the pretend ISO is tiny, so they're
    # checked on their own below)
    sed -n '/^        tails)$/,/^            ;;$/p' "$SESSION" | grep -q 'assert 500 \* 2\*\*20 < size < 8 \* 2\*\*30' &&
        sed_size='s/assert 500 \* 2\*\*20 < size < 8 \* 2\*\*30, size/assert 0 < size, size/'
    sed "$sed_size" "$SESSION" >"$T/session-small"
    SESSION=$T/session-small
    tails_json "$sha" "$size" 7.16
    sign "$T/www/tails-amd64-7.16.iso" "$T/www/tails-amd64-7.16.iso.sig"
    check "Tails: the newest ISO, signed, with the list's SHA-256 and size: kept" \
        run tails 'fetch && [ "$(cat "$IMAGES/current")" = tails-amd64-7.16.iso ] && [ -s "$IMAGES/tails-amd64-7.16.iso" ]'
    check "...and its signature came from tails.net, not the download server" grep -qx 'https://tails.net/torrents/files/tails-amd64-7.16.iso.sig' "$T/urls"
    check "...a download left half done before is cleared away" \
        run tails 'mkdir -p "$IMAGES"; : >"$IMAGES/old.iso.part"; : >"$IMAGES/tails-amd64-7.15.iso"; fetch; [ "$(ls "$IMAGES")" = "$(printf "current\ntails-amd64-7.16.iso")" ]'
    check "...and when the image is already the newest, too" \
        run tails 'fetch; : >"$IMAGES/old.iso.part"; fetch; [ ! -e "$IMAGES/old.iso.part" ]'
    check "...fetched again: nothing downloaded" \
        run tails 'fetch; : >"$T/urls"; fetch; ! grep -q "\.iso$" "$T/urls"'
    sign "$T/www/tails-amd64-7.16.iso" "$T/www/tails-amd64-7.16.iso.sig" other
    check "Tails: signed by another key: thrown away, nothing kept" \
        run tails 'out=$(fetch); [[ $out == *"signature isn"* ]] && [ ! -e "$IMAGES/current" ] && [ -z "$(ls "$IMAGES")" ]'
    sign "$T/www/tails-amd64-7.16.iso" "$T/www/tails-amd64-7.16.iso.sig"
    tails_json "$(printf '0%.0s' {1..64})" "$size" 7.16
    check "Tails: signed, but not the SHA-256 the list names (an older one?): thrown away" \
        run tails 'out=$(fetch); [[ $out == *"SHA-256"* ]] && [ ! -e "$IMAGES/current" ]'
    tails_json "$sha" 99 7.16
    check "Tails: not the size the list gives: thrown away" run tails 'out=$(fetch); [[ $out == *size* ]]'
    tails_json "$sha" "$size" 7.15
    check "Tails: a list whose address doesn't match its version: refused" \
        run tails 'out=$(fetch); [[ $out == *"isn'"'"'t as expected"* ]]'
    SESSION=$HERE/bin/distro-vm-session
    tails_json "$sha" "$size" 7.16
    check "Tails: the real size limits refuse a file of a few bytes" \
        run tails 'out=$(fetch); [[ $out == *"isn'"'"'t as expected"* ]]'

    # Arch: the release list's newest, its SHA-256, and the ISO's own signature
    printf 'arch iso\n' >"$T/www/archlinux-2026.11.01-x86_64.iso"
    asha=$(sha256sum "$T/www/archlinux-2026.11.01-x86_64.iso" | cut -d' ' -f1)
    arch_json() { # SHA [ISO-URL]
        printf '{"releases":[{"version":"2026.12.01","available":false,"sha256_sum":"x","iso_url":"y"},{"version":"2026.11.01","available":true,"sha256_sum":"%s","iso_url":"%s"},{"version":"2026.10.01","available":true,"sha256_sum":"%s","iso_url":"/iso/2026.10.01/archlinux-2026.10.01-x86_64.iso"}]}' \
            "$1" "${2:-/iso/2026.11.01/archlinux-2026.11.01-x86_64.iso}" "$1" >"$T/www/releases.json"
    }
    arch_json "$asha"
    sign "$T/www/archlinux-2026.11.01-x86_64.iso" "$T/www/archlinux-2026.11.01-x86_64.iso.sig"
    : >"$T/urls"
    check "Arch: the newest available release, signed, its SHA-256: kept" \
        run arch 'fetch && [ "$(cat "$IMAGES/current")" = archlinux-2026.11.01-x86_64.iso ]'
    check "...from Arch's own mirror over https" grep -qx 'https://geo.mirror.pkgbuild.com/iso/2026.11.01/archlinux-2026.11.01-x86_64.iso' "$T/urls"
    rm "$T/www/archlinux-2026.11.01-x86_64.iso.sig"
    check "Arch: no signature to be had: thrown away" run arch 'out=$(fetch); [[ $out == DIE* ]] && [ ! -e "$IMAGES/current" ]'
    sign "$T/www/archlinux-2026.11.01-x86_64.iso" "$T/www/archlinux-2026.11.01-x86_64.iso.sig" other
    check "Arch: signed by another key: thrown away" run arch 'out=$(fetch); [[ $out == *"signature isn"* ]]'
    arch_json "$asha" /iso/evil/archlinux.iso
    check "Arch: a list naming an address of another shape: refused" run arch 'out=$(fetch); [[ $out == *"isn'"'"'t as expected"* ]]'

    # Kali: a signed checksum list, checked before it is read
    printf 'kali iso\n' >"$T/www/kali-linux-2026.3-installer-amd64.iso"
    ksha=$(sha256sum "$T/www/kali-linux-2026.3-installer-amd64.iso" | cut -d' ' -f1)
    printf '%s  kali-linux-2026.3-live-amd64.iso\n%s  kali-linux-2026.3-installer-amd64.iso\n%s  kali-linux-2026.3-installer-amd64.iso.torrent\n' \
        "$ksha" "$ksha" "$ksha" >"$T/www/SHA256SUMS"
    sign "$T/www/SHA256SUMS" "$T/www/SHA256SUMS.gpg"
    check "Kali: the installer ISO from a list signed by Kali's key: kept" \
        run kali 'fetch && [ "$(cat "$IMAGES/current")" = kali-linux-2026.3-installer-amd64.iso ]'
    sign "$T/www/SHA256SUMS" "$T/www/SHA256SUMS.gpg" other
    check "Kali: the list signed by another key: refused before the ISO is fetched" \
        run kali ': >"$T/urls"; out=$(fetch); [[ $out == *"isn'"'"'t signed by Kali"* ]] && ! grep -q "\.iso$" "$T/urls"'
    printf '%s  kali-linux-2026.3-installer-amd64.iso\n' "$ksha" >"$T/www/SHA256SUMS"
    sign "$T/www/SHA256SUMS" "$T/www/SHA256SUMS.gpg"
    printf 'tampered\n' >"$T/www/kali-linux-2026.3-installer-amd64.iso"
    check "Kali: an ISO that isn't the one in the signed list: thrown away" \
        run kali 'out=$(fetch); [[ $out == *"SHA-256"* ]] && [ ! -e "$IMAGES/current" ] && [ -z "$(ls "$IMAGES")" ]'
    printf '%s  kali-linux-2026.3-installer-amd64.iso\n%s  kali-linux-2026.4-installer-amd64.iso\n' "$ksha" "$ksha" >"$T/www/SHA256SUMS"
    sign "$T/www/SHA256SUMS" "$T/www/SHA256SUMS.gpg"
    check "Kali: a list with two installer ISOs: refused (which one would be a guess)" \
        run kali 'out=$(fetch); [[ $out == *"isn'"'"'t as expected"* ]]'

    check "a key file with another fingerprint than pinned: no signature counts" bash -c '
        cp -r "$1/keys" "$1/keys2"; echo 0000000000000000000000000000000000000000 >"$1/keys2/kali.fpr"
        KEYS=$1/keys2 NAME=kali T=$1 SESSION=$2 bash -c ". \"\$T/harness.sh\"; KEYS=\$T/keys2; good_sig \"\$T/www/SHA256SUMS.gpg\" \"\$T/www/SHA256SUMS\"" | grep -q "DIE\|^$" ||
        ! KEYS=$1/keys2 NAME=kali T=$1 SESSION=$2 bash -c ". \"\$T/harness.sh\"; KEYS=\$T/keys2; good_sig \"\$T/www/SHA256SUMS.gpg\" \"\$T/www/SHA256SUMS\""' _ "$T" "$HERE/bin/distro-vm-session"
else
    echo "  ok    skipped the signature checks: no gpg or python3"
fi

# ---- the session refuses to be anyone else, and takes its network from root's file
out=$(bash "$SESSION" status 2>&1)
check "the session refuses to run as a user that isn't one of the VMs'" grep -q 'only for the distro-vm users' <<<"$out"
check "the session's network comes from root's file, never from the caller" \
    not grep -qE 'MODE=\$\{?[0-9]|MODE=\$\{?1' "$SESSION"
check "Tails runs on the direct network, whatever the file says" grep -qx '\[ "$NAME" != tails \] || MODE=direct' "$SESSION"
check "the VM's screen is a Unix socket, and no agent channel (clipboard, files) is set up" bash -c '
    grep -q -- "-spice \"unix=on" "$1" && ! grep -qE "vdagent|spicevmc|usb-redir|-audio|-soundhw" "$1"' _ "$SESSION"
check "QEMU runs under its syscall filter" grep -q -- '-sandbox "on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny"' "$SESSION"
check "no port of the guest is forwarded to this computer" not grep -q 'hostfwd' "$SESSION"
check "the net check runs before a start and before a download, and keeps watch while it runs" bash -c '
    [ "$(sed -n "/^start() {/,/^}/p" "$1" | grep -c netcheck_or_die)" -ge 1 ] &&
    [ "$(sed -n "/^fetch() {/,/^}/p" "$1" | grep -c netcheck_or_die)" -ge 1 ] &&
    sed -n "/^start() {/,/^}/p" "$1" | grep -q "kill \"\$pid\""' _ "$SESSION"

# ---- the extra
check "the sudo rule it writes passes visudo, and names only the VMs' users" bash -c '
    command -v visudo >/dev/null || PATH=$PATH:/usr/sbin; command -v visudo >/dev/null || exit 0
    OWNER=me SESSION=/usr/local/libexec/distro-vm-session chosen=(kali arch)
    eval "$(grep -A1 "^    printf .# Written by Wren Linux extras/distro-vm.sh. %s may run" "$1" | sed "s/>\"\$rule\"\$/>\"\$2\"/")"
    visudo -cf "$2" && grep -qx "me ALL=(dvm-kali,dvm-arch) NOPASSWD: /usr/local/libexec/distro-vm-session" "$2"' _ "$EXTRA" "$T/sudoers"
check "the summary fits the list (52 characters at most)" test "$(sed -n 's/^# summary: //p' "$EXTRA" | wc -L)" -le 52
check "--remove takes the firewall, the sudo rule, the keys and the Tor block out" bash -c '
    r=$(sed -n "/--remove ]; then/,/^fi/p" "$1")
    for w in "nft delete table inet wren_distro_vm" "\$SUDOERS" "\$KEYS" "\$BEGIN" "remove_bin distro-vm"; do grep -qF "$w" <<<"$r" || exit 1; done' _ "$EXTRA"
check "parts/sandbox-dns.sh fills its DNS set" grep -q 'wren-distro-vm-firewall' "$HERE/parts/sandbox-dns.sh"
check "the Tor service is kept while it is in use (lib/tor.sh's marks)" grep -q '\.wren-distro-vm' "$HERE/lib/tor.sh"
check "the Tor ports in the rule are the ones written into torrc" bash -c '
    grep -qx "TRANS_PORT=9041" "$1" && grep -qx "DNS_PORT=9054" "$1" &&
    grep -q "redirect to :9041" "$2" && grep -q "redirect to :9054" "$2"' _ "$EXTRA" "$FW"

[ "$fails" -eq 0 ]
