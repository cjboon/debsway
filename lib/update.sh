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

# update_signed COMMIT: COMMIT carries a good signature from debsway's own key,
# DEBSWAY_SIGNING_FPR (pins.sh), taken from this copy's
# data/debsway-signing-key.asc: never from what is coming in, so a change can't
# bring its own key. Only that one key goes into the throwaway keyring
# (_keyring, lib/appimage.sh), so a second key slipped into the file doesn't
# count, and an expired or revoked key's signature fails (_good_sig). gpg is run
# as gpg whatever your git config's gpg.program says. Needs lib/appimage.sh.
update_signed() {
    local home rc=0 key=$DEBSWAY_DIR/data/debsway-signing-key.asc
    [ -f "$key" ] || { warn "pins.sh names debsway's key, but $key is missing."; return 1; }
    home=$(_keyring "$DEBSWAY_SIGNING_FPR" "$key") || return 1
    GNUPGHOME=$home git -C "$DEBSWAY_DIR" -c gpg.format=openpgp -c gpg.program=gpg -c gpg.openpgp.program=gpg \
        verify-commit --raw "$1" >/dev/null 2>"$home/status" || true
    _good_sig "$DEBSWAY_SIGNING_FPR" "$home/status" || rc=1
    _keyring_done "$home"
    return "$rc"
}

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

# update_stale: the scripts set up here one of whose commands in ~/.local/bin
# (install_bin) is debsway's but not this copy's: brought in by hand before
# update.sh first ran (it takes what is there then as done), or a run that
# was cut short. Offered whatever changed upstream, so no fix is left behind.
update_stale() {
    local script name
    while IFS= read -r script; do
        update_installed "$script" || continue
        while IFS= read -r name; do
            if grep -qis 'written by debsway' "$BIN/$name" && ! cmp -s "$DEBSWAY_DIR/bin/$name" "$BIN/$name"; then
                echo "$script"
                break
            fi
        done < <(sed -n 's/^[[:space:]]*install_bin[[:space:]][[:space:]]*\([A-Za-z0-9._-][A-Za-z0-9._-]*\).*/\1/p' "$DEBSWAY_DIR/$script")
    done < <(update_scripts)
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
    update_affected_by "$(git -C "$DEBSWAY_DIR" diff --name-only "$1" "$2" --)" "$(update_pin_vars "$1" "$2")"
}

# update_affected_by CHANGED VARS: the same, from a list of changed files and
# of changed pins.sh names (one per line each), however they were found: git
# for a checkout, the record of the last run for the package (update_manifest)
update_affected_by() {
    local changed=$1 vars=$2 script
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

# The debsway package's copy has no git: what changed is found by comparing it
# with a record of every file, kept when the setup was last brought up to date
# (update_manifest_save), and a copy of pins.sh from then.
# update_manifest: "SHA-256  path" for every file of this copy, sorted
update_manifest() {
    (cd "$DEBSWAY_DIR" && find . -path ./.git -prune -o -path ./offline -prune -o -path ./ignore -prune -o -type f -print0 |
        sort -z | xargs -0 -r sha256sum | sed 's|  \./|  |')
}
# update_manifest_save DIR: the record, and pins.sh as it is, into DIR
update_manifest_save() {
    mkdir -p "$1"
    update_manifest >"$1/applied-files"
    # (install, not cp: a new file of yours, whatever the mode of the original)
    install -m 0644 "$DEBSWAY_DIR/pins.sh" "$1/applied-pins.sh"
}
# update_manifest_changed DIR: the files that differ from the record in DIR
# (changed, new or gone), one per line
update_manifest_changed() {
    diff <(cat "$1/applied-files") <(update_manifest) | sed -n 's/^[<>] [0-9a-f]\{64\}  //p' | sort -u
}
# update_manifest_pin_vars DIR: the names in pins.sh whose lines changed since
update_manifest_pin_vars() {
    diff "$1/applied-pins.sh" "$DEBSWAY_DIR/pins.sh" | sed -n 's/^[<>] \([A-Z][A-Z0-9_]*\)=.*/\1/p' | sort -u
}
# update_manifest_new_parts DIR: base parts (PARTS) that weren't there then
update_manifest_new_parts() {
    local f p
    # shellcheck disable=SC1091  # PARTS is the list in packages.sh
    . "$DEBSWAY_DIR/packages.sh"
    while IFS= read -r f; do
        p=${f#parts/}
        p=${p%.sh}
        case " ${PARTS[*]} " in *" $p "*) echo "$f" ;; esac
    done < <(comm -13 <(sed 's/^[0-9a-f]\{64\}  //' "$1/applied-files" | sort) <(update_manifest | sed 's/^[0-9a-f]\{64\}  //' | sort) | grep '^parts/[^/]*\.sh$')
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
