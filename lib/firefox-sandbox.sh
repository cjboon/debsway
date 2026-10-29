# shellcheck shell=bash
# lib/firefox-sandbox.sh: the locked-down users the sandboxed Firefox runs as.
# Sourced after lib.sh by extras/firefox-sandbox.sh (the user "firefox") and
# extras/firefox-profiles/new-profile.sh (one user "fx-NAME" per profile).
# All of them share one system group, so one firewall rule covers every one of
# them and a new profile never has to touch the firewall.

FX_GROUP=debsway-fx
FX_PROFILE_DIR=/etc/debsway/firefox-profiles
FX_HOME_ROOT=/var/lib/debsway-fx
# (the two paths can be pointed elsewhere by a test)
FX_SESSION=${DEBSWAY_FX_SESSION:-/usr/local/libexec/firefox-session}
FX_CLIENT=${DEBSWAY_FX_CLIENT:-/usr/local/bin/firefox}

# fx_profile_name_ok NAME: a name that makes a valid user, fx-NAME (at most 31 characters)
fx_profile_name_ok() { [[ $1 =~ ^[a-z][a-z0-9-]{0,27}$ ]]; }

fx_ensure_group() {
    getent group "$FX_GROUP" >/dev/null || sudo groupadd --system "$FX_GROUP"
}

# fx_create_user USER HOME COMMENT: a system user in the shared group with no
# password, no login shell and a home only it can enter. Run again, it fixes
# the group and the permissions of an existing one.
fx_create_user() {
    local user=$1 home=$2 comment=$3
    fx_ensure_group
    if id "$user" >/dev/null 2>&1; then
        [ "$(id -u "$user")" -lt 1000 ] ||
            die "A regular user account called $user already exists; this needs a system user. Rename or remove it first."
        sudo usermod -g "$FX_GROUP" "$user"
    else
        sudo mkdir -p "${home%/*}"
        sudo useradd --system --gid "$FX_GROUP" --create-home --home-dir "$home" \
            --shell /usr/sbin/nologin --comment "$comment" "$user"
    fi
    sudo usermod --lock --shell /usr/sbin/nologin "$user"
    sudo chmod 0700 "$home"
    # Firefox opens the GPU's render node (software rendering is forced; this
    # is only so it can start). render, not video: no modesetting.
    if getent group render >/dev/null; then sudo usermod -aG render "$user"; fi
}

# fx_allow_session USER: your user may run the session script as USER and
# nothing else. The sudoers file is checked with visudo first: a broken one
# would lock you out of sudo.
fx_allow_session() {
    local user=$1 rule
    rule=$(mktemp)
    printf '# Written by debsway (sandboxed Firefox). %s may run the firefox session script,\n# and nothing else, as the user %s.\n%s ALL=(%s) NOPASSWD: %s\n' \
        "$(id -un)" "$user" "$(id -un)" "$user" "$FX_SESSION" >"$rule"
    if ! sudo visudo -cf "$rule" >/dev/null; then
        rm -f "$rule"
        die "The sudoers rule didn't pass visudo's check, so it wasn't installed."
    fi
    sudo install -o root -g root -m 0440 "$rule" "/etc/sudoers.d/debsway-$user"
    rm -f "$rule"
}

fx_disallow_session() { sudo rm -f "/etc/sudoers.d/debsway-$1"; }

# fx_profile_names: the profiles that have a user, one per line
fx_profile_names() {
    local f
    for f in "$FX_PROFILE_DIR"/*.conf; do
        [ -f "$f" ] || continue
        f=${f##*/}
        echo "${f%.conf}"
    done
}
