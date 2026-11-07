#!/bin/bash
# Checks bin/git, the guard for repositories in ~/projects, with real git in a
# temporary folder. Changes nothing of yours. Run by test.sh, or:
#   bash tools/test-git-guard.sh
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
GUARD=$HERE/bin/git

T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
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

# Another account's folder, ~/projects-NAME, is guarded the same way
A=$T/home/projects-work/app
mkdir -p "$A" && (cd "$A" && real init -q && echo hi >a && real add a && real commit -qm first)
printf '#!/bin/sh\necho planted\n' >"$A/.git/hooks/pre-commit"
check "in another account's folder (~/projects-work) a hook is refused too" bash -c "cd '$A' && ! bash '$GUARD' status"
rm "$A/.git/hooks/pre-commit"
check "...and a clean one works" bash -c "cd '$A' && bash '$GUARD' status"

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
(cd "$P" && WREN_REAL_GIT="$T/fakegit" WREN_AGENT_USER=$(id -un) bash "$GUARD" status)
check "one made by claude-agent gets safe.directory for that command" grep -q -- "-c safe.directory=$P -c safe.directory=$P/\* status" "$T/calls"
: >"$T/calls"
(cd "$P" && WREN_REAL_GIT="$T/fakegit" WREN_AGENT_USER=nobody-here bash "$GUARD" status)
check "one made by you gets no trust added, only the refusal of bare repositories" grep -qx -- "-c safe.bareRepository=explicit status" "$T/calls"
: >"$T/calls"
(cd "$T/home/other" && WREN_REAL_GIT="$T/fakegit" WREN_AGENT_USER=$(id -un) bash "$GUARD" status)
check "outside ~/projects nothing is ever added" grep -qx "status" "$T/calls"
: >"$T/calls"
printf '#!/bin/sh\n' >"$P/.git/hooks/pre-commit"
(cd "$P" && WREN_REAL_GIT="$T/fakegit" WREN_AGENT_USER=$(id -un) bash "$GUARD" status 2>/dev/null)
check "a bad repository is not trusted, and git is not run" bash -c "! grep -q status '$T/calls'"
rm -f "$P/.git/hooks/pre-commit"

# A bare repository needs no .git: claude-agent can write HEAD, objects, refs and
# a config into any folder here. Git must not take it for a repository.
bare() { /usr/bin/git init -q --bare "$1" && /usr/bin/git -C "$1" config alias.pwn "!touch $T/bare-ran"; }
bare "$T/home/projects/evil"
(cd "$T/home/projects/evil" && git pwn) >/dev/null 2>&1
check "a bare repository planted in ~/projects doesn't run its settings" test ! -e "$T/bare-ran"
rm -f "$T/bare-ran"
bare "$P/planted"
(cd "$P/planted" && git pwn) >/dev/null 2>&1
check "...nor one planted inside a clean repository" test ! -e "$T/bare-ran"
rm -rf "$P/planted"
bare "$T/home/projects-work/evil"
(cd "$T/home/projects-work/evil" && git pwn) >/dev/null 2>&1
check "...nor one in another account's folder" test ! -e "$T/bare-ran"
check "...while one you name yourself still works (--git-dir)" bash -c "bash '$GUARD' --git-dir='$T/home/projects/evil' rev-parse --is-bare-repository | grep -qx true"
: >"$T/calls"
(cd "$T/home/other" && WREN_REAL_GIT="$T/fakegit" bash "$GUARD" status)
check "...and outside ~/projects nothing is added" grep -qx "status" "$T/calls"

