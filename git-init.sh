#!/bin/bash
# git-init.sh: sets git up for you, and connects a copy of Wren Linux to the
# published one. It changes no file of a repository, and never pushes.
#  1. Your name and email on commits (git config --global): asked when they
#     aren't set, offered to change when they are. For a GitHub repository, an
#     email you keep private on GitHub makes it refuse your pushes (GH007), so
#     it offers your GitHub no-reply address instead, looked up from your
#     public profile.
#  2. A copy of Wren Linux from an install stick or a download (the files, no
#     git) becomes a git checkout of the published Wren Linux, so update.sh
#     can bring in what is new:
#     - It fetches the published history (WREN_GIT_URL in pins.sh), and, once
#       pins.sh names Wren Linux's signing key, only if the newest commit there
#       is signed by exactly that key.
#     - It finds the published commit whose files are exactly yours. Found,
#       your copy is set at that commit, and update.sh then offers what came
#       after it. Not found, your files differ from everything that was
#       published (changed by you, or on the stick by someone else): it says
#       so, and git status shows what differs.
#  3. How git logs in to push, for a server reached over https (fetching needs
#     no login):
#       token   a token you paste at each push: nothing is saved (the safest)
#       memory  the same, kept in memory for an hour after you paste it
#       gh      GitHub's own login, through a web page: saved in plain text in
#               ~/.config/gh, for every repository on your account
#     Over ssh, git uses your ssh key: there is nothing to set.
# Usage: bash git-init.sh         this copy of Wren Linux: steps 1 to 3
#        bash git-init.sh DIR     any git repository of yours: steps 1 and 3
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
. "$WREN_DIR/lib/update.sh"
. "$WREN_DIR/lib/appimage.sh"
not_root

g() { git -C "$WREN_DIR" "$@"; }
# (a test points these at pretend ones)
GH=${WREN_GH:-gh}
WGET=${WREN_WGET:-wget}
NOREPLY=users.noreply.github.com

# https_host URL: the server of an https address, with its port (empty otherwise)
https_host() {
    if [[ $1 =~ ^https://([^/@]+@)?([A-Za-z0-9.-]+(:[0-9]{1,5})?)(/|$) ]]; then echo "${BASH_REMATCH[2]}"; fi
}
# github_owner URL: the account in a GitHub address (github.com/OWNER/REPO)
github_owner() {
    if [[ $1 =~ github\.com[:/]([A-Za-z0-9-]{1,39})/ ]]; then echo "${BASH_REMATCH[1]}"; fi
}
# value VAR "Question" CURRENT: a line typed, or CURRENT on Enter
value() {
    local _a
    tty_read _a "    $2${3:+ [$3]}: "
    printf -v "$1" '%s' "${_a:-$3}"
}

# identity REPO: the name and email on your commits
identity() {
    local repo=$1 name email new
    name=$(git config --global user.name || true)
    email=$(git config --global user.email || true)
    say "Your name and email on commits"
    if [ -n "$name" ] && [ -n "$email" ]; then
        note "$name <$email>"
        ask "Change them?" n || { noreply_offer "$repo"; return 0; }
    fi
    note "They go into every commit, for anyone who sees the repository (Enter keeps what is shown)."
    value new "Name" "$name"
    if [ -n "$new" ] && [ "$new" != "$name" ]; then git config --global user.name "$new"; fi
    value new "Email" "$email"
    if [ -n "$new" ] && [ "$new" != "$email" ]; then git config --global user.email "$new"; fi
    noreply_offer "$repo"
}

# noreply_offer REPO: for a GitHub repository, your no-reply address instead of
# one GitHub would refuse to publish
noreply_offer() {
    local repo=$1 url email user json id old n
    url=$(git -C "$repo" remote get-url origin 2>/dev/null) || return 0
    case $url in *github.com[/:]*) ;; *) return 0 ;; esac
    email=$(git config --global user.email || true)
    case $email in *@$NOREPLY) return 0 ;; esac
    note "On GitHub, an email you keep private (github.com/settings/emails) makes it refuse"
    note "your pushes (GH007). Your no-reply address keeps it private, and is always taken."
    ask "Use your GitHub no-reply address on commits?" n || return 0
    value user "Your GitHub user name" "$(github_owner "$url")"
    [[ $user =~ ^[A-Za-z0-9](-?[A-Za-z0-9]){0,38}$ ]] || { warn "\"$user\" isn't a GitHub user name; nothing was changed."; return 0; }
    # The account's number, from its public profile: the address is NUMBER+NAME
    json=$("$WGET" -qO- --timeout=20 "https://api.github.com/users/$user" 2>/dev/null) || json=
    id=$(grep -o '"id": *[0-9]\{1,15\}' <<<"$json" | head -n1 | grep -o '[0-9]*$')
    if [ -z "$id" ]; then
        warn "Couldn't look up $user on GitHub (offline, or no such user?); nothing was changed."
        note "The address is under \"Keep my email addresses private\" at github.com/settings/emails:"
        note "  git config --global user.email 'NUMBER+$user@$NOREPLY'"
        return 0
    fi
    old=$email
    git config --global user.email "$id+$user@$NOREPLY"
    note "Your commits now carry $id+$user@$NOREPLY."
    # Commits made already keep the old address; those not pushed yet can change
    [ -n "$old" ] || return 0
    n=$(git -C "$repo" log --format=%ae '@{upstream}..HEAD' 2>/dev/null | grep -cxF -- "$old" || true)
    if [ "${n:-0}" -gt 0 ]; then
        note "$n commits not pushed yet still carry $old, and GitHub would refuse them. To change them:"
        note "  git -C $repo -c commit.gpgsign=false rebase @{upstream} --exec 'git -c commit.gpgsign=false commit --amend --no-edit --reset-author --allow-empty'"
    fi
}

