#!/bin/bash
# Brings Wren Linux up to date: fetches what is new, shows it, and (only if you
# say yes) merges it; then lists the parts and extras you have set up whose
# files changed and offers to run them again, one at a time. Running a script
# again is how a change gets installed (/usr/local, the firewall, Firefox's
# policy...), and it is safe: scripts repair, never remove.
#
# An extra Wren Linux retired (its "# retired:" line says why) is not run
# again: it asks whether to take each one you still have out with its own
# --remove, and Enter keeps it (it asks again next time). Apart from that it
# never runs --remove, never merges anything but a plain fast-forward (so it
# can't overwrite your own changes), and asks before each step.
#
# It remembers the commit it last brought you to (~/.local/state/wren/
# updated-to); a script is offered when a file it uses changed since then.
# The first time, it takes what you have now as already applied: for what you
# pulled earlier by hand, use --since COMMIT, or --all for everything set up.
#
# Once pins.sh names Wren Linux's signing key (WREN_SIGNING_FPR), it brings
# in only a newest commit with a good signature from that key.
#
# Each time, it also checks the signing keys of the apt repositories Wren Linux
# added (lib/apt-keys.sh), and fetches a pinned key again when it has expired
# or will soon.
#
# In the Wren Linux package's copy (/usr/share/wren: root's, no git) apt brings
# what is new; update.sh then finds what changed against a record of every
# file it keeps after each run, and offers those scripts in the same way.
#
# Usage: bash update.sh [--since COMMIT | --all]
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
. "$WREN_DIR/lib/update.sh"
# (its signature helpers check Wren Linux's own commits too: update_signed)
. "$WREN_DIR/lib/appimage.sh"
. "$WREN_DIR/lib/apt-keys.sh"
not_root

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/wren"
STATE="$STATE_DIR/updated-to"
# (a test replaces bash with something that only writes down what it was asked to run)
RUNNER=${WREN_UPDATE_RUNNER:-bash}

g() { git -C "$WREN_DIR" "$@"; }

main() {
    local since='' everything=false
    case "${1:-}" in
        --since) since=${2:-}; [ -n "$since" ] || die "Usage: bash update.sh [--since COMMIT | --all]" ;;
        --all) everything=true ;;
        "") ;;
        *) die "Usage: bash update.sh [--since COMMIT | --all]" ;;
    esac

    if ! g rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        [ ! -w "$WREN_DIR" ] ||
            die "$WREN_DIR isn't a git checkout yet (a copy from a stick or a download). Connect it to the published Wren Linux first: bash $WREN_DIR/git-helper.sh"
        # The Wren Linux package's copy: root's, no git. apt brings what is new;
        # this reruns what it changed
        [ -z "$since" ] || die "--since is for a git copy of Wren Linux; the package's has no commits."
        package_offers "$everything"
        run_offered
        return
    fi
    # A hooks folder that came in with the update would run as you
    [ -z "$(g config core.hooksPath)" ] ||
        die "core.hooksPath is set in $WREN_DIR; remove it first: git -C $WREN_DIR config --unset core.hooksPath"
    g rev-parse '@{upstream}' >/dev/null 2>&1 ||
        die "This copy of Wren Linux doesn't follow a branch on a server. Set one with: git -C $WREN_DIR branch --set-upstream-to=origin/main"

    say "Looking for a newer Wren Linux"
    g fetch --quiet || die "Couldn't reach the server (is the network up?)."

    local before upstream
    before=$(g rev-parse HEAD)
    upstream=$(g rev-parse '@{upstream}')
    if [ "$before" != "$upstream" ]; then
        if g merge-base --is-ancestor "$upstream" "$before"; then
            note "You are ahead of the server; nothing to bring in."
        elif ! g merge-base --is-ancestor "$before" "$upstream"; then
            die "Your copy and the server's have both changed, so it can't be brought in as a plain update. Look at: git -C $WREN_DIR status"
        else
            # (as plain text: what the server sends could steer the terminal otherwise)
            g --no-pager log --stat --format='%n%h %s%n%b' 'HEAD..@{upstream}' | printable
            echo
            note "Every changed line: git -C $WREN_DIR diff HEAD..@{upstream}"
            # Only what Wren Linux's own key signed (pins.sh), checked before the merge
            if [ -n "${WREN_SIGNING_FPR:-}" ]; then
                update_signed "$upstream" ||
                    die "The newest commit on the server isn't signed by Wren Linux's key ($WREN_SIGNING_FPR), so nothing was brought in. Someone may have changed what the server gives you: don't bring it in by hand either."
                note "The newest commit is signed by Wren Linux's key ($WREN_SIGNING_FPR); it vouches for everything above."
            else
                note "(Its signature is not checked: no signing key is pinned in pins.sh yet, so this is as the server gives it.)"
            fi
            ask "Bring these in?" n || { note "Nothing changed."; return 0; }
            g merge --ff-only --quiet "$upstream" ||
                die "Couldn't bring it in (your files in $WREN_DIR conflict with it?). Look at: git -C $WREN_DIR status"
        fi
    else
        note "Wren Linux is up to date with the server."
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

