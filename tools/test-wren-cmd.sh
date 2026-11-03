#!/bin/bash
# Checks bin/wrenctl (the Wren Linux command) and its man page, with a pretend
# Wren Linux folder whose scripts only write down how they were called. Changes
# nothing. Run by test.sh, or:  bash tools/test-wren-cmd.sh
# shellcheck disable=SC2016  # the inner shells and pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CMD=$HERE/bin/wrenctl

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
printf '#!/bin/sh\necho "menu${*:+ $*}" >>"%s/ran"\n' "$T" >"$T/home/.local/bin/wren-menu"
# shellcheck disable=SC2016
printf '#!/bin/sh\necho "keys" >>"%s/ran"\n' "$T" >"$T/home/.local/bin/keys"
# shellcheck disable=SC2016
printf '#!/bin/sh\necho "radios $*" >>"%s/ran"\n' "$T" >"$T/home/.local/bin/radios"
chmod +x "$T/dir/"*.sh "$T/home/.local/bin/"*

d() { : >"$T/ran"; env -u WAYLAND_DISPLAY HOME="$T/home" WREN_DIR="$T/dir" bash "$CMD" "$@"; }
dsway() { : >"$T/ran"; env WAYLAND_DISPLAY=wayland-1 HOME="$T/home" WREN_DIR="$T/dir" bash "$CMD" "$@"; }

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
d --mic off
check "--mic off goes to the radio switch" grep -qx 'radios mic off' "$T/ran"
d --wifi
check "--wifi alone asks for its state" grep -qx 'radios wifi' "$T/ran"
d --bluetooth toggle
check "--bluetooth takes its word on" grep -qx 'radios bluetooth toggle' "$T/ran"
d update
check "a bare word works too (wrenctl update)" grep -qx 'update *' "$T/ran"
check "--dir says where the folder is" test "$(d --dir)" = "$T/dir"

# the menu, and the help
dsway
check "with no option, on a sway screen, it opens the menu" grep -qx 'menu' "$T/ran"
dsway --menu
check "--menu opens the menu" grep -qx 'menu' "$T/ran"
out=$(d)
check "with no option anywhere else it shows the help" grep -q '^usage: wrenctl' <<<"$out"
check "...and starts nothing" test ! -s "$T/ran"
check "--menu without a sway screen or a terminal says so" grep -q 'needs your sway session or a terminal' <(d --menu 2>&1)
check "--menu without a sway screen or a terminal fails" not d --menu
# a text console or ssh: no sway, but a terminal (script gives it one)
tty_d() { : >"$T/ran"; env -u WAYLAND_DISPLAY HOME="$T/home" WREN_DIR="$T/dir" script -qec "bash '$CMD' $*" /dev/null >/dev/null 2>&1; }
if command -v script >/dev/null; then
    tty_d
    check "with no option in a terminal without sway, it opens the menu right there" grep -qx 'menu --tui' "$T/ran"
    tty_d --menu
    check "--menu does the same" grep -qx 'menu --tui' "$T/ran"
fi

# mistakes
d --nonsense >/dev/null 2>"$T/err"; rc=$?
check "an unknown option exits 2" test "$rc" -eq 2
check "...and says which one, with the help" grep -q 'unknown option "--nonsense"' "$T/err"
check "a missing folder is explained" grep -q "can't find the Wren Linux folder" <(env HOME="$T/home" WREN_DIR="$T/nowhere" bash "$CMD" --update 2>&1)
check "--help works without the folder" env HOME="$T/home" WREN_DIR="$T/nowhere" bash "$CMD" --help

# install, remove, manual NAME; list; part NAME: only Wren Linux's own scripts, by exact name
mkdir -p "$T/dir/extras" "$T/dir/parts" "$T/dir/elsewhere"
for s in extras/vim extras/claude-vm parts/ufw elsewhere/evil; do
    # shellcheck disable=SC2016  # written into the pretend scripts, expanded when they run
    printf '#!/bin/bash\necho "%s $*" >>"%s/ran"\n' "$s" "$T" >"$T/dir/$s.sh"