# login REPO: how git logs in to push to REPO's server
login() {
    local repo=$1 url host owner how now options=(token memory)
    url=$(git -C "$repo" remote get-url origin 2>/dev/null) || { note "$repo has no server (origin) yet, so there is no login to set."; return 0; }
    host=$(https_host "$url")
    if [ -z "$host" ]; then
        case $url in
            *@*:* | ssh://*) note "$url is reached over ssh: git logs in with your ssh key, nothing to set here." ;;
        esac
        return 0
    fi
    owner=
    if [ "$host" = github.com ]; then owner=$(github_owner "$url"); fi
    say "Logging in to $host, to push (fetching needs no login)"
    # what is set now
    now=none
    case $(git config --global --get-all "credential.https://$host.helper" 2>/dev/null | tail -n1) in
        *"auth git-credential"*) now=gh ;;
        cache*) now=memory ;;
        store*) now=store ;;
        "") if git config --global --get-all "credential.https://$host.helper" >/dev/null 2>&1; then now=token; fi ;;
    esac
    # git's store helper, for every server: it applies next to the one above
    if git config --global --get-all credential.helper 2>/dev/null | grep -q '^store'; then now=store; fi
    case $now in
        token) note "Now: you paste a token at each push; nothing is saved." ;;
        memory) note "Now: you paste a token, kept in memory for an hour." ;;
        gh) note "Now: GitHub's gh login, saved in plain text in ~/.config/gh." ;;
        store) warn "Now: git's store helper keeps your password or token in plain text (~/.git-credentials)." ;;
        none) note "Now: git asks for a user name and password at each push." ;;
    esac
    if [ "$now" != none ] && [ "$now" != store ]; then
        ask "Change it?" n || return 0
    fi
    note "token   paste a token at each push: nothing is saved here (the safest)"
    note "memory  the same, kept in memory for an hour after you paste it"
    if [ "$host" = github.com ] && command -v "$GH" >/dev/null; then
        options+=(gh)
        note "gh      log in through a web page: saved in plain text in ~/.config/gh,"
        note "        readable by any program of yours, for every repository on your account"
    fi
    note "skip    leave it as it is"
    options+=(skip)
    choose how "How should git log in?" token "${options[@]}"
    case $how in
        skip) note "Left as it was."; return 0 ;;
        gh)
            "$GH" auth login --hostname github.com --git-protocol https && "$GH" auth setup-git ||
                warn "That didn't work; nothing else was changed. Try again later: bash $WREN_DIR/git-init.sh"
            return 0 ;;
    esac
    # token or memory: no helper but git's own (an empty one drops the rest)
    git config --global --replace-all "credential.https://$host.helper" ''
    if [ "$how" = memory ]; then git config --global --add "credential.https://$host.helper" 'cache --timeout=3600'; fi
    if [ -n "$owner" ]; then git config --global "credential.https://$host.username" "$owner"; fi
    if [ "$host" = github.com ] && command -v "$GH" >/dev/null && "$GH" auth status --hostname github.com >/dev/null 2>&1; then
        ask "gh is logged in too, its token saved in plain text. Log it out (the token there goes)?" y &&
            "$GH" auth logout --hostname github.com
    fi
    if git config --global --get-all credential.helper 2>/dev/null | grep -q '^store' &&
        ask "Stop git's store helper, so nothing is saved in plain text from now on?" y; then
        git config --global --unset-all credential.helper '^store'
    fi
    if [ -f "$HOME/.git-credentials" ]; then
        warn "$HOME/.git-credentials holds saved passwords or tokens in plain text. Delete it if you don't need them."
    fi
    if [ "$host" = github.com ]; then
        note "Make a token: https://github.com/settings/personal-access-tokens/new"
        note "  Repository access: Only select repositories, this one ($(sed -E 's|.*github\.com[:/]||; s|\.git$||' <<<"$url"))"
        note "  Repository permissions: Add permissions, Contents, then Read and write; and an expiry date"
        note "Keep it in your password manager. At a push: user name ${owner:-yours}, password the token."
    else
        note "Make an access token on $host that may write to this repository, and keep it in your"
        note "password manager. At a push: your user name there, and the token as the password."
    fi
    note "(It shows nothing as you paste it; press Enter after.)"
}

need_tools git:git
if [ $# -ge 1 ]; then
    # Any repository: only your name, email and login
    repo=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) ||
        die "$1 isn't a git repository (git init or git clone makes one)."
    identity "$repo"
    login "$repo"
    exit 0
fi

identity "$WREN_DIR"
if [ -e "$WREN_DIR/.git" ]; then
    note "$WREN_DIR is a git checkout already ($(g remote get-url origin 2>/dev/null || echo "no server set")); nothing to connect."
    login "$WREN_DIR"
    exit 0
fi
if [ ! -w "$WREN_DIR" ]; then
    note "$WREN_DIR is read-only (the Wren Linux package's): apt brings its updates. For a"
    note "repository of yours: bash $WREN_DIR/git-init.sh DIR"
    exit 0
fi
url=${WREN_GIT_URL:?pins.sh has no WREN_GIT_URL}
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
    login "$WREN_DIR"
else
    g reset -q origin/main
    g branch -q -u origin/main
    warn "Your files aren't exactly any commit that was published at $url."
    warn "Either you changed them, or someone changed them on the stick. Before you run anything"
    warn "that uses sudo, look at what differs:  git -C $WREN_DIR status   and   git -C $WREN_DIR diff"
    exit 1
fi
