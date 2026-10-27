# shellcheck shell=bash
# lib/offline.sh: checks that the .debs saved in offline/debs are really
# Debian's. Debian's packages aren't signed one by one; the archive signs
# its Release file, which lists the hash of each Packages file, which
# lists the hash of each .deb. prep/fetch-offline-debs.sh saves the signed
# Release files and Packages files next to the .debs (offline/debs/verify/),
# and wifi.sh walks that chain with Debian's own archive keyring before it
# installs anything from a USB stick. Sourced after lib.sh.

# The archives packages can come from: NAME BASE-URL SUITE. NAME is the
# folder under verify/.
offline_sources() {
    printf '%s\n' \
        "debian https://deb.debian.org/debian $DEBIAN_RELEASE" \
        "updates https://deb.debian.org/debian $DEBIAN_RELEASE-updates" \
        "security https://security.debian.org/debian-security $DEBIAN_RELEASE-security"
}
# Components with Wi-Fi software: firmware is in non-free-firmware
OFFLINE_COMPONENTS=(main non-free-firmware)

# fetch_offline_lists DIR: downloads each archive's InRelease and Packages
# files into DIR/NAME/ (COMPONENT_Packages.gz, or COMPONENT_Packages when
# the archive has no .gz; mirrors only serve that one compressed, so it is
# unpacked here). Nothing is trusted yet; verify_offline_lists
# does that.
fetch_offline_lists() {
    local dir=$1 name base suite comp rel want file
    rm -rf "$dir"
    while read -r name base suite; do
        mkdir -p "$dir/$name"
        if ! wget -q -O "$dir/$name/InRelease" "$base/dists/$suite/InRelease"; then
            warn "No $suite archive at $base; skipped."
            rm -rf "${dir:?}/$name"
            continue
        fi
        for comp in "${OFFLINE_COMPONENTS[@]}"; do
            # The Release file lists the names it has: prefer the gzipped one
            if grep -qE " $comp/binary-amd64/Packages\.gz\$" "$dir/$name/InRelease"; then
                want=Packages.gz
            elif grep -qE " $comp/binary-amd64/Packages\$" "$dir/$name/InRelease"; then
                want=Packages
            else
                continue
            fi
            file="$dir/$name/${comp}_$want"
            if [ "$want" = Packages ]; then
                # Mirrors only serve it compressed. The Release file also lists
                # the hash of the plain file, so that is what gets saved.
                command -v xz >/dev/null || die "xz is missing. Install it with: sudo apt install xz-utils"
                wget -q -O - "$base/dists/$suite/$comp/binary-amd64/Packages.xz" | xz -dc >"$file" ||
                    die "Couldn't download $base/dists/$suite/$comp/binary-amd64/Packages.xz"
            else
                wget -q -O "$file" "$base/dists/$suite/$comp/binary-amd64/$want" ||
                    die "Couldn't download $base/dists/$suite/$comp/binary-amd64/$want"
            fi
        done
    done < <(offline_sources)
}

# verify_offline_lists DIR OUT: checks every DIR/NAME/InRelease against
# Debian's archive keyring and every Packages file against its InRelease,
# then writes the SHA-256 of every package they list to OUT. Returns 1, with
# a reason on stderr, if anything doesn't check out.
verify_offline_lists() {
    local dir=$1 out=$2 k keyargs=() home rel d name pk base comp want got n=0 rc=0
    for k in /usr/share/keyrings/debian-archive-*.pgp /usr/share/keyrings/debian-archive-*.gpg; do
        if [ -r "$k" ] && [[ $k != *removed* ]]; then keyargs+=(--keyring "$k"); fi
    done
    if [ ${#keyargs[@]} -eq 0 ]; then
        warn "Debian's archive keyring isn't installed (package debian-archive-keyring)."
        return 1
    fi
    home=$(mktemp -d)
    rel=$(mktemp)
    : >"$out"
    for d in "$dir"/*/; do
        [ -f "$d/InRelease" ] || continue
        name=$(basename -- "$d")
        if ! gpgv --quiet --homedir "$home" "${keyargs[@]}" --output "$rel" "$d/InRelease" 2>/dev/null; then
            warn "The signature on $name/InRelease isn't Debian's."
            rc=1
            break
        fi
        for pk in "$d"/*_Packages "$d"/*_Packages.gz; do
            [ -f "$pk" ] || continue
            base=$(basename -- "$pk")
            comp=${base%%_Packages*}
            want=$(awk -v p="$comp/binary-amd64/${base#"${comp}"_}" '
                /^SHA256:/ { s = 1; next }
                /^[A-Za-z]/ { s = 0 }
                s && $3 == p { print $1; exit }' "$rel")
            got=$(sha256sum "$pk" | cut -d' ' -f1)
            if [ -z "$want" ] || [ "$want" != "$got" ]; then
                warn "$name/$base doesn't match the signed Release file."
                rc=1
                break 2
            fi
            case $pk in
                *.gz) zcat "$pk" ;;
                *) cat "$pk" ;;
            esac | awk '/^SHA256:/ { print $2 }' >>"$out"
            n=$((n + 1))
        done
    done
    rm -rf "$home" "$rel"
    if [ "$rc" -eq 0 ] && [ "$n" -eq 0 ]; then
        warn "No package lists to check against."
        rc=1
    fi
    return "$rc"
}

# check_offline_debs REPO SUMS: every .deb in REPO, and every package its
# Packages index describes, must have a SHA-256 from the verified lists, and
# the index may only name files in REPO itself.
check_offline_debs() {
    local repo=$1 sums=$2 f h bad=0
    for f in "$repo"/*.deb; do
        [ -f "$f" ] || continue
        h=$(sha256sum "$f" | cut -d' ' -f1)
        if ! grep -qxF "$h" "$sums"; then
            warn "${f##*/} isn't a package from Debian's archive (or is an old version of one)."
            bad=1
        fi
    done
    while read -r h; do
        grep -qxF "$h" "$sums" || { warn "Packages index lists a package that isn't Debian's."; bad=1; break; }
    done < <(awk '/^SHA256:/ { print $2 }' "$repo/Packages")
    if grep '^Filename:' "$repo/Packages" | grep -qvE '^Filename: \./[^/]+\.deb$'; then
        warn "Packages index points outside the folder."
        bad=1
    fi
    return "$bad"
}
