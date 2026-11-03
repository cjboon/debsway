#!/bin/bash
# Checks parts/wren-repo.sh (Wren Linux's own apt repository) with a pretend
# sudo (install and tee go into a temp folder, the rest is logged) and
# throwaway keys, in a copy of Wren Linux whose pins.sh the test fills in: nothing
# until the key and the address are pinned; then the pinned key only, trusted
# for that repository only, and an apt pin that lets nothing but Wren Linux come
# from it. Nothing on this computer changes. Run by test.sh, or:
#   bash tools/test-wren-repo.sh
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

mkdir -m 700 "$T/gh"
for n in good other; do
    gpg --homedir "$T/gh" --batch --quiet --passphrase '' --quick-gen-key "$n <$n@test>" ed25519 sign 1y 2>/dev/null
    gpg --homedir "$T/gh" --batch --armor --export "$n@test" >"$T/$n.asc"
done
GOOD=$(gpg --show-keys --with-colons "$T/good.asc" | awk -F: '/^fpr/ { print $10; exit }')
[ -n "$GOOD" ] || { echo "  ok    skipped: gpg couldn't make test keys here"; exit 0; }

# A copy of Wren Linux to change pins.sh and the key file in
mkdir "$T/d"
(cd "$HERE" && git ls-files -co --exclude-standard | tar -cf - -T -) | tar -C "$T/d" -xf -
mkdir -p "$T/bin" "$T/root" "$T/home"
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
chmod +x "$T/bin/sudo"
P=$T/d/parts/wren-repo.sh
run() { : >"$T/calls"; HOME="$T/home" WREN_SUDO="$T/bin/sudo" bash "$P" "$@" >"$T/out" 2>&1; }
pin() { sed -i "s|^WREN_SIGNING_FPR=.*|WREN_SIGNING_FPR=$1|; s|^WREN_REPO_URL=.*|WREN_REPO_URL=$2|" "$T/d/pins.sh"; }
R=$T/root
KEY=$R/usr/share/keyrings/wren-archive-keyring.asc
LIST=$R/etc/apt/sources.list.d/wren.sources
PREF=$R/etc/apt/preferences.d/wren.pref

check "pins.sh has the two lines, empty for now" bash -c 'grep -qx "WREN_SIGNING_FPR=" "$1" && grep -qx "WREN_REPO_URL=" "$1"' _ "$HERE/pins.sh"
run
check "nothing pinned: it changes nothing, and says why" bash -c '[ -z "$(ls -A "$1")" ] && grep -q "isn.t set up yet" "$2"' _ "$R" "$T/out"

cp "$T/good.asc" "$T/d/data/wren-signing-key.asc"
pin "$GOOD" "http://example.org/debian"
run
check "an address that is neither https nor .onion is refused" bash -c '[ -z "$(ls -A "$1")" ]' _ "$R"

cp "$T/other.asc" "$T/d/data/wren-signing-key.asc"
pin "$GOOD" "https://example.org/debian"
run
check "a key file that isn't the pinned key: nothing goes in" bash -c '[ -z "$(ls -A "$1")" ] && grep -q "isn.t exactly the pinned key" "$2"' _ "$R" "$T/out"

cp "$T/good.asc" "$T/d/data/wren-signing-key.asc"
run
check "the pinned key goes in, as the repository's only key" cmp "$T/good.asc" "$KEY"
check "...the repository, trusted with that key alone" bash -c '
    grep -qx "URIs: https://example.org/debian" "$1" && grep -qx "Signed-By: /usr/share/keyrings/wren-archive-keyring.asc" "$1" && grep -qx "Suites: trixie" "$1"' _ "$LIST"
