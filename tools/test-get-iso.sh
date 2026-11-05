#!/bin/bash
# Checks get-iso (extras/get-iso.sh, lib/get-iso.sh) against a pretend internet
# (WREN_ISO_MIRROR) and throwaway signing keys put in place of the pinned ones,
# in a copy of this checkout: the newest release is the one taken, a list or
# image signed by any other key is refused, a download that fails the checks is
# deleted, and a kept image is reused. No network, no sudo, no USB stick (the
# stick part is checked in test-tails-usb.sh). Run by test.sh, or:
# bash tools/test-get-iso.sh
# shellcheck disable=SC2016  # the inner bash expands its own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'gpgconf --homedir "$T/gh" --kill all 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

mkdir -m 700 "$T/gh"
[ -z "${GPG_AGENT_PROGRAM:-}" ] || echo "agent-program $GPG_AGENT_PROGRAM" >"$T/gh/gpg.conf"
G=(gpg --homedir "$T/gh" --batch --quiet --pinentry-mode loopback --passphrase '')
fpr_of() { "${G[@]}" --list-keys --with-colons "$1" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }'; }
"${G[@]}" --quick-generate-key project@test ed25519 sign 1y
"${G[@]}" --quick-generate-key someone-else@test ed25519 sign 1y
GOOD=$(fpr_of project@test) OTHER=$(fpr_of someone-else@test)
[ -n "$GOOD" ] && [ -n "$OTHER" ] || { echo "  ok    skipped: gpg couldn't make test keys here (is gpg-agent installed?)"; exit 0; }
sign() { "${G[@]}" --yes --local-user "${2:-project@test}" --detach-sign -o "$1.${3:-sig}" "$1"; }

# A copy of this checkout whose pins are the test key (served at keys.test)
mkdir "$T/W"
(cd "$HERE" && git ls-files -co --exclude-standard | tar -cf - -T -) | tar -C "$T/W" -xf -
for v in DEBIAN_CD KALI PARROT WHONIX ARCH_ISO TAILS QUBES; do
    sed -i "s|^${v}_FPR=.*|${v}_FPR=$GOOD|; s|^${v}_KEY_URL=.*|${v}_KEY_URL=https://keys.test/key.asc|" "$T/W/pins.sh"
done
M=$T/mirror
mkdir -p "$M/keys.test"
"${G[@]}" --export --armor project@test >"$M/keys.test/key.asc"

# Debian: two releases in the list; the newer must be taken
D=$M/cdimage.debian.org/debian-cd/current/amd64/iso-cd
mkdir -p "$D"
echo "debian 13.10.0" >"$D/debian-13.10.0-amd64-netinst.iso"
{ printf '%s  debian-13.9.0-amd64-netinst.iso\n' "$(printf 'x' | sha512sum | cut -d' ' -f1)"
  printf '%s  debian-13.10.0-amd64-netinst.iso\n' "$(sha512sum <"$D/debian-13.10.0-amd64-netinst.iso" | cut -d' ' -f1)"
} >"$D/SHA512SUMS"
sign "$D/SHA512SUMS" project@test sign
# Kali
K=$M/cdimage.kali.org/current
mkdir -p "$K"
echo "kali" >"$K/kali-linux-2026.3-installer-amd64.iso"
(cd "$K" && sha256sum kali-linux-2026.3-installer-amd64.iso >SHA256SUMS)
sign "$K/SHA256SUMS" project@test gpg
# Parrot: folders 7.4 and 7.10 (7.10 is newer); a clearsigned list, with an
# unsigned line in front of it naming another file
P=$M/deb.parrot.sh/parrot/iso
mkdir -p "$P/7.4" "$P/7.10"
printf '<a href="7.4/">7.4/</a> <a href="7.10/">7.10/</a> <a href="caine/">caine/</a>\n' >"$P/index.html"
echo "parrot security" >"$P/7.10/Parrot-security-7.10_amd64.iso"
(cd "$P/7.10" && sha256sum Parrot-security-7.10_amd64.iso >sums)
"${G[@]}" --local-user project@test --clearsign -o "$P/7.10/signed.part" "$P/7.10/sums"
{ printf '%s  Parrot-home-7.10_amd64.iso\n' "$(printf 'evil' | sha256sum | cut -d' ' -f1)"; cat "$P/7.10/signed.part"; } >"$P/7.10/signed-hashes.txt"
echo "parrot home" >"$P/7.10/Parrot-home-7.10_amd64.iso"
# Kicksecure: the page names two versions; the image has its own signature
KS=$M/www.kicksecure.com
mkdir -p "$KS/wiki" "$KS/download/iso/18.2.4.2" "$KS/download/iso/18.10.1"
printf 'download/iso/18.2.4.2/Kicksecure-LXQt-18.2.4.2.Intel_AMD64.iso\ndownload/iso/18.10.1/Kicksecure-LXQt-18.10.1.Intel_AMD64.iso\n' >"$KS/wiki/ISO"
KI=$KS/download/iso/18.10.1/Kicksecure-LXQt-18.10.1.Intel_AMD64.iso
echo "kicksecure" >"$KI"
sign "$KI" project@test asc
# Arch: the release list, and the image's own signature
mkdir -p "$M/archlinux.org/releng/releases/json" "$M/geo.mirror.pkgbuild.com/iso/2026.11.01"
AI=$M/geo.mirror.pkgbuild.com/iso/2026.11.01/archlinux-2026.11.01-x86_64.iso
echo "arch" >"$AI"
sign "$AI"
printf '{"releases": [{"version": "2026.11.01", "available": true, "sha256_sum": "%s", "iso_url": "/iso/2026.11.01/archlinux-2026.11.01-x86_64.iso"}]}\n' \
    "$(sha256sum <"$AI" | cut -d' ' -f1)" >"$M/archlinux.org/releng/releases/json/index.html"

