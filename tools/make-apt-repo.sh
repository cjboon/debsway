#!/bin/bash
# make-apt-repo.sh: a signed apt repository of debsway's packages, made on
# your own computer with your own key, never on the server. What you upload
# (the website, a mirror) is only files: whoever runs that server can hold
# updates back, or serve an older signed set until it expires, but can't
# change a package, because apt checks every file against InRelease, and
# InRelease against your key.
#   bash tools/make-apt-repo.sh --key FINGERPRINT --out FOLDER DEB...
#     [--valid-days N]   InRelease is good for N days (default 14): sign again
#                        within that time, or apt stops taking the repository
#                        (so a server can't keep serving an old, fixed hole)
# FOLDER gets pool/ and dists/trixie/ for amd64 (debsway's packages are for every
# architecture), and the key as debsway-archive-keyring.asc. Any older
# repository in FOLDER is replaced. Needs apt-ftparchive (apt-utils) and gpg
# with the key's secret part (gpg asks for its passphrase or token).
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../pins.sh
. "$HERE/pins.sh"

die() { printf 'make-apt-repo: %s\n' "$*" >&2; exit 1; }
usage="usage: make-apt-repo.sh --key FINGERPRINT --out FOLDER [--valid-days N] DEB..."

key='' out='' days=14 debs=()
while [ $# -gt 0 ]; do
    case $1 in
        --key) key=${2:?$usage}; shift 2 ;;
        --out) out=${2:?$usage}; shift 2 ;;
        --valid-days) days=${2:?$usage}; shift 2 ;;
        -*) die "$usage" ;;
        *) debs+=("$1"); shift ;;
    esac
done
[ -n "$key" ] && [ -n "$out" ] && [ ${#debs[@]} -gt 0 ] || die "$usage"
[[ $key =~ ^[0-9A-F]{40}$ ]] || die "the key is its full fingerprint: 40 hexadecimal digits, in capitals."
[[ $days =~ ^[0-9]+$ ]] && [ "$days" -ge 1 ] && [ "$days" -le 90 ] || die "--valid-days is 1 to 90."
command -v apt-ftparchive >/dev/null || die "apt-ftparchive is missing: sudo apt install apt-utils"
command -v gpg >/dev/null || die "gpg is missing."
# Only the key the debsway computers pin: a repository signed with another
# would only make every one of them refuse it
if [ -n "${DEBSWAY_SIGNING_FPR:-}" ] && [ "$key" != "$DEBSWAY_SIGNING_FPR" ]; then
    die "pins.sh pins $DEBSWAY_SIGNING_FPR; a repository signed with $key would be refused by every debsway computer."
fi
gpg --batch --list-secret-keys "$key" >/dev/null 2>&1 || die "gpg has no secret key $key here."
for d in "${debs[@]}"; do
    [ -f "$d" ] || die "no file $d"
    p=$(dpkg-deb -f "$d" Package 2>/dev/null) || die "$d isn't a package."
    case $p in debsway | debsway-*) ;; *) die "$d is $p, not one of debsway's packages." ;; esac
done

mkdir -p "$out"
out=$(cd "$out" && pwd)
rm -rf "$out/pool" "$out/dists"
mkdir -p "$out/pool/main" "$out/dists/$DEBIAN_RELEASE/main/binary-amd64"
for d in "${debs[@]}"; do
    p=$(dpkg-deb -f "$d" Package)
    mkdir -p "$out/pool/main/${p:0:1}/$p"
    cp "$d" "$out/pool/main/${p:0:1}/$p/"
done
(
    cd "$out"
    apt-ftparchive packages pool >"dists/$DEBIAN_RELEASE/main/binary-amd64/Packages"
    gzip -9nk "dists/$DEBIAN_RELEASE/main/binary-amd64/Packages"
    xz -kf "dists/$DEBIAN_RELEASE/main/binary-amd64/Packages"
    apt-ftparchive \
        -o APT::FTPArchive::Release::Origin=debsway \
        -o APT::FTPArchive::Release::Label=debsway \
        -o APT::FTPArchive::Release::Suite="$DEBIAN_RELEASE" \
        -o APT::FTPArchive::Release::Codename="$DEBIAN_RELEASE" \
        -o APT::FTPArchive::Release::Architectures=amd64 \
        -o APT::FTPArchive::Release::Components=main \
        -o APT::FTPArchive::Release::Description="debsway's own packages" \
        release "dists/$DEBIAN_RELEASE" >"$out/Release.tmp"
)
# Valid-Until: apt refuses the repository after that, so a server that keeps
# serving this set (with a hole that a later one fixed) is noticed
{
    sed -n '1,/^Date:/p' "$out/Release.tmp"
    echo "Valid-Until: $(LC_ALL=C date -u -R -d "+$days days")"
    sed '1,/^Date:/d' "$out/Release.tmp"
} >"$out/dists/$DEBIAN_RELEASE/Release"
rm -f "$out/Release.tmp"
gpg --batch --yes --local-user "$key" --clearsign -o "$out/dists/$DEBIAN_RELEASE/InRelease" "$out/dists/$DEBIAN_RELEASE/Release"
gpg --batch --yes --local-user "$key" --armor --detach-sign -o "$out/dists/$DEBIAN_RELEASE/Release.gpg" "$out/dists/$DEBIAN_RELEASE/Release"
gpg --batch --armor --export "$key" >"$out/debsway-archive-keyring.asc"

echo "Repository in $out, signed by $key, good until $(LC_ALL=C date -u -d "+$days days" +%Y-%m-%d)."
echo "Upload all of $out as it is (rsync -a --delete). Sign it again before then."
