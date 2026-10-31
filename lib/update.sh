# shellcheck shell=bash
# lib/update.sh: what update.sh needs to decide which scripts to run again
# after debsway changes. Sourced by update.sh after lib.sh.
#
# A part or extra is "affected" by a change when a file it installs or reads
# changed: the script itself, the bin/, data/ and vendor/ files it names, the
# lib/ files it sources by choice, a line of pins.sh that it uses, and the
# files in its "# files:" header line (for what a library function installs for
# it). The core libraries that lib.sh always loads (lib/core.sh and the rest)
# are not counted: nearly everything uses them, so a change there is only
# reported, and you decide.

UPDATE_CORE_FILES="lib.sh lib/core.sh lib/apt.sh lib/sway.sh lib/net.sh lib/tor.sh lib/mime.sh lib/update.sh packages.sh install-base.sh install-extras.sh update.sh"

# update_inputs SCRIPT: the repo files SCRIPT (parts/X.sh or extras/X.sh)
# installs or reads, one per line, itself included.
update_inputs() {
    local script=$1 path="$DEBSWAY_DIR/$1" f
    {
        echo "$script"
        # "$DEBSWAY_DIR/bin/NAME", .../data/NAME, .../vendor/DIR/NAME, .../lib/NAME.sh
        # (paths like /usr/local/bin/NAME are where things are installed, not repo files)
        grep -oE 'DEBSWAY_DIR[}"]*/(bin|data|vendor|lib)/[A-Za-z0-9._/-]+' "$path" |
            sed 's|^DEBSWAY_DIR[}"]*/||; s/[./-]*$//'
        # install_bin NAME puts bin/NAME in place
        sed -n 's/^[[:space:]]*install_bin[[:space:]][[:space:]]*\([A-Za-z0-9._-][A-Za-z0-9._-]*\).*/bin\/\1/p' "$path"
        # "# files: bin/x data/y" says what a library function installs for it
        sed -n 's/^# files: //p' "$path" | tr ' ' '\n'
    } | sort -u | while IFS= read -r f; do
        [ -f "$DEBSWAY_DIR/$f" ] || continue
        case " $UPDATE_CORE_FILES " in *" $f "*) continue ;; esac
        echo "$f"
    done
}

# update_scripts: every part, then every extra, as parts/X.sh and extras/X.sh,
# in the order they are meant to run
update_scripts() {
    local p f
    # shellcheck disable=SC1091  # PARTS is the list in packages.sh
    . "$DEBSWAY_DIR/packages.sh"
    for p in "${PARTS[@]}"; do
        [ -f "$DEBSWAY_DIR/parts/$p.sh" ] && echo "parts/$p.sh"
    done
    # the parts that aren't in the base list (incognito, firefox-hardening...)
    for f in "$DEBSWAY_DIR"/parts/*.sh; do
        p=${f##*/}
        case " ${PARTS[*]} " in *" ${p%.sh} "*) continue ;; esac
        echo "parts/$p"
    done
    for f in "$DEBSWAY_DIR"/extras/*.sh; do
        [ -f "$f" ] && echo "extras/${f##*/}"
    done
}

# update_installed SCRIPT: succeeds if SCRIPT is set up on this computer
# (the "# status:" line). DEBSWAY_UPDATE_ASSUME_INSTALLED, a list of scripts,
# stands in for that in tests.
update_installed() {
    if [ -n "${DEBSWAY_UPDATE_ASSUME_INSTALLED+x}" ]; then
        case " $DEBSWAY_UPDATE_ASSUME_INSTALLED " in *" $1 "*) return 0 ;; esac
        return 1
    fi
    [ -n "$(script_found "$DEBSWAY_DIR/$1")" ]
}

# update_pin_vars OLD NEW: the names in pins.sh whose lines changed
update_pin_vars() {
    git -C "$DEBSWAY_DIR" diff -U0 "$1" "$2" -- pins.sh 2>/dev/null |
        sed -n 's/^[+-]\([A-Z][A-Z0-9_]*\)=.*/\1/p' | sort -u
}

# update_affected OLD NEW: the scripts (all, installed or not) that the change
# from commit OLD to commit NEW touches, in running order
update_affected() {
    local old=$1 new=$2 changed vars script
    changed=$(git -C "$DEBSWAY_DIR" diff --name-only "$old" "$new" --)
    vars=$(update_pin_vars "$old" "$new")
    local inputs=()
    while IFS= read -r script; do
        mapfile -t inputs < <(update_inputs "$script")
        if [ -n "$(comm -12 <(printf '%s\n' "${inputs[@]}") <(sort <<<"$changed"))" ]; then
            echo "$script"
            continue
        fi
        # a pin used by the script, or by a library it sources
        if [ -n "$vars" ] && (cd "$DEBSWAY_DIR" && grep -qwFf <(echo "$vars") -- "${inputs[@]}"); then
            echo "$script"
        fi
    done < <(update_scripts)
}

# update_new_parts OLD NEW: parts of the base desktop (the PARTS list in
# packages.sh) that are new between OLD and NEW. They aren't set up yet, so
# the "is it installed" test can't find them, but a base part is meant to be
# there.
update_new_parts() {
    local f p
    # shellcheck disable=SC1091  # PARTS is the list in packages.sh
    . "$DEBSWAY_DIR/packages.sh"
    while IFS= read -r f; do
        p=${f#parts/}
        p=${p%.sh}
        case " ${PARTS[*]} " in *" $p "*) echo "$f" ;; esac
    done < <(git -C "$DEBSWAY_DIR" diff --name-only --diff-filter=A "$1" "$2" -- 'parts/*.sh')
}

# update_core_changes OLD NEW: the shared files (lib/, install-base.sh...)
# that changed, one per line
update_core_changes() {
    local f
    for f in $UPDATE_CORE_FILES; do
        git -C "$DEBSWAY_DIR" diff --quiet "$1" "$2" -- "$f" 2>/dev/null || echo "$f"
    done
}
