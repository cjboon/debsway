#!/bin/bash
# Checks bin/claude-share against a real git server in a temp folder: it asks first, a branch of
# its own with only those files, no name, email or time zone, main untouched, hidden files and links
# left out, too much refused; --done deletes only its own. Run by test.sh, or:
#   bash tools/test-claude-share.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
SHARE=$HERE/bin/claude-share
export HOME=$T/home
mkdir -p "$HOME/pics/sub/.hidden" "$HOME/hooks"
git config --global user.name 'Secret Person'
git config --global user.email secret@example.org
git config --global init.defaultBranch main
git config --global core.hooksPath "$HOME/hooks"
printf '#!/bin/sh\ntouch "%s/hook-ran"\n' "$T" >"$HOME/hooks/pre-commit"
chmod +x "$HOME/hooks/pre-commit"
git init -q --bare "$T/server.git"
git init -q "$T/copy"
git -C "$T/copy" -c core.hooksPath=/dev/null commit -q --allow-empty -m first
git -C "$T/copy" remote add origin "$T/server.git"
git -C "$T/copy" -c core.hooksPath=/dev/null push -q origin main
git -C "$T/copy" -c core.hooksPath=/dev/null push -q origin main:claude
main=$(git -C "$T/copy" rev-parse HEAD)
cd "$HOME/pics" || exit 1
echo a >one.jpg
echo b >sub/two.png
echo no >.wren-wallpapers
echo no >sub/.hidden/secret.txt
echo no >"$HOME/private.txt"
ln -s "$HOME/private.txt" link.txt
cd "$T/copy" || exit 1
heads() { git -C "$T/server.git" for-each-ref --format='%(refname:short)' refs/heads; }
one() { heads | grep '^claude-share-'; }

echo n | bash "$SHARE" "$HOME/pics" >"$T/out" 2>&1
check "it shows the names and says anyone can see them" bash -c 'grep -q "ANYONE" "$1" && grep -q "pics/one.jpg" "$1"' _ "$T/out"
check "answering no sends nothing" test -z "$(one)"
echo | bash "$SHARE" "$HOME/pics" >/dev/null 2>&1
check "...and so does Enter" test -z "$(one)"

TZ=Asia/Tokyo bash "$SHARE" "$HOME/pics" <<<y >"$T/out" 2>&1
b=$(one)
tree=$(git -C "$T/server.git" ls-tree -r --name-only "$b" 2>/dev/null | paste -sd' ')
log=$(git -C "$T/server.git" log --format='%an %ae %cn %ce %ad' --date=iso "$b" 2>/dev/null)
check "yes: a branch of its own, and it says which" bash -c 'test -n "$1" && grep -q "$1" "$2"' _ "$b" "$T/out"
check "...with those files, nothing hidden and no links" test "$tree" = "pics/one.jpg pics/sub/two.png"
ln -s "$HOME/private.txt" "$HOME/pics/sub/linked.jpg"
check "...one commit, sharing no history" test "$(git -C "$T/server.git" rev-list --count "$b")" = 1
check "...no name or email of yours" not grep -q secret <<<"$log"
check "...no time zone of yours" grep -q '+0000$' <<<"$log"
check "...your own git hooks didn't run" test ! -e "$T/hook-ran"
check "main and claude didn't move" bash -c '[ "$(git -C "$1" rev-parse main)" = "$2" ] && [ "$(git -C "$1" rev-parse claude)" = "$2" ]' _ "$T/server.git" "$main"

