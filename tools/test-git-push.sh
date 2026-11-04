#!/bin/bash
# Checks tools/git-push.sh with a pretend server (a bare repository in a temp folder),
# a throwaway key and a pretend wren-key that signs with it: the first time it sets
# git up and pins the key, both files committed; unsigned work gets a signed commit on
# top; it pushes only after that and only if you say so. Changes nothing outside a
# temp folder. Run by test.sh, or:  bash tools/test-git-push.sh
# shellcheck disable=SC2016  # the pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v gpg >/dev/null || { echo "  ok    skipped: gpg isn't installed"; exit 0; }
T=$(mktemp -d)
export GNUPGHOME=$T/gh
trap 'gpgconf --kill all 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null
export HOME=$T/home XDG_DATA_HOME='' WREN_KEYS_ROOT=$T/no-keys
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/wren/signing-key"
mkdir -m 700 "$GNUPGHOME"
gpg --batch --quiet --passphrase '' --quick-gen-key "pinned <p@t>" ed25519 sign 1y 2>/dev/null
gpg --batch --quiet --passphrase '' --quick-gen-key "other <o@t>" ed25519 sign 1y 2>/dev/null
F=$(gpg --batch --with-colons --list-keys p@t 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }')
[ -n "$F" ] || { echo "  ok    skipped: gpg couldn't make test keys here"; exit 0; }
echo "$F" >"$HOME/.local/share/wren/signing-key/fingerprint"
# git signs through this, with $SIGN_FAILS making the key refuse
cat >"$T/signer" <<EOF
#!/bin/sh
case " \$* " in *" -b"*) [ ! -e "$T/sign-fails" ] || exit 1 ;; esac
exec gpg --batch --pinentry-mode loopback --passphrase '' "\$@"
EOF
chmod +x "$T/signer"
# The pretend wren-key: what the real one does for these two (tools/test-signing-key.sh checks that)
cat >"$HOME/.local/bin/wren-key" <<EOF
#!/bin/bash
echo "wren-key \$*" >>"$T/calls"
case \$1 in
    git-setup) git -C "\$2" config user.signingkey "$F"; git -C "\$2" config gpg.format openpgp
        git -C "\$2" config gpg.program "$T/signer"; git -C "\$2" config commit.gpgsign true ;;
    pin) gpg --batch --armor --export "$F" >"\$2/data/wren-signing-key.asc"
        sed -i "s/^WREN_SIGNING_FPR=.*/WREN_SIGNING_FPR=$F/" "\$2/pins.sh" ;;
esac
EOF
chmod +x "$HOME/.local/bin/wren-key"

# Your copy L, from this checkout's files, and the server O
mkdir "$T/L"
(cd "$HERE" && git ls-files -co --exclude-standard | tar -cf - -T -) | tar -C "$T/L" -xf -
# (as it was before any key: this checkout may pin the real one by now)
sed -i 's/^WREN_SIGNING_FPR=.*/WREN_SIGNING_FPR=/' "$T/L/pins.sh"
rm -f "$T/L/data/wren-signing-key.asc"
git -C "$T/L" init -q -b main && git -C "$T/L" add -A && git -C "$T/L" -c commit.gpgsign=false commit -q -m first
git clone -q --bare "$T/L" "$T/O.git"
git -C "$T/L" remote add origin "$T/O.git"
git -C "$T/L" fetch -q origin
server() { git -C "$T/O.git" rev-parse main; }
head_() { git -C "$T/L" rev-parse HEAD; }
gp() { : >"$T/calls"; printf '%s\n' "$@" >"$T/answers"; WREN_TEST_ANSWERS=$T/answers bash "$T/L/tools/git-push.sh" >"$T/out" 2>&1; }
commit() { echo "$1" >>"$T/L/README.md"; git -C "$T/L" -c commit.gpgsign=false commit -q -am "$1"; }
# verified MY-COMMIT: signed by the pinned key, as update.sh checks it
verified() { bash -c '. "$1/lib.sh"; . "$1/lib/appimage.sh"; . "$1/lib/update.sh"; WREN_SIGNING_FPR=$2; update_signed "$3"' _ "$T/L" "$F" "$1"; }

before=$(server)
commit 'work of a helper'
gp y n
check "the first time: git is set up to sign, and the key pinned" bash -c '
    grep -qx "wren-key git-setup $2" "$1" && grep -qx "wren-key pin $2" "$1"' _ "$T/calls" "$T/L"
