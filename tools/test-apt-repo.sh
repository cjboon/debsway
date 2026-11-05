#!/bin/bash
# Checks tools/make-apt-repo.sh with throwaway keys and Debian's own apt, run
# as you against a repository in a temp folder (every apt folder is moved
# there; nothing of this computer's apt is read or changed): apt takes the
# repository signed with the pinned key, and refuses one signed with another
# key, one whose Valid-Until has passed, and one with a changed package list.
# Run by test.sh, or:  bash tools/test-apt-repo.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
# (gpg never looks in your own ~/.gnupg)
export GNUPGHOME=$T/.gnupg-default
mkdir -m 700 "$GNUPGHOME"
trap 'gpgconf --homedir "$T/gh" --kill all 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
for c in apt-ftparchive apt-get dpkg-deb gpg; do
    command -v "$c" >/dev/null || { echo "  ok    skipped: $c isn't installed"; exit 0; }
done

mkdir -m 700 "$T/gh"
[ -z "${GPG_AGENT_PROGRAM:-}" ] || echo "agent-program $GPG_AGENT_PROGRAM" >"$T/gh/gpg.conf"
export GNUPGHOME=$T/gh
G=(gpg --batch --quiet --pinentry-mode loopback --passphrase '')
fpr_of() { "${G[@]}" --list-keys --with-colons "$1" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }'; }
# as docs/maintaining.md says: a primary key that certifies, a subkey that signs
"${G[@]}" --quick-generate-key pinned@test ed25519 cert 1y
"${G[@]}" --quick-add-key "$(fpr_of pinned@test)" ed25519 sign 1y
"${G[@]}" --quick-generate-key other@test ed25519 sign 1y
FPIN=$(fpr_of pinned@test) FOTHER=$(fpr_of other@test)
if [ -z "$FPIN" ] || [ -z "$FOTHER" ]; then
    echo "  ok    skipped: gpg couldn't make test keys here (is gpg-agent installed?)"
    exit 0
fi
# gpg in the tools signs without asking (the test keys have no passphrase)
mkdir -p "$T/bin"
printf '#!/bin/sh\nexec /usr/bin/gpg --pinentry-mode loopback --passphrase "" "$@"\n' >"$T/bin/gpg"
chmod +x "$T/bin/gpg"
export PATH="$T/bin:$PATH"

# Two packages to publish: Wren Linux, and one that isn't Wren Linux's
mkdir -p "$T/p/DEBIAN" "$T/q/DEBIAN"
chmod 0755 "$T/p" "$T/p/DEBIAN" "$T/q" "$T/q/DEBIAN"
printf 'Package: wren-linux\nVersion: 1.0\nArchitecture: all\nMaintainer: t <t@t>\nDescription: test\n' >"$T/p/DEBIAN/control"
printf 'Package: openssl\nVersion: 99\nArchitecture: all\nMaintainer: t <t@t>\nDescription: test\n' >"$T/q/DEBIAN/control"
chmod 0644 "$T/p/DEBIAN/control" "$T/q/DEBIAN/control"
dpkg-deb --root-owner-group --build "$T/p" "$T/wren-linux_1.0_all.deb" >/dev/null
dpkg-deb --root-owner-group --build "$T/q" "$T/openssl_99_all.deb" >/dev/null

# (a copy with no key pinned, as before any: this checkout may pin the real one by now)
mkdir -p "$T/m/tools"
cp "$HERE/tools/make-apt-repo.sh" "$T/m/tools/"
sed 's/^WREN_SIGNING_FPR=.*/WREN_SIGNING_FPR=/' "$HERE/pins.sh" >"$T/m/pins.sh"
M=$T/m/tools/make-apt-repo.sh
sed "s/^WREN_SIGNING_FPR=.*/WREN_SIGNING_FPR=$(printf 'A%.0s' {1..40})/" "$HERE/pins.sh" >"$T/pinned.sh"
mkdir -p "$T/mp/tools"; cp "$HERE/tools/make-apt-repo.sh" "$T/mp/tools/"; cp "$T/pinned.sh" "$T/mp/pins.sh"
check "with a key pinned, it refuses to sign with another: every computer would refuse that" bash -c '
    out=$(bash "$1/tools/make-apt-repo.sh" --key "$(printf "B%.0s" {1..40})" --out "$1/r" "$2" 2>&1); [ $? -ne 0 ] && grep -q "would be refused" <<<"$out"' _ "$T/mp" "$T/wren-linux_1.0_all.deb"
mk() { bash "$M" --out "$T/repo" "$@" >"$T/mk.out" 2>&1; }
check "it refuses a package that isn't Wren Linux's" bash -c '! bash "$1" --key "$2" --out "$3/r2" "$3/openssl_99_all.deb"' _ "$M" "$FPIN" "$T"
check "it refuses a key that isn't a full fingerprint" bash -c '! bash "$1" --key ABCD --out "$2/r2" "$2/wren-linux_1.0_all.deb"' _ "$M" "$T"

