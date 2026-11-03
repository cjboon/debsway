#!/bin/bash
# Checks extras/vim.sh and data/vimrc: Debian's full vim is installed; the
# vimrc colors code by file type, turns modelines off, and follows debsway's
# light or dark theme; it is written only where you have no vimrc of your
# own, rewritten while its first line is debsway's, and --remove takes out
# only debsway's. Runs the extra with a pretend sudo (only logs) and
# dpkg-query (its packages "already installed"), in a temp home, so nothing on
# this computer changes; vim itself only if the full vim is installed here.
# Run by test.sh, or:  bash tools/test-vim.sh
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

V=$HERE/data/vimrc
check "the vimrc colors code by language, with indenting by file type" bash -c 'grep -qx "syntax on" "$1" && grep -qx "filetype plugin indent on" "$1"' _ "$V"
check "...turns modelines off (settings hidden in a file you open)" grep -qx 'set nomodeline' "$V"
check "...and reads no .vimrc or .exrc from the folder vim starts in" grep -qx 'set noexrc secure' "$V"

# vim itself, if the full vim is here: the vimrc loads cleanly, light or dark with the theme
if command -v vim.basic >/dev/null; then
    bg() { HOME=$T/vh vim.basic -u "$V" -i NONE -N -es -c 'echo &background' -c 'qall!' </dev/null 2>&1 | tr -d '\r\n '; }
    mkdir -p "$T/vh/.config/debsway"
    check "vim reads it without an error, dark without a theme" test "$(bg)" = dark
    echo light >"$T/vh/.config/debsway/theme"
    check "...light in debsway's light theme" test "$(bg)" = light
    check "...modelines off in vim itself" test "$(HOME=$T/vh vim.basic -u "$V" -i NONE -N -es -c 'echo &modeline' -c 'qall!' </dev/null 2>&1 | tr -d '\r\n ')" = 0
else
    echo "  ok    skipped running vim: the full vim isn't installed here"
fi

# ---- the extra, with pretend programs
mkdir -p "$T/bin" "$T/home"
cat >"$T/bin/sudo" <<EOF
#!/bin/sh
[ "\$1" = -v ] && exit 0
echo "\$*" >>"$T/root-calls"
EOF
cat >"$T/bin/dpkg-query" <<'EOF'
#!/bin/sh
case "$*" in
    *Status*) echo 'install ok installed' ;;
    *Depends*) echo 'vim' ;;
esac
EOF
chmod +x "$T/bin/"*
W=$T/r
mkdir -p "$W/extras" "$W/data"
sed 's|^export PATH=.*|export PATH="$VIM_TEST_PATH"|' "$HERE/lib.sh" >"$W/lib.sh"
grep -q VIM_TEST_PATH "$W/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
cp "$HERE/pins.sh" "$HERE/packages.sh" "$W/"
ln -s "$HERE/lib" "$W/lib"
cp "$HERE/extras/vim.sh" "$W/extras/"
cp "$V" "$W/data/"
export VIM_TEST_PATH="$T/bin:$PATH"
[ "$(bash -c '. "$1/lib.sh"; command -v sudo' _ "$W")" = "$T/bin/sudo" ] || { echo "  FAIL  the real sudo would run; stopping"; exit 1; }
run() { : >"$T/root-calls"; HOME=$T/home bash "$W/extras/vim.sh" "$@" >"$T/out" 2>&1; }

run
check "it installs Debian's full vim" grep -qx 'apt_install vim' "$HERE/extras/vim.sh"
check "...and writes debsway's vimrc where there was none" cmp "$V" "$T/home/.vimrc"
echo '" old debsway lines' >>"$T/home/.vimrc"
run
check "run again: debsway's vimrc is written again (its first line is debsway's)" cmp "$V" "$T/home/.vimrc"
printf 'set number\n' >"$T/home/.vimrc"
run
check "a vimrc of your own is left alone" test "$(cat "$T/home/.vimrc")" = 'set number'
check "...and it says what to add for the colors" grep -q 'syntax on' "$T/out"
run --remove
check "--remove leaves a vimrc of your own" test -f "$T/home/.vimrc"
cp "$V" "$T/home/.vimrc"
run --remove
check "...and takes out debsway's" test ! -e "$T/home/.vimrc"
check "...and vim (vim-tiny, Debian's own, stays)" grep -q 'vim-tiny' "$T/out"

[ "$fails" -eq 0 ]
