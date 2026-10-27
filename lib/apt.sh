# shellcheck shell=bash
# lib/apt.sh: installing and removing packages, and third-party apt
# repositories. Sourced by lib.sh.

# Installing and removing packages without breaking each other.
#
# Several scripts need the same packages (QEMU for Whonix and mockvps-kvm,
# XWayland for every X11 app). So a script's packages are not installed
# directly: apt_install builds a tiny package, debsway-NAME, that does
# nothing but depend on what NAME asked for, and installs that. The packages
# come in as its dependencies, which apt marks "automatic". apt_purge then
# removes debsway-NAME and lets apt autoremove whatever nothing else needs:
# a package another script's marker (or you, with apt-mark manual) still
# needs is kept. NAME is the script's own name, or $DEBSWAY_OWNER.

# apt_marker: the marker package for the running script
apt_marker() {
    local name=${DEBSWAY_OWNER:-$(basename -- "$0" .sh)}
    name=$(printf '%s' "$name" | tr 'A-Z_' 'a-z-' | tr -cd 'a-z0-9.+-')
    printf 'debsway-%s\n' "${name:-script}"
}

# marker_depends MARKER: the packages an installed MARKER depends on
marker_depends() {
    dpkg-query -W -f='${Depends}' "$1" 2>/dev/null | tr ',' '\n' |
        sed 's/^ *//; s/ *(.*//; s/ *$//' | grep . || true
}

# marker_build MARKER DIR PACKAGE...: writes DIR/MARKER.deb, an empty
# package that depends on the PACKAGEs
marker_build() {
    local marker=$1 dir=$2 root deps
    shift 2
    deps=$(printf '%s\n' "$@" | sort -u | paste -sd, - | sed 's/,/, /g')
    root=$(mktemp -d)
    mkdir -p "$root/DEBIAN"
    {
        echo "Package: $marker"
        # Newer than any earlier one, so a second call replaces the first
        echo "Version: 0.$(date +%s%N)"
        echo "Architecture: all"
        echo "Maintainer: debsway <debsway@localhost>"
        echo "Section: misc"
        echo "Priority: optional"
        echo "Depends: $deps"
        echo "Description: what ${marker#debsway-} installed, written by debsway"
        echo " Depends on the packages that debsway's ${marker#debsway-} script"
        echo " installed. Removing this package (or running that script with"
        echo " --remove) lets apt autoremove the ones nothing else needs."
    } >"$root/DEBIAN/control"
    dpkg-deb --root-owner-group --build "$root" "$dir/$marker.deb" >/dev/null
    rm -rf "$root"
}

# apt_drop PACKAGE...: this script no longer wants these (it switched to
# another package that conflicts with them). They are taken out of its
# marker's list the next time apt_install runs.
apt_drop() { APT_DROP+=("$@"); }
APT_DROP=()