# Ways to send git to a folder the guard hasn't looked at. Each has a real hook there, and a
# real commit through the guard: the hook must not run. (Each in a folder of its own.)
evil_gitdir() { # DIR: a repository's insides, with a hook that leaves a mark
    /usr/bin/git init -q --bare "$1"
    /usr/bin/git -C "$1" config --unset core.bare
    printf '#!/bin/sh\ntouch "%s/hook-ran"\n' "$T" >"$1/hooks/pre-commit"
    chmod +x "$1/hooks/pre-commit"
}
try_commit() { # DIR: a commit there through the guard
    rm -f "$T/hook-ran"
    (cd "$1" && echo x >f && bash "$GUARD" add f && bash "$GUARD" commit -qm x) >/dev/null 2>&1
}
hook_held() { # DESCRIPTION: the hook didn't run
    check "$1" test ! -e "$T/hook-ran"
}
X=$T/home/projects
# .git/commondir, an absolute path (git uses it as it is)
mkdir -p "$X/abs" && (cd "$X/abs" && real init -q)
evil_gitdir "$X/abs-evil"
rm -rf "$X/abs/.git/hooks" "$X/abs/.git/config" "$X/abs/.git/objects" "$X/abs/.git/refs"
printf '%s\n' "$X/abs-evil" >"$X/abs/.git/commondir"
try_commit "$X/abs"
hook_held "commondir with an absolute path: its hook doesn't run"
check "...and the refusal says what it found" bash -c "cd '$X/abs' && bash '$GUARD' status 2>&1 | grep -q 'hooks/pre-commit'"
# .git/commondir, two lines (git takes them as one name)
mkdir -p "$X/two" && (cd "$X/two" && real init -q)
evil_gitdir "$X/two/clean
evil"
mkdir -p "$X/two/clean"
rm -rf "$X/two/.git/hooks" "$X/two/.git/config" "$X/two/.git/objects" "$X/two/.git/refs"
printf '../clean\nevil\n' >"$X/two/.git/commondir"
try_commit "$X/two"
hook_held "commondir of two lines: its hook doesn't run"
# a .git file, two lines
mkdir -p "$X/file"
real init -q --bare "$X/file/clean"
evil_gitdir "$X/file/clean
evil"
printf 'gitdir: clean\nevil\n' >"$X/file/.git"
try_commit "$X/file"
hook_held "a .git file of two lines: its hook doesn't run"
# an empty .git folder isn't a repository: git goes on up, to one the guard must look at too
mkdir -p "$T/home/projects-up/sub/.git"
(cd "$T/home/projects-up" && real init -q)
printf '#!/bin/sh\ntouch "%s/hook-ran"\n' "$T" >"$T/home/projects-up/.git/hooks/pre-commit"
chmod +x "$T/home/projects-up/.git/hooks/pre-commit"
try_commit "$T/home/projects-up/sub"
hook_held "an empty .git folder, a repository with a hook above it: the hook doesn't run"
# a .git file that leads nowhere the guard can see is refused, not waved through
mkdir -p "$X/nowhere"
printf 'gitdir: /no/such/folder\n' >"$X/nowhere/.git"
check "a .git file that leads nowhere: refused by the guard itself" bash -c "cd '$X/nowhere'; bash '$GUARD' status 2>&1 | grep -q 'not running here'"
rm -rf "$X/abs" "$X/abs-evil" "$X/two" "$X/file" "$X/nowhere" "$T/home/projects-up"
# a real worktree, and a submodule's .git file, still work
(cd "$P" && real worktree add -q ../wt2 >/dev/null 2>&1)
check "a real worktree still works after all that" bash -c "cd '$T/home/projects/wt2' && bash '$GUARD' status"
(cd "$P" && real worktree remove --force ../wt2 2>/dev/null)
mkdir -p "$P/nested" && (cd "$P/nested" && real init -q)
check "a clean repository inside a clean repository works" bash -c "cd '$P/nested' && bash '$GUARD' status"
rm -rf "$P/nested"
# a repository that lives inside this one, recorded as a submodule: git status goes into it, and
# what its .git holds runs as you. Nothing above it is wrong, so the guard must look down too.
N=$T/home/projects/holds-one
mkdir -p "$N/deep/sub" && (cd "$N" && real init -q && cd deep/sub && real init -q && echo x >f && real add f && real commit -qm one)
(cd "$N" && real add deep/sub 2>/dev/null && real commit -qm top)
check "(the nested repository is recorded as a submodule)" bash -c "cd '$N' && /usr/bin/git ls-files -s | grep -q '^160000'"
check "a clean repository recorded inside a clean one works" bash -c "cd '$N' && bash '$GUARD' status"
printf '#!/bin/sh\ntouch "%s/nested-ran"\nexit 1\n' "$T" >"$T/nested-evil"
chmod +x "$T/nested-evil"
real -C "$N/deep/sub" config core.fsmonitor "$T/nested-evil"
(cd "$N" && bash "$GUARD" status) >"$T/nested-out" 2>&1
check "a setting in a nested repository: git status doesn't run its program" test ! -e "$T/nested-ran"
check "...and the refusal says where it is" grep -q 'deep/sub/.git: config: core.fsmonitor' "$T/nested-out"
real -C "$N/deep/sub" config --unset core.fsmonitor
check "...and fine again once it is gone" bash -c "cd '$N' && bash '$GUARD' status"
printf '#!/bin/sh\n' >"$N/deep/sub/.git/hooks/post-index-change"
check "a hook in a nested repository is refused" bash -c "cd '$N' && ! bash '$GUARD' status"
rm -rf "$N"

# explicit choices pass straight through
check "--git-dir is left alone" bash -c "cd '$P' && printf '#!/bin/sh\n' >.git/hooks/pre-commit && bash '$GUARD' --git-dir='$P/.git' status; r=\$?; rm -f .git/hooks/pre-commit; exit \$r"

[ "$fails" -eq 0 ]
