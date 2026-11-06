#!/bin/bash
# publish-image.sh: builds the install image of a release, signs its checksums, and puts
# them on the server tools/setup-vps.sh set up, in /srv/wren-images/VERSION (at
# https://DOMAIN/images/VERSION/). Only from a commit with a release's signed tag
# (tools/tag-release.sh), so an image is always of something the key vouched for.
#  - The image is built with make-install-iso.sh --public: no name, time zone or saved
#    downloads of this computer's on it. It asks for the user's password at install.
#  - The image hands out Debian's programs, and the GPL asks that their source be offered
#    too, so Debian's source for that exact image goes beside it (about 3 GB; SOURCE.txt says
#    what's there), checked against Debian's signed list. No source, nothing is published.
#  - SHA256SUMS, all of it, is signed by Wren Linux's key, after your sudo password, so this
#    can't run unattended. That signature is checked with the pinned key alone before anything goes out.
#  - It's rebuilt only if you ask, and an image on the server is never replaced: a wrong
#    one gets a newer release.
#  - Same settings as publish-site.sh: --host, or VPS_HOST in ~/.config/wren/vps/site.conf
# The image isn't built byte for byte the same each time (the package on it is): what
# you can check is its signature, and that the Debian image under it was Debian's.
# Usage: bash tools/publish-image.sh [--host HOST] [--dry-run]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$WREN_DIR/lib/appimage.sh"
. "$WREN_DIR/lib/install-iso.sh"
not_root

g() { git -C "$WREN_DIR" "$@"; }
usage() { die "Usage: bash tools/publish-image.sh [--host HOST] [--dry-run]"; }
# (a test points these at pretend programs and a local folder)
RSYNC=${WREN_RSYNC:-rsync}
CONF=${XDG_CONFIG_HOME:-$HOME/.config}/wren/vps/site.conf
BUILD=${WREN_BUILD_IMAGE:-$WREN_DIR/prep/make-install-iso.sh}

host='' dry=false
while [ $# -gt 0 ]; do
    case $1 in
        --host) host=${2:-}; shift 2 || usage ;;
        --dry-run) dry=true; shift ;;
        *) usage ;;
    esac
done
if [ -z "$host" ] && [ -f "$CONF" ]; then
    host=$(sed -n 's/^VPS_HOST=//p' "$CONF" | head -n1)
fi
[ -n "$host" ] || die "Which server? --host wren-vps (the name from tools/vps-client.sh ssh-config), or VPS_HOST= in $CONF"
[[ $host =~ ^([a-z][a-z0-9-]{0,30}@)?[A-Za-z0-9][A-Za-z0-9.-]*$ ]] || die "\"$host\" isn't an ssh name (wren-vps, or user@address)."

g rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "$WREN_DIR isn't a git copy (wrenctl install wren-dev gets one)."
[ -n "${WREN_SIGNING_FPR:-}" ] || die "pins.sh pins no signing key, so nothing can be checked."
[ -x "$BIN/wren-key" ] || die "There is no signing key here. Make one: bash $WREN_DIR/extras/signing-key.sh"
[ -z "$(g status --porcelain --untracked-files=no)" ] || die "There are changes that aren't committed; the image is of a release."
version=$(g tag --points-at HEAD --list '[0-9][0-9][0-9][0-9].[0-9][0-9]*' --sort=-v:refname | grep -E '^[0-9]{4}\.[0-9]{2}(\.[0-9]+)?$' | head -n1) || version=
[ -n "$version" ] || die "This commit isn't a release. Make one first: bash $WREN_DIR/tools/tag-release.sh"
home=$(_keyring "$WREN_SIGNING_FPR" "$WREN_DIR/data/wren-signing-key.asc") || die "Couldn't read the pinned key."
GNUPGHOME=$home git -C "$WREN_DIR" -c gpg.format=openpgp -c gpg.program=gpg -c gpg.openpgp.program=gpg \
    verify-tag --raw "$version" >/dev/null 2>"$home/status" || true
_good_sig "$WREN_SIGNING_FPR" "$home/status" || { _keyring_done "$home"; die "Release $version's tag isn't signed by Wren Linux's key. Nothing was built."; }
_keyring_done "$home"

out=${XDG_CACHE_HOME:-$HOME/.cache}/wren/images/$version
name=wren-linux-$version-amd64.iso
mkdir -p "$out"
if [ -s "$out/$name" ] && ! ask "$out/$name is there already. Build it again?" n; then
    note "Using the one that's there."
else
    say "Building the image of $version"
    bash "$BUILD" --public --out "$out/$name" || die "The image wasn't built; nothing was published."
fi
[ -s "$out/$name" ] || die "The build named no image at $out/$name; nothing was published."

say "Debian's source for the image"
base=$(head -n1 "$out/DEBIAN-BASE.txt" 2>/dev/null) || base=
[ -n "$base" ] || die "The build didn't say which Debian image it used, so its source can't be found; nothing was published."
debian_live_source "$base" "$out" || die "Debian's source for the image isn't here, and the image shouldn't go out without it; nothing was published."
source=${base%-amd64-standard.iso}-source-standard
cat >"$out/SOURCE.txt" <<SOURCE
Where the source of this image is

Debian's programs on this image come from $base, unchanged.
Debian's source for it is right here: $source.tar
(what's in it: $source.contents). It's Debian's own, checked against the list
of checksums the Debian CD signing key signed.

Wren Linux's own files are MIT licensed. They are the commit tagged $version:
$WREN_GIT_URL
SOURCE
# the tag's message, the release notes, as plain text beside the image
g tag --list --format='%(contents:subject)%0a%0a%(contents:body)' "$version" | sed '/^-----BEGIN PGP/,$d' | printable >"$out/RELEASE-NOTES.txt"

say "Signing the checksums"
(cd "$out" && sha256sum "$name" "$source.tar" "$source.contents" SOURCE.txt DEBIAN-BASE.txt RELEASE-NOTES.txt >SHA256SUMS)
"$BIN/wren-key" detach-sign <"$out/SHA256SUMS" >"$out/SHA256SUMS.asc" || die "The key didn't sign them; nothing was published."
home=$(_keyring "$WREN_SIGNING_FPR" "$WREN_DIR/data/wren-signing-key.asc") || die "Couldn't read the pinned key."
gpg --homedir "$home" --batch --status-fd=2 --verify "$out/SHA256SUMS.asc" "$out/SHA256SUMS" >/dev/null 2>"$home/status" || true
_good_sig "$WREN_SIGNING_FPR" "$home/status" || { _keyring_done "$home"; die "That signature didn't check out with the pinned key; nothing was published."; }
_keyring_done "$home"
note "The image's SHA-256: $(sha256sum "$out/$name" | cut -d' ' -f1)"

dest=${WREN_PUBLISH_IMAGES:-$host:/srv/wren-images/}$version/
say "Copying it to $host"
# --ignore-existing: what's on the server already is never replaced
flags=(-rlt --ignore-existing "--chmod=D755,F644")
if $dry; then flags+=(--dry-run); fi
[ -n "${WREN_RSYNC:-}" ] || need_tools rsync:rsync
"$RSYNC" "${flags[@]}" -e ssh "$out/" "$dest" || die "The copy didn't go through (can you log in? ssh $host)."
if $dry; then note "(--dry-run: nothing was copied)"; exit 0; fi
note "Published $name to $host, in images/$version/."
