#!/bin/bash
# Checks bin/debsway (the debsway command) and its man page, with a pretend
# debsway folder whose scripts only write down how they were called. Changes
# nothing. Run by test.sh, or:  bash tools/test-debsway-cmd.sh
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CMD=$HERE/bin/debsway

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

mkdir -p "$T/dir" "$T/home/.local/bin"
: >"$T/dir/lib.sh"
for s in update install-extras status test; do
    # shellcheck disable=SC2016  # written into the pretend scripts, expanded when they run
    printf '#!/bin/bash\necho "%s $*" >>"%s/ran"\n' "$s" "$T" >"$T/dir/$s.sh"
done
# shellcheck disable=SC2016  # written into the pretend program, expanded when it runs
printf '#!/bin/sh\necho "menu" >>"%s/ran"\n' "$T" >"$T/home/.local/bin/debsway-menu"
# shellcheck disable=SC2016
printf '#!/bin/sh\necho "keys" >>"%s/ran"\n' "$T" >"$T/home/.local/bin/keys"
chmod +x "$T/dir/"*.sh "$T/home/.local/bin/"*

d() { : >"$T/ran"; env -u WAYLAND_DISPLAY HOME="$T/home" DEBSWAY_DIR="$T/dir" bash "$CMD" "$@"; }
dsway() { : >"$T/ran"; env WAYLAND_DISPLAY=wayland-1 HOME="$T/home" DEBSWAY_DIR="$T/dir" bash "$CMD" "$@"; }

# what each option starts
d --update --since abc123
check "--update runs update.sh with its arguments" grep -qx 'update --since abc123' "$T/ran"
d --apps --list
check "--apps runs install-extras.sh with its arguments" grep -qx 'install-extras --list' "$T/ran"
d --status
check "--status runs status.sh" grep -qx 'status *' "$T/ran"
d --test --offline
check "--test runs test.sh" grep -qx 'test --offline' "$T/ran"
d --welcome
check "--welcome shows the key cheat sheet" grep -qx 'keys' "$T/ran"
d update
check "a bare word works too (debsway update)" grep -qx 'update *' "$T/ran"
check "--dir says where the folder is" test "$(d --dir)" = "$T/dir"

# the menu, and the help
dsway
check "with no option, on a sway screen, it opens the menu" grep -qx 'menu' "$T/ran"
dsway --menu
check "--menu opens the menu" grep -qx 'menu' "$T/ran"
out=$(d)
check "with no option anywhere else it shows the help" grep -q '^usage: debsway' <<<"$out"
check "...and starts nothing" test ! -s "$T/ran"
check "--menu without a sway screen says so" grep -q 'needs your sway session' <(d --menu 2>&1)
check "--menu without a sway screen fails" not d --menu

# mistakes
d --nonsense >/dev/null 2>"$T/err"; rc=$?
check "an unknown option exits 2" test "$rc" -eq 2
check "...and says which one, with the help" grep -q 'unknown option "--nonsense"' "$T/err"
check "a missing folder is explained" grep -q "can't find the debsway folder" <(env HOME="$T/home" DEBSWAY_DIR="$T/nowhere" bash "$CMD" --update 2>&1)
check "--help works without the folder" env HOME="$T/home" DEBSWAY_DIR="$T/nowhere" bash "$CMD" --help

# the help text and the man page say the same
help_opts=$(bash "$CMD" --help | grep -o '^  --[a-z]*' | tr -d ' ' | sort -u)
man_opts=$(sed -n 's/^\.B \\-\\-\([a-z]*\)$/--\1/p' "$HERE/data/debsway.1" | sort -u)
check "the help lists options" test -n "$help_opts"
check "every option in the help is in the man page, and the other way round" test "$help_opts" = "$man_opts"
check "the man page has no groff warnings" test -z "$(groff -ww -man -Tutf8 "$HERE/data/debsway.1" 2>&1 >/dev/null)"
# shellcheck disable=SC2016  # expanded by the inner bash, on purpose
check "the man page has the usual sections" bash -c 'for s in NAME SYNOPSIS DESCRIPTION OPTIONS FILES; do grep -q "^.SH $s" "$1" || exit 1; done' _ "$HERE/data/debsway.1"
# shellcheck disable=SC2016  # expanded by the inner bash, on purpose
check "the part installs the command and the man page" bash -c 'grep -q "install_bin debsway$" "$1" && grep -q "data/debsway.1" "$1"' _ "$HERE/parts/debsway-menu.sh"

[ "$fails" -eq 0 ]