# Qubes: 4.3.1 and 4.3.10 of the pinned series, and a 4.4 whose key isn't pinned
Q=$M/mirrors.edge.kernel.org/qubes/iso
mkdir -p "$Q"
printf '<a href="Qubes-R4.3.1-x86_64.iso">x</a> <a href="Qubes-R4.3.10-x86_64.iso">x</a> <a href="Qubes-R4.3.10-x86_64.iso.asc">x</a> <a href="Qubes-R4.4.0-x86_64.iso">x</a>\n' >"$Q/index.html"
echo "qubes" >"$Q/Qubes-R4.3.10-x86_64.iso"
sign "$Q/Qubes-R4.3.10-x86_64.iso" project@test asc

# ---- the release each finds ----
rel() { # NAME: its DIR/release line, or "failed"
    (cd "$T/W" && . ./lib.sh && . lib/appimage.sh && . lib/tails.sh && . lib/get-iso.sh && set +e &&
        d=$(mktemp -d) && { iso_release "$1" "$d" 2>/dev/null && cut -d' ' -f1-3 "$d/release" || echo failed; rm -rf "$d"; })
}
export WREN_ISO_MIRROR=$M
check "Debian: the newest installer in the signed list (13.10.0, not 13.9.0)" \
    test "$(rel debian)" = "13.10.0 https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.10.0-amd64-netinst.iso sha512"
check "Kali: the installer its signed list names" \
    test "$(rel kali)" = "2026.3 https://cdimage.kali.org/current/kali-linux-2026.3-installer-amd64.iso sha256"
check "Parrot: the newest folder (7.10, not 7.4), from the signed list" \
    test "$(rel parrot-security)" = "7.10 https://deb.parrot.sh/parrot/iso/7.10/Parrot-security-7.10_amd64.iso sha256"
check "...a line outside the signed text is never read (Parrot Home isn't in the signed part)" test "$(rel parrot-home)" = failed
check "Kicksecure: the newest version on its page (18.10.1, not 18.2.4.2), with the image's own signature" \
    test "$(rel kicksecure)" = "18.10.1 https://www.kicksecure.com/download/iso/18.10.1/Kicksecure-LXQt-18.10.1.Intel_AMD64.iso sig"
check "Qubes: the newest of the pinned key's series (4.3.10, not 4.3.1, nor 4.4.0 whose key isn't pinned)" \
    test "$(rel qubes)" = "4.3.10 https://mirrors.edge.kernel.org/qubes/iso/Qubes-R4.3.10-x86_64.iso sig"
