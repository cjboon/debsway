#!/bin/bash
# Tor Browser through Debian's torbrowser-launcher. On first run it
# downloads Tor Browser from torproject.org and checks its signature;
# it also keeps it updated. The launcher is in Debian's contrib section,
# so this turns contrib on in your apt sources, and --remove turns it
# off again if this script was what turned it on.
# Tor Browser runs on X11 on purpose (less fingerprintable), so XWayland
# is installed too.
# Before Tor Browser's first start this also writes a user.js into its
# profile: the Safest security level, JavaScript off, and a bridge if you
# need one (it asks first, then offers obfs4, webtunnel, Snowflake or meek),
# so its very first connection goes through it. Firefox
# applies user.js at every start, so these come back after a restart even
# if changed in the browser; run this again to change them.
# If prep/fetch-tor-browser.sh saved a copy into ../offline/torbrowser, that copy is
# checked and installed, so nothing is fetched from torproject.org.
# Usage: bash tor-browser.sh [--remove]
# summary: Tor Browser with your bridges (bridge lines needed)
# status: apt:torbrowser-launcher
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$DEBSWAY_DIR/lib/appimage.sh"
need_user

MARK=/etc/apt/debsway-enabled-contrib
CLASSIC=/etc/apt/sources.list

# Debian's own sources: classic lines in sources.list, deb822 stanzas in
# *.sources files that point at debian.org
deb822_files() {
    grep -ls 'debian\.org' /etc/apt/sources.list.d/*.sources 2>/dev/null || true
}

enable_contrib() {
    local changed=false f
    if [ -f "$CLASSIC" ] && grep -Eq '^deb(-src)?[[:space:]].*debian.*[[:space:]]main([[:space:]]|$)' "$CLASSIC" &&
        grep -E '^deb(-src)?[[:space:]].*debian' "$CLASSIC" | grep -vq '[[:space:]]contrib\b'; then
        sudo sed -i -E '/^deb(-src)?[[:space:]].*debian/ { /[[:space:]]contrib([[:space:]]|$)/! s/[[:space:]]main([[:space:]]|$)/ main contrib\1/ }' "$CLASSIC"
        changed=true
    fi
    for f in $(deb822_files); do
        if grep -q '^Components:' "$f" && grep '^Components:' "$f" | grep -vq '\bcontrib\b'; then
            sudo sed -i -E '/^Components:/ { /\bcontrib\b/! s/$/ contrib/ }' "$f"
            changed=true
        fi
    done
    if $changed; then
        sudo touch "$MARK"
        note "Turned on Debian's contrib section."
    else
        note "contrib is already on."
    fi
}

disable_contrib() {
    local f
    [ -e "$MARK" ] || { note "contrib was on before this script; leaving it."; return 0; }
    if [ -f "$CLASSIC" ]; then sudo sed -i -E 's/ main contrib([[:space:]]|$)/ main\1/' "$CLASSIC"; fi
    for f in $(deb822_files); do sudo sed -i -E '/^Components:/ s/ contrib\b//' "$f"; done
    sudo rm -f "$MARK"
    sudo apt-get update >/dev/null
    note "Turned Debian's contrib section off again."
}

# The package's AppArmor profile lets Tor read /etc/resolv.conf, but that
# is usually a symlink and AppArmor checks the real file. Plain Tor never
# notices (relays are IP addresses), but webtunnel and other bridges given
# as hostnames fail with "Temporary failure in name resolution".
TOR_LOCAL=/etc/apparmor.d/local/torbrowser.Tor.tor
DNS_BEGIN='# >>> debsway: DNS through the resolv.conf symlink >>>'
DNS_END='# <<< debsway <<<'

fix_apparmor_dns() {
    [ -f /etc/apparmor.d/torbrowser.Tor.tor ] || return 0
    if ! sudo grep -qxF "$DNS_BEGIN" "$TOR_LOCAL" 2>/dev/null; then
        printf '%s\n' "$DNS_BEGIN" \
            '@{run}/resolvconf/resolv.conf r,' \
            '@{run}/NetworkManager/{,no-stub-}resolv.conf r,' \
            '@{run}/systemd/resolve/{,stub-}resolv.conf r,' \
            "$DNS_END" | sudo tee -a "$TOR_LOCAL" >/dev/null
        note "Let Tor's AppArmor profile read resolv.conf, for bridges given as hostnames."
    fi
    if [ -d /sys/kernel/security/apparmor ]; then
        sudo apparmor_parser -r /etc/apparmor.d/torbrowser.Tor.tor
    fi
}

unfix_apparmor_dns() {
    [ -f "$TOR_LOCAL" ] || return 0
    sudo sed -i "\\|^$DNS_BEGIN\$|,\\|^$DNS_END\$|d" "$TOR_LOCAL"
}

# torbrowser-launcher unpacks Tor Browser here. Unpacking only adds files,
# so a user.js written before the first download is there at first start.
TBB="$HOME/.local/share/torbrowser/tbb/$(uname -m)/tor-browser"
PROFILE="$TBB/Browser/TorBrowser/Data/Browser/profile.default"
USERJS="$PROFILE/user.js"
JS_BEGIN='// >>> debsway extras/tor-browser.sh >>>'
JS_END='// <<< debsway <<<'

OFFLINE="$DEBSWAY_DIR/offline/torbrowser"
TBL_SETTINGS="$HOME/.config/torbrowser/settings.json"

# Unpack the copy prep/fetch-tor-browser.sh saved, checked against the key it
# saved, so torbrowser-launcher finds Tor Browser installed and just runs it
install_offline_copy() {
    local copies tarball
    [ ! -e "$TBB/start-tor-browser.desktop" ] || return 0
    copies=("$OFFLINE"/tor-browser-linux-"$(uname -m)"-*.tar.xz)
    if [ ! -f "${copies[-1]}" ]; then
        note "No saved copy in $OFFLINE, so torbrowser-launcher will download Tor Browser."
        return 0
    fi
    tarball=$(printf '%s\n' "${copies[@]}" | sort -V | tail -1)
    verify_detached "$TB_FPR" "$OFFLINE/tor-browser-developers.asc" "$tarball.asc" "$tarball" ||
        die "The saved copy $tarball didn't pass its signature check. Run prep/fetch-tor-browser.sh again."
    mkdir -p "$(dirname -- "$TBB")"
    tar -xJf "$tarball" -C "$(dirname -- "$TBB")"
    # Without a settings file the launcher doesn't look for an installed
    # Tor Browser and downloads one; it fills in its other settings itself
    if [ ! -f "$TBL_SETTINGS" ]; then
        mkdir -p "$(dirname -- "$TBL_SETTINGS")"
        echo '{"installed": true}' >"$TBL_SETTINGS"
    fi
    note "Installed Tor Browser from $(basename -- "$tarball"), checked against the developers' key."
}

tor_browser_running() { pgrep -f "^$TBB/Browser/firefox" >/dev/null; }

# Our block's bridge lines, if any, from an earlier run
current_bridges() {
    [ -f "$USERJS" ] || return 0 # first run: nothing saved yet
    sed -n "\|^$JS_BEGIN\$|,\|^$JS_END\$|p" "$USERJS" 2>/dev/null |
        sed -n 's/^user_pref("torbrowser\.settings\.bridges\.bridge_strings\.[0-9]*", "\(.*\)");$/\1/p'
}

# Our block's built-in bridge type (obfs4, snowflake, meek), if any
current_builtin() {
    [ -f "$USERJS" ] || return 0
    sed -n "\|^$JS_BEGIN\$|,\|^$JS_END\$|p" "$USERJS" 2>/dev/null |
        sed -n 's/^user_pref("torbrowser\.settings\.bridges\.builtin_type", "\(.*\)");$/\1/p' | head -1
}

# Safest and JavaScript off (data/tor-browser-safest.js), plus bridges
write_userjs() {
    local i tmp
    mkdir -p "$PROFILE"
    chmod 700 "$PROFILE"
    tmp=$(mktemp "$PROFILE/.user.js.XXXXXX")
    if [ -f "$USERJS" ]; then
        sed "\|^$JS_BEGIN\$|,\|^$JS_END\$|d" "$USERJS" >"$tmp"
    fi
    {
        echo "$JS_BEGIN"
        cat "$DEBSWAY_DIR/data/tor-browser-safest.js"
        # source: 0 = Tor Browser's built-in bridges, 2 = lines you provide
        case $BRIDGE_TYPE in
            obfs4 | webtunnel)
                echo 'user_pref("torbrowser.settings.bridges.enabled", true);'
                echo 'user_pref("torbrowser.settings.bridges.source", 2);'
                for i in "${!BRIDGES[@]}"; do
                    printf 'user_pref("torbrowser.settings.bridges.bridge_strings.%d", "%s");\n' "$i" "${BRIDGES[$i]}"
                done ;;
            obfs4-builtin | snowflake | meek)
                echo 'user_pref("torbrowser.settings.bridges.enabled", true);'
                echo 'user_pref("torbrowser.settings.bridges.source", 0);'
                printf 'user_pref("torbrowser.settings.bridges.builtin_type", "%s");\n' "${BRIDGE_TYPE%-builtin}" ;;
        esac
        echo "$JS_END"
    } >>"$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$USERJS"
    # Bridges saved earlier from the browser's settings would be used too,
    # so drop them; Tor Browser rewrites prefs.js from user.js at start.
    if [ "$BRIDGE_TYPE" != none ] && [ -f "$PROFILE/prefs.js" ]; then
        sed -i '/^user_pref("torbrowser\.settings\.bridges\.bridge_strings\./d' "$PROFILE/prefs.js"
    fi
}

prepare_profile() {
    local old old_builtin
    if tor_browser_running; then
        warn "Tor Browser is running. Quit it and run this again to set its security level and bridges."
        return 0
    fi
    mapfile -t old < <(current_bridges)
    old_builtin=$(current_builtin)
    if [ ${#old[@]} -gt 0 ] && ask "Keep the ${#old[@]} bridge line(s) set up last time?" y; then
        BRIDGES=("${old[@]}")
        BRIDGE_TYPE=obfs4
        [[ ${old[0]} != webtunnel* ]] || BRIDGE_TYPE=webtunnel
    elif [ -n "$old_builtin" ] && ask "Keep using Tor Browser's built-in $old_builtin bridges, set up last time?" y; then
        BRIDGE_TYPE=$old_builtin
        [ "$BRIDGE_TYPE" != obfs4 ] || BRIDGE_TYPE=obfs4-builtin
    else
        pick_bridges tor-browser
    fi
    write_userjs
    note "Tor Browser starts at the Safest level with JavaScript off ($USERJS)."
    if [ "$BRIDGE_TYPE" != none ]; then
        note "Its first connection goes through a bridge: $(bridge_summary)."
    else
        note "No bridge: Tor Browser connects to Tor directly. Run this again to set one up,"
        note "or choose one in its settings before you click Connect."
    fi
    if [ ! -e "$TBB/start-tor-browser.desktop" ]; then
        note "Note: the first run downloads Tor Browser from torproject.org without Tor,"
        note "so your network can see that you fetched it (not what you do with it)."
    fi
}

if [ "${1:-}" = --remove ]; then
    unfix_apparmor_dns
    apt_purge torbrowser-launcher
    disable_contrib
    if [ -d "$HOME/.local/share/torbrowser" ] &&
        ask "Also delete the downloaded Tor Browser and its bookmarks (~/.local/share/torbrowser)?" n; then
        rm -rf "$HOME/.local/share/torbrowser" "$HOME/.cache/torbrowser" "$HOME/.config/torbrowser"
        note "Deleted."
    elif [ -f "$USERJS" ]; then
        sed -i "\|^$JS_BEGIN\$|,\|^$JS_END\$|d" "$USERJS"
        note "Took the debsway settings out of $USERJS; Tor Browser keeps their last values."
    fi
    exit
fi

say "Debian contrib section"
enable_contrib
# A fresh update, so apt sees the contrib packages
unset DEBSWAY_APT_UPDATED

say "Installing torbrowser-launcher"
need_xwayland
apt_install torbrowser-launcher xz-utils
fix_apparmor_dns
install_offline_copy

say "Tor Browser security level and bridges"
prepare_profile
note "Run it with: torbrowser-launcher   (or Super+d)"
note "The first run downloads Tor Browser and checks its signature."