# retired_offers: retired extras are not run again (out of offered); those
# still set up here are offered for removal, each asked on its own, into removing
retired_offers() {
    local script why kept=()
    for script in "${offered[@]}"; do
        [ -n "$(update_retired "$script")" ] || kept+=("$script")
    done
    offered=("${kept[@]}")
    while IFS= read -r script; do
        [[ $script == extras/* ]] || continue
        why=$(update_retired "$script")
        [ -n "$why" ] && update_installed "$script" || continue
        say "Wren Linux retired ${script#extras/}"
        note "$why"
        if ask "Take it out now (bash $script --remove)?" n; then
            removing+=("$script")
        else
            note "Kept. It gets no more updates; update.sh asks again next time."
        fi
    done < <(update_scripts)
}

# run_offered: offers the scripts in offered, runs them one after the other if
# you say so (and the --remove of those in removing), and on success records
# that the setup is up to date (save_state)
run_offered() {
    local script declined=false
    retired_offers
    if [ ${#offered[@]} -eq 0 ] && [ ${#removing[@]} -eq 0 ]; then
        save_state "$now"
        say "Nothing to run again."
        return 0
    fi

    if [ ${#offered[@]} -gt 0 ]; then
        say "These are set up here and use files that changed:"
        for script in "${offered[@]}"; do note "$script"; done
        ask "Run them again now, one after the other?" y || {
            note "Left for next time: run  bash update.sh  again (or run them yourself: bash <script>)."
            offered=() declined=true
            [ ${#removing[@]} -gt 0 ] || return 0
        }
    fi
    # The password once, here: a wrong one stops everything before any script
    # runs (and does not move on to ask again for the next), and the permission
    # is kept fresh while they run so there is no second question part way.
    if ! sudo_keepalive; then
        warn "sudo didn't accept the password, so nothing was run."
        warn "Run  bash update.sh  again when you are ready; the new files are already in place."
        return 1
    fi

    local failed=()
    for script in "${removing[@]}"; do
        say "Taking out ${script#extras/}"
        if ! "$RUNNER" "$WREN_DIR/$script" --remove; then
            failed+=("$script --remove")
            warn "$script --remove did not finish."
        fi
    done
    for script in "${offered[@]}"; do
        say "Running $script"
        if ! "$RUNNER" "$WREN_DIR/$script"; then
            failed+=("$script")
            warn "$script did not finish."
        fi
    done
    if [ ${#failed[@]} -gt 0 ]; then
        warn "These failed: ${failed[*]}. Run one again with: bash <script>. (update.sh will offer them again.)"
        return 1
    fi
    # (what you left for next time is offered again then)
    $declined && return 0
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

# package_offers ALL: for the Wren Linux package's copy, which has no git: the
# scripts set up here whose files changed since the last run (the record
# save_state keeps), or all set up with ALL=true; into offered
package_offers() {
    local script
    note "Wren Linux is installed here as the Wren Linux package ($WREN_DIR): apt brings what is new"
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

offered=() removing=() now=
# Everything runs inside main: git may replace this very file while it runs
main "$@"
rc=$?
pause_if_asked
exit $rc
