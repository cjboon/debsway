# shellcheck shell=bash
# mullvad-repo.sh: Mullvad's apt repository, shared by mullvad-vpn.sh and
# mullvad-browser.sh. Sourced after lib.sh. The repository key is only
# trusted if its fingerprint is MULLVAD_FPR (pins.sh), Mullvad's code
# signing key as published at mullvad.net/en/help/verifying-signatures.

MULLVAD_KEY=/usr/share/keyrings/mullvad-keyring.asc
MULLVAD_LIST=/etc/apt/sources.list.d/mullvad.list

add_mullvad_repo() {
    local tmp fpr
    if [ ! -s "$MULLVAD_KEY" ]; then
        command -v gpg >/dev/null || apt_install gpg
        tmp=$(mktemp)
        wget -qO "$tmp" "$MULLVAD_KEY_URL" ||
            die "Couldn't download Mullvad's signing key."
        fpr=$(gpg --show-keys --with-colons "$tmp" | awk -F: '/^fpr/ { print $10; exit }')
        if [ "$fpr" != "$MULLVAD_FPR" ]; then
            rm -f "$tmp"
            die "Mullvad's key fingerprint is $fpr, expected $MULLVAD_FPR. Not trusting it."
        fi
        sudo install -m 0644 "$tmp" "$MULLVAD_KEY"
        rm -f "$tmp"
        note "Mullvad's key verified: $fpr"
    fi
    echo "deb [signed-by=$MULLVAD_KEY arch=$(dpkg --print-architecture)] https://repository.mullvad.net/deb/stable stable main" |
        sudo tee "$MULLVAD_LIST" >/dev/null
    # A fresh update, so apt sees Mullvad's packages
    unset DEBSWAY_APT_UPDATED
}

# Only once neither Mullvad package is left
remove_mullvad_repo_if_unused() {
    is_installed mullvad-vpn || is_installed mullvad-browser || {
        sudo rm -f "$MULLVAD_LIST" "$MULLVAD_KEY"
        note "Removed Mullvad's apt repository."
    }
}
