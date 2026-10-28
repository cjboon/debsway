#!/bin/bash
# Checks release_fresh (lib/offline.sh): old signed package lists are refused.
# Uses sample Release text and a pretend clock. Run by test.sh, or:
#   bash tools/test-offline-fresh.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/offline.sh"
set +e +o pipefail

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
at() { # DATE: the pretend "now"
    DEBSWAY_NOW=$(date -d "$1" +%s)
    export DEBSWAY_NOW
}

# What Debian's lists look like (see dists/trixie, -updates and -security)
printf 'Suite: stable\nCodename: trixie\nDate: Sat, 12 Sep 2026 07:55:41 UTC\n' >"$T/stable"
printf 'Suite: stable-security\nDate: Wed, 28 Oct 2026 21:40:30 UTC\nValid-Until: Wed, 04 Nov 2026 21:40:30 UTC\n' >"$T/security"
printf 'Suite: x\nCodename: y\n' >"$T/nodate"

at "2026-10-29 00:00 UTC"
check "a current security list passes" release_fresh "$T/security" security
check "the stable list from the last point release passes (no Valid-Until)" release_fresh "$T/stable" debian
at "2026-11-03 00:00 UTC"
check "a security list is good until its Valid-Until" release_fresh "$T/security" security
at "2026-11-05 00:00 UTC"
check "a security list is refused after its Valid-Until" not release_fresh "$T/security" security
at "2027-01-09 00:00 UTC"
check "the stable list is fine just under 120 days old" release_fresh "$T/stable" debian
at "2027-01-13 00:00 UTC"
check "the stable list is refused when older than 120 days" not release_fresh "$T/stable" debian
at "2026-01-01 00:00 UTC"
check "a list dated after this computer's clock is let through" release_fresh "$T/security" security
at "2026-10-29 00:00 UTC"
check "a list with no Date is refused" not release_fresh "$T/nodate" odd
at "2027-06-01 00:00 UTC"
# shellcheck disable=SC2016  # expanded by the inner bash, on purpose
check "DEBSWAY_OFFLINE_ALLOW_STALE=1 accepts an old list" env DEBSWAY_OFFLINE_ALLOW_STALE=1 DEBSWAY_NOW="$DEBSWAY_NOW" \
    bash -c '. "$1/lib.sh"; . "$1/lib/offline.sh"; release_fresh "$2" security' _ "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" "$T/security"

[ "$fails" -eq 0 ]