done
d install vim
check "install NAME runs that extra" grep -qx 'extras/vim ' "$T/ran"
d --install vim
check "...--install too" grep -qx 'extras/vim ' "$T/ran"
d remove vim
check "remove NAME runs it with --remove" grep -qx 'extras/vim --remove' "$T/ran"
d manual vim
check "manual NAME runs it with --manual" grep -qx 'extras/vim --manual' "$T/ran"
d install claude-vm --account work
check "options after NAME go to the script" grep -qx 'extras/claude-vm --account work' "$T/ran"
d remove claude-vm --account work
check "...after --remove too" grep -qx 'extras/claude-vm --remove --account work' "$T/ran"
d list
check "list prints the extras (install-extras.sh --list)" grep -qx 'install-extras --list' "$T/ran"
d part ufw
check "part NAME runs that part" grep -qx 'parts/ufw ' "$T/ran"
for bad in ../elsewhere/evil ../parts/ufw 'vim;id' 'vim ' Vim -vim nosuch ''; do
    d install "$bad" >/dev/null 2>&1; rc=$?
    check "install \"$bad\" is refused and runs nothing" bash -c '[ "$1" -ne 0 ] && [ ! -s "$2" ]' _ "$rc" "$T/ran"
done
d install >/dev/null 2>"$T/err"
check "...with no name it asks which" grep -q 'which extra?' "$T/err"
d install nosuch >/dev/null 2>"$T/err"
check "...an unknown one is named, with where to look" grep -q 'no extra called "nosuch". wrenctl --list' "$T/err"
d part vim >/dev/null 2>&1; rc=$?
check "part takes parts only, not an extra" bash -c '[ "$1" -ne 0 ] && [ ! -s "$2" ]' _ "$rc" "$T/ran"
d part ../extras/vim >/dev/null 2>&1; rc=$?
check "...nor a path" bash -c '[ "$1" -ne 0 ] && [ ! -s "$2" ]' _ "$rc" "$T/ran"
d part ufw extra >/dev/null 2>&1; rc=$?
check "...and one name only" bash -c '[ "$1" -ne 0 ] && [ ! -s "$2" ]' _ "$rc" "$T/ran"

# Tab completion, with a pretend Wren Linux that answers --help and --dir
COMP=$HERE/data/wrenctl-completion.bash
mkdir -p "$T/cbin"
# shellcheck disable=SC2016
printf '#!/bin/sh\ncase "$1" in --dir) echo "%s/dir" ;; --help) WREN_DIR=%s/dir bash %s --help ;; esac\n' "$T" "$T" "$CMD" >"$T/cbin/wrenctl"
chmod +x "$T/cbin/wrenctl"
comp() { PATH="$T/cbin:$PATH" bash -c '. "$1"; shift; COMP_WORDS=("$@"); COMP_CWORD=$(($# - 1)); _wrenctl; printf "%s\n" "${COMPREPLY[@]}"' _ "$COMP" "$@" | sort | paste -sd' '; }
check "Tab after wrenctl: the options, with and without dashes" bash -c '[[ " $1 " == *" install "* && " $1 " == *" --install "* && " $1 " == *" part "* ]]' _ "$(comp wrenctl '')"
check "...a start of one completes it" test "$(comp wrenctl ins)" = install
check "Tab after install: the extras" test "$(comp wrenctl install '')" = "claude-vm vim"
check "...after --remove and manual too" bash -c '[ "$1" = "vim" ] && [ "$2" = "claude-vm vim" ]' _ "$(comp wrenctl --remove v)" "$(comp wrenctl manual '')"
check "Tab after part: the parts" test "$(comp wrenctl part '')" = ufw
check "Tab after --mic: on and off" test "$(comp wrenctl --mic '')" = "off on"
check "nothing after the name" test -z "$(comp wrenctl install vim '')"
check "the part installs the completion where bash-completion looks" \
    grep -q '"$WREN_DIR/data/wrenctl-completion.bash" "$COMPLETION"' "$HERE/parts/wren-menu.sh"

# the help text and the man page say the same
help_opts=$(bash "$CMD" --help | grep -o '^  --[a-z]*' | tr -d ' ' | sort -u)
man_opts=$(sed -n 's/^\.B \\-\\-\([a-z]*\)$/--\1/p' "$HERE/data/wrenctl.1" | sort -u)
check "the help lists options" test -n "$help_opts"
check "every option in the help is in the man page, and the other way round" test "$help_opts" = "$man_opts"
check "the man page has no groff warnings" test -z "$(groff -ww -man -Tutf8 "$HERE/data/wrenctl.1" 2>&1 >/dev/null)"
# shellcheck disable=SC2016  # expanded by the inner bash, on purpose
check "the man page has the usual sections" bash -c 'for s in NAME SYNOPSIS DESCRIPTION OPTIONS FILES; do grep -q "^.SH $s" "$1" || exit 1; done' _ "$HERE/data/wrenctl.1"
# shellcheck disable=SC2016  # expanded by the inner bash, on purpose
check "the part installs the command and the man page" bash -c 'grep -q "install_bin wrenctl$" "$1" && grep -q "data/wrenctl.1" "$1"' _ "$HERE/parts/wren-menu.sh"

[ "$fails" -eq 0 ]
