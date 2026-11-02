#!/bin/bash
# Checks webtunnel for the system tor (lib/tor.sh): the Tor Project's
# repository goes in only with the pinned key; its apt pin lets lyrebird and
# nothing else come from it; it goes through Tor when apt does; it is taken
# away once lyrebird is gone; key_ok wants a key that can still sign; and
# apt over Tor, remote access and the onion site install lyrebird for it.
# Runs the library with a pretend sudo (install and tee go into the temp
# folder, the rest is logged), a pretend server serving throwaway keys and a
# pretend dpkg, so nothing on this computer changes.
# Run by test.sh, or:  bash tools/test-webtunnel.sh
# shellcheck disable=SC2016  # the pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v gpg >/dev/null || { echo "  ok    skipped: gpg isn't installed"; exit 0; }

T=$(mktemp -d)
trap 'gpgconf --homedir "$T/gh" --kill all 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

# Throwaway keys: the "pinned" one, another, and one that can only certify
# (no key in it can sign anything any more)
mkdir -m 700 "$T/gh"
for n in good other; do
    gpg --homedir "$T/gh" --batch --quiet --passphrase '' --quick-gen-key "$n <$n@test>" ed25519 sign never 2>/dev/null
    gpg --homedir "$T/gh" --batch --armor --export "$n@test" >"$T/$n.asc"
done
gpg --homedir "$T/gh" --batch --quiet --passphrase '' --quick-gen-key "cert <cert@test>" ed25519 cert never 2>/dev/null
gpg --homedir "$T/gh" --batch --armor --export "cert@test" >"$T/cert.asc"
fpr() { gpg --show-keys --with-colons "$1" | awk -F: '/^fpr/ { print $10; exit }'; }
GOOD=$(fpr "$T/good.asc") CERT=$(fpr "$T/cert.asc")

mkdir -p "$T/bin" "$T/root"
cat >"$T/bin/sudo" <<EOF
#!/bin/bash
[ "\$1" = -v ] && exit 0
echo "sudo \$*" >>"$T/calls"
case "\$1" in
    install) args=("\$@"); dest=\${args[-1]}; mkdir -p "$T/root\${dest%/*}"; args[-1]="$T/root\$dest"; "\${args[@]}" ;;
    tee) mkdir -p "\$(dirname "$T/root\$2")"; cat >"$T/root\$2" ;;
    rm) shift; for f in "\$@"; do [ "\$f" = -f ] || rm -f "$T/root\$f"; done ;;
esac
EOF
printf '#!/bin/sh\ncp "%s/served.asc" "$2"\n' "$T" >"$T/bin/wget"
# dpkg-query: lyrebird installed while $T/has-lyrebird exists
printf '#!/bin/sh\ncase "$*" in *lyrebird*) [ -e "%s/has-lyrebird" ] && echo "install ok installed" ;; *Status*) echo "install ok installed" ;; esac\n' "$T" >"$T/bin/dpkg-query"
chmod +x "$T/bin/"*

R=$T/r
mkdir -p "$R"
sed 's|^export PATH=.*|export PATH="$WT_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q WT_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
sed "s|^TORPROJECT_FPR=.*|TORPROJECT_FPR=$GOOD|" "$HERE/pins.sh" >"$R/pins.sh"
for f in packages.sh lib data docs bin; do ln -s "$HERE/$f" "$R/$f"; done
export WT_TEST_PATH="$T/bin:$PATH" HOME=$T/home DEBSWAY_ETC=$T/root/etc
mkdir -p "$HOME"
[ "$(bash -c '. "$1/lib.sh"; command -v sudo' _ "$R")" = "$T/bin/sudo" ] || { echo "  FAIL  the real sudo would run; stopping"; exit 1; }
lib() { : >"$T/calls"; bash -c '. "$1/lib.sh"; shift; "$@"' _ "$R" "$@" >"$T/out" 2>&1; }
LIST=$T/root/etc/apt/sources.list.d/debsway-torproject.list
PREF=$T/root/etc/apt/preferences.d/debsway-torproject.pref
KEY=$T/root/usr/share/keyrings/debsway-torproject.asc