err() { bash "$SHARE" "$@" </dev/null 2>&1; }
check "your whole home folder is refused" grep -q 'whole home' <<<"$(err "$HOME")"
check "...and a folder above it" grep -q 'whole home' <<<"$(err "$T")"
check "a link is refused" grep -q 'is a link' <<<"$(err "$HOME/pics/link.txt")"
mkdir -p "$HOME/.ssh" "$HOME/empty"; echo key >"$HOME/.ssh/id_ed25519"; echo no >"$HOME/empty/.only"
check "a hidden file is refused" grep -q 'is hidden' <<<"$(err "$HOME/pics/.wren-wallpapers")"
check "...and a hidden folder, named directly: ~/.ssh" grep -q 'is hidden' <<<"$(err "$HOME/.ssh")"
check "...and a file inside one: ~/.ssh/id_ed25519" grep -q 'is hidden' <<<"$(err "$HOME/.ssh/id_ed25519")"
check "...and going round it: ~/pics/../.ssh" grep -q 'is hidden' <<<"$(err "$HOME/pics/../.ssh")"
check "a folder of only hidden files has nothing to share" grep -q 'nothing to share' <<<"$(err "$HOME/empty")"
truncate -s 51M "$T/big.iso"
check "a file too big for GitHub is refused" grep -q 'too big' <<<"$(err "$T/big.iso")"
check "a name that isn't there is refused" grep -q 'there is no' <<<"$(err "$HOME/nothing")"
n=$(heads | wc -l)
check "...none of those sent anything" test "$n" = 3

: >"$HOME/pics/$(printf 'evil\033[2Jname.jpg')"
echo n | bash "$SHARE" "$HOME/pics" >"$T/out" 2>&1
check "a file name can't steer your terminal" not grep -q "$(printf '\033')" "$T/out"
rm "$HOME/pics"/evil*

# Where it goes, outside a git copy. A loose copy of the script, so this test's own
# repository (the real one) can't be picked up
mkdir -p "$T/loose" "$T/fakebin"
cp "$SHARE" "$T/loose/claude-share"
LOOSE=$T/loose/claude-share
printf '#!/bin/sh\nexit 1\n' >"$T/fakebin/wrenctl"
chmod +x "$T/fakebin/wrenctl"
(cd "$T" && PATH=$T/fakebin:$PATH bash "$LOOSE" "$HOME/pics" </dev/null >"$T/out" 2>&1)
check "outside a git copy, with no Wren Linux folder: it says so" grep -q "isn't a git copy" "$T/out"
git init -q --bare "$T/wren.git"
git clone -q "$T/wren.git" "$T/wren-copy" 2>/dev/null
printf '#!/bin/sh\necho "%s"\n' "$T/wren-copy" >"$T/fakebin/wrenctl"
(cd "$T" && echo n | PATH=$T/fakebin:$PATH bash "$LOOSE" "$HOME/pics" >"$T/out" 2>&1)
check "...installed: the folder wrenctl knows" grep -q "$T/wren.git" "$T/out"
mkdir -p "$T/wren-copy/bin"
cp "$SHARE" "$T/wren-copy/bin/"
: >"$T/wren-copy/lib.sh"
git init -q --bare "$T/other.git"
printf '#!/bin/sh\necho "%s"\n' "$T/nowhere" >"$T/fakebin/wrenctl"
(cd "$T" && echo n | PATH=$T/fakebin:$PATH bash "$T/wren-copy/bin/claude-share" "$HOME/pics" >"$T/out" 2>&1)
check "...run from a copy: that copy" grep -q "$T/wren.git" "$T/out"
git init -q "$T/mine"
git -C "$T/mine" remote add origin "$T/other.git"
(cd "$T/mine" && echo n | bash "$T/wren-copy/bin/claude-share" "$HOME/pics" >"$T/out" 2>&1)
check "...but the repository you're in comes first" grep -q "$T/other.git" "$T/out"

echo n | bash "$SHARE" --done >/dev/null 2>&1
check "--done, answering no, keeps them" test -n "$(one)"
git -C "$T/copy" -c core.hooksPath=/dev/null push -q origin main:claude-shared-work
bash "$SHARE" --done <<<y >/dev/null 2>&1
check "--done deletes its branches" test -z "$(one)"
check "...and no other: main, claude, even one with a similar name" test "$(heads | sort | paste -sd' ')" = "claude claude-shared-work main"

[ "$fails" -eq 0 ]
