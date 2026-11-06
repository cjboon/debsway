#!/bin/bash
# Checks tools/tag-release.sh and tools/publish-image.sh with a pretend server (a bare
# repository and a folder), throwaway keys, and pretend wren-key, image build and rsync: a tag
# signed by the pinned key, or none; the notes from the log; asked before it pushes; an image
# only of a signed release, with checksums the pinned key signed, and Debian's source for it,
# checked against a pretend Debian's signed list; nothing on the server replaced. Changes nothing outside a temp folder. Run by test.sh, or:
#   bash tools/test-tag-release.sh
# shellcheck disable=SC2016  # the inner shells and pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v gpg >/dev/null || { echo "  ok    skipped: gpg isn't installed"; exit 0; }
T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
export GNUPGHOME=$T/gh
trap 'gpgconf --kill all 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
export HOME=$T/home XDG_DATA_HOME='' XDG_CACHE_HOME='' XDG_CONFIG_HOME='' WREN_KEYS_ROOT=$T/no-keys
unset VISUAL EDITOR
mkdir -p "$HOME/.local/bin"
mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --passphrase '' --quick-gen-key "pinned <p@t>" ed25519 sign 1y 2>/dev/null
gpg --batch --quiet --passphrase '' --quick-gen-key "other <o@t>" ed25519 sign 1y 2>/dev/null
F=$(gpg --batch --with-colons --list-keys p@t 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }')
O=$(gpg --batch --with-colons --list-keys o@t 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }')
[ -n "$F" ] && [ -n "$O" ] || { echo "  ok    skipped: gpg couldn't make test keys here"; exit 0; }
SIGNER=$T/signer
cat >"$SIGNER" <<EOF
#!/bin/sh
exec gpg --batch --pinentry-mode loopback --passphrase '' "\$@"
EOF
chmod +x "$SIGNER"
# The pretend wren-key signs with whichever key $T/signing-key names
echo "$F" >"$T/signing-key"
cat >"$HOME/.local/bin/wren-key" <<EOF
#!/bin/bash
[ "\$1" = detach-sign ] || exit 2
exec gpg --batch --pinentry-mode loopback --passphrase '' --armor --detach-sign --local-user "\$(cat "$T/signing-key")"
EOF
chmod +x "$HOME/.local/bin/wren-key"

L=$T/L
mkdir "$L"
(cd "$HERE" && git ls-files -co --exclude-standard | tar -cf - -T -) | tar -C "$L" -xf -
sed -i "s/^WREN_SIGNING_FPR=.*/WREN_SIGNING_FPR=$F/" "$L/pins.sh"
gpg --batch --armor --export "$F" >"$L/data/wren-signing-key.asc"
git -C "$L" init -q -b main
git -C "$L" config gpg.format openpgp; git -C "$L" config gpg.program "$SIGNER"
git -C "$L" config user.signingkey "$F"; git -C "$L" config commit.gpgsign true; git -C "$L" config tag.gpgSign true
git -C "$L" add -A && git -C "$L" commit -q -m first
git clone -q --bare "$L" "$T/S.git"
git -C "$L" remote add origin "$T/S.git"
git -C "$L" fetch -q origin
commit() { # MESSAGE, signed, and on the server
    echo "$1" >>"$L/README.md"
    git -C "$L" commit -q -am "$1"
    git -C "$L" push -q origin main
}
now=$(date -d '2026-11-20 12:00 UTC' +%s)
tr_() { printf '%s\n' "$@" >"$T/answers"; WREN_NOW=$now WREN_TEST_ANSWERS=$T/answers bash "$L/tools/tag-release.sh" >"$T/out" 2>&1; }
said() { grep -q -- "$1" "$T/out"; }
on_server() { git -C "$T/S.git" rev-parse --verify --quiet "refs/tags/$1" >/dev/null; }
here() { git -C "$L" rev-parse --verify --quiet "refs/tags/$1" >/dev/null; }

