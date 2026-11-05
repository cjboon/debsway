#!/bin/bash
# gh-helper.sh: sets up GitHub's gh for you, with a token you make (a fine-grained
# personal access token), and the rules that keep a repository's main branch
# yours. It never pushes, and changes no file of a repository.
#  - gh comes from Debian (its package, signed by Debian, updated by apt).
#  - The token: by default nothing is saved, and each command that needs it asks
#    for it, hidden. Saved (your choice), gh keeps it in your keyring if you run
#    one, otherwise in plain text in ~/.config/gh/hosts.yml, readable by every
#    program of yours: a token for one repository, with an expiry date, then.
#  - rulesets: on GitHub, main may be updated only by the repository's admins
#    (you), and by nobody force-pushed or deleted. A helper's deploy key (Claude
#    in claude-vm) can then push its own branch, never main. They are added only
#    if missing, then the rules that apply to main are read back.
# Usage: bash gh-helper.sh                       install gh; save a token, or not
#        bash gh-helper.sh rulesets [OWNER/REPO] the rules on main (default: this
#                                              copy's GitHub repository)
#        bash gh-helper.sh --logout              forget a saved token
# (wrenctl gh runs it)
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
not_root

# (a test points it at a pretend one)
GH=${WREN_GH:-gh}
RULE_ONLY_OWNER="main: only the owner updates it"
RULE_NO_FORCE="main: no force-push, no delete"
TOKEN_PAGE=https://github.com/settings/personal-access-tokens/new

# secret VAR "Prompt": a line typed without showing it
secret() {
    local _s=
    if [ -n "${WREN_TEST_ANSWERS:-}" ]; then
        tty_read _s "$2"
    elif { : </dev/tty; } 2>/dev/null; then
        IFS= read -rs -p "$2" _s </dev/tty || _s=
        echo >/dev/tty
    fi
    printf -v "$1" '%s' "$_s"
}

# token_ok TOKEN: looks like a GitHub token (and nothing that could be more)
token_ok() {
    case $1 in
        github_pat_*) [[ $1 =~ ^github_pat_[A-Za-z0-9_]{20,255}$ ]] ;;
        gh[pousr]_*)
            [[ $1 =~ ^gh[pousr]_[A-Za-z0-9]{20,255}$ ]] || return 1
            warn "That is a classic token: it reaches every repository you have. A fine-grained one is narrower."
            ;;
        *) return 1 ;;
    esac
}

# token_help WHAT: how to make the token, with the permission WHAT needs
token_help() {
    note "Make a fine-grained token: $TOKEN_PAGE"
    note "  Expiration: as short as will do (a day, for a one-off)"
    note "  Repository access: Only select repositories, the one you mean"
    note "  Repository permissions: $1"
    note "Keep it in your password manager. (Pasting shows nothing; press Enter after.)"
}

logged_in() { "$GH" auth status --hostname github.com >/dev/null 2>&1; }

# this_repo: OWNER/REPO of this copy's GitHub server (empty if it has none)
this_repo() {
    local url
    url=$(git -C "$WREN_DIR" remote get-url origin 2>/dev/null) || return 0
    if [[ $url =~ github\.com[:/]([A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100})$ ]]; then
        echo "${BASH_REMATCH[1]%.git}"
    fi
}

# have_gh: gh, from Debian if it isn't here
have_gh() { command -v "$GH" >/dev/null || need_tools gh:gh; }

setup() {
    have_gh
    say "gh's login"
    if logged_in; then
        note "gh is logged in, its token saved. To forget it: wrenctl gh --logout"
        return 0
    fi
    note "Nothing is saved now: wrenctl gh rulesets asks for a token when it needs one."
    note "Saved, gh keeps the token in your keyring if you run one, otherwise in plain"
    note "text (~/.config/gh/hosts.yml), readable by every program of yours."
    ask "Save a token for gh?" n || { note "Nothing saved."; return 0; }
    token_help "only what you will use gh for (rulesets: Administration, Read and write)"
    local tok
    secret tok "    Token: "
    token_ok "$tok" || die "That isn't a GitHub token; nothing was saved."
    printf '%s\n' "$tok" | "$GH" auth login --hostname github.com --with-token ||
        die "gh didn't take it (expired, or mistyped?); nothing was saved."
    note "Saved. gh auth status shows it; wrenctl gh --logout forgets it."
}