check "...the pin commits both files (a pin with no key file refuses every update)" bash -c '
    git -C "$1" show --name-only --format= HEAD | sort | paste -sd" " | grep -qx "data/wren-signing-key.asc pins.sh"' _ "$T/L"
check "...the newest commit is signed by the key" verified HEAD
check "...it shows what would go out" grep -q 'work of a helper' "$T/out"
check "no to the push: nothing goes out" test "$(server)" = "$before"
check "...and they stay here" grep -q 'stay here' "$T/out"

gp y
check "...and it says exactly how to install it here" grep -q 'sudo apt install /tmp/wren-linux_\*.deb' "$T/out"
check "yes: it goes out, already signed, nothing added" bash -c '[ "$(git -C "$2" rev-parse main)" = "$1" ] && ! grep -q "isn.t signed" "$3"' _ "$(head_)" "$T/O.git" "$T/out"
gp
check "nothing new: it says so" grep -q 'Nothing to push' "$T/out"
check "...and asks about no key any more" test ! -s "$T/calls"

commit 'more work of a helper'
tip=$(head_)
check "(an unsigned commit doesn't pass the check)" not verified HEAD
gp y y
check "an unsigned newest commit: signed by a commit on top" bash -c '[ "$(git -C "$1" rev-parse HEAD~1)" = "$2" ] && [ "$(git -C "$1" log -1 --format=%s)" = "Signed: the commits below are reviewed" ]' _ "$T/L" "$tip"
check "...what reaches the server passes the check" bash -c '[ "$(git -C "$1" rev-parse main)" = "$2" ]' _ "$T/O.git" "$(head_)"
check "...and it is signed" verified HEAD

commit 'not to be signed'
pushed=$(server)
gp n
check "no to signing: nothing goes out" test "$(server)" = "$pushed"
check "...and no commit is added" test "$(git -C "$T/L" log -1 --format=%s)" = 'not to be signed'
: >"$T/sign-fails"
gp y y
check "the key doesn't sign: nothing goes out" test "$(server)" = "$pushed"
check "...and it says so" grep -q "didn't sign" "$T/out"
rm "$T/sign-fails"
# signed by another key: the check is the pinned key's alone
git -C "$T/L" -c user.signingkey=o@t commit -q --allow-empty -m 'by another key'
gp y y
check "a newest commit signed by another key gets signed by this one before it goes" verified main

echo changed >>"$T/L/README.md"
pushed=$(server)
gp y y y
check "changes not committed: nothing goes out, and it names them" bash -c '[ "$(git -C "$1" rev-parse main)" = "$2" ] && grep -q README.md "$3"' _ "$T/O.git" "$pushed" "$T/out"
git -C "$T/L" checkout -q -- README.md

git clone -q "$T/O.git" "$T/other" && git -C "$T/other" -c commit.gpgsign=false commit -q --allow-empty -m 'from elsewhere' && git -C "$T/other" push -q origin main
theirs=$(server)
gp y y y
check "the server has commits you don't: refused, never forced" bash -c 'grep -q "server has commits" "$1" && [ "$(git -C "$2" rev-parse main)" = "$3" ]' _ "$T/out" "$T/O.git" "$theirs"
check "it never forces" not grep -qE 'push .*(-f|--force)' "$HERE/tools/git-push.sh"
git -C "$T/L" fetch -q origin; git -C "$T/L" -c commit.gpgsign=false merge -q --no-edit origin/main 2>/dev/null

git -C "$T/L" checkout -q -b side
gp y y y
check "another branch: refused" grep -q 'for the branch main' "$T/out"
git -C "$T/L" checkout -q main

rm "$HOME/.local/share/wren/signing-key/fingerprint"
gp y y y
check "no key made yet: it says how" grep -q 'extras/signing-key.sh' "$T/out"
echo "$F" >"$HOME/.local/share/wren/signing-key/fingerprint"
sed -i "s/^WREN_SIGNING_FPR=.*/WREN_SIGNING_FPR=0000000000000000000000000000000000000000/" "$T/L/pins.sh"
git -C "$T/L" -c commit.gpgsign=false commit -q -am 'another pin'
gp y y y
check "pins.sh pins another key: refused" grep -q 'pins another key' "$T/out"

[ "$fails" -eq 0 ]
