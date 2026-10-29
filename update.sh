#!/bin/bash
# Brings debsway up to date: fetches what is new, shows it, and (only if you
# say yes) merges it; then lists the parts and extras you have set up whose
# files changed and offers to run them again, one at a time. Running a script
# again is how a change gets installed (/usr/local, the firewall, Firefox's
# policy...), and it is safe: scripts repair, never remove.
#
# It never runs --remove, never merges anything but a plain fast-forward
# (so it can't overwrite your own changes), and asks before each step.
#
# It remembers the commit it last brought you to (~/.local/state/debsway/
# updated-to); a script is offered when a file it uses changed since then.
# The first time, it takes what you have now as already applied: for what you
# pulled earlier by hand, use --since COMMIT, or --all for everything set up.
#
# Usage: bash update.sh [--since COMMIT | --all]
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
. "$DEBSWAY_DIR/lib/update.sh"
not_root

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/debsway"
STATE="$STATE_DIR/updated-to"
# (a test replaces bash with something that only writes down what it was asked to run)
RUNNER=${DEBSWAY_UPDATE_RUNNER:-bash}

g() { git -C "$DEBSWAY_DIR" "$@"; }

main() {
    local since='' everything=false
    case "${1:-}" in
        --since) since=${2:-}; [ -n "$since" ] || die "Usage: bash update.sh [--since COMMIT | --all]" ;;
        --all) everything=true ;;
        "") ;;
        *) die "Usage: bash update.sh [--since COMMIT | --all]" ;;
    esac

    g rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
        die "$DEBSWAY_DIR isn't a git checkout, so there is nothing to update from. Get debsway again with: git clone <its address>"
    # A hooks folder that came in with the update would run as you
    [ -z "$(g config core.hooksPath)" ] ||
        die "core.hooksPath is set in $DEBSWAY_DIR; remove it first: git -C $DEBSWAY_DIR config --unset core.hooksPath"
    g rev-parse '@{upstream}' >/dev/null 2>&1 ||
        die "This copy of debsway doesn't follow a branch on a server. Set one with: git -C $DEBSWAY_DIR branch --set-upstream-to=origin/main"

    say "Looking for a newer debsway"
    g fetch --quiet || die "Couldn't reach the server (is the network up?)."

    local before upstream
    before=$(g rev-parse HEAD)
    upstream=$(g rev-parse '@{upstream}')
    if [ "$before" != "$upstream" ]; then
        if g merge-base --is-ancestor "$upstream" "$before"; then
            note "You are ahead of the server; nothing to bring in."
        elif ! g merge-base --is-ancestor "$before" "$upstream"; then
            die "Your copy and the server's have both changed, so it can't be brought in as a plain update. Look at: git -C $DEBSWAY_DIR status"
        else
            g --no-pager log --stat --format='%n%C(yellow)%h%Creset %s%n%b' 'HEAD..@{upstream}'
            echo
            note "Every changed line: git -C $DEBSWAY_DIR diff HEAD..@{upstream}"
            # (a signature check on what comes in belongs here, before the merge)
            ask "Bring these in?" n || { note "Nothing changed."; return 0; }
            g merge --ff-only --quiet '@{upstream}' ||
                die "Couldn't bring it in (your files in $DEBSWAY_DIR conflict with it?). Look at: git -C $DEBSWAY_DIR status"
        fi
    else
        note "debsway is up to date with the server."
    fi
    local now
    now=$(g rev-parse HEAD)

    # Where this computer's setup was last brought up to
    local old=
    if [ -n "$since" ]; then
        old=$(g rev-parse --verify --quiet "$since^{commit}") || die "I don't know the commit \"$since\"."
    elif [ -r "$STATE" ] && g cat-file -e "$(cat "$STATE")^{commit}" 2>/dev/null; then
        old=$(cat "$STATE")
    else
        old=$before
    fi

    local script offered=() core
    if $everything; then
        while IFS= read -r script; do
            if update_installed "$script"; then offered+=("$script"); fi
        done < <(update_scripts)
    elif [ "$old" != "$now" ]; then
        while IFS= read -r script; do
            if update_installed "$script"; then offered+=("$script"); fi
        done < <(update_affected "$old" "$now")
        core=$(update_core_changes "$old" "$now" | paste -sd' ')
        if [ -n "$core" ]; then
            note "Shared files changed too ($core). They aren't counted against any one script;"
            note "if something looks off, run the script for it again, or: bash update.sh --all"
        fi
    fi

    if [ ${#offered[@]} -eq 0 ]; then
        save_state "$now"
        say "Nothing to run again."
        return 0
    fi

    say "These are set up here and use files that changed:"
    for script in "${offered[@]}"; do note "$script"; done
    ask "Run them again now, one after the other?" y || {
        note "Left for next time: run  bash update.sh  again (or run them yourself: bash <script>)."
        return 0
    }

    local failed=()
    for script in "${offered[@]}"; do
        say "Running $script"
        if ! "$RUNNER" "$DEBSWAY_DIR/$script"; then
            failed+=("$script")
            warn "$script did not finish."
        fi
    done
    if [ ${#failed[@]} -gt 0 ]; then
        warn "These failed: ${failed[*]}. Run one again with: bash <script>. (update.sh will offer them again.)"
        return 1
    fi
    save_state "$now"
    say "Up to date."
}

# save_state COMMIT: this computer's setup now matches COMMIT
save_state() {
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$1" >"$STATE"
}

# Everything runs inside main: git may replace this very file while it runs
main "$@"
exit $?
