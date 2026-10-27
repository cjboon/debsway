# shellcheck shell=bash
# lib.sh: shared helpers, sourced by every debsway script.
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

DEBSWAY_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# Signing keys and versions debsway trusts, each with the date it was checked
. "$DEBSWAY_DIR/pins.sh"
SWAY_CONFIG="$HOME/.config/sway/config"
SWAY_SNIPPETS="$HOME/.config/sway/config.d"
SWAY_INCLUDE="include $SWAY_SNIPPETS/*.conf"

if [ "$(id -u)" -eq 0 ]; then SUDO=; else SUDO=sudo; fi

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# tty_read VAR "Prompt": reads a line from the terminal into VAR, or
# leaves it empty when there is no terminal. The prompt goes to stderr,
# so only the check for a terminal is silenced, never the prompt.
tty_read() {
    local _line=
    if { : </dev/tty; } 2>/dev/null; then
        IFS= read -r -p "$2" _line </dev/tty || _line=
    fi
    printf -v "$1" '%s' "$_line"
}

# ask "Question?" [y|n]: default answer is the second argument
ask() {
    local reply def=${2:-n} hint='[y/N]'
    [ "$def" = y ] && hint='[Y/n]'
    tty_read reply "$1 $hint "
    [[ ${reply:-$def} =~ ^[Yy] ]]
}

# For scripts that only touch your home folder
not_root() {
    [ "$(id -u)" -ne 0 ] || die "Run this as your normal user, not root."
}

# Desktop scripts run as the normal user and use sudo for system changes
need_user() {
    [ "$(id -u)" -ne 0 ] ||
        die "Run this as your normal user, not root. It uses sudo when it needs to."
    command -v sudo >/dev/null ||
        die "sudo isn't installed. Log in as root and run: bash $DEBSWAY_DIR/setup-sudo.sh $(id -un)"
    sudo -v ||
        die "Your user can't use sudo. Log in as root and run: bash $DEBSWAY_DIR/setup-sudo.sh $(id -un)"
}

is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

have_internet() { getent hosts deb.debian.org >/dev/null 2>&1; }

# Exported, so parts run from install-base.sh don't update apt again
apt_install() {
    have_internet || die "No internet connection. Connect first: bash $DEBSWAY_DIR/wifi.sh"
    if [ -z "${DEBSWAY_APT_UPDATED:-}" ]; then
        $SUDO apt-get update
        export DEBSWAY_APT_UPDATED=1
    fi
    $SUDO apt-get install -y --no-install-recommends "$@"
}

