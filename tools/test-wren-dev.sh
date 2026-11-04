#!/bin/bash
# Checks extras/wren-dev.sh's git copy: it is fetched into ~/wren-linux when there is
# none, kept when there is one, and something else by that name is left alone; with
# a key pinned, an unsigned server is refused and nothing is left behind. And the
# package's copy (read-only, no git) sends you here. In a temp home, with a pretend
# sudo and dpkg-query (its packages "already installed") and a pretend server in a
# temp folder. Run by test.sh, or:  bash tools/test-wren-dev.sh
# shellcheck disable=SC2016  # the pretend programs expand their own variables
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
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null

mkdir -p "$T/bin" "$T/home"
printf '#!/bin/sh\n[ "$1" = -v ] && exit 0\necho "sudo $*" >>"%s/calls"\n' "$T" >"$T/bin/sudo"
cat >"$T/bin/dpkg-query" <<'EOF'
#!/bin/sh
case "$*" in
    *Status*) echo 'install ok installed' ;;
    *Depends*) echo 'lintian, shellcheck, git' ;;
esac
EOF
chmod +x "$T/bin/"*
# The server
mkdir "$T/w" && echo hello >"$T/w/README.md"
git -C "$T/w" init -q -b main && git -C "$T/w" add -A && git -C "$T/w" -c commit.gpgsign=false commit -q -m first
git clone -q --bare "$T/w" "$T/server.git"
# Wren Linux as the package has it: no git, no tools; pins.sh names the pretend server
R=$T/usr/share/wren
mkdir -p "$R/extras"
sed 's|^export PATH=.*|export PATH="$DEV_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
sed "s|^WREN_GIT_URL=.*|WREN_GIT_URL=file://$T/server.git|" "$HERE/pins.sh" >"$R/pins.sh"
for f in packages.sh lib data docs bin; do ln -s "$HERE/$f" "$R/$f"; done
cp "$HERE/extras/wren-dev.sh" "$R/extras/"
export DEV_TEST_PATH="$T/bin:$PATH" HOME=$T/home
[ "$(bash -c '. "$1/lib.sh"; command -v sudo' _ "$R")" = "$T/bin/sudo" ] || { echo "  FAIL  the real sudo would run; stopping"; exit 1; }
run() { bash "$R/extras/wren-dev.sh" "$@" >"$T/out" 2>&1; }

run
check "no copy: it is fetched into ~/wren-linux" test "$(git -C "$HOME/wren-linux" rev-parse HEAD)" = "$(git -C "$T/w" rev-parse HEAD)"
check "...it says the signature wasn't checked while no key is pinned" grep -q 'not checked' "$T/out"
check "...and nothing else is left in your home" test "$(find "$HOME" -maxdepth 1 -name '.wren-linux*' | wc -l)" = 0
echo mine >"$HOME/wren-linux/mine.txt"
run
check "a copy there: left as it is" bash -c 'grep -q "You have one" "$1" && [ -f "$2/wren-linux/mine.txt" ]' _ "$T/out" "$HOME"
rm -rf "$HOME/wren-linux"; mkdir "$HOME/wren-linux"; echo mine >"$HOME/wren-linux/notes"
run
check "something else by that name: left alone, and it says so" bash -c 'grep -q "left alone" "$1" && [ "$(ls "$2/wren-linux")" = notes ]' _ "$T/out" "$HOME"
rm -rf "$HOME/wren-linux"
git -C "$R" init -q 2>/dev/null
run
check "in a git copy already: nothing fetched" bash -c 'grep -q "This is one" "$1" && [ ! -e "$2/wren-linux" ]' _ "$T/out" "$HOME"
rm -rf "$R/.git"
sed -i "s|^WREN_GIT_URL=.*|WREN_GIT_URL=file://$T/nothing.git|" "$R/pins.sh"
check "a server it can't reach: it says so" not run
check "...and leaves nothing behind" test "$(find "$HOME" -maxdepth 1 -name '.wren-linux*' | wc -l)" = 0
sed -i "s|^WREN_GIT_URL=.*|WREN_GIT_URL=file://$T/server.git|" "$R/pins.sh"
if command -v gpg >/dev/null; then
    export GNUPGHOME=$T/gh
    mkdir -m 700 "$GNUPGHOME"
    gpg --batch --quiet --passphrase '' --quick-gen-key "pinned <p@t>" ed25519 sign 1y 2>/dev/null
    F=$(gpg --batch --with-colons --list-keys 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }')
    if [ -n "$F" ]; then
        rm "$R/data"; mkdir "$R/data"; gpg --batch --armor --export "$F" >"$R/data/wren-signing-key.asc" 2>/dev/null
        sed -i "s|^WREN_SIGNING_FPR=.*|WREN_SIGNING_FPR=$F|" "$R/pins.sh"
        run
        check "a key pinned and an unsigned server: refused, nothing left behind" bash -c 'grep -q "signed by Wren Linux" "$1" && [ ! -e "$2/wren-linux" ] && [ -z "$(find "$2" -maxdepth 1 -name ".wren-linux*")" ]' _ "$T/out" "$HOME"
        git -C "$T/w" -c user.signingkey="$F" commit -q -S --allow-empty -m signed
        git -C "$T/w" push -q "$T/server.git" main
        run
        check "...a signed one: it is fetched" test -d "$HOME/wren-linux/.git"
        gpgconf --kill all 2>/dev/null
    fi
fi
check "making an install stick says to get a git copy, in the package's copy" grep -q 'wrenctl install wren-dev' "$HERE/prep/make-install-iso.sh"

[ "$fails" -eq 0 ]
