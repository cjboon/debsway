#!/bin/bash
# Checks extras/tutamail.sh and verify_rsa_sha512 (lib/appimage.sh): only an
# AppImage signed by the pinned Tuta key is installed, the unpacked app must be
# the version Tuta's release file names, an older one never replaces a newer
# one, and the launcher runs the app itself (not AppRun, which can turn
# Electron's sandbox off). Runs the extra with a throwaway RSA key, a pretend
# server (wget), a pretend AppImage, sudo that only logs and a pretend
# dpkg-query (its packages "already installed"), in a temp home, so nothing on
# this computer changes. Run by test.sh, or:  bash tools/test-tutamail.sh
# shellcheck disable=SC2016  # the pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$HERE/lib.sh"
. "$HERE/lib/appimage.sh"
set +e +o pipefail
command -v openssl >/dev/null || { echo "  ok    skipped: openssl isn't installed"; exit 0; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
warn() { :; }  # verify_rsa_sha512 complains on failure; the checks only want the result

# ---- the pinned key (pins.sh, read by lib.sh) ----
check "data/tuta-pub.pem is the pinned Tuta key" \
    test "$(openssl pkey -pubin -in "$HERE/data/tuta-pub.pem" -outform DER 2>/dev/null | sha256sum | cut -d' ' -f1)" = "$TUTA_KEY_SHA256"

# ---- verify_rsa_sha512 on its own ----
key_hash() { openssl pkey -pubin -in "$1" -outform DER | sha256sum | cut -d' ' -f1; }
for k in good other; do
    openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$T/$k.key" 2>/dev/null
    openssl pkey -in "$T/$k.key" -pubout -out "$T/$k.pem"
done
GOOD=$(key_hash "$T/good.pem")
echo data >"$T/file"
openssl dgst -sha512 -sign "$T/good.key" -out "$T/file.sig" "$T/file"
openssl dgst -sha512 -sign "$T/other.key" -out "$T/file.other" "$T/file"
openssl dgst -sha256 -sign "$T/good.key" -out "$T/file.sha256" "$T/file"
check "a good signature passes" verify_rsa_sha512 "$GOOD" "$T/good.pem" "$T/file.sig" "$T/file"
echo changed >>"$T/file"
check "a changed file fails" not verify_rsa_sha512 "$GOOD" "$T/good.pem" "$T/file.sig" "$T/file"
echo data >"$T/file"
check "a signature by another key fails" not verify_rsa_sha512 "$GOOD" "$T/good.pem" "$T/file.other" "$T/file"
check "...also when that key is the one handed in, if it isn't pinned" \
    not verify_rsa_sha512 "$GOOD" "$T/other.pem" "$T/file.other" "$T/file"
check "a SHA-256 signature isn't taken for SHA-512" not verify_rsa_sha512 "$GOOD" "$T/good.pem" "$T/file.sha256" "$T/file"
check "a missing key file fails" not verify_rsa_sha512 "$GOOD" "$T/none.pem" "$T/file.sig" "$T/file"

# ---- the extra, run with pretend programs ----
mkdir -p "$T/bin" "$T/srv" "$T/home"
cat >"$T/bin/sudo" <<EOF
#!/bin/sh
[ "\$1" = -v ] && exit 0
echo "sudo \$*" >>"$T/sudo-calls"
EOF
# The packages it asks for are "already installed", held by its marker
eval "$(sed -n '/^LIBS=(/,/)/p' "$HERE/extras/tutamail.sh")"
deps=$(printf '%s, ' "${LIBS[@]}")
cat >"$T/bin/dpkg-query" <<EOF
#!/bin/sh
case "\$*" in
    *Status*) echo 'install ok installed' ;;
    *Depends*) echo '${deps%, }' ;;
esac
EOF
# wget [-q] [--show-progress] -O FILE URL: serves $T/srv
cat >"$T/bin/wget" <<EOF
#!/bin/sh
out=
while [ \$# -gt 1 ]; do
    case "\$1" in -O) out=\$2; shift 2 ;; *) shift ;; esac
done
echo "\$1" >>"$T/fetched"
cp "$T/srv/\${1##*/}" "\$out" 2>/dev/null
EOF
chmod +x "$T/bin/"*

