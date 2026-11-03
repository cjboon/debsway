#!/bin/bash
# Checks tools/build-deb.sh: the debsway package holds what is committed and
# nothing else, all of it root's and read-only to everyone else, runs nothing
# when installed, and two builds of one commit are the same file. The package
# is unpacked into a temp folder and used from there, never installed.
# Run by test.sh, or:  bash tools/test-build-deb.sh
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
command -v dpkg-deb >/dev/null || { echo "  ok    skipped: dpkg-deb isn't installed"; exit 0; }

# A copy of this checkout with one more commit, so what isn't committed (a
# file left in the folder) can be told apart from what is
mkdir "$T/src"
(cd "$HERE" && git ls-files -co --exclude-standard | tar -cf - -T -) | tar -C "$T/src" -xf -
git -C "$T/src" init -q -b main
git -C "$T/src" add -A
git -C "$T/src" -c user.name=t -c user.email=t@t commit -q -m "as it is now" --allow-empty
echo "not committed" >"$T/src/UNCOMMITTED.txt"
B=$T/src/tools/build-deb.sh
mkdir "$T/a" "$T/b"
outa=$(bash "$B" --out "$T/a" --version 1.0 2>&1)
check "it builds" test -f "$T/a/debsway_1.0_all.deb"
D=$T/a/debsway_1.0_all.deb
bash "$B" --out "$T/b" --version 1.0 >/dev/null 2>&1
check "two builds of one commit are the same file, byte for byte" cmp "$D" "$T/b/debsway_1.0_all.deb"
check "...and it says the SHA-256 to compare" grep -qx "SHA-256: $(sha256sum "$D" | cut -d' ' -f1)" <<<"$outa"
mkdir "$T/c"
bash "$B" --out "$T/c" >/dev/null 2>&1
check "without --version: 0~git, the commit's date and id" bash -c 'ls "$1" | grep -qxE "debsway_0~git[0-9]{8}\.[0-9a-f]{10}_all\.deb"' _ "$T/c"
check "a version that isn't one is refused" bash -c '! bash "$1" --out "$2" --version "1 0;x" 2>/dev/null' _ "$B" "$T/c"

f() { dpkg-deb -f "$D" "$1"; }
check "the package is debsway, for every architecture" bash -c '[ "$1" = debsway ] && [ "$2" = all ]' _ "$(f Package)" "$(f Architecture)"
check "...it depends on what the parts need before they run" bash -c 'for d in bash sudo git gpg python3 acl nftables; do grep -qw "$d" <<<"$1" || exit 1; done' _ "$(f Depends)"
check "no install scripts: installing it runs nothing as root" test "$(dpkg-deb --ctrl-tarfile "$D" | tar -t | sort | paste -sd' ')" = "./ ./control ./md5sums"

dpkg-deb -c "$D" >"$T/list"
check "everything is root's" bash -c '! awk "{ print \$2 }" "$1" | grep -vx root/root' _ "$T/list"
check "nothing is writable by anyone but root" bash -c '! awk "{ print \$1 }" "$1" | grep -E "^.....w|^........w"' _ "$T/list"
check "nothing is setuid or setgid" bash -c '! awk "{ print \$1 }" "$1" | grep -E "^...[sS]|^......[sS]"' _ "$T/list"
check "nothing outside /usr" bash -c '! awk "{ print \$6 }" "$1" | grep -vE "^\./(usr/.*)?$"' _ "$T/list"

mkdir "$T/root"
dpkg-deb -x "$D" "$T/root"
S=$T/root/usr/share/debsway
check "debsway is in /usr/share/debsway" test -f "$S/lib.sh"
check "...what was committed, not what was only in the folder" test ! -e "$S/UNCOMMITTED.txt"
check "...without the project's own CI and notes" bash -c '[ ! -e "$1/.github" ] && [ ! -e "$1/CLAUDE.md" ]' _ "$S"
check "...every committed file" test "$(git -C "$T/src" ls-files | grep -cvE '^(\.github/|\.gitignore$|CLAUDE\.md$)')" = "$(cd "$S" && find . -type f | wc -l)"
check "...executable where git says so, and only there" bash -c '
    cd "$1" && git -C "$2" ls-tree -r HEAD | awk "\$1 == \"100755\" { sub(/^[^\t]*\t/, \"\"); print }" | sort >"$3/x-git"
    find . -type f -perm -u+x | sed "s|^\./||" | sort >"$3/x-pkg"
    cmp "$3/x-git" "$3/x-pkg"' _ "$S" "$T/src" "$T"
check "the debsway command in /usr/bin, the same as bin/debsway" cmp "$T/root/usr/bin/debsway" "$S/bin/debsway"
check "its man page" bash -c 'zcat "$1" | grep -q "^.TH DEBSWAY 1"' _ "$T/root/usr/share/man/man1/debsway.1.gz"
check "its Tab completion where bash-completion looks" cmp "$T/root/usr/share/bash-completion/completions/debsway" "$S/data/debsway-completion.bash"
check "the licenses, debsway's and mockvps-kvm's" bash -c 'grep -q "^License: MIT" "$1" && grep -q "vendor/mockvps-kvm" "$1"' _ "$T/root/usr/share/doc/debsway/copyright"
check "the md5sums match the files" bash -c 'cd "$1" && dpkg-deb --ctrl-tarfile "$2" | tar -xO ./md5sums | md5sum -c --quiet -' _ "$T/root" "$D"

# Used from where it is unpacked, as from /usr/share/debsway
ds() { env -u DEBSWAY_DIR HOME="$T/home" DEBSWAY_SYSTEM_DIR="$S" bash "$T/root/usr/bin/debsway" "$@"; }
mkdir -p "$T/home"
check "the command finds the package's copy" test "$(ds --dir)" = "$S"
check "...and lists the extras from it" bash -c 'grep -q "vim" <<<"$1"' _ "$(ds --list 2>&1)"

chmod -R a-w "$T/root"
out=$(HOME="$T/home" bash "$S/update.sh" 2>&1)
check "debsway update from the package's copy says a newer package brings updates" grep -q "debsway package's, read-only" <<<"$out"
chmod -R u+w "$T/root"

[ "$fails" -eq 0 ]
