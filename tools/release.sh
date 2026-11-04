#!/bin/bash
# release.sh: publishes this git copy of Wren Linux and brings this computer up to
# it, in one command, stopping at the first step that doesn't work. As you, in a
# terminal. Every question and password of the steps is still yours to answer:
#   1. tools/git-push.sh: shows what would go out, signs it, asks, pushes
#   2. tools/build-deb.sh: the package, from the commit, in a new private folder
#   3. sudo apt install: that one file, with its SHA-256 shown first
#   4. wrenctl --update: offers to run again the scripts whose files changed
# The private folder matters: /tmp is open to every user, the sandboxes' too, and
# apt installs as root, so a name like /tmp/wren-linux_*.deb could also pick up a
# package a hacked sandbox left there.
# Usage: bash tools/release.sh           publish, then install here
#        bash tools/release.sh --local   install here only, nothing is pushed (to try
#                                     the last commit; what isn't committed stays out)
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
not_root

g() { git -C "$WREN_DIR" "$@"; }
# (a test gives its own pretend wrenctl)
WRENCTL=${WREN_WRENCTL:-wrenctl}

local_only=false
case ${1:-} in
    "") ;;
    --local) local_only=true ;;
    *) die "Usage: bash tools/release.sh [--local]" ;;
esac
g rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "$WREN_DIR isn't a git copy (wrenctl install wren-dev gets one)."

if $local_only; then
    say "Nothing is pushed: this installs the last commit here"
    if [ -n "$(g status --porcelain --untracked-files=no)" ]; then
        warn "You have changes that aren't committed; the package has the last commit without them."
    fi
else
    say "Publishing"
    bash "$WREN_DIR/tools/git-push.sh" || die "It wasn't published, so nothing was installed."
    # (saying no to the push isn't a failure to git-push.sh)
    [ "$(g rev-list --count origin/main..HEAD)" = 0 ] ||
        die "Not everything was pushed, so nothing was installed. To try it here without publishing: bash tools/release.sh --local"
fi

say "Building the package"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
# apt reads the file as its own user, _apt; nobody else can write in here
chmod 755 "$work"
bash "$WREN_DIR/tools/build-deb.sh" --commit HEAD --out "$work" >"$work/build.out" ||
    { cat "$work/build.out"; die "The package wasn't built, so nothing was installed."; }
sed 1d "$work/build.out"
deb=$(head -n1 "$work/build.out")
case $deb in
    "$work"/wren-linux_*_all.deb) ;;
    *) die "The build named an unexpected file ($deb), so nothing was installed." ;;
esac
[ -f "$deb" ] && [ ! -L "$deb" ] || die "The package isn't there ($deb), so nothing was installed."
chmod 644 "$deb"

say "Installing ${deb##*/}"
$SUDO apt install "$deb" || die "The package wasn't installed, so nothing else was run."

say "Bringing this computer up to it"
"$WRENCTL" --update
