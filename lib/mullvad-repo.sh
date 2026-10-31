# shellcheck shell=bash
# lib/mullvad-repo.sh: Mullvad's apt repository, shared by mullvad-vpn.sh
# and mullvad-browser.sh. Sourced after lib.sh. The repository key is only
# trusted if it is exactly MULLVAD_FPR (pins.sh), Mullvad's code signing
# key as published at mullvad.net/en/help/verifying-signatures.

MULLVAD_KEY=/usr/share/keyrings/mullvad-keyring.asc
MULLVAD_LIST=/etc/apt/sources.list.d/mullvad.list

add_mullvad_repo() {
    install_apt_key "$MULLVAD_FPR" "$MULLVAD_KEY_URL" "$MULLVAD_KEY"
    echo "deb [signed-by=$MULLVAD_KEY arch=$(dpkg --print-architecture)] https://repository.mullvad.net/deb/stable stable main" |
        sudo tee "$MULLVAD_LIST" >/dev/null
    allow_unattended_updates mullvad repository.mullvad.net
    # A fresh update, so apt sees Mullvad's packages
    unset DEBSWAY_APT_UPDATED
}

# Only once neither Mullvad package is left
remove_mullvad_repo_if_unused() {
    is_installed mullvad-vpn || is_installed mullvad-browser || {
        sudo rm -f "$MULLVAD_LIST" "$MULLVAD_KEY"
        forget_unattended_updates mullvad
        note "Removed Mullvad's apt repository."
    }
}