# apt_install PACKAGE|FILE.deb...: installs them through the running
# script's marker package. A .deb file is installed first (the marker then
# depends on the package inside it).
apt_install() {
    local marker p name pkgs=() debs=() prev=() add=() all=() new=() tmp need_net=false stale=false
    marker=$(apt_marker)
    for p in "$@"; do
        if [[ $p == *.deb && -f $p ]]; then debs+=("$p"); else pkgs+=("$p"); fi
    done
    if is_installed "$marker"; then mapfile -t prev < <(marker_depends "$marker"); fi
    if [ ${#APT_DROP[@]} -gt 0 ] && [ ${#prev[@]} -gt 0 ]; then
        mapfile -t prev < <(printf '%s\n' "${prev[@]}" | grep -vxF -f <(printf '%s\n' "${APT_DROP[@]}") || true)
        # Even if nothing new is asked for, the marker must lose them
        stale=true
    fi
    for p in "${pkgs[@]}"; do
        if ! printf '%s\n' "${prev[@]}" | grep -qxF -- "$p"; then
            new+=("$p")
            is_installed "$p" || need_net=true
        fi
    done
    # Nothing new, so the marker already holds everything
    if [ ${#new[@]} -eq 0 ] && [ ${#debs[@]} -eq 0 ] && ! $stale; then return 0; fi

    if $need_net || [ ${#debs[@]} -gt 0 ]; then
        have_internet || die "No internet connection. Connect first: bash $DEBSWAY_DIR/wifi.sh"
        if [ -z "${DEBSWAY_APT_UPDATED:-}" ]; then
            $SUDO apt-get update
            export DEBSWAY_APT_UPDATED=1
        fi
    fi
    if [ ${#debs[@]} -gt 0 ]; then
        $SUDO apt-get install -y --no-install-recommends "${debs[@]}"
        for p in "${debs[@]}"; do
            name=$(dpkg-deb -f "$p" Package)
            add+=("$name")
        done
    fi

    all=("${prev[@]}" "${pkgs[@]}" "${add[@]}")
    tmp=$(mktemp -d)
    # apt reads the file as its own user, which can't enter a private folder
    chmod 755 "$tmp"
    marker_build "$marker" "$tmp" "${all[@]}"
    $SUDO apt-get install -y --no-install-recommends "$tmp/$marker.deb"
    rm -rf "$tmp"
    # A .deb installed from a file is "manual" to apt; make it automatic so
    # that removing the marker removes it. Packages that were already
    # installed stay as they are: they may belong to a script that installed
    # them before markers existed, and removing one script must not take
    # them from another.
    if [ ${#add[@]} -gt 0 ]; then $SUDO apt-mark auto "${add[@]}" >/dev/null; fi
}

# apt_purge PACKAGE...: removes what the running script installed with
# apt_install, except what other debsway scripts still need. PACKAGEs are
# used only when this script installed its packages before markers existed.
apt_purge() {
    local marker p other pkgs=()
    marker=$(apt_marker)
    if is_installed "$marker"; then
        $SUDO apt-get purge -y "$marker"
        $SUDO apt-get autoremove --purge -y
        return 0
    fi
    for p in "$@"; do
        is_installed "$p" || continue
        other=$(apt_needed_by_marker "$p")
        if [ -n "$other" ]; then
            note "Keeping $p: $other needs it."
        else
            pkgs+=("$p")
        fi
    done
    if [ ${#pkgs[@]} -gt 0 ]; then
        $SUDO apt-get purge -y "${pkgs[@]}"
        $SUDO apt-get autoremove --purge -y
    elif [ $# -eq 0 ]; then
        note "No packages were recorded for this script, so none are removed."
    fi
}

# apt_needed_by_marker PACKAGE: the first installed marker that depends on it
apt_needed_by_marker() {
    local m
    while read -r m; do
        if marker_depends "$m" | grep -qxF -- "$1"; then
            echo "${m#debsway-}"
            return 0
        fi
    done < <(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'debsway-*' 2>/dev/null |
        awk '$1 == "ii" { print $2 }')
}

# key_ok FILE FPR: FILE holds exactly one key, it is FPR, and it hasn't
# expired or been revoked. apt trusts every key in a signed-by file, so a
# file with a second key next to the pinned one must not pass.
key_ok() {
    local out
    out=$(gpg --show-keys --with-colons "$1" 2>/dev/null) || return 1
    [ "$(grep -c '^pub:' <<<"$out")" -eq 1 ] || return 1
    [ "$(awk -F: '/^fpr:/ { print $10; exit }' <<<"$out")" = "$2" ] || return 1
    awk -F: '/^pub:/ { exit ($2 ~ /[er]/) }' <<<"$out"
}

# install_apt_key FPR URL DEST: the signing key at URL, into DEST (for
# signed-by=), only if it is exactly the key with fingerprint FPR. A key
# already in DEST is checked again, and replaced if it no longer passes
# (expired, rotated, or tampered with).
install_apt_key() {
    local fpr=$1 url=$2 dest=$3 tmp
    command -v gpg >/dev/null || apt_install gpg
    if [ -s "$dest" ] && key_ok "$dest" "$fpr"; then return 0; fi
    tmp=$(mktemp)
    if ! wget -qO "$tmp" "$url"; then
        rm -f "$tmp"
        die "Couldn't download the signing key from $url"
    fi
    if ! key_ok "$tmp" "$fpr"; then
        rm -f "$tmp"
        die "The key at $url isn't exactly the pinned key $fpr (or it has expired). Not trusting it."
    fi
    $SUDO install -D -m 0644 "$tmp" "$dest"
    rm -f "$tmp"
    note "Key verified: $fpr"
}

# allow_unattended_updates NAME SITE: unattended-upgrades also installs the
# updates from the apt repository at SITE. By default it only takes
# Debian's, which would leave NAME's packages without security fixes.
allow_unattended_updates() {
    printf '%s\n' "// Written by debsway ($1)" \
        "Unattended-Upgrade::Origins-Pattern:: \"site=$2\";" |
        $SUDO tee "/etc/apt/apt.conf.d/52debsway-$1" >/dev/null
    note "Updates from $2 install themselves too."
}

forget_unattended_updates() { $SUDO rm -f "/etc/apt/apt.conf.d/52debsway-$1"; }