R=$T/r
mkdir -p "$R/extras" "$R/data"
sed 's|^export PATH=.*|export PATH="$TUTA_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q TUTA_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
sed "s|^TUTA_KEY_SHA256=.*|TUTA_KEY_SHA256=$GOOD|; s|^TUTA_DESKTOP_URL=.*|TUTA_DESKTOP_URL=https://tuta.test/desktop|" \
    "$HERE/pins.sh" >"$R/pins.sh"
cp "$HERE/packages.sh" "$R/"
ln -s "$HERE/lib" "$R/lib"
cp "$HERE/extras/tutamail.sh" "$R/extras/"
cp "$T/good.pem" "$R/data/tuta-pub.pem"
export TUTA_TEST_PATH="$T/bin:$PATH"

# serve OFFERED INSIDE [KEY]: the server names version OFFERED; its AppImage,
# signed by KEY (good), unpacks to an app whose package.json says INSIDE
serve() {
    printf 'version: %s\nfiles:\n  - url: tutanota-desktop-linux.AppImage\n' "$1" >"$T/srv/latest-linux.yml"
    cat >"$T/srv/tutanota-desktop-linux.AppImage" <<EOF
#!/bin/sh
[ "\$1" = --appimage-extract ] || exit 1
mkdir -p squashfs-root/resources
printf '#!/bin/sh\n' >squashfs-root/AppRun
printf '#!/bin/sh\n' >squashfs-root/tutanota-desktop
chmod +x squashfs-root/AppRun squashfs-root/tutanota-desktop
printf '{\n  "name": "tutanota-desktop",\n  "version": "%s",\n}\n' "$2" >squashfs-root/resources/app.asar
EOF
    openssl dgst -sha512 -sign "$T/${3:-good}.key" -out "$T/srv/linux-sig.bin" "$T/srv/tutanota-desktop-linux.AppImage"
}
run() {
    : >"$T/fetched"
    HOME=$T/home bash "$R/extras/tutamail.sh" "$@" >"$T/out" 2>&1
}
ver() { cat "$T/home/.local/opt/tuta/.wren-version" 2>/dev/null; }
L=$T/home/.local/bin/tuta

serve 362.1 362.1
run
check "a signed AppImage is installed" test "$(ver)" = 362.1
check "...its launcher runs the app itself, not AppRun" grep -q '/tutanota-desktop" "\$@"$' "$L"
check "...on Wayland" grep -q 'ELECTRON_OZONE_PLATFORM_HINT=wayland' "$L"
check "...and never with the sandbox off" not grep -q 'no-sandbox' "$L"
check "...from Tuta's own server" grep -qx 'https://tuta.test/desktop/tutanota-desktop-linux.AppImage' "$T/fetched"
run
check "the same version again isn't downloaded again" not grep -q AppImage "$T/fetched"
serve 362.0 362.0
run
check "an older version offered is refused" grep -q 'older than the installed 362.1' "$T/out"
check "...and the newer one stays" test "$(ver)" = 362.1
serve 363.1 363.1 other
run
check "an AppImage signed by another key is refused" grep -q "isn't signed by Tuta" "$T/out"
check "...unchanged" test "$(ver)" = 362.1
serve 363.1 362.0
run
check "an old signed AppImage passed off as a new version is refused" grep -q "isn't version 363.1" "$T/out"
check "...and the installed one stays" test "$(ver)" = 362.1
check "...with no half-unpacked folder left" not compgen -G "$T/home/.local/opt/.unpack.*"
serve '363.1;rm' 363.1
run
check "a version that isn't a version number is refused" grep -q "Couldn't read the newest version" "$T/out"
check "...before anything else is downloaded" not grep -q AppImage "$T/fetched"
openssl pkey -in "$T/other.key" -pubout -out "$R/data/tuta-pub.pem"
serve 363.1 363.1 other
run
check "a key file that isn't the pinned key is refused" grep -q "isn't the pinned one" "$T/out"
check "...and nothing is installed with it" test "$(ver)" = 362.1
cp "$T/good.pem" "$R/data/tuta-pub.pem"
serve 363.1 363.1
run
check "a newer signed version is installed" test "$(ver)" = 363.1
run --remove
check "--remove deletes the app" test ! -e "$T/home/.local/opt/tuta"
check "...and its launcher" test ! -e "$L"
check "...through its marker package" grep -q 'apt-get purge -y wren-tutamail' "$T/sudo-calls"

[ "$fails" -eq 0 ]
