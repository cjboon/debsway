#!/bin/bash
# tag-release.sh: marks what's published on main as a release of Wren Linux: a signed tag
# named for the year and month (2026.11, then 2026.11.1 if there is another that
# month), whose message is the release notes. You read the notes, and may edit them.
#  - Only a commit that's already signed and on the server: tools/git-push.sh does both.
#  - It checks the tag's signature as anyone checking a release would: with the pinned key
#    alone, in a keyring of its own. Then it asks before it pushes the tag.
#  - A tag is never moved or replaced. A wrong release gets a newer one.
# The key signs after your sudo password, so this can't run unattended, on purpose: if
# a script could sign alone, so could anything else running as you.
# (wren-release --tag runs this after publishing)
# Usage: bash tools/tag-release.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$WREN_DIR/lib/appimage.sh"
. "$WREN_DIR/lib/update.sh"
not_root

g() { git -C "$WREN_DIR" "$@"; }
VERSION_RE='^[0-9]{4}\.[0-9]{2}(\.[0-9]+)?$'

# versions: this repository's releases, newest first
versions() { g tag --list '[0-9][0-9][0-9][0-9].[0-9][0-9]*' --sort=-v:refname | grep -E "$VERSION_RE" || true; }
# next_version: this month's, or the next one in this month (a test sets WREN_NOW)
next_version() {
    local base n=0
    base=$(date -u -d "@${WREN_NOW:-$(date +%s)}" +%Y.%m)
    g rev-parse --verify --quiet "refs/tags/$base" >/dev/null || { echo "$base"; return; }
    while n=$((n + 1)); g rev-parse --verify --quiet "refs/tags/$base.$n" >/dev/null; do :; done
    echo "$base.$n"
}
# tag_signed TAG: a good signature from the pinned key, whatever gpg git is set to use
tag_signed() {
    local home rc=0 key=$WREN_DIR/data/wren-signing-key.asc
    home=$(_keyring "$WREN_SIGNING_FPR" "$key") || return 1
    GNUPGHOME=$home git -C "$WREN_DIR" -c gpg.format=openpgp -c gpg.program=gpg -c gpg.openpgp.program=gpg \
        verify-tag --raw "$1" >/dev/null 2>"$home/status" || true
    _good_sig "$WREN_SIGNING_FPR" "$home/status" || rc=1
    _keyring_done "$home"
    return "$rc"
}

g rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "$WREN_DIR isn't a git copy (wrenctl install wren-dev gets one)."
[ "$(g rev-parse --abbrev-ref HEAD)" = main ] || die "A release comes from main; you are on $(g rev-parse --abbrev-ref HEAD)."
[ -n "${WREN_SIGNING_FPR:-}" ] || die "pins.sh pins no signing key, so nothing can be checked. Publish once first: bash tools/git-push.sh"
[ -z "$(g status --porcelain --untracked-files=no)" ] || die "There are changes that aren't committed. Commit them, or put them back, first."
g fetch --quiet origin main || die "Couldn't reach the server; nothing was changed."
[ "$(g rev-parse HEAD)" = "$(g rev-parse origin/main)" ] || die "This copy and the server's main differ. Publish first: bash tools/git-push.sh"
update_signed HEAD || die "The newest commit isn't signed by Wren Linux's key. Publish first: bash tools/git-push.sh"

last=$(versions | head -n1)
if [ -n "$last" ] && [ "$(g rev-parse "$last^{commit}")" = "$(g rev-parse HEAD)" ]; then
    note "This commit is already release $last; nothing to do."
    exit 0
fi

version=$(next_version)
notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
{
    echo "Wren Linux $version"
    echo
    # (as plain text: a helper's commit message could steer the terminal otherwise)
    g log --no-merges --format='- %s' "${last:+$last..}HEAD" | grep -vE '^- Signed: ' | printable
} >"$notes"

say "Wren Linux $version${last:+, since $last}"
cat "$notes"
echo
if [ -n "${VISUAL:-${EDITOR:-}}" ] && ask "Edit these notes first?" y; then
    ${VISUAL:-$EDITOR} "$notes" || die "The editor failed; nothing was changed."
fi
[ -s "$notes" ] || die "The notes are empty; nothing was changed."

ask "Sign this as release $version?" y || { note "Nothing was changed."; exit 0; }
g tag --sign --file="$notes" "$version" HEAD || die "The key didn't sign it. Nothing was changed."
if ! tag_signed "$version"; then
    g tag --delete "$version" >/dev/null
    die "The tag's signature didn't check out with the pinned key, so it was deleted. Nothing was pushed."
fi
note "Signed by Wren Linux's key: $version"

if ! ask "Push the tag to $(g remote get-url origin)?" n; then
    note "Not pushed; it stays here, signed. To push it later: git -C $WREN_DIR push origin refs/tags/$version"
    exit 0
fi
g push --quiet origin "refs/tags/$version" || die "The push didn't go through; the tag stays here, signed."
note "Released $version. To publish an install image of it: bash $WREN_DIR/tools/publish-image.sh"
