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
    WREN_NOW=$(date -d "$1" +%s)
    export WREN_NOW
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
check "WREN_OFFLINE_ALLOW_STALE=1 accepts an old list" env WREN_OFFLINE_ALLOW_STALE=1 WREN_NOW="$WREN_NOW" \
    bash -c '. "$1/lib.sh"; . "$1/lib/offline.sh"; release_fresh "$2" security' _ "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" "$T/security"

# The signature: checked with sqv (apt in Debian 13 depends on it, so a new
# install without a network has it), also where gpgv isn't installed
if command -v gpg >/dev/null && command -v sqv >/dev/null; then
    mkdir -m 700 "$T/gh"
    G=(gpg --homedir "$T/gh" --batch --quiet --passphrase '' --pinentry-mode loopback)
    for n in debian other; do
        "${G[@]}" --quick-gen-key "$n <$n@test>" ed25519 sign never 2>/dev/null
        "${G[@]}" --export "$n@test" >"$T/$n.pgp"
    done
    "${G[@]}" --local-user debian@test --clearsign -o "$T/InRelease" "$T/security" 2>/dev/null
    sed 's/^Suite: stable-security/Suite: evil/' "$T/InRelease" >"$T/tampered"
    "${G[@]}" --local-user other@test --clearsign -o "$T/other-signed" "$T/security" 2>/dev/null
    # only sqv and rm on the PATH: no gpgv
    mkdir "$T/nogpgv"
    for c in sqv rm; do ln -s "$(command -v "$c")" "$T/nogpgv/$c"; done
    ci() { # FILE: check_inrelease with Debian's pretend key, without gpgv
        rm -f "$T/out"
        # shellcheck disable=SC2123  # only sqv and rm, on purpose
        (PATH=$T/nogpgv; check_inrelease "$T/gh" "$T/out" "$1" --keyring "$T/debian.pgp")
    }
    ci "$T/InRelease"
    check "without gpgv: a list signed by the key passes, its text comes out" grep -qx 'Suite: stable-security' "$T/out"
    check "...a changed list is refused" not ci "$T/tampered"
    check "...so is one signed by another key" not ci "$T/other-signed"
else
    echo "  ok    skipped the signature checks: gpg or sqv isn't installed"
fi

[ "$fails" -eq 0 ]
