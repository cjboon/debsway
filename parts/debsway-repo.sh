#!/bin/bash
# debsway's own apt repository, so updates to debsway come as signed packages
# (tools/make-apt-repo.sh makes it). It does nothing until pins.sh names both
# debsway's signing key (DEBSWAY_SIGNING_FPR) and the repository's address
# (DEBSWAY_REPO_URL). Then:
#  - the key, from this copy's data/debsway-signing-key.asc and only if it is
#    exactly the pinned one, goes to /usr/share/keyrings/debsway-archive-keyring.asc,
#    and the repository is trusted with that key alone (Signed-By), never for
#    Debian's packages;
#  - an apt pin lets only the package debsway come from it: whoever got hold of
#    the key or the server still couldn't replace a Debian package or add any
#    other;
#  - unattended-upgrades installs its updates, as it does Debian's.
# Usage: bash debsway-repo.sh [--remove]
# status: file:/etc/apt/sources.list.d/debsway.sources
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

KEY=/usr/share/keyrings/debsway-archive-keyring.asc
LIST=/etc/apt/sources.list.d/debsway.sources
PREF=/etc/apt/preferences.d/debsway.pref

if [ "${1:-}" = --remove ]; then
    $SUDO rm -f "$LIST" "$PREF" "$KEY"
    forget_unattended_updates debsway
    note "debsway's repository is gone; the debsway package (if installed) stays, and gets no more updates from it."
    exit
fi

if [ -z "${DEBSWAY_SIGNING_FPR:-}" ] || [ -z "${DEBSWAY_REPO_URL:-}" ]; then
    note "debsway's own apt repository isn't set up yet (pins.sh has no DEBSWAY_SIGNING_FPR or DEBSWAY_REPO_URL); nothing changed."
    exit 0
fi
# https, or an onion address (Tor's own encryption): the signature protects the
# packages either way, this keeps what you fetch from your network
[[ $DEBSWAY_REPO_URL =~ ^(https://[A-Za-z0-9.-]+|http://[a-z2-7]{56}\.onion)(/[A-Za-z0-9._~/-]*)?$ ]] ||
    die "DEBSWAY_REPO_URL in pins.sh isn't an https:// or .onion address: $DEBSWAY_REPO_URL"
host=${DEBSWAY_REPO_URL#*://}
host=${host%%/*}

say "debsway's own apt repository"
src=$DEBSWAY_DIR/data/debsway-signing-key.asc
key_ok "$src" "$DEBSWAY_SIGNING_FPR" ||
    die "$src isn't exactly the pinned key $DEBSWAY_SIGNING_FPR (or it can't sign any more); nothing changed."
$SUDO install -D -m 0644 "$src" "$KEY"
note "Key: $DEBSWAY_SIGNING_FPR (the one pinned in pins.sh)"

printf '%s\n' "# Written by debsway parts/debsway-repo.sh. Only the package debsway" \
    "# comes from debsway's repository; nothing else there can be installed." \
    "Package: debsway" "Pin: origin $host" "Pin-Priority: 500" "" \
    "Package: *" "Pin: origin $host" "Pin-Priority: -1" | $SUDO tee "$PREF" >/dev/null
printf '%s\n' "# Written by debsway parts/debsway-repo.sh" "Types: deb" "URIs: $DEBSWAY_REPO_URL" \
    "Suites: $DEBIAN_RELEASE" "Components: main" "Architectures: $(dpkg --print-architecture)" "Signed-By: $KEY" |
    $SUDO tee "$LIST" >/dev/null
allow_unattended_updates debsway "$host"
note "From now on apt takes debsway from $DEBSWAY_REPO_URL, signed by that key, and nothing else."
note "Install it with: sudo apt update && sudo apt install debsway"