rulesets() {
    local repo=${1:-$(this_repo)} tok="" have
    [ -n "$repo" ] || die "Which repository? wrenctl gh rulesets OWNER/REPO"
    [[ $repo =~ ^[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}$ ]] || die "\"$repo\" isn't OWNER/REPO."
    have_gh
    if ! logged_in; then
        say "A token for this, used now and not saved"
        token_help "Administration, Read and write"
        secret tok "    Token: "
        token_ok "$tok" || die "That isn't a GitHub token; nothing was changed."
    fi
    # The token reaches gh in its environment (only you can read that), never
    # on a command line
    gh_() { if [ -n "$tok" ]; then GH_TOKEN=$tok "$GH" "$@"; else "$GH" "$@"; fi; }

    say "The rules on $repo's main"
    have=$(gh_ api "repos/$repo/rulesets" --jq '.[].name') ||
        die "GitHub didn't list $repo's rules (the token needs Administration, Read and write, on $repo). Nothing was changed."
    if grep -qxF "$RULE_ONLY_OWNER" <<<"$have"; then
        note "Already there: $RULE_ONLY_OWNER"
    else
        # (actor 5 is the repository role admin: you, as its owner)
        gh_ api -X POST "repos/$repo/rulesets" --input - >/dev/null <<EOF || die "GitHub refused \"$RULE_ONLY_OWNER\"; nothing else was changed."
{"name":"$RULE_ONLY_OWNER","target":"branch","enforcement":"active",
 "conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}},
 "rules":[{"type":"update"}],
 "bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}]}
EOF
        note "Added: $RULE_ONLY_OWNER"
    fi
    # (no bypass for anyone: a bypass covers every rule of its set)
    if grep -qxF "$RULE_NO_FORCE" <<<"$have"; then
        note "Already there: $RULE_NO_FORCE"
    else
        gh_ api -X POST "repos/$repo/rulesets" --input - >/dev/null <<EOF || die "GitHub refused \"$RULE_NO_FORCE\"."
{"name":"$RULE_NO_FORCE","target":"branch","enforcement":"active",
 "conditions":{"ref_name":{"include":["refs/heads/main"],"exclude":[]}},
 "rules":[{"type":"non_fast_forward"},{"type":"deletion"}]}
EOF
        note "Added: $RULE_NO_FORCE"
    fi

    # What GitHub now applies to main, as it says
    local applied t
    applied=$(gh_ api "repos/$repo/rules/branches/main" --jq '.[].type') || applied=
    for t in update non_fast_forward deletion; do
        grep -qx "$t" <<<"$applied" || die "GitHub doesn't apply \"$t\" to main. See: https://github.com/$repo/settings/rules"
    done
    note "GitHub applies them to main: only you update it; nobody force-pushes or deletes it."
    if [ -n "$tok" ]; then
        note "The token wasn't saved. Made for this alone? Delete it: https://github.com/settings/personal-access-tokens"
    fi
}

case ${1:-} in
    "") setup ;;
    rulesets) shift; [ $# -le 1 ] || die "Usage: bash gh-helper.sh rulesets [OWNER/REPO]"; rulesets "$@" ;;
    --logout)
        command -v "$GH" >/dev/null || { note "gh isn't installed: nothing saved."; exit 0; }
        if logged_in; then "$GH" auth logout --hostname github.com; else note "gh has no token saved."; fi ;;
    *) die "Usage: bash gh-helper.sh [rulesets [OWNER/REPO] | --logout]" ;;
esac
