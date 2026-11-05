#!/bin/bash
# Checks tools/build-deb.sh: the Wren Linux package holds what is committed and
# nothing else, all of it root's and read-only to everyone else, runs nothing
# when installed, and two builds of one commit are the same file. The package
# is unpacked into a temp folder and used from there, never installed.
# Run by test.sh, or:  bash tools/test-build-deb.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
not() { ! "$@"; }
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
git -C "$T/src" -c user.name=t -c user.email=t@example.org commit -q -m "as it is now" --allow-empty
echo "not committed" >"$T/src/UNCOMMITTED.txt"
B=$T/src/tools/build-deb.sh
mkdir "$T/a" "$T/b"
outa=$(bash "$B" --out "$T/a" --version 1.0 2>&1)
check "it builds" test -f "$T/a/wren-linux_1.0_all.deb"
D=$T/a/wren-linux_1.0_all.deb
bash "$B" --out "$T/b" --version 1.0 >/dev/null 2>&1
check "two builds of one commit are the same file, byte for byte" cmp "$D" "$T/b/wren-linux_1.0_all.deb"
check "...and it says the SHA-256 to compare" grep -qx "SHA-256: $(sha256sum "$D" | cut -d' ' -f1)" <<<"$outa"
mkdir "$T/c"
bash "$B" --out "$T/c" >/dev/null 2>&1
check "without --version: 0~git, the commit's time and id" bash -c 'ls "$1" | grep -qxE "wren-linux_0~git[0-9]{14}\.[0-9a-f]{10}_all\.deb"' _ "$T/c"
# Later commits sort higher, whatever their ids: apt called a newer commit of the
# same day a downgrade when its id happened to sort lower, and wouldn't have upgraded
v_of() { dpkg-deb -f "$1"/wren-linux_*_all.deb Version; }
newer=true
for n in 1 2 3 4 5 6; do
    GIT_COMMITTER_DATE="$(date -u -d "2030-01-01 12:00:0$n")" git -C "$T/src" -c user.name=t -c user.email=t@example.org commit -q --allow-empty -m "later $n"
    rm -rf "$T/v"; mkdir "$T/v"; bash "$B" --out "$T/v" >/dev/null 2>&1
    now=$(v_of "$T/v")
    if [ -n "${before:-}" ] && ! dpkg --compare-versions "$now" gt "$before"; then newer=false; fi
    before=$now
done
git -C "$T/src" reset -q --soft HEAD~6
check "...a later commit always has a higher version, the same day too" "$newer"
check "a version that isn't one is refused" bash -c '! bash "$1" --out "$2" --version "1 0;x" 2>/dev/null' _ "$B" "$T/c"

f() { dpkg-deb -f "$D" "$1"; }
check "the package is Wren Linux, for every architecture" bash -c '[ "$1" = wren-linux ] && [ "$2" = all ]' _ "$(f Package)" "$(f Architecture)"
check "...it depends only on sudo, which every Debian install has (bash is essential: never named): the install stick puts it in with no network" test "$(f Depends)" = "sudo"
check "...and recommends the tools the parts install themselves" bash -c 'for d in gpg git wget python3 acl nftables; do grep -qw "$d" <<<"$1" || exit 1; done' _ "$(f Recommends)"
check "no install scripts: installing it runs nothing as root" test "$(dpkg-deb --ctrl-tarfile "$D" | tar -t | sort | paste -sd' ')" = "./ ./control ./md5sums"

dpkg-deb -c "$D" >"$T/list"
check "everything is root's" bash -c '! awk "{ print \$2 }" "$1" | grep -vx root/root' _ "$T/list"
check "nothing is writable by anyone but root" bash -c '! awk "{ print \$1 }" "$1" | grep -E "^.....w|^........w"' _ "$T/list"
check "nothing is setuid or setgid" bash -c '! awk "{ print \$1 }" "$1" | grep -E "^...[sS]|^......[sS]"' _ "$T/list"
check "nothing outside /usr" bash -c '! awk "{ print \$6 }" "$1" | grep -vE "^\./(usr/.*)?$"' _ "$T/list"

mkdir "$T/root"
dpkg-deb -x "$D" "$T/root"
S=$T/root/usr/share/wren
check "Wren Linux is in /usr/share/wren" test -f "$S/lib.sh"
check "...what was committed, not what was only in the folder" test ! -e "$S/UNCOMMITTED.txt"
check "...without the project's own CI and notes" bash -c '[ ! -e "$1/.github" ] && [ ! -e "$1/CLAUDE.md" ]' _ "$S"
DEVONLY='^(\.github/|\.gitignore$|CLAUDE\.md$|tools/|docs/maintaining\.md$|docs/distro-plan\.md$|docs/vps\.md$|extras/signing-key\.sh$|docs/extras/signing-key\.md$|bin/wren-key$|bin/wren-key-gpg$|bin/wren-signer$|data/wren-key\.1$|data/signer-firewall\.nft$|site/)'
check "...every committed file but what only someone working on Wren Linux uses" test "$(git -C "$T/src" ls-files | grep -cvE "$DEVONLY")" = "$(cd "$S" && find . -type f | wc -l)"
check "...no tests or build tools, no maintainer's documents" bash -c '[ ! -e "$1/tools" ] && [ ! -e "$1/docs/maintaining.md" ] && [ ! -e "$1/docs/distro-plan.md" ]' _ "$S"
check "...no signing key tools (their sudo rule and user are for the publisher only)" bash -c '
    for f in extras/signing-key.sh bin/wren-key bin/wren-key-gpg bin/wren-signer data/signer-firewall.nft; do [ ! -e "$1/$f" ] || exit 1; done' _ "$S"