# ---- a release ----
commit 'A fix people want'
git -C "$L" commit -q --allow-empty -m 'Signed: the commits below are reviewed'
git -C "$L" push -q origin main
tr_ n
check "no to signing: no tag" not here 2026.11
tr_ y n
check "the version is the year and month" here 2026.11
check "...signed by the pinned key" bash -c 'git -C "$1" -c gpg.program=gpg verify-tag --raw 2026.11 2>&1 | grep -q "VALIDSIG.* $2\$"' _ "$L" "$F"
check "...the notes come from the commits" bash -c 'git -C "$1" tag -l --format="%(contents)" 2026.11 | grep -q "^- A fix people want"' _ "$L"
check "...the commits that only sign are left out" bash -c '! git -C "$1" tag -l --format="%(contents)" 2026.11 | grep -q "^- Signed:"' _ "$L"
check "no to pushing: it stays here, and it says how" bash -c '! git -C "$1" rev-parse --verify --quiet refs/tags/2026.11 && grep -q "push origin refs/tags/2026.11" "$2"' _ "$T/S.git" "$T/out"
tr_ y
check "the same commit again: already a release, no second tag" bash -c 'grep -q "already release 2026.11" "$1" && [ "$(git -C "$2" tag | wc -l)" = 1 ]' _ "$T/out" "$L"
git -C "$L" push -q origin refs/tags/2026.11
commit 'More work'
tr_ y y
check "another in the same month: 2026.11.1" here 2026.11.1
check "...pushed, since you said so" on_server 2026.11.1
check "...its notes only what's new" bash -c 'n=$(git -C "$1" tag -l --format="%(contents)" 2026.11.1); grep -q "More work" <<<"$n" && ! grep -q "A fix people want" <<<"$n"' _ "$L"
commit 'Next month'
WREN_NOW=$(date -d '2026-12-02 12:00 UTC' +%s) WREN_TEST_ANSWERS=$T/answers bash -c 'printf "y\nn\n" >"$1"; bash "$2/tools/tag-release.sh" >/dev/null 2>&1' _ "$T/answers" "$L"
check "...a new month starts over: 2026.12" here 2026.12

# ---- it refuses ----
head_before=$(git -C "$L" tag | wc -l)
echo x >>"$L/README.md"
tr_ y y; rc=$?
check "changes not committed: refused" bash -c '[ "$1" != 0 ] && grep -q "aren.t committed" "$2"' _ "$rc" "$T/out"
git -C "$L" checkout -q README.md
echo y >>"$L/README.md"; git -C "$L" commit -q -am 'Not on the server yet'
tr_ y y; rc=$?
check "not on the server: refused, publish first" bash -c '[ "$1" != 0 ] && grep -q "Publish first" "$2"' _ "$rc" "$T/out"
git -C "$L" push -q origin main
echo z >>"$L/README.md"; git -C "$L" -c commit.gpgsign=false commit -q -am 'Nobody signed this'; git -C "$L" push -q origin main
tr_ y y; rc=$?
check "the newest commit unsigned: refused" bash -c '[ "$1" != 0 ] && grep -q "isn.t signed" "$2"' _ "$rc" "$T/out"
git -C "$L" -c user.signingkey="$O" commit -q --allow-empty -m 'Signed by another key'; git -C "$L" push -q origin main
tr_ y y; rc=$?
check "...or signed by another key: refused" bash -c '[ "$1" != 0 ] && grep -q "isn.t signed" "$2"' _ "$rc" "$T/out"
commit 'Good again'
git -C "$L" config user.signingkey "$O"
tr_ y y; rc=$?
check "a tag the key didn't sign: deleted, nothing pushed" bash -c '[ "$1" != 0 ] && grep -q "was deleted" "$2" && ! git -C "$3" rev-parse --verify --quiet refs/tags/2026.11.2' _ "$rc" "$T/out" "$L"
git -C "$L" config user.signingkey "$F"
check "...the number is free again" test "$(git -C "$L" tag | wc -l)" = "$head_before"

