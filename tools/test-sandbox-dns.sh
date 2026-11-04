#!/bin/bash
# Checks that Wren Linux's sandbox users send DNS only to this computer's
# resolver: every sandbox's firewall rule takes port 53 only to its
# "resolvers" set; the helper (bin/sandbox-dns-update) fills each such set
# with the IPv4 resolvers in /etc/resolv.conf and nothing else, and touches
# no other table; the part (parts/sandbox-dns.sh) runs it at boot, when
# resolv.conf changes and after each sandbox's firewall loads. A pretend nft
# and sudo; nothing outside a temp folder changes. Run by test.sh, or:
#   bash tools/test-sandbox-dns.sh
# shellcheck disable=SC2016  # the inner shells and pretend programs expand their own variables
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

# ---- every sandbox's rule ----
RULES=(claude claude-vm firefox incognito onion-site opencode-vm wifi-signin yt-dlp)
for r in "${RULES[@]}"; do
    f=$HERE/data/$r-firewall.nft
    body=$(grep -v '^[[:space:]]*#' "$f")
    check "$r: DNS only to its resolvers set, no port 53 to anywhere else" bash -c '
        grep -qx "    set resolvers {" <<<"$1" && grep -qx "        type ipv4_addr" <<<"$1" &&
        grep -qx "        ip daddr @resolvers udp dport 53 accept" <<<"$1" && grep -qx "        ip daddr @resolvers tcp dport 53 accept" <<<"$1" &&
        [ "$(grep -c "dport 53" <<<"$1")" = 2 ]' _ "$body"
done
if PATH=/usr/sbin:/sbin:$PATH command -v nft >/dev/null && unshare -rn true 2>/dev/null; then
    for r in "${RULES[@]}"; do
        # nft looks user names up as it loads; root stands in for the sandbox user here
        sed -E 's/meta skuid "[a-z-]+"/meta skuid 0/; s/meta skgid "[a-z-]+"/meta skgid 0/' "$HERE/data/$r-firewall.nft" >"$T/$r.nft"
        check "$r: Debian's nft takes it" env PATH="/usr/sbin:/sbin:$PATH" unshare -rn nft -c -f "$T/$r.nft"
    done
fi

# ---- the helper ----
H=$HERE/bin/sandbox-dns-update
# a pretend nft: two Wren Linux tables with a resolvers set, one without, one not Wren Linux's
cat >"$T/nft" <<EOF
#!/bin/bash
case "\$*" in
    "list tables") printf '%s\n' "table inet wren_firefox" "table inet wren_secure_dns" "table inet wren_ytdlp" "table ip other" ;;
    "list set inet wren_firefox resolvers" | "list set inet wren_ytdlp resolvers") exit 0 ;;
    "list set "*) exit 1 ;;
    "-f "*) cp "\$2" "$T/applied" ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$T/nft"
up() { rm -f "$T/applied"; printf '%s\n' "$@" >"$T/resolv.conf"; WREN_RESOLV_CONF=$T/resolv.conf WREN_NFT=$T/nft bash "$H"; }

up "# Written by Wren Linux parts/secure-dns.sh" "nameserver 127.0.0.1"
check "secure DNS on: each sandbox's set holds Unbound (127.0.0.1) alone" bash -c '
    [ "$(cat "$1")" = "$(printf "%s\n" "flush set inet wren_firefox resolvers" "add element inet wren_firefox resolvers { 127.0.0.1 }" "flush set inet wren_ytdlp resolvers" "add element inet wren_ytdlp resolvers { 127.0.0.1 }")" ]' _ "$T/applied"
check "...and no table without such a set, and none that isn't Wren Linux's, is touched" bash -c '! grep -qE "wren_secure_dns|other" "$1"' _ "$T/applied"
up "nameserver 192.168.1.1" "nameserver fe80::1%wlan0" "nameserver 192.168.1.1" "nameserver 10.0.0.53" "search lan" "nameserver 999.1.1.1" "nameserver 1.2.3.4; reboot"
check "secure DNS off: the network's resolvers, once each; no IPv6, no address that isn't one" grep -qx 'add element inet wren_firefox resolvers { 192.168.1.1,10.0.0.53 }' "$T/applied"
up "search lan"
check "no resolver at all: the sets are emptied (no DNS), nothing added" bash -c '[ "$(grep -c "^flush set" "$1")" = 2 ] && ! grep -q "add element" "$1"' _ "$T/applied"
printf '#!/bin/bash\ncase "$*" in "list tables") echo "table ip other" ;; "-f "*) touch "%s/applied" ;; *) exit 1 ;; esac\n' "$T" >"$T/nft"
up "nameserver 127.0.0.1"
check "no sandbox set up: nothing is loaded" test ! -e "$T/applied"

