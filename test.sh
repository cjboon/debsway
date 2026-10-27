#!/bin/bash
# test.sh: checks that debsway still works. Its own scripts, and the
# outside things they depend on: Debian packages, download pages,
# signing keys, release signatures, and the Firefox and Debian features
# the hardening relies on. It installs and changes nothing; downloads
# are small (signatures and checksum lists) and go to a temporary folder.
# Run it now and then, and before you reinstall.
#
#   bash test.sh            everything (needs internet)
#   bash test.sh --offline  only what needs no internet
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
. "$DEBSWAY_DIR/extras/appimage.sh"
. "$DEBSWAY_DIR/packages.sh"
# Keep going after a failure; every check reports for itself
set +e +o pipefail

OFFLINE=false
[ "${1:-}" = --offline ] && OFFLINE=true
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
n_ok=0 n_warn=0 n_fail=0
ok() { printf '  \033[32mok\033[0m    %s\n' "$*"; n_ok=$((n_ok + 1)); }
meh() { printf '  \033[33mWARN\033[0m  %s\n' "$*"; n_warn=$((n_warn + 1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; n_fail=$((n_fail + 1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$*"; }
online() { ! $OFFLINE; }

cd "$DEBSWAY_DIR" || exit 1
mapfile -t SCRIPTS < <(find . -path ./ignore -prune -o -path ./debs -prune -o \
    \( -name '*.sh' -o -path ./config/sway-status -o -path ./config/ublock-allow \) -type f -print | sort)

# --------------------------------------------------------------------
section "Scripts"
bad_syntax=0
for f in "${SCRIPTS[@]}"; do
    bash -n "$f" 2>"$TMP/err" || { bad "syntax error in $f: $(head -1 "$TMP/err")"; bad_syntax=1; }
done
[ $bad_syntax -eq 1 ] || ok "${#SCRIPTS[@]} scripts parse"
if command -v shellcheck >/dev/null; then
    if shellcheck "${SCRIPTS[@]}" >"$TMP/sc" 2>&1; then
        ok "shellcheck finds nothing"
    else
        bad "shellcheck: $(grep -c '^In ' "$TMP/sc") problem(s); run: shellcheck ${SCRIPTS[*]}"
    fi
else
    meh "shellcheck isn't installed (sudo apt install shellcheck), skipped"
fi
for f in parts/*.sh extras/*.sh; do
    case $f in extras/appimage.sh | extras/mullvad-repo.sh) continue ;; esac
    grep -q -- '--remove' "$f" || meh "$f has no --remove"
done

# --------------------------------------------------------------------
section "Pinned keys and versions (pins.sh): checked by hand within a year?"
now=$(date +%s)
# Each "# checked: DATE" line belongs to the next VARIABLE= line
while read -r day what; do
    age=$(((now - $(date -d "$day" +%s)) / 86400))
    if [ "$age" -gt 365 ]; then
        meh "$what last checked $day ($age days ago): check it again by hand"
    else
        ok "$what checked $day"
    fi
done < <(awk '/^# checked: / { day = $3 } /^[A-Z_]+=/ && day { sub(/=.*/, ""); print day, $0; day = "" }' pins.sh)

# --------------------------------------------------------------------
section "Debian and Firefox features debsway relies on"
. /etc/os-release
[ "${VERSION_CODENAME:-}" = "$DEBIAN_RELEASE" ] && ok "this is Debian $DEBIAN_RELEASE" ||
    meh "this is ${PRETTY_NAME:-unknown}, debsway is written for $DEBIAN_RELEASE"
if is_installed firefox-esr; then
    [ "$(readlink /usr/share/firefox-esr/browser/defaults/syspref)" = /etc/firefox-esr ] &&
        ok "Firefox reads default prefs from /etc/firefox-esr (firefox-hardening)" ||
        bad "Debian's Firefox no longer links browser/defaults/syspref to /etc/firefox-esr"
fi
UBO="/usr/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/uBlock0@raymondhill.net"
if [ -f "$UBO/managed_storage.json" ]; then
    grep -q '"adminSettings"' "$UBO/managed_storage.json" &&
        ok "uBlock Origin still takes adminSettings (medium mode policy)" ||
        bad "uBlock Origin no longer has adminSettings; ublock-allow needs updating"
fi
if [ -f /etc/apparmor.d/torbrowser.Tor.tor ]; then
    grep -qs 'debsway' /etc/apparmor.d/local/torbrowser.Tor.tor &&
        ok "Tor Browser's AppArmor profile has the DNS fix" ||
        meh "Tor Browser's AppArmor profile lacks the DNS fix: bash extras/tor-browser.sh"
fi
if [ -f "$SWAY_CONFIG" ] && command -v sway >/dev/null; then
    check_sway_config 2>"$TMP/sway" && ok "your sway config has no errors" ||
        bad "your sway config has errors: $(head -1 "$TMP/sway")"
fi

online || { section "Skipping the online checks (--offline)"; }

# --------------------------------------------------------------------
if online; then
    section "Debian packages"
    # Every package name in the scripts' apt_install lines and package lists
    mapfile -t names < <(
        {
            printf '%s\n' "${PKGS[@]}" "${PARTS_PKGS[@]}"
            cat parts/*.sh extras/*.sh firefox-profiles/*.sh wifi.sh | awk '
                /(PKGS|LIBS|pkgs)\+?=\(/ { grab = 1 }
                /apt_install / && !/apt_install "/ { sub(/.*apt_install /, ""); sub(/[;|#].*/, ""); print; next }
                grab { line = $0; sub(/.*=\(/, "", line); if (sub(/\).*/, "", line)) grab = 0; print line }' |
                tr -s ' ()' '\n'
        } | grep -E '^[a-z0-9][a-z0-9.+-]+$' | sort -u
    )
    # Not from Debian: checked further down
    elsewhere=" claude-code mullvad-vpn mullvad-browser sparrowwallet "
    missing=()
    for p in "${names[@]}"; do
        [[ $elsewhere == *" $p "* ]] && continue
        cand=$(apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/ { print $2 }')
        if [ -z "$cand" ] || [ "$cand" = "(none)" ]; then missing+=("$p"); fi
    done
    for p in "${missing[@]}"; do
        if [ "$p" = torbrowser-launcher ] &&
            wget -q --spider "https://packages.debian.org/$DEBIAN_RELEASE/$p"; then
            meh "$p is in Debian's contrib section, which this machine's apt doesn't use"
        else
            bad "Debian package $p not found (renamed or removed?)"
        fi
    done
    [ ${#missing[@]} -gt 0 ] || ok "all ${#names[@]} packages exist"

    # ----------------------------------------------------------------
    section "Signing keys: still published, still the pinned key, not expiring"
    check_key() { # NAME FPR URL
        local f="$TMP/key-$1" fpr exp sig
        if ! wget -qO "$f" "$3"; then bad "$1: key not downloadable from $3"; return; fi
        fpr=$(gpg --show-keys --with-colons "$f" 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }')
        if [ "$fpr" != "$2" ]; then bad "$1: key at $3 is $fpr, pinned $2"; return; fi
        exp=$(gpg --show-keys --with-colons "$f" 2>/dev/null | awk -F: '/^pub/ { print $7; exit }')
        # A signing-capable key or subkey that's neither expired nor revoked
        sig=$(gpg --show-keys --with-colons "$f" 2>/dev/null |
            awk -F: '($1 == "pub" || $1 == "sub") && $12 ~ /s/ && $2 !~ /[er]/ && ($7 == "" || $7 > '"$now"') { n++ } END { print n + 0 }')
        if [ -n "$exp" ] && [ "$exp" -lt $((now + 90 * 86400)) ]; then
            meh "$1: key expires $(date -d "@$exp" +%F); its owner usually extends it, re-check then"
        elif [ "$sig" -eq 0 ]; then
            bad "$1: key has no valid signing key left"
        else
            ok "$1: $fpr"
        fi
    }
    check_key "Claude Code" "$ANTHROPIC_FPR" "$ANTHROPIC_KEY_URL"
    check_key "Tor Browser" "$TB_FPR" "$TB_KEY_URL"
    check_key "Whonix" "$WHONIX_FPR" "$WHONIX_KEY_URL"
    check_key "Feather" "$FEATHER_FPR" "$FEATHER_KEY_URL"
    check_key "SimpleX" "$SIMPLEX_FPR" "$SIMPLEX_KEY_URL"
    check_key "Sparrow" "$SPARROW_FPR" "$SPARROW_KEY_URL"
    check_key "Mullvad" "$MULLVAD_FPR" "$MULLVAD_KEY_URL"

    # ----------------------------------------------------------------
    section "Newest releases: found, and signed by the pinned key"
    exists() { wget -q --spider "$1"; }

    v=$(wget -qO- https://aus1.torproject.org/torbrowser/update_3/release/download-linux-x86_64.json |
        sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    if [[ $v =~ ^[0-9.]+$ ]]; then
        u="https://dist.torproject.org/torbrowser/$v/tor-browser-linux-x86_64-$v.tar.xz"
        exists "$u" && exists "$u.asc" && ok "Tor Browser $v (fetch-tor-browser.sh)" ||
            bad "Tor Browser $v: download or signature missing at $u"
        [ "${v%%.*}" = "$TB_SAFEST_VERSION" ] ||
            meh "Tor Browser is now $v; re-check config/tor-browser-safest.js against its SecurityLevel.sys.mjs, then TB_SAFEST_VERSION in pins.sh"
    else
        bad "Tor Browser: can't read the newest version (download-linux-x86_64.json changed?)"
    fi

    v=$(wget -qO- https://www.whonix.org/wiki/KVM |
        grep -o "download/libvirt/[0-9.]*/Whonix-LXQt-[0-9.]*\.Intel_AMD64" |
        sed 's|.*/Whonix-[^-]*-\(.*\)\.Intel_AMD64|\1|' | sort -uV | tail -1)
    if [[ $v =~ ^[0-9.]+$ ]]; then
        u="https://www.whonix.org/download/libvirt/$v/Whonix-LXQt-$v.Intel_AMD64.qcow2.libvirt.xz"
        exists "$u" && wget -qO "$TMP/w.asc" "$u.asc" && ok "Whonix $v (extras/whonix.sh)" ||
            bad "Whonix $v: download or signature missing at $u"
        [ "${v%%.*}" = "$WHONIX_TESTED_VERSION" ] ||
            meh "Whonix is now $v; re-check the image edits in extras/whonix.sh, then WHONIX_TESTED_VERSION"
    else
        bad "Whonix: can't read the newest version from whonix.org/wiki/KVM"
    fi

    v=$(latest_github_tag feather-wallet/feather)
    F=https://featherwallet.org/files/releases
    if [ -n "$v" ] && wget -qO "$TMP/fh" "$F/hashes-$v.txt" &&
        verify_clearsigned "$FEATHER_FPR" "$FEATHER_KEY_URL" "$TMP/fh" "$TMP/fs" 2>/dev/null &&
        grep -q "feather-$v.AppImage" "$TMP/fs" && exists "$F/linux-appimage/feather-$v.AppImage"; then
        ok "Feather $v: signed hash list and AppImage"
    else
        bad "Feather ${v:-?}: release, hash list or signature not as expected"
    fi

    v=$(latest_github_tag simplex-chat/simplex-chat)
    G=https://github.com/simplex-chat/simplex-chat/releases/download/$v
    if [ -n "$v" ] && wget -qO "$TMP/ss" "$G/_sha256sums" && wget -qO "$TMP/ss.asc" "$G/_sha256sums.asc" &&
        verify_detached "$SIMPLEX_FPR" "$SIMPLEX_KEY_URL" "$TMP/ss.asc" "$TMP/ss" 2>/dev/null &&
        grep -q "$v/simplex-desktop-x86_64.AppImage" "$TMP/ss"; then
        ok "SimpleX $v: signed hash list"
    else
        bad "SimpleX ${v:-?}: release, hash list or signature not as expected"
    fi

    v=$(latest_github_tag sparrowwallet/sparrow)
    G=https://github.com/sparrowwallet/sparrow/releases/download/$v
    if [ -n "$v" ] && wget -qO "$TMP/sm" "$G/sparrow-$v-manifest.txt" &&
        wget -qO "$TMP/sm.asc" "$G/sparrow-$v-manifest.txt.asc" &&
        verify_detached "$SPARROW_FPR" "$SPARROW_KEY_URL" "$TMP/sm.asc" "$TMP/sm" 2>/dev/null &&
        grep -q "sparrowwallet_$v-1_amd64.deb" "$TMP/sm"; then
        ok "Sparrow $v: signed manifest lists the .deb"
    else
        bad "Sparrow ${v:-?}: release, manifest or signature not as expected"
    fi

    check_repo() { # NAME FPR KEYURL BASE PACKAGES...
        local name=$1 fpr=$2 key=$3 base=$4 p
        shift 4
        if ! wget -qO "$TMP/ir" "$base/InRelease" ||
            ! verify_clearsigned "$fpr" "$key" "$TMP/ir" "$TMP/ir.txt" 2>/dev/null; then
            bad "$name apt repository: InRelease missing or not signed by the pinned key"
            return
        fi
        wget -qO "$TMP/pk" "$base/main/binary-amd64/Packages" ||
            { bad "$name apt repository: no package list"; return; }
        for p in "$@"; do
            grep -qx "Package: $p" "$TMP/pk" || { bad "$name apt repository has no $p"; return; }
        done
        ok "$name apt repository: signed, has $*"
    }
    check_repo "Mullvad" "$MULLVAD_FPR" "$MULLVAD_KEY_URL" \
        https://repository.mullvad.net/deb/stable/dists/stable mullvad-vpn mullvad-browser
    check_repo "Claude Code" "$ANTHROPIC_FPR" "$ANTHROPIC_KEY_URL" \
        https://downloads.claude.ai/claude-code/apt/stable/dists/stable claude-code
fi

# --------------------------------------------------------------------
section "Saved offline copies"
any=false
for f in torbrowser/tor-browser-linux-*.tar.xz; do
    [ -f "$f" ] || continue
    any=true
    verify_detached "$TB_FPR" torbrowser/tor-browser-developers.asc "$f.asc" "$f" 2>/dev/null &&
        ok "$f verifies" || bad "$f doesn't verify: run fetch-tor-browser.sh again"
done
for f in whonix/Whonix-*.libvirt.xz; do
    [ -f "$f" ] || continue
    any=true
    verify_detached "$WHONIX_FPR" whonix/derivative.asc "$f.asc" "$f" 2>/dev/null &&
        ok "$f verifies" || bad "$f doesn't verify: run extras/whonix.sh --fetch again"
done
if [ -f debs/Packages ]; then
    any=true
    ok "debs/: $(grep -c '^Package:' debs/Packages) packages for wifi.sh"
fi
$any || ok "none saved (that's fine)"

# --------------------------------------------------------------------
printf '\n%d ok, %d warnings, %d failures\n' "$n_ok" "$n_warn" "$n_fail"
[ "$n_fail" -eq 0 ]
