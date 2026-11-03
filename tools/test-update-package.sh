#!/bin/bash
# Checks update.sh in the debsway package's copy: read-only and without git,
# as /usr/share/debsway is. apt brings the new files; update.sh finds what
# changed against its record of the last run and offers to run those scripts
# again. A pretend upgrade changes the copy in place; a runner only writes down
# what it was asked to run, and sudo is a pretend one. Changes nothing outside
# a temp folder. Run by test.sh, or:  bash tools/test-update-package.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'chmod -R u+w "$T"; rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
ran() { grep -qxF "$P/$1" "$T/ran"; }

export HOME="$T/home" XDG_STATE_HOME="$T/state" DEBSWAY_KEYS_ROOT="$T/no-keys"
mkdir -p "$HOME"
# The package's copy: this checkout's files, no git, read-only
P=$T/usr/share/debsway
mkdir -p "$P"
(cd "$HERE" && git ls-files -co --exclude-standard | tar -cf - -T -) | tar -C "$P" -xf -
chmod -R a-w "$P"
# upgrade CMD...: what apt does: the files change in place, root's again after
upgrade() { chmod -R u+w "$P"; (cd "$P" && "$@"); chmod -R a-w "$P"; }

# shellcheck disable=SC2016  # written into the runner, expanded when it runs
printf '#!/bin/bash\necho "$1" >>"%s/ran"\n[ "$1" != "$FAIL_ON" ]\n' "$T" >"$T/runner"
printf '#!/bin/sh\nexit 0\n' >"$T/sudo"
chmod +x "$T/runner" "$T/sudo"
export DEBSWAY_UPDATE_RUNNER="$T/runner" DEBSWAY_SUDO="$T/sudo"
export DEBSWAY_UPDATE_ASSUME_INSTALLED="parts/incognito.sh extras/claude-code.sh extras/media.sh extras/sparrow-wallet.sh"
# shellcheck disable=SC2086  # ARGS: none, or an option and its word
upd() { : >"$T/ran"; printf '%s\n' "$@" >"$T/answers"; DEBSWAY_TEST_ANSWERS="$T/answers" bash "$P/update.sh" $ARGS 2>&1; }

ARGS='' out=$(upd y)
check "the package's copy: it says apt brings what is new" grep -q "installed here as the debsway package" <<<"$out"
check "...the first run takes what is set up as up to date, and runs nothing" bash -c 'grep -q "first run from the package" <<<"$1" && [ ! -s "$2" ]' _ "$out" "$T/ran"
check "...and keeps a record of every file, and pins.sh" bash -c '[ -s "$1/applied-files" ] && cmp "$1/applied-pins.sh" "$2/pins.sh"' _ "$T/state/debsway" "$P"
check "...without fetching or merging anything (no git here)" not grep -qi "Looking for a newer debsway\|fetch" <<<"$out"

# An upgrade: a command incognito installs, a pinned key sparrow uses, a new base part
upgrade sh -c 'echo "# changed" >>bin/incognito; sed -i "s/^\(SPARROW_FPR=.\)./\1X/" pins.sh
    printf "#!/bin/bash\n# status: bin:newpart\n" >parts/newpart.sh; sed -i "s/^PARTS=(/PARTS=(newpart /" packages.sh'
ARGS='' out=$(upd y)
check "after an upgrade: what uses a changed file runs again (incognito)" ran parts/incognito.sh
check "...what uses a changed pin (sparrow-wallet)" ran extras/sparrow-wallet.sh
check "...a base part that is new" ran parts/newpart.sh
check "...but not what didn't change (media, claude-code)" bash -c '! grep -qE "extras/(media|claude-code)\.sh" "$1"' _ "$T/ran"
ARGS='' out=$(upd y)
check "the next time, nothing (the record was brought up to date)" bash -c '[ ! -s "$1" ] && grep -q "Nothing to run again" <<<"$2"' _ "$T/ran" "$out"

# A script that fails is offered again next time
upgrade sh -c 'echo "# changed again" >>bin/incognito'
ARGS='' out=$(FAIL_ON="$P/parts/incognito.sh" upd y)
check "a script that fails: said" grep -q "did not finish" <<<"$out"
ARGS='' out=$(upd y)
check "...and offered again next time" ran parts/incognito.sh

# Saying no runs nothing, and keeps it for next time
upgrade sh -c 'echo "# and again" >>bin/incognito'
ARGS='' out=$(upd n)
check "saying no runs nothing" test ! -s "$T/ran"
ARGS='' out=$(upd y)
check "...and it is offered again next time" ran parts/incognito.sh

ARGS='--all' out=$(upd y)
check "--all offers everything set up" bash -c 'for s in parts/incognito.sh extras/claude-code.sh extras/media.sh extras/sparrow-wallet.sh; do grep -qxF "$2/$s" "$1" || exit 1; done' _ "$T/ran" "$P"
ARGS='--since HEAD' out=$(upd y)
check "--since is refused: the package's copy has no commits" grep -q "is for a git copy" <<<"$out"

[ "$fails" -eq 0 ]
