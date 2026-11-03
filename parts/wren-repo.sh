#!/bin/bash
# Wren Linux's own apt repository, so updates to Wren Linux come as signed packages
# (tools/make-apt-repo.sh makes it). It does nothing until pins.sh names both
# Wren Linux's signing key (WREN_SIGNING_FPR) and the repository's address
# (WREN_REPO_URL). Then:
#  - the key, from this copy's data/wren-signing-key.asc and only if it is
#    exactly the pinned one, goes to /usr/share/keyrings/wren-archive-keyring.asc,
#    and the repository is trusted with that key alone (Signed-By), never for
#    Debian's packages;
#  - an apt pin lets only the package Wren Linux come from it: whoever got hold of
#    the key or the server still couldn't replace a Debian package or add any
#    other;
#  - unattended-upgrades installs its updates, as it does Debian's.
# Usage: bash wren-repo.sh [--remove]
# status: file:/etc/apt/sources.list.d/wren.sources
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

KEY=/usr/share/keyrings/wren-archive-keyring.asc
LIST=/etc/apt/sources.list.d/wren.sources
PREF=/etc/apt/preferences.d/wren.pref

if [ "${1:-}" = --remove ]; then
    $SUDO rm -f "$LIST" "$PREF" "$KEY"
    forget_unattended_updates wren-linux
    note "Wren Linux's repository is gone; the Wren Linux package (if installed) stays, and gets no more updates from it."
    exit
fi

if [ -z "${WREN_SIGNING_FPR:-}" ] || [ -z "${WREN_REPO_URL:-}" ]; then
    note "Wren Linux's own apt repository isn't set up yet (pins.sh has no WREN_SIGNING_FPR or WREN_REPO_URL); nothing changed."
    exit 0
fi
# https, or an onion address (Tor's own encryption): the signature protects the
# packages either way, this keeps what you fetch from your network
[[ $WREN_REPO_URL =~ ^(https://[A-Za-z0-9.-]+|http://[a-z2-7]{56}\.onion)(/[A-Za-z0-9._~/-]*)?$ ]] ||
    die "WREN_REPO_URL in pins.sh isn't an https:// or .onion address: $WREN_REPO_URL"
host=${WREN_REPO_URL#*://}
host=${host%%/*}

say "Wren Linux's own apt repository"
src=$WREN_DIR/data/wren-signing-key.asc
key_ok "$src" "$WREN_SIGNING_FPR" ||
    die "$src isn't exactly the pinned key $WREN_SIGNING_FPR (or it can't sign any more); nothing changed."
$SUDO install -D -m 0644 "$src" "$KEY"
note "Key: $WREN_SIGNING_FPR (the one pinned in pins.sh)"

printf '%s\n' "# Written by Wren Linux parts/wren-repo.sh. Only the package Wren Linux" \
    "# comes from Wren Linux's repository; nothing else there can be installed." \
    "Package: wren-linux" "Pin: origin $host" "Pin-Priority: 500" "" \
    "Package: *" "Pin: origin $host" "Pin-Priority: -1" | $SUDO tee "$PREF" >/dev/null
printf '%s\n' "# Written by Wren Linux parts/wren-repo.sh" "Types: deb" "URIs: $WREN_REPO_URL" \
    "Suites: $DEBIAN_RELEASE" "Components: main" "Architectures: $(dpkg --print-architecture)" "Signed-By: $KEY" |
    $SUDO tee "$LIST" >/dev/null
allow_unattended_updates wren-linux "$host"
note "From now on apt takes Wren Linux from $WREN_REPO_URL, signed by that key, and nothing else."
note "Install it with: sudo apt update && sudo apt install Wren Linux"
