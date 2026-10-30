#!/bin/bash
# Checks update.sh and lib/update.sh with a pretend server and a pretend
# "your copy", both made here from the real files, and a runner that only
# writes down which scripts it was asked to run. Changes nothing outside a
# temp folder. Run by test.sh, or:  bash tools/test-update.sh
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
ran() { grep -qxF "$T/L/$1" "$T/ran"; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export HOME="$T/home" XDG_STATE_HOME="$T/state"
mkdir -p "$HOME"

# The server's working copy W (this checkout's files), the server O, your copy L
mkdir "$T/W"
(cd "$HERE" && git ls-files -co --exclude-standard | tar -cf - -T -) | tar -C "$T/W" -xf -
git -C "$T/W" init -q -b main && git -C "$T/W" add -A && git -C "$T/W" commit -q -m first
git clone -q --bare "$T/W" "$T/O.git"
git clone -q "$T/O.git" "$T/L"
git -C "$T/W" remote add origin "$T/O.git"
FIRST=$(git -C "$T/L" rev-parse HEAD)

# A change on the server: an installed file, a firewall file, a shared library
# of some extras, a pinned fingerprint, and a core library
echo '# changed' >>"$T/W/bin/incognito"
echo '# changed' >>"$T/W/data/claude-firewall.nft"
echo '# changed' >>"$T/W/data/claude-vm-firewall.nft"
echo '# changed' >>"$T/W/lib/appimage.sh"
echo '# changed' >>"$T/W/lib/core.sh"
sed -i 's/^\(SPARROW_FPR=.\)./\1X/' "$T/W/pins.sh"
# a new base part (in the PARTS list) and a new part that isn't one
printf '#!/bin/bash\n# status: bin:newpart\n' >"$T/W/parts/newpart.sh"
printf '#!/bin/bash\n# status: bin:otherpart\n' >"$T/W/parts/otherpart.sh"
sed -i 's/^PARTS=(/PARTS=(newpart /' "$T/W/packages.sh"
git -C "$T/W" add -A
git -C "$T/W" commit -q -am second && git -C "$T/W" push -q origin main
SECOND=$(git -C "$T/W" rev-parse HEAD)

# A runner that writes down what it was asked to run (and fails on request)
# shellcheck disable=SC2016  # written into the runner, expanded when it runs
printf '#!/bin/bash\necho "$1" >>"%s/ran"\n[ "$1" != "$FAIL_ON" ]\n' "$T" >"$T/runner"
chmod +x "$T/runner"
export DEBSWAY_UPDATE_RUNNER="$T/runner"
# A pretend sudo: -v succeeds (or fails with FAKE_SUDO_RC); every call is written down
# shellcheck disable=SC2016  # written into the pretend program, expanded when it runs
printf '#!/bin/bash\necho "sudo $*" >>"%s/sudolog"\n[ "$1" = -v ] && exit "${FAKE_SUDO_RC:-0}"\nexit 0\n' "$T" >"$T/sudo"
chmod +x "$T/sudo"
export DEBSWAY_SUDO="$T/sudo"
# What is "set up here": incognito, claude-code (not claude-vm), media (not changed),
# and two that use the changed library or pin
export DEBSWAY_UPDATE_ASSUME_INSTALLED="parts/incognito.sh extras/claude-code.sh extras/media.sh extras/feather-wallet.sh extras/sparrow-wallet.sh"
upd() { # ANSWERS... then the arguments of update.sh in $ARGS
    printf '%s\n' "$@" >"$T/answers"
    # shellcheck disable=SC2086
    DEBSWAY_TEST_ANSWERS="$T/answers" bash "$T/L/update.sh" $ARGS 2>&1
}

# 1. saying no brings nothing in
: >"$T/ran"
ARGS='' out=$(upd n)
check "saying no to the update changes nothing" test "$(git -C "$T/L" rev-parse HEAD)" = "$FIRST"
check "...and runs nothing" test ! -s "$T/ran"

# 2. saying yes merges, and offers the scripts that use what changed
ARGS='' out=$(upd y y)
check "the update is brought in" test "$(git -C "$T/L" rev-parse HEAD)" = "$SECOND"
check "a changed bin/ file reruns the script that installs it" ran parts/incognito.sh
check "a changed data/ file reruns the script that uses it" ran extras/claude-code.sh
check "a changed library reruns the scripts that source it" ran extras/feather-wallet.sh
check "a changed pin reruns the script that uses it" ran extras/sparrow-wallet.sh
check "a base part that is new is offered although it isn't set up yet" ran parts/newpart.sh
check "a new part outside the base list is not" not ran parts/otherpart.sh
check "an installed script whose files didn't change is left alone" not ran extras/media.sh
check "a changed script that isn't set up here is left alone" not ran extras/claude-vm.sh
check "a changed core library is reported, not counted against every script" grep -q 'lib/core.sh' <<<"$out"
check "the commit it brought you to is remembered" test "$(cat "$T/state/debsway/updated-to")" = "$SECOND"

# 2b. the sudo password is asked once, before the first script, not by each script
check "sudo is asked for once, before any script runs" test "$(grep -c '^sudo -v' "$T/sudolog")" -eq 1
check "...and kept fresh in the background while they run" grep -q '^sudo -n true' "$T/sudolog"

# 3. nothing new: nothing to run
: >"$T/ran"
ARGS='' out=$(upd)
check "a second run finds nothing to do" test ! -s "$T/ran"

# 4. --since offers again what changed after a commit
ARGS="--since $FIRST" out=$(upd y)
check "--since runs again what changed after that commit" ran parts/incognito.sh

# 5. --all offers everything that is set up
: >"$T/ran"
ARGS=--all out=$(upd y)
check "--all runs everything that is set up" test "$(wc -l <"$T/ran")" -eq 5
check "--all still leaves out what isn't set up" not ran extras/claude-vm.sh

# 6. a script that fails: reported, and the commit is not remembered
rm -f "$T/state/debsway/updated-to"
: >"$T/ran"
FAIL_ON="$T/L/parts/incognito.sh"
export FAIL_ON
ARGS="--since $FIRST" out=$(upd y)
check "a failing script is reported" grep -q 'did not finish' <<<"$out"
check "the other scripts still run" ran extras/claude-code.sh
check "a failed run is not remembered as done" test ! -e "$T/state/debsway/updated-to"
unset FAIL_ON

# 6b. a wrong sudo password stops everything: no script runs, the next one is not tried
rm -f "$T/state/debsway/updated-to"
: >"$T/ran"; : >"$T/sudolog"
printf 'y\n' >"$T/answers"
bad=$(FAKE_SUDO_RC=1 DEBSWAY_TEST_ANSWERS="$T/answers" bash "$T/L/update.sh" --since "$FIRST" 2>&1; echo "rc=$?")
check "a refused sudo password runs no script at all" test ! -s "$T/ran"
check "...says so, in plain words" grep -q "sudo didn't accept the password, so nothing was run" <<<"$bad"
check "...fails, so it is not mistaken for success" not grep -qx 'rc=0' <<<"$bad"
check "...asks only once (it does not go on to the next script and ask again)" test "$(grep -c '^sudo -v' "$T/sudolog")" -eq 1
check "...and does not record the update as done" test ! -e "$T/state/debsway/updated-to"

# 7. a plain-git problem: your own commit on top
echo mine >"$T/L/mine.txt"
git -C "$T/L" add mine.txt && git -C "$T/L" commit -q -m mine
echo '# more' >>"$T/W/bin/media-sandbox"
git -C "$T/W" commit -q -am third && git -C "$T/W" push -q origin main
ARGS='' out=$(upd y y)
check "your own commits stop a plain update, with a message" grep -q 'both changed' <<<"$out"

# Every command a script installs is one of its files: a script that installs
# them from a list (install_bin "$c") must name them on its "# files:" line, or
# update.sh never puts in a newer one when only that command changed (timer and
# the bar, installed by parts/core-commands.sh, were missed that way)
# shellcheck disable=SC2016  # the inner shell expands its own variables
missing=$(cd "$HERE" && bash -c '. ./lib.sh; . lib/update.sh
    for s in parts/*.sh extras/*.sh; do
        grep -qF "install_bin \"\$" "$s" || continue
        names=$(sed -n "s/^COMMANDS=(\(.*\))\$/\1/p" "$s")
        [ -n "$names" ] || { echo "$s: installs a command named by a variable, and has no COMMANDS=(...) to check"; continue; }
        # (the list first: grep -q stops reading early, which pipefail counts as a failure)
        inputs=$(update_inputs "$s")
        for n in $names; do grep -qx "bin/$n" <<<"$inputs" || echo "$s: bin/$n"; done
    done' 2>&1)
check "update.sh sees every command a script installs from a list${missing:+ (missing: $(paste -sd' ' <<<"$missing"))}" test -z "$missing"

[ "$fails" -eq 0 ]