# ---- the image ----
cat >"$T/build" <<EOF
#!/bin/bash
echo "\$*" >"$T/built"
[ ! -e "$T/build-fails" ] || exit 1
echo image-bytes >"\${3:?}"
cat "$T/base-name" >"\${3%/*}/DEBIAN-BASE.txt"
EOF
echo debian-live-13.7.0-amd64-standard.iso >"$T/base-name"
# A pretend Debian: its signing key is a throwaway too, its files in folders by address.
gpg --batch --quiet --passphrase '' --quick-gen-key "debian cd <d@t>" ed25519 sign 1y 2>/dev/null
DF=$(gpg --batch --with-colons --list-keys d@t 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }')
gpg --batch --armor --export "$DF" >"$T/debian-key.asc"
sed -i -e "s/^DEBIAN_CD_FPR=.*/DEBIAN_CD_FPR=$DF/" -e "s|^DEBIAN_CD_KEY_URL=.*|DEBIAN_CD_KEY_URL=$T/debian-key.asc|" "$L/pins.sh"
git -C "$L" add -A; git -C "$L" commit -q -m 'the pretend Debian key'; git -C "$L" push -q origin main
D=$T/debian
# debian_source FOLDER VERSION [SIGN-KEY]: that version's source and its signed checksums
debian_source() {
    local d=$D/$1
    mkdir -p "$d"
    echo "source of $2" >"$d/debian-live-$2-source-standard.tar"
    echo "contents of $2" >"$d/debian-live-$2-source-standard.contents"
    (cd "$d" && sha512sum debian-live-"$2"-source-standard.* >SHA512SUMS)
    gpg --batch --yes --pinentry-mode loopback --passphrase '' --local-user "${3:-$DF}" --detach-sign --output "$d/SHA512SUMS.sign" "$d/SHA512SUMS" 2>/dev/null
}
debian_source debian-cd/current-live/source/tar 13.7.0
cat >"$T/wget" <<EOF
#!/bin/bash
# wget [-q] [-c] [--show-progress] -O FILE URL, from the folders above
while [ \$# -gt 0 ]; do case \$1 in -O) f=\$2; shift 2 ;; -*) shift ;; *) url=\$1; shift ;; esac; done
echo "wget \$url" >>"$T/fetched"
[ ! -e "$T/wget-fails" ] || exit 1
cp "$D/\${url#https://cdimage.debian.org/}" "\$f" 2>/dev/null
EOF
chmod +x "$T/wget"
printf '#!/bin/bash\necho "$*" >"%s/rsynced"\n[ -e "%s/rsync-fails" ] && exit 1\nfor a; do last_src=$src; src=$a; done\ncp -r "$last_src"/. "%s/srv/"\n' "$T" "$T" "$T" >"$T/rsync"
chmod +x "$T/build" "$T/rsync"
mkdir "$T/srv"
pi() { printf '%s\n' "$@" >"$T/answers"; rm -f "$T/rsynced" "$T/built"; WREN_WGET=$T/wget WREN_BUILD_IMAGE=$T/build WREN_RSYNC=$T/rsync WREN_PUBLISH_IMAGES=$T/srv/ WREN_TEST_ANSWERS=$T/answers bash "$L/tools/publish-image.sh" --host wren-vps >"$T/out" 2>&1; }
pi; rc=$?
check "the image: not of a release, refused, and nothing is built" bash -c '[ "$1" != 0 ] && grep -q "isn.t a release" "$2" && [ ! -e "$3/built" ]' _ "$rc" "$T/out" "$T"
git -C "$L" -c tag.gpgSign=false -c user.signingkey="$O" tag --sign -m 'x' 2099.01 HEAD
pi; rc=$?
check "...a tag another key signed: refused, nothing built" bash -c '[ "$1" != 0 ] && grep -q "isn.t signed by" "$2" && [ ! -e "$3/built" ]' _ "$rc" "$T/out" "$T"
git -C "$L" tag --delete 2099.01 >/dev/null
tr_ y y
V=$(git -C "$L" tag --points-at HEAD)
check "...(a release of this commit: $V)" test -n "$V"
pi; rc=$?
I=$HOME/.cache/wren/images/$V
check "of a signed release: it's built for anyone (--public)" bash -c '[ "$1" = 0 ] && grep -q -- "--public --out .*wren-linux-$2-amd64.iso" "$3/built"' _ "$rc" "$V" "$T"
check "...its checksum in SHA256SUMS" bash -c 'cd "$1" && sha256sum -c SHA256SUMS' _ "$I"
check "...Debian's source for that image beside it, for the GPL" bash -c 'grep -qx "source of 13.7.0" "$1/debian-live-13.7.0-source-standard.tar"' _ "$I"
check "...and its list of contents" test -s "$I/debian-live-13.7.0-source-standard.contents"
check "...both, and the notes, in the signed list" bash -c '
    for f in debian-live-13.7.0-source-standard.tar debian-live-13.7.0-source-standard.contents SOURCE.txt RELEASE-NOTES.txt DEBIAN-BASE.txt; do grep -q "  $f\$" "$1/SHA256SUMS" || exit 1; done' _ "$I"
check "...SOURCE.txt says what's there, and where Wren Linux's own is" bash -c 'grep -q "debian-live-13.7.0-source-standard.tar" "$1/SOURCE.txt" && grep -q "$2" "$1/SOURCE.txt"' _ "$I" "$V"
check "...signed by the pinned key" bash -c 'gpg --status-fd=1 --verify "$1/SHA256SUMS.asc" "$1/SHA256SUMS" 2>/dev/null | grep -q "VALIDSIG.* $2\$"' _ "$I" "$F"
check "...with the release notes beside it, without the signature" bash -c 'grep -q "Wren Linux" "$1/RELEASE-NOTES.txt" && ! grep -q "BEGIN PGP" "$1/RELEASE-NOTES.txt"' _ "$I"
check "...on the server, in that version's folder, nothing there replaced" bash -c 'grep -q -- "--ignore-existing" "$1/rsynced" && grep -q "$2/\$" "$1/rsynced" && ! grep -q -- "--delete" "$1/rsynced"' _ "$T" "$V"
echo "$O" >"$T/signing-key"
pi n; rc=$?
check "the key signs wrongly: nothing goes out" bash -c '[ "$1" != 0 ] && [ ! -e "$2/rsynced" ] && grep -q "didn.t check out" "$3"' _ "$rc" "$T" "$T/out"
echo "$F" >"$T/signing-key"
pi n; rc=$?
check "the image is there already, and you say keep it: not built again" bash -c '[ "$1" = 0 ] && [ ! -e "$2/built" ]' _ "$rc" "$T"
: >"$T/build-fails"
pi y; rc=$?
check "the build fails: nothing goes out" bash -c '[ "$1" != 0 ] && [ ! -e "$2/rsynced" ]' _ "$rc" "$T"
rm -f "$T/build-fails"

# Debian's source for the image: checked as carefully as the image
fresh_image() { rm -rf "$I" "$T/fetched"; mkdir -p "$I"; rm -rf "$T/srv"; mkdir "$T/srv"; }
fresh_image
echo debian-live-13.5.0-amd64-standard.iso >"$T/base-name"
debian_source cdimage/archive/13.5.0-live/source/tar 13.5.0
pi n; rc=$?
check "Debian has moved on since: the older version's, from its archive" bash -c '[ "$1" = 0 ] && grep -qx "source of 13.5.0" "$2/debian-live-13.5.0-source-standard.tar"' _ "$rc" "$I"
check "...never the newest in its place" test ! -e "$I/debian-live-13.7.0-source-standard.tar"
fresh_image
echo debian-live-13.1.0-amd64-standard.iso >"$T/base-name"
pi n; rc=$?
check "that version's source can't be found: nothing goes out" bash -c '[ "$1" != 0 ] && [ ! -e "$2/rsynced" ] && grep -q "source" "$3"' _ "$rc" "$T" "$T/out"
fresh_image
echo debian-live-13.5.0-amd64-standard.iso >"$T/base-name"
debian_source cdimage/archive/13.5.0-live/source/tar 13.5.0 "$O"
pi n; rc=$?
check "its checksums signed by another key: nothing goes out" bash -c '[ "$1" != 0 ] && [ ! -e "$2/rsynced" ]' _ "$rc" "$T"
fresh_image
debian_source cdimage/archive/13.5.0-live/source/tar 13.5.0
echo tampered >>"$D/cdimage/archive/13.5.0-live/source/tar/debian-live-13.5.0-source-standard.tar"
pi n; rc=$?
check "a source file that doesn't match them: deleted, nothing goes out" bash -c '[ "$1" != 0 ] && [ ! -e "$2/rsynced" ] && [ ! -e "$3/debian-live-13.5.0-source-standard.tar" ]' _ "$rc" "$T" "$I"
fresh_image
debian_source cdimage/archive/13.5.0-live/source/tar 13.5.0
: >"$T/wget-fails"
pi n; rc=$?
check "no way to fetch it: nothing goes out" bash -c '[ "$1" != 0 ] && [ ! -e "$2/rsynced" ]' _ "$rc" "$T"
rm -f "$T/wget-fails"
fresh_image
printf 'debian-live-13.5.0-amd64-standard.iso; rm -rf /\n' >"$T/base-name"
pi n; rc=$?
check "a base name that isn't one: refused, and nothing is fetched" bash -c '[ "$1" != 0 ] && [ ! -e "$2/fetched" ] && [ ! -e "$2/rsynced" ]' _ "$rc" "$T"
echo debian-live-13.7.0-amd64-standard.iso >"$T/base-name"

# ---- --public, in the image's own script ----
M=$HERE/prep/make-install-iso.sh
check "--public: nothing of this computer's name or clock" bash -c 'sed -n "/^if \$public; then/,/^fi/p" "$1" | grep -q "user=user keymap=us locale=en_US.UTF-8 timezone=Etc/UTC"' _ "$M"
check "...no saved downloads on it" grep -qF 'if [ -d "$OFFLINE_DIR" ] && ! $public; then' "$M"
check "...it says which Debian image it was built on" grep -qF 'DEBIAN-BASE.txt' "$M"
check "...and always disk encryption" grep -q '\$encrypt || die "--public and --noencrypt' "$M"
check "wren-release --tag marks it after publishing, before installing" bash -c '
    a=$(grep -n "tag-release.sh" "$1" | tail -1 | cut -d: -f1); b=$(grep -n "git-push.sh\" ||" "$1" | cut -d: -f1); c=$(grep -n "build-deb.sh\" --commit" "$1" | cut -d: -f1)
    [ "$b" -lt "$a" ] && [ "$a" -lt "$c" ]' _ "$HERE/tools/release.sh"
check "the server has a folder for images, apart from the site (--delete empties that)" bash -c '
    grep -q "^IMAGEDIR=/srv/wren-images" "$1" && grep -q "handle_path /images/\*" "$1" && grep -qF "root * \$IMAGEDIR" "$1"' _ "$HERE/tools/setup-vps.sh"

[ "$fails" -eq 0 ]
