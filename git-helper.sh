#!/bin/bash
# git-helper.sh: sets git up for you, and connects a copy of Wren Linux to the
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
#  3. How you push to GitHub: over ssh, with a key of your own made for it
#     (on a security key, or a key file with a passphrase), that no ssh-agent
#     holds, checked against GitHub's host keys pinned in pins.sh. You add the
#     key to your GitHub account once; it tests it before it changes anything.
#     Fetching stays on the public address, and needs no key.
# Usage: bash git-helper.sh         this copy of Wren Linux: steps 1 to 3
#        bash git-helper.sh DIR     any git repository of yours: steps 1 and 3
# (wrenctl git [DIR] runs it: for DIR, or the repository you are in)
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
. "$WREN_DIR/lib/update.sh"
. "$WREN_DIR/lib/appimage.sh"
not_root

g() { git -C "$WREN_DIR" "$@"; }
# (a test points these at pretend ones)
GH=${WREN_GH:-gh}
WGET=${WREN_WGET:-wget}
NOREPLY=users.noreply.github.com

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

# Pushing to GitHub over ssh, with a key of your own that is only for GitHub: no token,
# nothing saved by git, and a key no agent holds (ssh asks its passphrase at every push,
# or a security key wants a touch), checked against GitHub's host keys in pins.sh.
# (a test points these at pretend ones)
SSH=${WREN_SSH:-ssh}
KEYGEN=${WREN_SSH_KEYGEN:-ssh-keygen}
GH_KEY=$HOME/.ssh/id_wren_github
GH_KNOWN=$HOME/.ssh/known_hosts_github
SSH_CONF=$HOME/.ssh/config
SSH_BEGIN='# >>> Wren Linux github >>>'
SSH_END='# <<< Wren Linux github <<<'

# ssh_key: GH_KEY, made now if there is none: on a security key if you have one plugged in,
# otherwise a key file with a passphrase (ssh-keygen asks for it)
ssh_key() {
    if [ -f "$GH_KEY" ] && [ -f "$GH_KEY.pub" ]; then
        note "Your key for GitHub: $GH_KEY"
        return 0
    fi
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    if ask "Is a security key (FIDO2) plugged in, to keep this key on? (each push then wants a touch)" n; then
        "$KEYGEN" -t ed25519-sk -C wren-github -f "$GH_KEY" || { warn "No key was made; nothing was changed."; return 1; }
    else
        note "A key file, then. Give it a passphrase (KeePassXC can keep it): ssh asks for it at every push."
        "$KEYGEN" -t ed25519 -C wren-github -f "$GH_KEY" || { warn "No key was made; nothing was changed."; return 1; }
    fi
    case $(cut -d' ' -f1 "$GH_KEY.pub") in
        sk-*) ;;
        *) if "$KEYGEN" -y -P '' -f "$GH_KEY" >/dev/null 2>&1; then
               warn "That key has no passphrase: anything running as you could push with it. Add one: ssh-keygen -p -f $GH_KEY"
           fi ;;
    esac
}

# ssh_settings: GitHub's host keys from pins.sh, in a file of their own, and one block at the
# top of ~/.ssh/config (ssh takes the first value it finds) saying how to reach GitHub
ssh_settings() {
    local tmp
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    printf '%s\n' "$GITHUB_HOST_KEYS" >"$GH_KNOWN"
    chmod 644 "$GH_KNOWN"
    tmp=$(mktemp)
    {
        printf '%s\n' "$SSH_BEGIN" '# (written by Wren Linux git-helper.sh: wrenctl git sets it again)' \
            'Host github.com' '    HostName github.com' '    User git' \
            "    IdentityFile $GH_KEY" '    IdentitiesOnly yes' '    IdentityAgent none' '    AddKeysToAgent no' \
            "    UserKnownHostsFile $GH_KNOWN" '    StrictHostKeyChecking yes' "$SSH_END"
        [ ! -f "$SSH_CONF" ] || sed "\\|^$SSH_BEGIN\$|,\\|^$SSH_END\$|d" "$SSH_CONF"
    } >"$tmp"
    install -m 0600 "$tmp" "$SSH_CONF"
    rm -f "$tmp"
}

# no_https_logins: what earlier versions set up for pushing over https, now not needed
no_https_logins() {
    if git config --global --get-regexp '^credential\.https://github\.com\.' >/dev/null 2>&1 &&
        ask "git's https login settings for GitHub aren't needed any more. Remove them?" y; then
        git config --global --remove-section credential.https://github.com 2>/dev/null || true
    fi
    if git config --global --get-all credential.helper 2>/dev/null | grep -q '^store' &&
        ask "git's store helper keeps passwords and tokens in plain text. Stop it?" y; then
        git config --global --unset-all credential.helper '^store'
    fi
    if command -v "$GH" >/dev/null && "$GH" auth status --hostname github.com >/dev/null 2>&1 &&
        ask "gh is logged in, its token saved on this computer. Log it out?" y; then
        "$GH" auth logout --hostname github.com
    fi
    if [ -f "$HOME/.git-credentials" ]; then
        warn "$HOME/.git-credentials holds saved passwords or tokens in plain text. Delete it if you don't need them."
    fi
}

# login REPO: how pushing to REPO's server works. On GitHub, over ssh with your own key; fetching
# stays on the public address, so updates need no key. Elsewhere it changes nothing.
login() {
    local repo=$1 url path want said
    url=$(git -C "$repo" remote get-url origin 2>/dev/null) || { note "$repo has no server (origin) yet, so there is no login to set."; return 0; }
    case $url in
        https://github.com/* | git@github.com:*) ;;
        *) note "$url isn't on GitHub: pushing there takes the login that server asks for."; return 0 ;;
    esac
    path=$(sed -E 's#^(https://github\.com/|git@github\.com:)##; s#\.git$##' <<<"$url")
    [[ $path =~ ^[A-Za-z0-9-]{1,39}/[A-Za-z0-9._-]{1,100}$ ]] || { warn "$url doesn't look like a GitHub repository; nothing set."; return 0; }
    want=git@github.com:$path.git
    say "Pushing to GitHub over ssh, with a key of your own"
    if [ "$(git -C "$repo" remote get-url --push origin)" = "$want" ] && [ -f "$GH_KEY" ] &&
        grep -qxF "$SSH_BEGIN" "$SSH_CONF" 2>/dev/null; then
        ssh_settings
        note "Already set up: pushes go over ssh with $GH_KEY (its settings written again)."
        no_https_logins
        return 0
    fi
    ssh_key || return 0
    ssh_settings
    note "Add this key to your GitHub account, once: Settings, SSH and GPG keys, New SSH key"
    note "(GitHub takes a key only there, or from a token, which this is to do without):"
    printf '\n    %s\n\n' "$(cat "$GH_KEY.pub")"
    ask "Added it? (Enter: yes)" y || { note "Run this again once it is there: wrenctl git $repo"; return 0; }
    said=$("$SSH" -T git@github.com 2>&1 </dev/null || true)
    if ! grep -q 'successfully authenticated' <<<"$said"; then
        warn "GitHub didn't take the key yet ($(printable <<<"$said" | tail -n 1)). Nothing in $repo was changed."
        warn "Check it is on your account, then run this again: wrenctl git $repo"
        return 0
    fi
    git -C "$repo" remote set-url --push origin "$want"
    note "Done: pushes go to $want with your key, and fetching stays on $url."
    no_https_logins
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
    note "repository of yours: wrenctl git DIR"
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
    say "Your copy is exactly the published commit $(g log -1 --format='%h (%ad): %s' --date=short "$match" | printable)"
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