check "...an apt pin: only Wren Linux from it, everything else there never" bash -c '
    [ "$(grep -v "^#" "$1" | paste -sd"|")" = "Package: wren-linux|Pin: origin example.org|Pin-Priority: 500||Package: *|Pin: origin example.org|Pin-Priority: -1" ]' _ "$PREF"
check "...and unattended-upgrades takes its updates" grep -q 'site=example.org' "$R/etc/apt/apt.conf.d/52wren-wren-linux"
pin "$GOOD" "http://abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrstuvwx.onion/debian"
run
check "an onion address is taken too" grep -qx "URIs: http://abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrstuvwx.onion/debian" "$LIST"
# The pin as written, with Debian's own apt (as you, every apt folder in $T):
# a repository at 127.0.0.1 that offers Wren Linux and an "openssl", served by a
# web server on this computer's loopback only
if command -v apt-ftparchive >/dev/null && command -v python3 >/dev/null; then
    pin "$GOOD" "https://127.0.0.1/debian"
    run
    E=$T/pinrepo
    mkdir -p "$E/repo/pool" "$E/repo/dists/trixie/main/binary-amd64"
    for pv in wren-linux:1.0 openssl:99; do
        mkdir -p "$E/${pv%%:*}/DEBIAN"
        chmod 0755 "$E/${pv%%:*}" "$E/${pv%%:*}/DEBIAN"
        printf 'Package: %s\nVersion: %s\nArchitecture: all\nMaintainer: t <t@t>\nDescription: t\n' "${pv%%:*}" "${pv#*:}" >"$E/${pv%%:*}/DEBIAN/control"
        chmod 0644 "$E/${pv%%:*}/DEBIAN/control"
        dpkg-deb --root-owner-group --build "$E/${pv%%:*}" "$E/repo/pool/${pv%%:*}.deb" >/dev/null
    done
    (cd "$E/repo" && apt-ftparchive packages pool >dists/trixie/main/binary-amd64/Packages &&
        apt-ftparchive -o APT::FTPArchive::Release::Suite=trixie -o APT::FTPArchive::Release::Codename=trixie \
            release dists/trixie >"$E/Release" && mv "$E/Release" dists/trixie/Release)
    port=$(python3 -I -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
    (cd "$E/repo" && exec python3 -I -m http.server --bind 127.0.0.1 "$port" >/dev/null 2>&1) &
    server=$!
    A=$E/apt
    mkdir -p "$A/etc/sources.list.d" "$A/etc/preferences.d" "$A/etc/apt.conf.d" "$A/state/lists/partial" "$A/cache/archives/partial"
    # (trusted=yes: the signature is tools/test-apt-repo.sh's to check; this is the pin)
    echo "deb [trusted=yes] http://127.0.0.1:$port trixie main" >"$A/etc/sources.list.d/wren.list"
    APT=(-o Dir::Etc="$A/etc" -o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts="$A/etc/sources.list.d"
        -o Dir::Etc::preferencesparts="$A/etc/preferences.d" -o Dir::Etc::parts="$A/etc/apt.conf.d"
        -o Dir::State="$A/state" -o Dir::Cache="$A/cache" -o Dir::State::status=/dev/null
        -o Debug::NoLocking=1 -o APT::Sandbox::User="$(id -un)" -o APT::Architecture=amd64)
    # (until the server answers: apt can end without an error when it couldn't reach one)
    for _ in $(seq 50); do (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && break; /bin/sleep 0.1; done
    apt-get "${APT[@]}" update >/dev/null 2>&1
    cand() { apt-cache "${APT[@]}" policy "$1" 2>/dev/null | sed -n 's/^  Candidate: //p'; }
    check "real apt, without the pin: the repository could bring openssl (so the next check means something)" test "$(cand openssl)" = 99
    cp "$PREF" "$A/etc/preferences.d/wren.pref"
    check "real apt, with the part's pin: openssl can't come from it" test "$(cand openssl)" = "(none)"
    check "...and Wren Linux still can" test "$(cand wren-linux)" = 1.0
    kill "$server" 2>/dev/null
fi

run --remove
check "--remove takes the key, the repository, the pin and the update rule out" bash -c '[ -z "$(find "$1" -type f)" ]' _ "$R"

[ "$fails" -eq 0 ]
