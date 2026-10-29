#!/bin/bash
# Checks verify_detached and verify_clearsigned (lib/appimage.sh) with throwaway
# keys made here: a good signature passes; a wrong key, a changed file, an
# expired key and a revoked key all fail. Changes nothing outside a temp
# folder. Run by test.sh, or:  bash tools/test-signatures.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib/appimage.sh"
set +e +o pipefail
command -v gpg >/dev/null || { echo "  ok    skipped: gpg isn't installed"; exit 0; }

T=$(mktemp -d)
trap 'gpgconf --homedir "$T/gh" --kill all 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
warn() { :; }  # the functions complain on failure; the checks only want the result

# latest_github_tag: the tag from GitHub's redirect goes into download addresses
# and file names, so only a plain one comes out (a pretend wget answers here)
mkdir -p "$T/fake"
cat >"$T/fake/wget" <<'EOF'
#!/bin/sh
printf '  Location: https://github.com/o/r/releases/tag/%s\n' "$(cat "$TAG_FILE")" >&2
EOF
chmod +x "$T/fake/wget"
tag_of() { printf '%s' "$1" >"$T/tag"; TAG_FILE=$T/tag PATH="$T/fake:$PATH" latest_github_tag o/r; }
check "a plain tag comes through" test "$(tag_of 2.8.1)" = 2.8.1
check "...and one with a v and a dash" test "$(tag_of v6.4.0-beta.1)" = v6.4.0-beta.1
# shellcheck disable=SC2016  # the $(id) is meant literally, as a hostile tag
for bad in '../../etc' '-O' '1.0;rm' '1.0$(id)' '1.0|x'; do
    check "a tag like '$bad' gives nothing" test -z "$(tag_of "$bad")"
done
check "feather-wallet.sh refuses a tag that isn't a version number" \
    grep -q 'version =~ ^\[0-9\]+(\\.\[0-9\]+)+\$' "$(dirname -- "${BASH_SOURCE[0]}")/../extras/feather-wallet.sh"


mkdir -m 700 "$T/gh"
# for a machine where gpg-agent isn't in the usual place
[ -z "${GPG_AGENT_PROGRAM:-}" ] || echo "agent-program $GPG_AGENT_PROGRAM" >"$T/gh/gpg.conf"
G=(gpg --homedir "$T/gh" --batch --quiet --pinentry-mode loopback --passphrase '')
fpr_of() { "${G[@]}" --list-keys --with-colons "$1" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }'; }

# A key made "in 2020" that lasts one day, so it has expired; one that is
# fine; and one that is revoked after use
"${G[@]}" --faked-system-time 20200101T000000 --quick-generate-key old@test ed25519 sign 1d
"${G[@]}" --quick-generate-key good@test ed25519 sign 1y
"${G[@]}" --quick-generate-key revoked@test ed25519 sign 1y
FOLD=$(fpr_of old@test)
FGOOD=$(fpr_of good@test)
FREV=$(fpr_of revoked@test)
[ -n "$FOLD" ] && [ -n "$FGOOD" ] && [ -n "$FREV" ] || { echo "  ok    skipped: gpg couldn't make test keys here (is gpg-agent installed?)"; [ "$fails" -eq 0 ]; exit; }
"${G[@]}" --export --armor good@test >"$T/good.pub"
"${G[@]}" --export --armor old@test >"$T/old.pub"

echo "release contents" >"$T/file"
"${G[@]}" --local-user "$FGOOD" --detach-sign --armor -o "$T/file.good.asc" "$T/file"
"${G[@]}" --faked-system-time 20200101T120000 --local-user "$FOLD" --detach-sign --armor -o "$T/file.old.asc" "$T/file"
"${G[@]}" --local-user "$FREV" --detach-sign --armor -o "$T/file.rev.asc" "$T/file"
"${G[@]}" --local-user "$FGOOD" --clearsign -o "$T/sums.good" "$T/file"
"${G[@]}" --faked-system-time 20200101T120000 --local-user "$FOLD" --clearsign -o "$T/sums.old" "$T/file"
# the revocation, published with the key
# (--gen-revoke refuses --batch, so it is answered through --command-fd)
printf 'y\n0\n\ny\n' | gpg --homedir "$T/gh" --quiet --no-tty --pinentry-mode loopback --passphrase '' \
    --command-fd 0 --output "$T/rev.cert" --gen-revoke "$FREV" 2>/dev/null
"${G[@]}" --import "$T/rev.cert" 2>/dev/null
"${G[@]}" --export --armor "$FREV" >"$T/rev.pub"

not() { ! "$@"; }
echo "changed" >"$T/file2"

check "a good signature passes" verify_detached "$FGOOD" "$T/good.pub" "$T/file.good.asc" "$T/file"
check "a signature checked against another key's fingerprint fails" not verify_detached "$FOLD" "$T/good.pub" "$T/file.good.asc" "$T/file"
check "a changed file fails" not verify_detached "$FGOOD" "$T/good.pub" "$T/file.good.asc" "$T/file2"
check "a signature from an expired key fails" not verify_detached "$FOLD" "$T/old.pub" "$T/file.old.asc" "$T/file"
check "a signature from a revoked key fails" not verify_detached "$FREV" "$T/rev.pub" "$T/file.rev.asc" "$T/file"
check "a clearsigned file from a good key passes" verify_clearsigned "$FGOOD" "$T/good.pub" "$T/sums.good" "$T/out.good"
check "a clearsigned file from an expired key fails" not verify_clearsigned "$FOLD" "$T/old.pub" "$T/sums.old" "$T/out.old"

[ "$fails" -eq 0 ]
