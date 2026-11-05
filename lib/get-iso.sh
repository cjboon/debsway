# shellcheck shell=bash
# lib/get-iso.sh: finding and checking other systems' install images
# (extras/get-iso.sh). Sourced after lib.sh, lib/appimage.sh (its signature
# checks) and lib/tails.sh.
#
# An image is kept only if it is the newest release, read from the project's
# own release list or folder over HTTPS (a signature alone would also take an
# older, genuinely signed image with known holes), and either its own signature
# or a signed list of checksums that names it is good and made by the
# project's key pinned in pins.sh.

# What can be fetched: NAME<TAB>what it is
ISO_LIST=$'debian\tDebian 13, the network installer (what Wren Linux is built on)
tails\tTails: a whole system on a USB stick, everything through Tor, forgets on shutdown
kicksecure\tKicksecure: hardened Debian from the makers of Whonix (live and installer)
kali\tKali Linux: security testing tools (the installer)
parrot-security\tParrot Security: security testing tools, live and installer
parrot-home\tParrot Home: an everyday desktop with privacy tools, live and installer
arch\tArch Linux: minimal and rolling, installed by hand'

# iso_names: the NAMEs, one a line
iso_names() { cut -f1 <<<"$ISO_LIST"; }

# iso_fetch URL FILE: downloads URL to FILE (going on with a partial FILE).
# Through Tor when ISO_VIA_TOR is true. WREN_ISO_MIRROR, a folder laid out as
# HOST/PATH, stands in for the internet in tests.
ISO_VIA_TOR=false
iso_fetch() {
    if [ -n "${WREN_ISO_MIRROR:-}" ]; then
        local f=$WREN_ISO_MIRROR/${1#https://}
        [ "${f%/}" = "$f" ] || f=${f%/}/index.html
        [ -f "$f" ] && cp "$f" "$2"
        return
    fi
    if $ISO_VIA_TOR; then
        torsocks wget -q --show-progress -c -O "$2" "$1"
    else
        wget -q --show-progress -c -O "$2" "$1"
    fi
}
# iso_get URL FILE: the same, quietly, for small files (always from the start)
iso_get() { rm -f "$2"; iso_fetch "$1" "$2" 2>/dev/null; }

# _iso_sum ALGO FILE NAME: NAME's checksum in a list of "HASH  NAME" lines, if
# it is one of ALGO's (64 hex digits for sha256, 128 for sha512)
_iso_sum() {
    local len=64
    [ "$1" = sha512 ] && len=128
    awk -v n="$3" -v len="$len" '($2 == n || $2 == "*" n) && length($1) == len && $1 ~ /^[0-9a-f]+$/ { print $1; exit }' "$2"
}

# iso_release NAME DIR: finds NAME's newest image and fetches into DIR what
# checking it needs, all checked that can be before the image is there. Writes
# DIR/release as "VERSION URL ALGO HASH": ALGO is sha256 or sha512, or "sig"
# when the image has a signature of its own (fetched to DIR/image.sig).
# DIR/fpr gets the fingerprint that signature must be by, DIR/key.asc its key.
# Fails, saying why, if anything is not as expected.
iso_release() {
    local name=$1 d=$2 v url file sum line
    case $name in
        debian)
            local base=https://cdimage.debian.org/debian-cd/current/amd64/iso-cd
            iso_get "$DEBIAN_CD_KEY_URL" "$d/key.asc" && iso_get "$base/SHA512SUMS" "$d/SHA512SUMS" &&
                iso_get "$base/SHA512SUMS.sign" "$d/SHA512SUMS.sign" || { warn "Couldn't fetch Debian's checksum list."; return 1; }
            verify_detached "$DEBIAN_CD_FPR" "$d/key.asc" "$d/SHA512SUMS.sign" "$d/SHA512SUMS" ||
                { warn "Debian's checksum list isn't signed by the Debian CD key."; return 1; }
            file=$(grep -oE 'debian-1[3-9]\.[0-9]+\.[0-9]+-amd64-netinst\.iso$' "$d/SHA512SUMS" | sort -V | tail -1)
            [ -n "$file" ] || { warn "Debian's checksum list names no network installer."; return 1; }
            v=${file#debian-}; v=${v%-amd64-netinst.iso}
            sum=$(_iso_sum sha512 "$d/SHA512SUMS" "$file")
            [ -n "$sum" ] || { warn "Debian's list has no SHA-512 for $file."; return 1; }
            echo "$v $base/$file sha512 $sum" >"$d/release" ;;
        tails)
            iso_get "$TAILS_LATEST_URL" "$d/latest.json" && line=$(tails_latest "$d/latest.json") ||
                { warn "Couldn't read Tails' release file."; return 1; }
            read -r v url sum _ <<<"$line"
            iso_get "$TAILS_KEY_URL" "$d/key.asc" && iso_get "$TAILS_SIG_BASE/${url##*/}.sig" "$d/image.sig" ||
                { warn "Couldn't fetch Tails' signing key or the image's signature."; return 1; }
            echo "$TAILS_FPR" >"$d/fpr"
            # its signature, and the SHA-256 the release file gives: both are checked
            echo "$v $url sig $sum" >"$d/release" ;;
        kicksecure)
            local page=https://www.kicksecure.com/wiki/ISO
            iso_get "$page" "$d/page" || { warn "Couldn't read Kicksecure's download page."; return 1; }
            v=$(grep -oE 'download/iso/[0-9]+(\.[0-9]+)+/Kicksecure-LXQt-[0-9.]+\.Intel_AMD64\.iso' "$d/page" |
                sed 's|.*/Kicksecure-LXQt-\(.*\)\.Intel_AMD64\.iso|\1|' | sort -uV | tail -1)
            [[ $v =~ ^[0-9]+(\.[0-9]+)+$ ]] || { warn "Couldn't read the newest version from Kicksecure's page."; return 1; }
            url=https://www.kicksecure.com/download/iso/$v/Kicksecure-LXQt-$v.Intel_AMD64.iso
            iso_get "$WHONIX_KEY_URL" "$d/key.asc" && iso_get "$url.asc" "$d/image.sig" ||
                { warn "Couldn't fetch Kicksecure's signing key or the image's signature."; return 1; }
            echo "$WHONIX_FPR" >"$d/fpr"
            echo "$v $url sig -" >"$d/release" ;;
        kali)
            local base=https://cdimage.kali.org/current
            iso_get "$KALI_KEY_URL" "$d/key.asc" && iso_get "$base/SHA256SUMS" "$d/SHA256SUMS" &&
                iso_get "$base/SHA256SUMS.gpg" "$d/SHA256SUMS.gpg" || { warn "Couldn't fetch Kali's checksum list."; return 1; }
            verify_detached "$KALI_FPR" "$d/key.asc" "$d/SHA256SUMS.gpg" "$d/SHA256SUMS" ||
                { warn "Kali's checksum list isn't signed by Kali's key."; return 1; }
            file=$(grep -oE 'kali-linux-20[0-9]{2}\.[0-9]+[a-z]?-installer-amd64\.iso$' "$d/SHA256SUMS" | sort -V | tail -1)
            [ -n "$file" ] || { warn "Kali's checksum list names no installer."; return 1; }
            v=${file#kali-linux-}; v=${v%-installer-amd64.iso}
            sum=$(_iso_sum sha256 "$d/SHA256SUMS" "$file")
            [ -n "$sum" ] || { warn "Kali's list has no SHA-256 for $file."; return 1; }
            echo "$v $base/$file sha256 $sum" >"$d/release" ;;
        parrot-security | parrot-home)
            local edition=${name#parrot-} base=https://deb.parrot.sh/parrot/iso
            iso_get "$base/" "$d/index" || { warn "Couldn't read Parrot's release folder."; return 1; }
            v=$(grep -oE 'href="[0-9]+\.[0-9]+(\.[0-9]+)?/"' "$d/index" | grep -oE '[0-9]+(\.[0-9]+)+' | sort -V | tail -1)
            [ -n "$v" ] || { warn "Couldn't read the newest version from Parrot's release folder."; return 1; }
            iso_get "$PARROT_KEY_URL" "$d/key.asc" && iso_get "$base/$v/signed-hashes.txt" "$d/signed" ||
                { warn "Couldn't fetch Parrot's signed checksum list."; return 1; }
            # Only the signed text is read: anything around it could say anything
            verify_clearsigned "$PARROT_FPR" "$d/key.asc" "$d/signed" "$d/hashes" ||
                { warn "Parrot's checksum list isn't signed by the Parrot Project's key."; return 1; }
            file=Parrot-$edition-${v}_amd64.iso
            sum=$(_iso_sum sha256 "$d/hashes" "$file")
            [ -n "$sum" ] || { warn "Parrot's signed list has no SHA-256 for $file."; return 1; }
            echo "$v $base/$v/$file sha256 $sum" >"$d/release" ;;
        arch)
            iso_get https://archlinux.org/releng/releases/json/ "$d/releases.json" ||
                { warn "Couldn't fetch Arch's release list."; return 1; }
            line=$(python3 -I - "$d/releases.json" <<'PY' 2>/dev/null
import json, re, sys
r = [x for x in json.load(open(sys.argv[1]))["releases"] if x["available"]][0]
v, sha = r["version"], r["sha256_sum"]
assert re.fullmatch(r"20[0-9]{2}\.[01][0-9]\.[0-3][0-9]", v), v
assert re.fullmatch(r"[0-9a-f]{64}", sha), sha
assert r["iso_url"] == "/iso/%s/archlinux-%s-x86_64.iso" % (v, v), r["iso_url"]
print(v, sha)
PY
            ) || { warn "Arch's release list isn't as expected."; return 1; }
            read -r v sum <<<"$line"
            url=https://geo.mirror.pkgbuild.com/iso/$v/archlinux-$v-x86_64.iso
            iso_get "$ARCH_ISO_KEY_URL" "$d/key.asc" && iso_get "$url.sig" "$d/image.sig" ||
                { warn "Couldn't fetch Arch's signing key or the image's signature."; return 1; }
            echo "$ARCH_ISO_FPR" >"$d/fpr"
            echo "$v $url sig $sum" >"$d/release" ;;
        *) warn "get-iso doesn't know \"$name\". It knows: $(iso_names | paste -sd' ')"; return 1 ;;
    esac
}

# iso_ok FILE DIR: FILE is the image DIR/release names: its checksum is the one
# in the signed list, or its own signature is good and by DIR/fpr's key (and,
# where the release list gives one, its SHA-256 matches too)
iso_ok() {
    local f=$1 d=$2 v url algo sum
    read -r v url algo sum <"$d/release"
    case $algo in
        sha256 | sha512)
            echo "$sum  $f" | "${algo}sum" -c --quiet - >/dev/null 2>&1 ||
                { warn "${f##*/} isn't the image the signed list names."; return 1; } ;;
        sig)
            verify_detached "$(cat "$d/fpr")" "$d/key.asc" "$d/image.sig" "$f" ||
                { warn "The signature on ${f##*/} isn't its project's key."; return 1; }
            [ "$sum" = - ] || echo "$sum  $f" | sha256sum -c --quiet - >/dev/null 2>&1 ||
                { warn "${f##*/} isn't the image the release list names (an older one?)."; return 1; } ;;
        *) return 1 ;;
    esac
}
