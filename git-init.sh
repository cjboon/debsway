#!/bin/bash
# git-init.sh: makes this copy of Wren Linux (from an install stick or a
# download, which have the files but no git) a git checkout of the published
# Wren Linux, so update.sh can bring in what is new. It changes no file.
#  - It fetches the published history (WREN_GIT_URL in pins.sh), and, once
#    pins.sh names Wren Linux's signing key, only if the newest commit there is
#    signed by exactly that key.
#  - It finds the published commit whose files are exactly yours. Found, your
#    copy is set at that commit, and update.sh then offers what came after it.
#    Not found, your files differ from everything that was published (changed
#    by you, or on the stick by someone else): it says so, and git status
#    shows what differs.
#  - It offers a GitHub login, which pushing needs (fetching doesn't), also on a
#    copy that is a checkout already. It never pushes: that stays yours to do.
# Usage: bash git-init.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
. "$WREN_DIR/lib/update.sh"
. "$WREN_DIR/lib/appimage.sh"
not_root

g() { git -C "$WREN_DIR" "$@"; }

# offer_login: for a copy whose server is GitHub, with no login yet
offer_login() {
    local gh=${WREN_GH:-gh}
    case $(g remote get-url origin 2>/dev/null) in *github.com[/:]*) ;; *) return 0 ;; esac
    if ! command -v "$gh" >/dev/null; then
        note "To push to GitHub from here you need a login: wrenctl install git offers gh, which does that."
        return 0
    fi
    if "$gh" auth status >/dev/null 2>&1; then return 0; fi
    if ask "Log in to GitHub, to push from here? (Updates need no login.)" n; then
        "$gh" auth login --hostname github.com --git-protocol https && "$gh" auth setup-git ||
            warn "That didn't work; nothing else was changed. Try again later: gh auth login && gh auth setup-git"
    else
        note "Later: gh auth login --hostname github.com --git-protocol https && gh auth setup-git"
    fi
}

if [ -e "$WREN_DIR/.git" ]; then
    note "$WREN_DIR is a git checkout already ($(g remote get-url origin 2>/dev/null || echo "no server set")); nothing to do."
    offer_login
    exit 0
fi
[ -w "$WREN_DIR" ] || die "$WREN_DIR is read-only (the Wren Linux package's?): apt brings its updates."
url=${WREN_GIT_URL:?pins.sh has no WREN_GIT_URL}
need_tools git:git
case $url in
    file://*) ;;
    *) have_internet || die "Not online. Connect first (bash $WREN_DIR/wifi.sh), then run this again." ;;
esac

say "Fetching the published Wren Linux from $url"
undo() { rm -rf "$WREN_DIR/.git"; }
g init -q -b main
g remote add origin "$url"
if ! g fetch -q origin main; then
    undo
    die "Couldn't fetch from $url; nothing was changed."
fi
tip=$(g rev-parse origin/main)

# Only what Wren Linux's own key signed, once it is pinned (as update.sh)
if [ -n "${WREN_SIGNING_FPR:-}" ]; then
    if ! update_signed "$tip"; then
        undo
        die "The newest commit at $url isn't signed by Wren Linux's key ($WREN_SIGNING_FPR); nothing was changed. Someone may have changed what that server gives you."
    fi
    note "The newest commit is signed by Wren Linux's key ($WREN_SIGNING_FPR)."
else
    note "(Its signature is not checked: no signing key is pinned in pins.sh yet.)"
fi

# Your files, each by its contents (what .gitignore leaves out, offline/ and
# ignore/, isn't counted; nor is the executable mark, which a FAT stick loses),
# and the published commit that has exactly those files
index=$(mktemp)
rm -f "$index"
GIT_INDEX_FILE=$index g add -A
GIT_INDEX_FILE=$index g ls-files -s | awk '{ print $2, $4 }' >"$index.mine"
rm -f "$index"
match=
while read -r c; do
    if g ls-tree -r "$c" | awk '{ print $3, $4 }' | cmp -s - "$index.mine"; then match=$c; break; fi
done < <(g rev-list origin/main)
rm -f "$index.mine"

if [ -n "$match" ]; then
    g reset -q "$match"
    g branch -q -u origin/main
    # the same contents: this only gives back the executable marks a stick lost
    g checkout -q -- .
    behind=$(g rev-list --count "$match..origin/main")
    say "Your copy is exactly the published commit $(g log -1 --format='%h (%ad): %s' --date=short "$match")"
    if [ "$behind" = 0 ]; then
        note "That is the newest: you are up to date."
    else
        note "$behind newer commits are published: bash $WREN_DIR/update.sh shows them and brings them in."
    fi
    offer_login
else
    g reset -q origin/main
    g branch -q -u origin/main
    warn "Your files aren't exactly any commit that was published at $url."
    warn "Either you changed them, or someone changed them on the stick. Before you run anything"
    warn "that uses sudo, look at what differs:  git -C $WREN_DIR status   and   git -C $WREN_DIR diff"
    exit 1
fi
