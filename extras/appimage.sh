# shellcheck shell=bash
# appimage.sh: helpers for the AppImage extras, sourced after lib.sh.
# Downloads are checked against a signed list of SHA-256 sums from a key
# whose fingerprint is pinned in each script. AppImages are unpacked into
# ~/.local/opt/NAME and run from there, so FUSE isn't needed.

OPT="$HOME/.local/opt"
BIN="$HOME/.local/bin"

latest_github_tag() {
    wget -qO- "https://api.github.com/repos/$1/releases/latest" |
        sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1
}

installed_version() { cat "$OPT/$1/.debsway-version" 2>/dev/null || true; }

# A throwaway keyring holding only the key at URL (or in a local file),
# checked to be FPR
_keyring() {
    local fpr=$1 url=$2 home
    home=$(mktemp -d)
    chmod 700 "$home"
    if [ -f "$url" ]; then
        cp "$url" "$home/key.asc"
    elif ! wget -qO "$home/key.asc" "$url"; then
        rm -rf "$home"
        warn "Couldn't download the signing key from $url"
        return 1
    fi
    gpg --homedir "$home" --batch --quiet --import "$home/key.asc" 2>/dev/null || true
    if ! gpg --homedir "$home" --batch --list-keys "$fpr" >/dev/null 2>&1; then
        _keyring_done "$home"
        warn "The key at $url isn't $fpr. Not trusting it."
        return 1
    fi
    echo "$home"
}

_keyring_done() {
    gpgconf --homedir "$1" --kill all 2>/dev/null || true
    rm -rf "$1"
}

# A good signature whose primary key is FPR, in gpg's --status-fd output.
# -a: notations (e.g. Sequoia's salt) can put raw bytes in that output
_good_sig() { grep -aq "^\[GNUPG:\] VALIDSIG .* $1\$" "$2"; }

# verify_detached FPR KEY_URL SIG DATA
verify_detached() {
    local home rc=0
    home=$(_keyring "$1" "$2") || return 1
    gpg --homedir "$home" --batch --status-file "$home/status" --verify "$3" "$4" 2>/dev/null || true
    _good_sig "$1" "$home/status" || rc=1
    _keyring_done "$home"
    return "$rc"
}

# verify_clearsigned FPR KEY_URL FILE OUT: OUT gets only the signed text
verify_clearsigned() {
    local home rc=0
    home=$(_keyring "$1" "$2") || return 1
    gpg --homedir "$home" --batch --status-file "$home/status" --output "$4" --yes \
        --decrypt "$3" 2>/dev/null || true
    _good_sig "$1" "$home/status" || rc=1
    _keyring_done "$home"
    return "$rc"
}

# check_sha256 SUMS_FILE NAME FILE: FILE's hash must match NAME's line
check_sha256() {
    local want
    want=$(awk -v n="$2" '$2 == n || $2 == "*" n { print $1; exit }' "$1")
    [ -n "$want" ] || { warn "No checksum for $2 in the signed list."; return 1; }
    echo "$want  $3" | sha256sum -c --quiet - >/dev/null 2>&1 ||
        { warn "Checksum mismatch for $2."; return 1; }
}

# install_appimage NAME FILE VERSION: unpack FILE into ~/.local/opt/NAME
install_appimage() {
    local name=$1 file=$2 version=$3 dest="$OPT/$1" work
    mkdir -p "$OPT"
    work=$(mktemp -d "$OPT/.unpack.XXXXXX")
    chmod +x "$file"
    if ! (cd "$work" && "$file" --appimage-extract >/dev/null) ||
        [ ! -x "$work/squashfs-root/AppRun" ]; then
        rm -rf "$work"
        die "Couldn't unpack $file."
    fi
    echo "$version" >"$work/squashfs-root/.debsway-version"
    rm -rf "$dest.old"
    if [ -d "$dest" ]; then mv "$dest" "$dest.old"; fi
    mv "$work/squashfs-root" "$dest"
    rm -rf "$dest.old" "$work"
    note "Unpacked $name $version into $dest"
}

# write_launcher NAME SCRIPT_NAME TARGET [VAR=VALUE...]: ~/.local/bin/NAME
# runs ~/.local/opt/NAME/TARGET. APPDIR is set because start scripts
# written for the AppImage runtime expect it.
write_launcher() {
    local name=$1 by=$2 target=$3
    shift 3
    mkdir -p "$BIN"
    cat >"$BIN/$name" <<EOF
#!/bin/sh
# $name: written by debsway extras/$by
dir="\$HOME/.local/opt/$name"
exec env APPDIR="\$dir" $* "\$dir/$target" "\$@"
EOF
    chmod +x "$BIN/$name"
    note "Run it with: $name   (or Super+d)"
}

remove_appimage() {
    local name=$1
    rm -rf "${OPT:?}/$name"
    if grep -qs 'written by debsway extras/' "$BIN/$name"; then rm -f "$BIN/$name"; fi
    note "Removed $OPT/$name and $BIN/$name"
}