check "Arch: the release list's newest, with the image's own signature" \
    test "$(rel arch)" = "2026.11.01 https://geo.mirror.pkgbuild.com/iso/2026.11.01/archlinux-2026.11.01-x86_64.iso sig"
check "a name it doesn't know is refused" test "$(rel ../../etc)" = failed
cp "$D/SHA512SUMS.sign" "$T/debian.sign"
sign "$D/SHA512SUMS" someone-else@test sign
check "a checksum list signed by another key is refused" test "$(rel debian)" = failed
cp "$T/debian.sign" "$D/SHA512SUMS.sign"

# ---- get-iso, start to end ----
ISOS=$T/home/ISOs
mkdir -p "$T/home"
gi() { # ANSWERS... then get-iso's arguments in $ARGS
    printf '%s\n' "$@" >"$T/answers"
    # shellcheck disable=SC2086
    HOME=$T/home WREN_ISO_DIR=$ISOS WREN_TEST_ANSWERS=$T/answers bash "$T/W/extras/get-iso.sh" --get $ARGS 2>&1
}
ARGS=debian out=$(gi n) && rc=0 || rc=$?
check "get-iso debian: ends well (status 0, nothing left over from the temp folder)" bash -c '[ "$1" = 0 ] && ! grep -q "unbound variable" <<<"$2"' _ "$rc" "$out"
check "get-iso debian: the checked image is kept in ~/ISOs/debian" cmp -s "$D/debian-13.10.0-amd64-netinst.iso" "$ISOS/debian/debian-13.10.0-amd64-netinst.iso"
check "...and says it was checked against the pinned key" grep -q "Checked against debian's pinned key" <<<"$out"
check "...and no stick is written when you say no" grep -q 'For a stick later: get-iso debian' <<<"$out"
ARGS=debian out=$(gi n)
check "a second time: the kept copy is checked again and used" grep -q 'Using the copy kept here, checked again' <<<"$out"
echo "older" >"$ISOS/debian/debian-13.9.0-amd64-netinst.iso"
rm -f "$ISOS/debian/debian-13.10.0-amd64-netinst.iso"
ARGS=debian out=$(gi n)
check "...an older image there is deleted once the newest is in" test ! -e "$ISOS/debian/debian-13.9.0-amd64-netinst.iso"
# An image changed on the way: the list is good, the image isn't
echo "changed on the way" >"$K/kali-linux-2026.3-installer-amd64.iso"
ARGS=kali out=$(gi n) && rc=0 || rc=$?
check "an image that isn't the one in the signed list is deleted, and it says so" \
    bash -c '[ "$1" -ne 0 ] && grep -q "didn.t pass the checks, so it was deleted" <<<"$2" && [ -z "$(ls -A "$3" 2>/dev/null)" ]' _ "$rc" "$out" "$ISOS/kali"
# An image whose own signature is another key's
sign "$AI" someone-else@test
ARGS=arch out=$(gi n) && rc=0 || rc=$?
check "an image signed by another key is deleted" bash -c '[ "$1" -ne 0 ] && [ -z "$(ls -A "$2" 2>/dev/null)" ]' _ "$rc" "$ISOS/arch"
sign "$AI"
ARGS=arch out=$(gi n)
check "...and with its own good signature it is kept" test -s "$ISOS/arch/archlinux-2026.11.01-x86_64.iso"
ARGS=nothing out=$(gi n) && rc=0 || rc=$?
check "get-iso NAME it doesn't know: says which it knows" bash -c '[ "$1" -ne 0 ] && grep -q "It knows: debian tails" <<<"$2"' _ "$rc" "$out"
check "--list names every one" bash -c 'o=$(bash "$1/extras/get-iso.sh" --list); for n in debian tails kicksecure qubes kali parrot-security parrot-home arch; do grep -q "^  $n " <<<"$o" || exit 1; done' _ "$T/W"
check "the stick is written with the shared code (lib/usb-stick.sh), after you say yes" \
    bash -c 'grep -q "^    stick_write \"\$img\" \"\$min\"" "$1" && grep -q "ask \"Write it to a USB stick now (everything on the stick is erased)?\" n" "$1"' _ "$HERE/extras/get-iso.sh"

[ "$fails" -eq 0 ]