check "...but the key every computer checks updates with, and wren-dev to get the rest" bash -c '[ -f "$1/lib/update.sh" ] && [ -f "$1/extras/wren-dev.sh" ] && [ -f "$1/data/wren-signing-key.asc" ] || [ ! -f "$2/data/wren-signing-key.asc" ]' _ "$S" "$HERE"
check "...and the list of extras links to no page it left out" bash -c '! grep -q "(signing-key.md)" "$1/docs/extras/README.md"' _ "$S"
out=$(cd "$S" && HOME=$T/pkghome bash test.sh --offline 2>&1)
check "wrenctl --test works there, without the tests of each piece" bash -c '! grep -qE "tools/test-|No such file|has no article|link to" <<<"$1" && grep -qE "^[0-9]+ ok, " <<<"$1"' _ "$out"
check "...executable where git says so, and only there" bash -c '
    cd "$1" && git -C "$2" ls-tree -r HEAD | awk "\$1 == \"100755\" { sub(/^[^\t]*\t/, \"\"); print }" | grep -vE "$4" | sort >"$3/x-git"
    find . -type f -perm -u+x | sed "s|^\./||" | sort >"$3/x-pkg"
    cmp "$3/x-git" "$3/x-pkg"' _ "$S" "$T/src" "$T" "$DEVONLY"
check "the Wren Linux command in /usr/bin, the same as bin/wrenctl" cmp "$T/root/usr/bin/wrenctl" "$S/bin/wrenctl"
check "its man page" bash -c 'zcat "$1" | grep -q "^.TH WRENCTL 1"' _ "$T/root/usr/share/man/man1/wrenctl.1.gz"
check "its Tab completion where bash-completion looks" cmp "$T/root/usr/share/bash-completion/completions/wrenctl" "$S/data/wrenctl-completion.bash"
check "the licenses, Wren Linux's and mockvps-kvm's" bash -c 'grep -q "^License: MIT" "$1" && grep -q "vendor/mockvps-kvm" "$1"' _ "$T/root/usr/share/doc/wren-linux/copyright"
check "the md5sums match the files" bash -c 'cd "$1" && dpkg-deb --ctrl-tarfile "$2" | tar -xO ./md5sums | md5sum -c --quiet -' _ "$T/root" "$D"

# Used from where it is unpacked, as from /usr/share/wren
ds() { env -u WREN_DIR HOME="$T/home" WREN_SYSTEM_DIR="$S" bash "$T/root/usr/bin/wrenctl" "$@"; }
mkdir -p "$T/home"
check "the command finds the package's copy" test "$(ds --dir)" = "$S"
check "...and lists the extras from it" bash -c 'grep -q "vim" <<<"$1"' _ "$(ds --list 2>&1)"

chmod -R a-w "$T/root"
out=$(HOME="$T/home" bash "$S/update.sh" 2>&1)
check "wrenctl update from the package's copy: apt brings what is new, and it runs again what that changed" grep -q "installed here as the Wren Linux package" <<<"$out"
chmod -R u+w "$T/root"

# lintian: remarks are one thing, lintian itself failing another
LC=$(sed -n '/^lintian_check() {/,/^}/p' "$HERE/tools/build-deb.sh")
# shellcheck disable=SC2317,SC2329  # lintian is called by the function in LC
lc_rc() { ( lc_code=$1 lc_out=${2:-}; lintian() { [ -z "$lc_out" ] || echo "$lc_out"; return "$lc_code"; }; eval "$LC"; lintian_check x 2>&1 ); }
check "lintian content: nothing more to say" test -z "$(lc_rc 0)"
check "lintian with remarks: shows them, and says so" bash -c 'grep -q "^W: x" <<<"$1" && grep -q "has remarks" <<<"$1"' _ "$(lc_rc 0 'W: x')"
check "...whatever code a lintian version gives for them: only its own failure is a failure" bash -c 'grep -q "NOT checked" <<<"$1" && grep -q "NOT checked" <<<"$2"' _ "$(lc_rc 1 'W: x')" "$(lc_rc 2 'E: x')"
check "lintian runs with --fail-on none: its own failure is then the only thing its exit code says" \
    grep -q 'lintian --fail-on none ' <<<"$LC"
check "lintian itself failing (a bad option is 25): says the package was NOT checked" bash -c 'grep -q "NOT checked" <<<"$1" && ! grep -q "has remarks" <<<"$1"' _ "$(lc_rc 25)"
# The option as this lintian takes it: fails here, in the tests, when one is renamed
if command -v lintian >/dev/null; then
    opt=$(sed -n 's/.*$(lintian \(--[^"]*\) "\$1").*/\1/p' "$HERE/tools/build-deb.sh")
    # shellcheck disable=SC2086  # the options, as the script has them
    out=$(lintian $opt /nonexistent.deb 2>&1); rc=$?
    check "this lintian takes the options build-deb.sh gives it" test "$rc" != 25
    check "...and doesn't warn that it will stop taking them" not grep -qi 'future release' <<<"$out"
    # The real lintian on the package built above: it ran, whatever it says
    out=$(eval "$LC"; lintian_check "$T/a/wren-linux_1.0_all.deb" 2>&1)
    check "the real lintian checks the package (it runs: no NOT checked)" not grep -q 'NOT checked' <<<"$out"
    check "...and finds no errors in it (E:)" not grep -q '^E: ' <<<"$out"
fi

[ "$fails" -eq 0 ]
