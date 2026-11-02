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

# release_fresh FILE NAME: FILE is the signed text of NAME's InRelease. A
# signature proves who made a list, not when: someone who can write to the
# USB stick could put back an older, genuine, vulnerable set. Debian's
# security and updates lists say how long they are good for (Valid-Until,
# a week); the stable list has none, and keeps the date of the last point
# release (up to about two months), so that one is only refused when it is
# older than OFFLINE_MAX_AGE_DAYS. A date in the future is let through: a
# computer with no network often has a clock that is wrong. Returns 1, with
# a reason on stderr, for an old list. DEBSWAY_OFFLINE_ALLOW_STALE=1 accepts
# old lists on purpose; DEBSWAY_NOW (seconds) is for tests.
OFFLINE_MAX_AGE_DAYS=120
release_fresh() {
    local file=$1 name=$2 now date_s until_s date_t until_t
    [ "${DEBSWAY_OFFLINE_ALLOW_STALE:-}" != 1 ] || return 0
    now=${DEBSWAY_NOW:-$(date +%s)}
    date_s=$(sed -n 's/^Date: *//p' "$file" | head -1)
    until_s=$(sed -n 's/^Valid-Until: *//p' "$file" | head -1)
    # (date -d "" means today, so an empty Date is checked for first)
    date_t=
    if [ -n "$date_s" ]; then date_t=$(date -d "$date_s" +%s 2>/dev/null) || date_t=; fi
    if [ -z "$date_t" ]; then
        warn "$name/InRelease has no readable Date, so how old it is can't be checked."
    elif [ "$now" -gt $((date_t + OFFLINE_MAX_AGE_DAYS * 86400)) ]; then
        warn "$name/InRelease is from $date_s, more than $OFFLINE_MAX_AGE_DAYS days ago."
    elif [ -n "$until_s" ] && { until_t=$(date -d "$until_s" +%s 2>/dev/null) || until_t=0; [ "$now" -gt "$until_t" ]; }; then
        warn "$name/InRelease was only valid until $until_s."
    else
        return 0
    fi
    warn "Make the packages again on a machine you trust (bash prep/fetch-offline-debs.sh),"
    warn "or set DEBSWAY_OFFLINE_ALLOW_STALE=1 to accept old lists on purpose."
    return 1
}

# offline_good_until DIR: until when wifi.sh will take the saved lists in DIR
# (DIR/NAME/InRelease), as seconds since 1970: the earliest of each list's
# Date plus OFFLINE_MAX_AGE_DAYS and its Valid-Until. Nothing, if DIR has no
# list or one has no readable Date. (Only the dates: verify_offline_lists
# checks the signatures.)
offline_good_until() {
    local f d u t best=
    for f in "$1"/*/InRelease; do
        [ -f "$f" ] || continue
        d=$(sed -n 's/^Date: *//p' "$f" | head -1)
        [ -n "$d" ] && t=$(date -d "$d" +%s 2>/dev/null) || return 0
        t=$((t + OFFLINE_MAX_AGE_DAYS * 86400))
        u=$(sed -n 's/^Valid-Until: *//p' "$f" | head -1)
        if [ -n "$u" ] && u=$(date -d "$u" +%s 2>/dev/null) && [ "$u" -lt "$t" ]; then t=$u; fi
        if [ -z "$best" ] || [ "$t" -lt "$best" ]; then best=$t; fi
    done
    [ -z "$best" ] || echo "$best"
}

# verify_offline_lists DIR OUT: checks every DIR/NAME/InRelease against
# Debian's archive keyring and every Packages file against its InRelease,
# then writes the SHA-256 of every package they list to OUT. The signature is
# checked with sqv, which Debian 13's apt depends on, so it is there on a new
# install without a network; gpgv only if sqv isn't (it may not be installed). Returns 1, with
# a reason on stderr, if anything doesn't check out.
# check_inrelease HOME OUT INRELEASE --keyring K...: the signed text of
# INRELEASE into OUT, if one of the keyrings signed it
check_inrelease() {
    local home=$1 out=$2 file=$3 k sqvargs=()
    shift 3
    if command -v sqv >/dev/null; then
        while [ $# -gt 0 ]; do k=$2; sqvargs+=("--keyring=$k"); shift 2; done
        # (sqv won't write over a file)
        rm -f "$out"
        sqv "${sqvargs[@]}" --output="$out" --cleartext "$file" >/dev/null 2>&1
    else
        gpgv --quiet --homedir "$home" "$@" --output "$out" "$file" 2>/dev/null
    fi
}

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
        if ! check_inrelease "$home" "$rel" "$d/InRelease" "${keyargs[@]}"; then
            warn "The signature on $name/InRelease isn't Debian's."
            rc=1
            break
        fi
        if ! release_fresh "$rel" "$name"; then
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