cp "$T/other.asc" "$T/served.asc"
lib add_torproject_repo
check "a key that isn't the pinned one: nothing goes in" bash -c '[ ! -e "$1" ] && [ ! -e "$2" ] && [ ! -e "$3" ]' _ "$LIST" "$PREF" "$KEY"
cat "$T/good.asc" "$T/other.asc" >"$T/served.asc"
lib add_torproject_repo
check "...nor the pinned key with a second one next to it" test ! -e "$KEY"
cp "$T/good.asc" "$T/served.asc"
lib add_torproject_repo
check "the pinned key: it goes in" cmp "$T/good.asc" "$KEY"
cn=$(. /etc/os-release && echo "$VERSION_CODENAME")
check "...the repository, trusted with that key only, over https" \
    grep -qx "deb \[signed-by=/usr/share/keyrings/debsway-torproject.asc arch=$(dpkg --print-architecture)\] https://deb.torproject.org/torproject.org $cn main" "$LIST"
check "...updated by unattended-upgrades" grep -q 'site=deb.torproject.org' "$T/root/etc/apt/apt.conf.d/52debsway-torproject"
# the pin, as apt reads it: lyrebird at 500 and everything else from there at -1
check "...an apt pin: lyrebird from it, at 500" \
    python3 -I -c 'import sys; r = [dict(l.split(": ", 1) for l in b.splitlines() if not l.startswith("#")) for b in open(sys.argv[1]).read().strip().split("\n\n")]; assert {"Package": "lyrebird", "Pin": "origin deb.torproject.org", "Pin-Priority": "500"} in r' "$PREF"
check "...and every other package from it at -1 (never installed: Debian's tor stays)" \
    python3 -I -c 'import sys; r = [dict(l.split(": ", 1) for l in b.splitlines() if not l.startswith("#")) for b in open(sys.argv[1]).read().strip().split("\n\n")]; assert {"Package": "*", "Pin": "origin deb.torproject.org", "Pin-Priority": "-1"} in r and len(r) == 2' "$PREF"
mkdir -p "$T/root/etc/tor"; : >"$T/root/etc/tor/.debsway-apt-tor"
lib add_torproject_repo
check "apt over Tor, but lyrebird not here yet: still https (Tor can't connect without it)" grep -q ' https://deb.torproject.org' "$LIST"
: >"$T/has-lyrebird"
lib add_torproject_repo
check "...with lyrebird: through Tor" grep -q ' tor+https://deb.torproject.org' "$LIST"
rm "$T/root/etc/tor/.debsway-apt-tor"

lib remove_torproject_repo_if_unused
check "lyrebird still installed: the repository stays" test -e "$LIST"
rm "$T/has-lyrebird"
lib remove_torproject_repo_if_unused
check "lyrebird gone: the repository, its key, its pin and its update rule go" \
    bash -c '[ ! -e "$1" ] && [ ! -e "$2" ] && [ ! -e "$3" ] && [ ! -e "$4/etc/apt/apt.conf.d/52debsway-torproject" ]' _ "$LIST" "$PREF" "$KEY" "$T/root"

check "key_ok: the pinned key passes" bash -c '. "$1/lib.sh"; key_ok "$2" "$3"' _ "$R" "$T/good.asc" "$GOOD"
check "key_ok: a key that can no longer sign doesn't (its signing subkey expired)" \
    not bash -c '. "$1/lib.sh"; key_ok "$2" "$3"' _ "$R" "$T/cert.asc" "$CERT"

for s in parts/apt-tor.sh extras/remote-access.sh extras/onion-site.sh; do
    check "$s: webtunnel adds the repository, then installs the bridge's package" \
        python3 -I -c 'import sys; s = open(sys.argv[1]).read(); a = s.index("add_torproject_repo"); b = s.index("bridge_packages)"); i = s.index("apt_install \"${pkgs[@]}\""); assert a < b < i' "$HERE/$s"
    check "$s --remove: lyrebird, then the repository if nothing else wants it" \
        python3 -I -c 'import sys, re; s = open(sys.argv[1]).read(); p = re.search(r"apt_purge [^\n]*lyrebird", s); assert p and s.index("remove_torproject_repo_if_unused") > p.start()' "$HERE/$s"
done
check "apt over Tor sends the Tor Project's repository through Tor too" grep -q 'deb\\.torproject' "$HERE/parts/apt-tor.sh"

[ "$fails" -eq 0 ]
