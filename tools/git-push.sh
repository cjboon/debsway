#!/bin/bash
# git-push.sh: publishes this git copy of Wren Linux, signed. Every computer that
# has the pin takes an update only if its newest commit is signed by Wren Linux's
# key, so this won't push anything else. As you, in a terminal; sudo asks for your
# password when the key signs.
#  - The first time, it sets git up to sign with the key (wren-key git-setup), and
#    pins the key: pins.sh and data/wren-signing-key.asc, both committed.
#  - It shows what would go out. If the newest commit isn't signed (a helper's work,
#    say), it signs it, with an empty commit on top that vouches for those below.
#  - It says what CI thinks of it, and asks first if CI failed or hasn't finished.
#  - It checks that signature as a computer updating would, then asks before it pushes.
#  - Pushing to GitHub over https, it asks your GitHub username once, and shows it each time.
# It only ever pushes main, and never forces.
# Usage: bash tools/git-push.sh
#        bash tools/git-push.sh --username [NAME]   change that name, and do nothing else
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$WREN_DIR/lib/appimage.sh"
. "$WREN_DIR/lib/update.sh"
not_root

g() { git -C "$WREN_DIR" "$@"; }
PRINT=${XDG_DATA_HOME:-$HOME/.local/share}/wren/signing-key/fingerprint

# The name git gives GitHub at a push over https. It is an ordinary git setting in your own
# ~/.gitconfig, the one wrenctl git makes, and no secret. Your token is: git still asks for
# that at each push, and nothing here sees it or keeps it.
USERNAME_SETTING=credential.https://github.com.username
username_command() {
    if command -v wren-release >/dev/null; then echo "wren-release --username"; else echo "bash $WREN_DIR/tools/release.sh --username"; fi
}
# GitHub's own rule for names. It also catches a token pasted by mistake (they are longer, or
# have a _), so what fails it is never kept or shown back.
username_ok() { [[ $1 =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,37}[A-Za-z0-9])?$ ]] && [[ $1 != *--* ]]; }
# ask_username: asks until it has a good name and keeps it; Enter leaves things as they are.
ask_username() {
    local name
    while :; do
        tty_read name "GitHub username (only your name, not your token; Enter to skip): "
        [ -n "$name" ] || { note "No name kept: git will ask for it at the push."; return 0; }
        if username_ok "$name"; then
            git config --global "$USERNAME_SETTING" "$name" || die "Couldn't save it in your git settings."
            note "Saved: $name. To change it: $(username_command)"
            return 0
        fi
        warn "That isn't a GitHub username (letters, numbers and single hyphens), so it wasn't kept."
    done
}
# github_username: asks the first time, then reminds you. Only for a push that uses it: an ssh
# address or another server doesn't, nor a login like gh's, which gives git the name itself.
github_username() {
    local name helper
    case $(g config --get remote.origin.url) in https://github.com/*) ;; *) return 0 ;; esac
    helper=$(g config --get-urlmatch credential.helper https://github.com || true)
    case $helper in "" | cache*) ;; *) return 0 ;; esac
    name=$(g config --get-urlmatch credential.username https://github.com || true)
    if [ -z "$name" ]; then
        ask_username
    else
        note "Pushing to GitHub as $(printable <<<"$name"). To change it: $(username_command)"
    fi
}
if [ "${1:-}" = --username ]; then
    if [ -z "${2:-}" ]; then
        ask_username
    else
        username_ok "$2" || die "That isn't a GitHub username (letters, numbers and single hyphens), so it wasn't kept."
        git config --global "$USERNAME_SETTING" "$2" || die "Couldn't save it in your git settings."
        note "Saved: $2"
    fi
    exit 0
fi

# ci_says REPO COMMIT: what GitHub's CI says of it: passed, failed, running or nothing
# known. Read only, with no login. CI vouches for nothing: what goes out is what you read and
# sign. It's a warning at the moment that counts, not a gate, so that an outage or a
# change at GitHub can't hold back an urgent fix. (WREN_WGET: a test's pretend wget)
ci_says() {
    "${WREN_WGET:-wget}" -q -T 15 -O - "https://api.github.com/repos/$1/commits/$2/check-runs" 2>/dev/null | python3 -I -c '
import json, sys
try:
    runs = json.load(sys.stdin)["check_runs"]
    states = [(r["status"], r["conclusion"]) for r in runs]
except Exception:
    states = []
if not states:
    print("unknown")
elif any(s != "completed" for s, _ in states):
    print("running")
elif all(c in ("success", "skipped", "neutral") for _, c in states):
    print("passed")
else:
    print("failed")
' 2>/dev/null || echo unknown
}
# ci_check: says what CI thinks of what would go out; red or unfinished, it asks first
ci_check() {
    local repo commit says url
    repo=${WREN_CI_REPO:-$(g remote get-url origin | sed -nE 's#^(https://github\.com/|git@github\.com:)([A-Za-z0-9-]+/[A-Za-z0-9._-]+)$#\2#p' | sed 's/\.git$//')}
    [ -n "$repo" ] || return 0
    commit=$(g rev-parse HEAD)
    url=https://github.com/$repo/commit/$commit
    says=$(ci_says "$repo" "$commit")
    case $says in
        passed) note "CI passed on this commit." ;;
        failed)
            warn "CI failed on this commit: $url"
            ask "Publish it anyway?" n || die "Nothing was pushed." ;;
        running)
            warn "CI is still running on this commit: $url"
            ask "Publish it without waiting?" n || die "Nothing was pushed. Run this again when CI has finished." ;;
        *) note "CI can't say about this commit (not pushed for it to try, or GitHub didn't answer)." ;;
    esac
}

g rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "$WREN_DIR isn't a git copy (wrenctl install wren-dev gets one)."
[ "$(g rev-parse --abbrev-ref HEAD)" = main ] || die "This is for the branch main; you are on $(g rev-parse --abbrev-ref HEAD)."
[ -x "$BIN/wren-key" ] && [ -s "$PRINT" ] || die "There is no signing key here yet. Make one: bash $WREN_DIR/extras/signing-key.sh, then wren-key"
fpr=$(cat "$PRINT")

changed=$(g status --porcelain --untracked-files=no)
[ -z "$changed" ] || die "These have changes that aren't committed. Commit them, or put them back, first:
$changed"

say "Comparing with the server"
g fetch --quiet origin main || die "Couldn't reach the server; nothing was changed."
g merge-base --is-ancestor origin/main HEAD ||
    die "The server has commits this copy doesn't. Look at: git -C $WREN_DIR log HEAD..origin/main"

if [ "$(g config user.signingkey)" != "$fpr" ] || [ "$(g config commit.gpgsign)" != true ]; then
    say "Setting git up to sign with the key"
    "$BIN/wren-key" git-setup "$WREN_DIR"
fi

if ! grep -qx "WREN_SIGNING_FPR=$fpr" "$WREN_DIR/pins.sh"; then
    grep -qx 'WREN_SIGNING_FPR=' "$WREN_DIR/pins.sh" ||
        die "pins.sh pins another key: $(grep '^WREN_SIGNING_FPR=' "$WREN_DIR/pins.sh"). Nothing was changed."
    say "Pinning the key"
    note "From this push on, computers that update take only what this key signed:"
    note "  $fpr"
    ask "Pin it?" y || die "Nothing was pushed."
    "$BIN/wren-key" pin "$WREN_DIR"
    # Both files: a pin with no key file makes a computer refuse every update after it
    g add pins.sh data/wren-signing-key.asc
    g commit --quiet -m 'Wren Linux is signed with its own key now' || die "The commit wasn't made (did the key sign it?). Nothing was pushed."
fi
WREN_SIGNING_FPR=$fpr

github_username

if [ "$(g rev-list --count origin/main..HEAD)" = 0 ]; then
    note "Nothing to push: the server has all of this."
    exit 0
fi

say "What would go out"
# (as plain text: a helper's commit message could steer the terminal otherwise)
g --no-pager log --format='  %h %s' origin/main..HEAD | printable
echo

ci_check
if ! update_signed HEAD; then
    note "The newest commit isn't signed. Signing vouches for everything listed above."
    ask "Sign it?" y || die "Nothing was pushed: computers with the pin would refuse it unsigned."
    g commit --quiet --allow-empty -m 'Signed: the commits below are reviewed' ||
        die "The key didn't sign it. Nothing was pushed."
fi

# As a computer updating would check it, on what is committed
update_signed HEAD || die "The newest commit doesn't carry a good signature from $fpr. Nothing was pushed."
g show HEAD:pins.sh | grep -qx "WREN_SIGNING_FPR=$fpr" || die "The commit doesn't pin this key. Nothing was pushed."
g cat-file -e HEAD:data/wren-signing-key.asc 2>/dev/null || die "The commit has no data/wren-signing-key.asc. Nothing was pushed."
note "The newest commit is signed by Wren Linux's key: $fpr"

ask "Push these to $(g remote get-url origin)?" n || { note "Nothing was pushed. They stay here, signed."; exit 0; }
g push --quiet origin main || die "The push didn't go through. If it was about your login, or your email (GH007): wrenctl git $WREN_DIR"
# (tools/release.sh goes on to install it by itself)
[ -n "${WREN_RELEASING:-}" ] || note "Pushed. To install it on this computer: bash $WREN_DIR/tools/release.sh --local"
