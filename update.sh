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
# Once pins.sh names debsway's signing key (DEBSWAY_SIGNING_FPR), it brings
# in only a newest commit with a good signature from that key.
#
# Each time, it also checks the signing keys of the apt repositories debsway
# added (lib/apt-keys.sh), and fetches a pinned key again when it has expired
# or will soon.
#
# In the debsway package's copy (/usr/share/debsway: root's, no git) apt brings
# what is new; update.sh then finds what changed against a record of every
# file it keeps after each run, and offers those scripts in the same way.
#
# Usage: bash update.sh [--since COMMIT | --all]
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
. "$DEBSWAY_DIR/lib/update.sh"
# (its signature helpers check debsway's own commits too: update_signed)
. "$DEBSWAY_DIR/lib/appimage.sh"
. "$DEBSWAY_DIR/lib/apt-keys.sh"
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

    if ! g rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        [ ! -w "$DEBSWAY_DIR" ] ||
            die "$DEBSWAY_DIR isn't a git checkout, so there is nothing to update from. Get debsway again with: git clone <its address>"
        # The debsway package's copy: root's, no git. apt brings what is new;
        # this reruns what it changed
        [ -z "$since" ] || die "--since is for a git copy of debsway; the package's has no commits."
        package_offers "$everything"
        run_offered
        return
    fi
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
            # Only what debsway's own key signed (pins.sh), checked before the merge
            if [ -n "${DEBSWAY_SIGNING_FPR:-}" ]; then
                update_signed "$upstream" ||
                    die "The newest commit on the server isn't signed by debsway's key ($DEBSWAY_SIGNING_FPR), so nothing was brought in. Someone may have changed what the server gives you: don't bring it in by hand either."
                note "The newest commit is signed by debsway's key ($DEBSWAY_SIGNING_FPR); it vouches for everything above."
            else
                note "(Its signature is not checked: no signing key is pinned in pins.sh yet, so this is as the server gives it.)"
            fi
            ask "Bring these in?" n || { note "Nothing changed."; return 0; }
            g merge --ff-only --quiet '@{upstream}' ||
                die "Couldn't bring it in (your files in $DEBSWAY_DIR conflict with it?). Look at: git -C $DEBSWAY_DIR status"
        fi
    else
        note "debsway is up to date with the server."
    fi
    now=$(g rev-parse HEAD)

    # Signing keys that expire or are renewed (says nothing when all are fine)
    apt_keys_refresh || true

    # Where this computer's setup was last brought up to
    local old=
    if [ -n "$since" ]; then
        old=$(g rev-parse --verify --quiet "$since^{commit}") || die "I don't know the commit \"$since\"."
    elif [ -r "$STATE" ] && g cat-file -e "$(cat "$STATE")^{commit}" 2>/dev/null; then
        old=$(cat "$STATE")
    else
        old=$before
    fi

    local script core
    if $everything; then
        while IFS= read -r script; do
            if update_installed "$script"; then offered+=("$script"); fi
        done < <(update_scripts)
    elif [ "$old" != "$now" ]; then
        while IFS= read -r script; do
            if update_installed "$script"; then offered+=("$script"); fi
        done < <(update_affected "$old" "$now")
        # a base part that is new in this update (it can't be "set up" yet)
        while IFS= read -r script; do
            case " ${offered[*]} " in *" $script "*) ;; *) offered+=("$script") ;; esac
        done < <(update_new_parts "$old" "$now")
        core=$(update_core_changes "$old" "$now" | paste -sd' ')
        if [ -n "$core" ]; then
            note "Shared files changed too ($core). They aren't counted against any one script;"
            note "if something looks off, run the script for it again, or: bash update.sh --all"
        fi
    fi

    # and those whose installed commands are older than this copy
    if ! $everything; then
        while IFS= read -r script; do
            case " ${offered[*]} " in *" $script "*) ;; *) offered+=("$script") ;; esac
        done < <(update_stale)
    fi

    run_offered
}

# run_offered: offers the scripts in offered, runs them one after the other if
# you say so, and on success records that the setup is up to date (save_state)
run_offered() {
    local script
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
    # The password once, here: a wrong one stops everything before any script
    # runs (and does not move on to ask again for the next), and the permission
    # is kept fresh while they run so there is no second question part way.
    if ! sudo_keepalive; then
        warn "sudo didn't accept the password, so nothing was run."
        warn "Run  bash update.sh  again when you are ready; the new files are already in place."
        return 1
    fi

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

# save_state [COMMIT]: this computer's setup now matches COMMIT (a git copy),
# and every file as it is now (the record a package's copy is compared with)
save_state() {
    mkdir -p "$STATE_DIR"
    [ -z "${1:-}" ] || printf '%s\n' "$1" >"$STATE"
    update_manifest_save "$STATE_DIR"
}

# package_offers ALL: for the debsway package's copy, which has no git: the
# scripts set up here whose files changed since the last run (the record
# save_state keeps), or all set up with ALL=true; into offered
package_offers() {
    local script
    note "debsway is installed here as the debsway package ($DEBSWAY_DIR): apt brings what is new"
    note "(unattended-upgrades every day, or: sudo apt update && sudo apt upgrade). This runs again what it changed."
    apt_keys_refresh || true
    if $1; then
        while IFS= read -r script; do
            if update_installed "$script"; then offered+=("$script"); fi
        done < <(update_scripts)
        return 0
    fi
    if [ -r "$STATE_DIR/applied-files" ] && [ -r "$STATE_DIR/applied-pins.sh" ]; then
        while IFS= read -r script; do
            if update_installed "$script"; then offered+=("$script"); fi
        done < <(update_affected_by "$(update_manifest_changed "$STATE_DIR")" "$(update_manifest_pin_vars "$STATE_DIR")")
        while IFS= read -r script; do
            case " ${offered[*]} " in *" $script "*) ;; *) offered+=("$script") ;; esac
        done < <(update_manifest_new_parts "$STATE_DIR")
    else
        note "The first run from the package: what is set up now counts as up to date (bash update.sh --all offers all of it)."
    fi
    while IFS= read -r script; do
        case " ${offered[*]} " in *" $script "*) ;; *) offered+=("$script") ;; esac
    done < <(update_stale)
}

offered=() now=
# Everything runs inside main: git may replace this very file while it runs
main "$@"
rc=$?
pause_if_asked
exit $rc