# apt, as you, with every folder of its own under $T/apt
A=$T/apt
mkdir -p "$A/etc/sources.list.d" "$A/etc/preferences.d" "$A/etc/apt.conf.d" "$A/state/lists/partial" "$A/cache/archives/partial"
APT=(-o Dir::Etc="$A/etc" -o Dir::Etc::sourcelist=/dev/null -o Dir::Etc::sourceparts="$A/etc/sources.list.d"
    -o Dir::Etc::preferencesparts="$A/etc/preferences.d" -o Dir::Etc::parts="$A/etc/apt.conf.d"
    -o Dir::State="$A/state" -o Dir::Cache="$A/cache" -o Dir::State::status=/dev/null
    -o Debug::NoLocking=1 -o APT::Sandbox::User="$(id -un)" -o APT::Architecture=amd64)
# trust exactly KEYFILE for the repository, as the Wren Linux computers will
trusting() { echo "deb [signed-by=$1] file://$T/repo trixie main" >"$A/etc/sources.list.d/wren.list"; }
fresh() { rm -rf "$A/state/lists"; mkdir -p "$A/state/lists/partial"; }
takes() { # apt update succeeds, with no warning, and Wren Linux 1.0 is there
    fresh
    apt-get "${APT[@]}" update >"$T/apt.out" 2>&1 && ! grep -qE '^(W|E):' "$T/apt.out" &&
        apt-cache "${APT[@]}" policy wren-linux 2>/dev/null | grep -q 'Candidate: 1.0'
}
"${G[@]}" --armor --export "$FPIN" >"$T/pinned.asc"

mk --key "$FPIN" "$T/wren-linux_1.0_all.deb"
check "a repository signed with the pinned key's signing subkey" grep -q "signed by $FPIN" "$T/mk.out"
trusting "$T/pinned.asc"
check "...apt takes it" takes
check "...and it gives the key with it" bash -c 'gpg --show-keys --with-colons "$1" | grep -q "^fpr:::::::::$2:"' _ "$T/repo/wren-archive-keyring.asc" "$FPIN"
check "...good for 14 days (Valid-Until)" bash -c '
    v=$(sed -n "s/^Valid-Until: //p" "$1"); d=$(( ($(date -d "$v" +%s) - $(date +%s)) / 86400 )); [ "$d" -ge 13 ] && [ "$d" -le 14 ]' _ "$T/repo/dists/trixie/Release"

# The same files, but apt trusts another key: refused
"${G[@]}" --armor --export "$FOTHER" >"$T/other.asc"
trusting "$T/other.asc"
fresh
apt-get "${APT[@]}" update >"$T/apt.out" 2>&1
check "trusting another key, apt refuses it (no package list)" bash -c '! apt-cache "$@" policy wren-linux 2>/dev/null | grep -q "Candidate: 1.0"' _ "${APT[@]}"
check "...because of the signature" grep -qE "NO_PUBKEY|not signed|couldn't be verified" "$T/apt.out"
trusting "$T/pinned.asc"

# A changed package list under the same signature: refused
cp -a "$T/repo" "$T/repo.good"
sed -i 's/^Version: 1.0$/Version: 9.9/' "$T/repo/dists/trixie/main/binary-amd64/Packages"
rm -f "$T/repo/dists/trixie/main/binary-amd64/Packages.gz" "$T/repo/dists/trixie/main/binary-amd64/Packages.xz"
fresh
apt-get "${APT[@]}" update >"$T/apt.out" 2>&1
check "a changed package list is refused" bash -c '! apt-cache "$@" policy wren-linux 2>/dev/null | grep -q "Candidate: 9.9"' _ "${APT[@]}"
check "...because it doesn't match what was signed" grep -qiE "hash sum mismatch|file has unexpected size" "$T/apt.out"
rm -rf "$T/repo"
mv "$T/repo.good" "$T/repo"

# Signed long ago, for one day: its Valid-Until has passed, so apt refuses it,
# as it would refuse a server that keeps serving an old set
mk --key "$FPIN" --valid-days 1 "$T/wren-linux_1.0_all.deb"
sed -i "s/^Valid-Until: .*/Valid-Until: $(LC_ALL=C date -u -R -d '-1 day')/" "$T/repo/dists/trixie/Release"
gpg --batch --yes --local-user "$FPIN" --clearsign -o "$T/repo/dists/trixie/InRelease" "$T/repo/dists/trixie/Release"
fresh
apt-get "${APT[@]}" update >"$T/apt.out" 2>&1
check "a repository past its Valid-Until is refused" bash -c '! apt-cache "$@" policy wren-linux 2>/dev/null | grep -q "Candidate: 1.0"' _ "${APT[@]}"
check "...and apt says why" grep -qi 'no longer valid\|expired' "$T/apt.out"

[ "$fails" -eq 0 ]