# ---- the part ----
mkdir -p "$T/bin" "$T/home" "$T/files"
cat >"$T/bin/sudo" <<EOF
#!/bin/bash
echo "sudo \$*" >>"$T/calls"
case \$1 in
    -v | -k | systemctl) exit 0 ;;
    tee) mkdir -p "$T/files\$(dirname "\$2")" && cat >"$T/files\$2" ;;
    install) shift; args=(); dir=false; while [ \$# -gt 0 ]; do case \$1 in -o | -g | -m) shift 2 ;; -d) dir=true; shift ;; *) args+=("\$1"); shift ;; esac; done
             \$dir && exit 0; mkdir -p "$T/files\$(dirname "\${args[-1]}")" && cp "\${args[0]}" "$T/files\${args[-1]}" ;;
    rm) exit 0 ;;
esac
EOF
chmod +x "$T/bin/sudo"
R=$T/r
mkdir -p "$R/parts" "$R/lib"
sed 's|^export PATH=.*|export PATH="$SD_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q SD_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
for f in pins.sh packages.sh data bin docs; do ln -s "$HERE/$f" "$R/$f"; done
for f in "$HERE"/lib/*; do ln -s "$f" "$R/lib/${f##*/}"; done
cp "$HERE/parts/sandbox-dns.sh" "$R/parts/"
export SD_TEST_PATH="$T/bin:$PATH"
: >"$T/calls"
HOME=$T/home bash "$R/parts/sandbox-dns.sh" >/dev/null 2>&1
F=$T/files/etc/systemd/system
check "the helper is installed as root's" bash -c 'cmp "$1" "$2/usr/local/libexec/wren-sandbox-dns" && grep -q "sudo install -o root -g root -m 0755 .*/bin/sandbox-dns-update /usr/local/libexec/wren-sandbox-dns" "$3"' _ "$H" "$T/files" "$T/calls"
check "it runs at boot, after the sandboxes' firewalls" bash -c '
    grep -qx "ExecStart=/usr/local/libexec/wren-sandbox-dns" "$1" && grep -q "^After=.*wren-firefox-firewall.service" "$1" && grep -qx "WantedBy=multi-user.target" "$1"' _ "$F/wren-sandbox-dns.service"
check "...whenever /etc/resolv.conf changes (a path unit, enabled)" bash -c '
    grep -qx "PathChanged=/etc/resolv.conf" "$1" && grep -q "sudo systemctl enable --now wren-sandbox-dns.path" "$2"' _ "$F/wren-sandbox-dns.path" "$T/calls"
missing=''
for u in wren-firefox-firewall wren-incognito-firewall wren-ytdlp-firewall wren-claude-firewall wren-claude-vm-firewall wren-opencode-vm-firewall wren-onion-site-firewall; do
    grep -qx "ExecStartPost=-/usr/local/libexec/wren-sandbox-dns" "$F/$u.service.d/60-wren-sandbox-dns.conf" 2>/dev/null || missing+=" $u"
done
check "...and right after each sandbox's firewall loads (which empties its set)${missing:+: missing$missing}" test -z "$missing"
# (the wallets' has no DNS at all: they reach Tor's port and nothing else)
units=$(grep -rhoE 'wren-[a-z-]+-firewall\.service' "$HERE/extras" "$HERE/parts" "$HERE/lib" | sort -u | grep -vE 'wren-(wallet|secure-dns|signer)-firewall' | sed 's/\.service$//' | paste -sd' ')
check "...every sandbox firewall service there is has that drop-in (the list is complete)" bash -c '
    for u in $1; do grep -q "$u" "$2" || { echo "$u"; exit 1; }; done' _ "$units" "$HERE/parts/sandbox-dns.sh"
check "it is in the base, after secure DNS" bash -c '. "$1/packages.sh"; [[ " ${PARTS[*]} " == *" secure-dns sandbox-dns "* ]]' _ "$HERE"

[ "$fails" -eq 0 ]
