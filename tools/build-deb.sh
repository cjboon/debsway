#!/bin/bash
# build-deb.sh: builds the Wren Linux package (.deb) from a git commit, never from
# files that aren't committed. It installs Wren Linux root-owned and read-only in
# /usr/share/wren, the Wren Linux command in /usr/bin, its man page and Tab
# completion; nothing else. It has no install scripts: installing it changes
# no setting and runs nothing as root. The parts and extras still run as you,
# from /usr/share/wren, when you ask for them (wrenctl part NAME, Wren Linux
# install NAME). The same commit always gives the same file, byte for byte
# (every date is the commit's), so anyone can check a published package
# against the source: build it again and compare the SHA-256.
#   bash tools/build-deb.sh [--commit REV] [--version VERSION] [--out FOLDER]
# Defaults: HEAD; a version from the commit's date and id (0~gitYYYYMMDD.ID);
# the current folder. Needs dpkg-deb and git only; lintian checks the result if
# it is installed. Changes nothing outside FOLDER and a temp folder.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

die() { printf 'build-deb: %s\n' "$*" >&2; exit 1; }

rev=HEAD version='' out=$PWD
while [ $# -gt 0 ]; do
    case $1 in
        --commit) rev=${2:?}; shift 2 ;;
        --version) version=${2:?}; shift 2 ;;
        --out) out=${2:?}; shift 2 ;;
        *) die "usage: build-deb.sh [--commit REV] [--version VERSION] [--out FOLDER]" ;;
    esac
done
command -v dpkg-deb >/dev/null || die "dpkg-deb is missing (package dpkg)."
g() { git -C "$HERE" "$@"; }
commit=$(g rev-parse --verify --quiet "$rev^{commit}") || die "no commit $rev here."
# every date in the package is the commit's: the same commit, the same file
SOURCE_DATE_EPOCH=$(g log -1 --format=%ct "$commit")
export SOURCE_DATE_EPOCH
if [ -z "$version" ]; then
    version="0~git$(date -u -d "@$SOURCE_DATE_EPOCH" +%Y%m%d).$(g rev-parse --short=10 "$commit")"
fi
[[ $version =~ ^[0-9][A-Za-z0-9.+~-]*$ ]] || die "a Debian version starts with a digit and has only letters, digits and . + ~ -: $version"
maint=$(g log -1 --format='%an <%ae>' "$commit")

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
R=$T/root
SHARE=$R/usr/share/wren
mkdir -p "$SHARE"
# What is committed, nothing else; not the project's own CI and notes, and not what
# only someone working on Wren Linux uses, which wren-dev's git copy has: the tests
# and build tools, the plans, and the signing key's tools (with their sudo rule and
# user). data/wren-signing-key.asc stays: every computer checks updates with it.
g archive --format=tar "$commit" | tar -C "$SHARE" -xf -
rm -rf "$SHARE/.github" "$SHARE/.gitignore" "$SHARE/CLAUDE.md" "$SHARE/tools" \
    "$SHARE/docs/maintaining.md" "$SHARE/docs/distro-plan.md" \
    "$SHARE/extras/signing-key.sh" "$SHARE/docs/extras/signing-key.md" \
    "$SHARE/bin/wren-key" "$SHARE/bin/wren-key-gpg" "$SHARE/bin/wren-signer" \
    "$SHARE/data/wren-key.1" "$SHARE/data/signer-firewall.nft"
sed -i '/(signing-key\.md)/d' "$SHARE/docs/extras/README.md"

# The command, its man page and its Tab completion where Debian looks for them
install -D -m 0755 "$SHARE/bin/wrenctl" "$R/usr/bin/wrenctl"
mkdir -p "$R/usr/share/man/man1"
gzip -9n <"$SHARE/data/wrenctl.1" >"$R/usr/share/man/man1/wrenctl.1.gz"
install -D -m 0644 "$SHARE/data/wrenctl-completion.bash" "$R/usr/share/bash-completion/completions/wrenctl"

# Debian's documentation files: the licenses, and a changelog
DOC=$R/usr/share/doc/wren-linux
mkdir -p "$DOC"
{
    echo "Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/"
    echo "Upstream-Name: Wren Linux"
    echo "Source: https://github.com/cjboon/wren-linux"
    echo
    echo "Files: *"
    echo "Copyright: the Wren Linux authors"
    echo "License: MIT"
    echo
    echo "Files: usr/share/wren/vendor/mockvps-kvm/*"
    echo "Copyright: the mockvps-kvm authors"
    echo "License: MIT"
    echo
    echo "License: MIT"
    sed 's/^$/./; s/^/ /' "$SHARE/LICENSE"
} >"$DOC/copyright"
{
    echo "wren-linux ($version) unstable; urgency=medium"
    echo
    echo "  * Built from commit $commit."
    echo
    echo " -- $maint  $(date -u -R -d "@$SOURCE_DATE_EPOCH")"
} | gzip -9n >"$DOC/changelog.gz"

# Root's files, read-only to everyone else: directories 0755, files 0644, and
# 0755 only for what git records as executable (a USB copy can lose the bit,
# git can't). Nothing setuid, nothing writable by others.
find "$R" -type d -exec chmod 0755 {} +
find "$R" -type f -exec chmod 0644 {} +
chmod 0755 "$R/usr/bin/wrenctl"
while IFS= read -r f; do
    chmod 0755 "$SHARE/$f"
done < <(g ls-tree -r "$commit" | awk '$1 == "100755" { sub(/^[^\t]*\t/, ""); print }' | grep -vx -e '.github/.*' -e CLAUDE.md || true)

mkdir -p "$R/DEBIAN"
installed_kb=$(du -sk --exclude=DEBIAN "$R" | cut -f1)
cat >"$R/DEBIAN/control" <<EOF
Package: wren-linux
Version: $version
Architecture: all
Maintainer: $maint
Installed-Size: $installed_kb
Depends: bash, sudo
Recommends: gpg, git, wget, python3, acl, nftables, bash-completion
Section: admin
Priority: optional
Homepage: https://github.com/cjboon/wren-linux
Description: small, privacy-minded sway desktop for Debian, as plain scripts
 Wren Linux turns a bare Debian 13 install into a small sway desktop with careful
 defaults: a firewall, kernel hardening, automatic security updates, encrypted
 DNS, and sandboxes for the browser, coding assistants and media. It is shell
 scripts you can read; this package puts them, root-owned, in
 /usr/share/wren, with the wrenctl command. Installing it changes nothing
 else: run "wrenctl" to set up the desktop and its optional programs.
EOF
(cd "$R" && find . -path ./DEBIAN -prune -o -type f -print0 | sort -z | xargs -0 md5sum | sed 's|  \./|  |') >"$R/DEBIAN/md5sums"
chmod 0755 "$R/DEBIAN"
chmod 0644 "$R/DEBIAN/control" "$R/DEBIAN/md5sums"
# the same date on every file, so the archive is the same each time
find "$R" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +

mkdir -p "$out"
deb=$out/wren-linux_${version}_all.deb
dpkg-deb --root-owner-group -Zxz --build "$R" "$deb" >/dev/null
echo "$deb"
sha256sum "$deb" | cut -d' ' -f1 | sed 's/^/SHA-256: /'
if command -v lintian >/dev/null; then
    lintian --no-tag-display-limit "$deb" || echo "(lintian has remarks: see above)"
else
    echo "(lintian isn't installed, so the package wasn't checked by it: wrenctl install wren-dev)"
fi
