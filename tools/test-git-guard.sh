#!/bin/bash
# Checks bin/git, the guard for repositories in ~/projects, with real git in a
# temporary folder. Changes nothing of yours. Run by test.sh, or:
#   bash tools/test-git-guard.sh
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
GUARD=$HERE/bin/git

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}

mkdir -p "$T/home/projects" "$T/home/other"
export HOME="$T/home" GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
unset GIT_DIR
git() { bash "$GUARD" "$@"; }
real() { /usr/bin/git "$@"; }
real config --global user.name tester
real config --global user.email tester@example.org
real config --global init.defaultBranch main

# a repository in ~/projects, with a commit
P=$T/home/projects/app
mkdir -p "$P" && (cd "$P" && real init -q && echo hi >a && real add a && real commit -qm first)

check "outside ~/projects it is plain git" bash -c "cd '$T/home/other' && bash '$GUARD' --version | grep -q 'git version'"
check "a clean repository in ~/projects works" bash -c "cd '$P' && bash '$GUARD' log --oneline | grep -q first"
check "from a subfolder too" bash -c "mkdir -p '$P/sub' && cd '$P/sub' && bash '$GUARD' status"
check "with -C" bash -c "cd '$T' && bash '$GUARD' -C '$P' status"
check "git init in ~/projects (no repository yet) works" bash -c "mkdir -p '$T/home/projects/new' && cd '$T/home/projects/new' && bash '$GUARD' init -q"

refused() { # DESCRIPTION: the repository now has something bad; git there must refuse
    check "$1" bash -c "cd '$P' && ! bash '$GUARD' status"
}
fixed() { check "$1" bash -c "cd '$P' && bash '$GUARD' status"; }

# hooks
printf '#!/bin/sh\necho planted\n' >"$P/.git/hooks/pre-commit"
refused "a hook is refused"
rm "$P/.git/hooks/pre-commit"
fixed "and fine again once it is gone"
check "the refusal names the hook" bash -c "printf '#!/bin/sh\n' >'$P/.git/hooks/post-merge'; cd '$P'; bash '$GUARD' status 2>&1 | grep -q 'hooks/post-merge'"
rm -f "$P/.git/hooks/post-merge"

# settings that can run a program, or steer git somewhere else
for setting in "core.fsmonitor=touch /tmp/x" "alias.st=!sh -c id" "core.sshCommand=sh -c id" "core.pager=sh -c id" \
    "core.editor=sh" "core.hooksPath=/tmp/hooks" "credential.helper=!sh -c id" "diff.x.textconv=sh" \
    "filter.x.clean=sh" "url.https://evil/.insteadOf=https://github.com/" "include.path=/tmp/more" \
    "extensions.worktreeConfig=true" "gpg.program=sh" "core.gitProxy=sh"; do
    (cd "$P" && real config --local "${setting%%=*}" "${setting#*=}")
    refused "refuses ${setting%%=*}"
    (cd "$P" && real config --local --unset-all "${setting%%=*}")
done
fixed "and all of that undone is fine"

# remotes: ordinary addresses are fine, helper programs are not
for url in https://example.org/a/b.git git@github.com:me/repo.git ssh://git@example.org/x.git ../sibling; do
    (cd "$P" && real remote add r "$url")
    fixed "remote $url is allowed"
    (cd "$P" && real remote remove r)
done
for url in "ext::sh -c id" "fd::17" "https://example.org/x y"; do
    (cd "$P" && real remote add r "$url")
    refused "remote '$url' is refused"
    (cd "$P" && real remote remove r)
done
(cd "$P" && real branch -q -u r 2>/dev/null; real config branch.main.remote origin; real config branch.main.merge refs/heads/main)
fixed "branch settings are fine"

# submodule and worktree folders
mkdir -p "$P/.git/modules/m/hooks"
printf '#!/bin/sh\n' >"$P/.git/modules/m/hooks/post-checkout"
refused "a hook in a submodule is refused"
rm -r "$P/.git/modules"
fixed "and fine when it is gone"
(cd "$P" && real worktree add -q ../wt >/dev/null 2>&1)
check "a worktree works" bash -c "cd '$T/home/projects/wt' && bash '$GUARD' status"
printf '#!/bin/sh\n' >"$P/.git/hooks/pre-push"
check "a hook in the main repository stops its worktree too" bash -c "cd '$T/home/projects/wt' && ! bash '$GUARD' status"
rm -f "$P/.git/hooks/pre-push"
(cd "$P" && real worktree remove --force ../wt 2>/dev/null)

# a repository made by claude-agent gets trusted for that one command
cat >"$T/fakegit" <<EOF
#!/bin/sh
echo "\$*" >>"$T/calls"
EOF
chmod +x "$T/fakegit"
: >"$T/calls"
(cd "$P" && DEBSWAY_REAL_GIT="$T/fakegit" DEBSWAY_AGENT_USER=$(id -un) bash "$GUARD" status)
check "one made by claude-agent gets safe.directory for that command" grep -q -- "-c safe.directory=$P -c safe.directory=$P/\* status" "$T/calls"
: >"$T/calls"
(cd "$P" && DEBSWAY_REAL_GIT="$T/fakegit" DEBSWAY_AGENT_USER=nobody-here bash "$GUARD" status)
check "one made by you gets nothing added" grep -qx "status" "$T/calls"
: >"$T/calls"
(cd "$T/home/other" && DEBSWAY_REAL_GIT="$T/fakegit" DEBSWAY_AGENT_USER=$(id -un) bash "$GUARD" status)
check "outside ~/projects nothing is ever added" grep -qx "status" "$T/calls"
: >"$T/calls"
printf '#!/bin/sh\n' >"$P/.git/hooks/pre-commit"
(cd "$P" && DEBSWAY_REAL_GIT="$T/fakegit" DEBSWAY_AGENT_USER=$(id -un) bash "$GUARD" status 2>/dev/null)
check "a bad repository is not trusted, and git is not run" bash -c "! grep -q status '$T/calls'"
rm -f "$P/.git/hooks/pre-commit"

# explicit choices pass straight through
check "--git-dir is left alone" bash -c "cd '$P' && printf '#!/bin/sh\n' >.git/hooks/pre-commit && bash '$GUARD' --git-dir='$P/.git' status; r=\$?; rm -f .git/hooks/pre-commit; exit \$r"

[ "$fails" -eq 0 ]