apt_purge() {
    local p pkgs=()
    for p in "$@"; do
        if is_installed "$p"; then pkgs+=("$p"); fi
    done
    if [ ${#pkgs[@]} -gt 0 ]; then
        $SUDO apt-get purge -y "${pkgs[@]}"
        $SUDO apt-get autoremove --purge -y
    fi
}

# Some apps only speak X11. sway runs them through XWayland, but only
# finds XWayland when sway starts, so a fresh install needs a re-login.
need_xwayland() {
    is_installed xwayland && return 0
    apt_install xwayland
    warn "Installed XWayland. Log out and back in once so sway can use it."
}

# The user's sway config is the stock /etc/sway/config plus one include
# line, so each parts/ script can add or remove its own snippet file.
ensure_sway_config() {
    [ -f /etc/sway/config ] || die "sway isn't installed. Run install-base.sh first."
    mkdir -p "$SWAY_SNIPPETS"
    [ -f "$SWAY_CONFIG" ] || cp /etc/sway/config "$SWAY_CONFIG"
    if ! grep -qxF "$SWAY_INCLUDE" "$SWAY_CONFIG"; then
        printf '\n# debsway feature snippets\n%s\n' "$SWAY_INCLUDE" >>"$SWAY_CONFIG"
    fi
}

# sway -C exits 0 even on errors, so look for them in its output
check_sway_config() {
    local out
    out=$(sway -C -c "$SWAY_CONFIG" 2>&1 || true)
    if grep -q '\[ERROR\]' <<<"$out"; then
        grep '\[ERROR\]' <<<"$out" >&2
        return 1
    fi
}

reload_sway() {
    if [ -n "${SWAYSOCK:-}" ] && swaymsg reload >/dev/null 2>&1; then
        note "Reloaded sway."
    else
        note "Takes effect the next time sway starts."
    fi
}

# put_snippet NAME < content: writes config.d/NAME.conf and checks it
put_snippet() {
    local f="$SWAY_SNIPPETS/$1.conf"
    ensure_sway_config
    cat >"$f"
    if ! check_sway_config; then
        rm -f "$f"
        die "sway rejected $f, so it was removed."
    fi
    note "Wrote $f"
    reload_sway
}

remove_snippet() {
    local f="$SWAY_SNIPPETS/$1.conf"
    if [ -f "$f" ]; then
        rm -f "$f"
        note "Removed $f"
        reload_sway
    fi
}

# drop_ifupdown_iface IF: comment out IF's stanza in /etc/network/interfaces
drop_ifupdown_iface() {
    local ifc=$1 file=/etc/network/interfaces tmp
    [ -f "$file" ] || return 0
    $SUDO grep -Eq "^[[:space:]]*(auto|allow-hotplug|iface)[[:space:]]+$ifc([[:space:]]|$)" "$file" ||
        return 0
    [ -e "$file.debsway.bak" ] || $SUDO cp -a "$file" "$file.debsway.bak"
    tmp=$(mktemp)
    $SUDO cat "$file" | awk -v i="$ifc" '
        /^[^[:space:]#]/ { inside = 0 }
        $1 == "iface" && $2 == i { inside = 1 }
        ($1 == "auto" || $1 == "allow-hotplug") && $2 == i && NF == 2 { print "#" $0; next }
        inside && !/^#/ { print "#" $0; next }
        { print }' >"$tmp"
    $SUDO tee "$file" <"$tmp" >/dev/null
    rm -f "$tmp"
    note "Commented out $ifc in $file (backup: $file.debsway.bak)"
}

wifi_ifaces() {
    local d
    for d in /sys/class/net/*; do
        if [ -d "$d/wireless" ] || [ -e "$d/phy80211" ]; then
            basename "$d"
        fi
    done
}

# read_bridges webtunnel|obfs4: reads bridge lines from the terminal into
# BRIDGES, until an empty line. A leading "Bridge" is dropped.
read_bridges() {
    local kind=$1 line ok
    BRIDGES=()
    note "Paste your $kind bridge lines, one per line, then press Enter on an empty line."
    note "Get them at https://bridges.torproject.org/options (choose $kind),"
    note "by email to bridges@torproject.org, or from @GetBridgesBot on Telegram."
    while :; do
        tty_read line "    bridge> "
        line=$(sed -E 's/^[[:space:]]*([Bb]ridge[[:space:]]+)?//; s/[[:space:]]+$//; s/[[:space:]]+/ /g' <<<"$line")
        [ -n "$line" ] || break
        ok=false
        case $kind in
            webtunnel) [[ $line =~ ^webtunnel\ [^\ ]+\ [0-9A-Fa-f]{40}\ .*url=https:// ]] && ok=true ;;
            obfs4) [[ $line =~ ^obfs4\ [^\ ]+:[0-9]+\ [0-9A-Fa-f]{40}\ .*cert= ]] && ok=true ;;
        esac
        if ! $ok || [[ $line == *[\"\\]* ]]; then
            warn "Skipped, not a $kind bridge line. Those look like: $kind ADDRESS:PORT FINGERPRINT ..."
            continue
        fi
        BRIDGES+=("$line")
    done
}

# set_default_app DESKTOP MIME...: opens these file types with DESKTOP
# (~/.config/mimeapps.list, read by Firefox and other apps)
set_default_app() {
    local app=$1 f="$HOME/.config/mimeapps.list" mime tmp
    shift
    mkdir -p "${f%/*}"
    [ -f "$f" ] || printf '[Default Applications]\n' >"$f"
    grep -q '^\[Default Applications\]' "$f" || printf '\n[Default Applications]\n' >>"$f"
    for mime in "$@"; do
        tmp=$(mktemp)
        awk -v k="$mime" -v v="$app" '
            /^\[/ { if (sect && !done) { print k "=" v; done = 1 } sect = ($0 == "[Default Applications]") }
            sect && index($0, k "=") == 1 { if (!done) print k "=" v; done = 1; next }
            { print }
            END { if (!done) print k "=" v }' "$f" >"$tmp"
        mv "$tmp" "$f"
    done
}

# unset_default_app DESKTOP: forgets every default that points at DESKTOP
unset_default_app() {
    local f="$HOME/.config/mimeapps.list"
    [ -f "$f" ] && sed -i "/=$1\$/d" "$f"
    return 0
}
