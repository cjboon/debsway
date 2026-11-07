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
#        bash gh-helper.sh deploy-key [OWNER/REPO] [--account NAME]
#                                              add the claude-vm VM's ssh key to the
#                                              repository (so the agent can push),
#                                              without a browser; main's rules first
#        bash gh-helper.sh --logout              forget a saved token
# (wrenctl gh runs it)
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
not_root

# (a test points it at a pretend one)
GH=${WREN_GH:-gh}
RULE_ONLY_OWNER="main: only the owner updates it"
RULE_NO_FORCE="main: no force-push, no delete"
TOKEN_PAGE=https://github.com/settings/personal-access-tokens/new
TOKEN_PAGE_LIST=https://github.com/settings/personal-access-tokens

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

# admin_token_help OWNER/REPO: the same for changing that repository, by a link that
# fills in the form (GitHub's URL parameters; no parameter picks the repository)
admin_token_help() {
    note "Make a token for this. The link fills in all but one choice:"
    note "  $TOKEN_PAGE?name=wren-gh-helper&target_name=${1%%/*}&expires_in=1&administration=write"
    note "  Repository access: pick Only select repositories, then $1 (the link can't;"
    note "  without it the token can read the repository but change nothing)"
    note "  Check that Administration says Read and write, then Generate token."
    note "(Pasting shows nothing; press Enter after.)"
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

# The token reaches gh in its environment (only you can read that), never on a
# command line. $tok is the caller's, from token_for_this.
gh_() { if [ -n "$tok" ]; then GH_TOKEN=$tok "$GH" "$@"; else "$GH" "$@"; fi; }

# token_for_this OWNER/REPO: into the caller's $tok, unless gh is logged in
token_for_this() {
    logged_in && return 0
    say "A token for this, used now and not saved"
    admin_token_help "$1"
    secret tok "    Token: "
    token_ok "$tok" || die "That isn't a GitHub token; nothing was changed."
}

# add_rules REPO: the rules on main, each only if missing; then what GitHub says
# it applies, or stop
add_rules() {
    local repo=$1 have
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
}

rulesets() {
    local repo=${1:-$(this_repo)} tok=""
    [ -n "$repo" ] || die "Which repository? wrenctl gh rulesets OWNER/REPO"
    [[ $repo =~ ^[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}$ ]] || die "\"$repo\" isn't OWNER/REPO."
    have_gh
    token_for_this "$repo"
    say "The rules on $repo's main"
    add_rules "$repo"
    if [ -n "$tok" ]; then
        note "The token wasn't saved. Made for this alone? Delete it: https://github.com/settings/personal-access-tokens"
    fi
}

# deploy_key [OWNER/REPO] [--account NAME]: adds the claude-vm VM's ssh public
# key to the repository as a deploy key that can write (so the agent can push).
# The key is public; the token that adds it stays on this computer, never in the
# VM. A deploy key reaches one repository only, and the branch rules keep it off
# main, so it can push its own branch and nothing else: they are checked first,
# and no key goes on while main is open or can't be checked.
deploy_key() {
    local repo="" account="" tok="" key existing applied t
    while [ $# -gt 0 ]; do
        case $1 in
            --account) [ $# -ge 2 ] || die "--account needs a name"; account=$2; shift 2 ;;
            -*) die "Usage: bash gh-helper.sh deploy-key [OWNER/REPO] [--account NAME]" ;;
            *) [ -z "$repo" ] || die "Usage: bash gh-helper.sh deploy-key [OWNER/REPO] [--account NAME]"; repo=$1; shift ;;
        esac
    done
    [ -n "$account" ] && [[ ! $account =~ ^[a-z][a-z0-9]{0,14}$ ]] &&
        die "An account name is small letters and digits, a letter first."
    repo=${repo:-$(this_repo)}
    [ -n "$repo" ] || die "Which repository? wrenctl gh deploy-key OWNER/REPO"
    [[ $repo =~ ^[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}$ ]] || die "\"$repo\" isn't OWNER/REPO."
    have_gh

    # The VM's public key, from the VM command (the key is public; a test points
    # WREN_CLAUDE_VM at a pretend one)
    local claude_vm=${WREN_CLAUDE_VM:-$HOME/.local/bin/claude-vm}
    [ -x "$claude_vm" ] ||
        die "The claude-vm sandbox isn't set up here, so there is no VM key to add. Set it up first: wrenctl install claude-vm${account:+ --account $account}"
    local vm_said
    vm_said=$("$claude_vm" ${account:+--account "$account"} pubkey 2>&1) || true
    key=$(grep -m1 -E '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-[a-z0-9-]+|sk-ssh-ed25519@openssh\.com) ' <<<"$vm_said") ||
        die "Couldn't read the VM's public key (claude-vm${account:+ --account $account} pubkey), so nothing was sent to GitHub. It said: $(printable <<<"$vm_said" | tail -n 3)"
    # The type and base64 body only (GitHub needs no comment). It holds nothing
    # but safe characters, so no quote or backslash in a comment could break out
    # of the JSON this becomes; it is also what GitHub stores and compares.
    local body
    body=$(awk '{print $1 " " $2}' <<<"$key")
    [[ $body =~ ^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+|sk-ssh-ed25519@openssh.com)\ [A-Za-z0-9+/]+=*$ ]] ||
        die "That doesn't look like a single ssh public key; nothing was sent to GitHub."

    token_for_this "$repo"

    # Can this token manage the repository's deploy keys at all? Asked first, so a
    # token that can't fails here, before anything else is checked or changed
    say "What the token may do on $repo"
    existing=$(gh_ api "repos/$repo/keys" --jq '.[].key' 2>&1) || {
        warn "GitHub won't show $repo's deploy keys to this token, so it can't add one. GitHub said: $(printable <<<"$existing" | tail -n 1)"
        warn "On the token's page ($TOKEN_PAGE_LIST), check two things and save:"
        warn "  Repository access: Only select repositories, $repo"
        warn "  Repository permissions: Administration, Read and write"
        die "Then run this again with the same token. No key was added, nothing was changed."
    }
    note "It may manage $repo's deploy keys."

    # Is main protected, so this write key can't reach it? Before the key goes on
    say "The rules on $repo's main"
    applied=$(gh_ api "repos/$repo/rules/branches/main" --jq '.[].type' 2>&1) ||
        die "Couldn't check the rules on $repo's main. No key was added. GitHub said: $(printable <<<"$applied")"
    local main_open=false
    for t in update non_fast_forward deletion; do
        grep -qx "$t" <<<"$applied" || main_open=true
    done
    if $main_open; then
        warn "main is not fully protected yet, so this key could push to main too."
        ask "Add the rules now (only you update main; nobody force-pushes or deletes it)?" y ||
            die "No key was added. When you want the rules: wrenctl gh rulesets $repo"
        add_rules "$repo"
    else
        note "main is protected: this key can push its own branch, never main."
    fi

    say "The claude-vm key on $repo"
    # Already there? (match on the type and body, not the comment)
    local title="wren-claude-vm${account:+-$account}"
    if grep -qxF "$body" <(awk '{print $1 " " $2}' <<<"$existing"); then
        note "The VM's key is already a deploy key on $repo; nothing was added."
    else
        gh_ api -X POST "repos/$repo/keys" --input - >/dev/null <<EOF ||
{"title":"$title","key":"$body","read_only":false}
EOF
            die "GitHub didn't add the key (a deploy key works on one repository only: is this key on another?). See: https://github.com/$repo/settings/keys"
        note "Added the VM's key as a deploy key on $repo (it can push, so the agent's work reaches you)."
    fi

    # A rebuild makes a new key, and the last VM's stays on GitHub, still able to
    # push. Only a key with this VM's exact title is offered, and only if you say so.
    local rows id old_title old_type old_body
    rows=$(gh_ api "repos/$repo/keys" --jq '.[] | "\(.id) \(.title) \(.key)"') || rows=
    while read -r id old_title old_type old_body _; do
        [ "$old_title" = "$title" ] && [[ $id =~ ^[0-9]+$ ]] && [ "$old_type $old_body" != "$body" ] || continue
        warn "Another key titled $title is on $repo (ending ${old_body: -12}): it can still push."
        ask "Remove it? (Yes if it was a VM you have rebuilt; no if another computer uses it)" n || continue
        if gh_ api -X DELETE "repos/$repo/keys/$id" </dev/null >/dev/null; then
            note "Removed the old key."
        else
            warn "It couldn't be removed. See: https://github.com/$repo/settings/keys"
        fi
    done <<<"$rows"
    note "The VM pushes to the branch claude; you bring its work in with claude-pull, after reviewing it."
    if [ -n "$tok" ]; then
        # (GitHub's rule: deleting the token that added a deploy key deletes the key)
        note "The token wasn't saved. Don't delete it: GitHub deletes the deploy key it added along with it."
        note "It runs out by itself (a day, made from the link)."
    fi
}

case ${1:-} in
    "") setup ;;
    rulesets) shift; [ $# -le 1 ] || die "Usage: bash gh-helper.sh rulesets [OWNER/REPO]"; rulesets "$@" ;;
    deploy-key | deploy_key) shift; deploy_key "$@" ;;
    --logout)
        command -v "$GH" >/dev/null || { note "gh isn't installed: nothing saved."; exit 0; }
        if logged_in; then "$GH" auth logout --hostname github.com; else note "gh has no token saved."; fi ;;
    *) die "Usage: bash gh-helper.sh [rulesets [OWNER/REPO] | deploy-key [OWNER/REPO] [--account NAME] | --logout]" ;;
esac
