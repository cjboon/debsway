#!/bin/bash
# Tor Browser as its own locked-down user, tor-browser, so a hacked page doesn't reach your
# files. It has no password or login, and its own home (/home/tor-browser), where the browser
# lives and updates itself through Tor.
#  - It opens inside cage, a tiny Wayland compositor shown as one window in your sway, with a
#    private X server: Tor Browser runs on X11 on purpose (less fingerprintable), and on X11 any
#    program can read every window and key. A restricted socket (bin/wayland-restrict) keeps it
#    from your screen.
#  - A firewall rule (data/tor-browser-firewall.nft) keeps it off this computer and your local
#    network. It doesn't force the browser through Tor: browser and Tor are one user, so a
#    hacked browser could go straight out and show your address. Whonix is what stops that.
#  - Nothing crosses by itself. A line of text goes through browser-sandbox clip (Super+Ctrl+b),
#    which shows it to you first; files through ~/Browsers/tor-browser.
#  - Debian's torbrowser-launcher is installed for the AppArmor profiles it brings, which confine
#    the browser and its Tor. The browser itself is the Tor Project's, checked against their key
#    (prep/fetch-tor-browser.sh): contrib is turned on for the launcher, and --remove turns it off
#    again if this script was what turned it on.
#  - Before its first start this writes a user.js into its profile: the Safest security level,
#    JavaScript off, and a bridge if you need one (it asks first, then offers obfs4, webtunnel,
#    Snowflake or meek), so its very first connection goes through it. Firefox applies user.js at
#    every start, so these come back after a restart even if changed in the browser; run this
#    again to change them.
# /usr/bin/torbrowser-launcher, by its full path, still runs as you. A copy you already had there
# is left alone, and --remove asks about it.
# Usage: bash tor-browser.sh [--remove | --manual]
# summary: Tor Browser as its own user, with a bridge if needed
# security: most
# status: file:/usr/local/bin/tor-browser
# files: lib/browser-sandbox.sh bin/browser-sandbox bin/browser-session data/tor-browser-firewall.nft data/tor-browser-safest.js prep/fetch-tor-browser.sh bin/no-abstract-sockets bin/wayland-restrict bin/sandbox-net-check
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$WREN_DIR/lib/appimage.sh"
. "$WREN_DIR/lib/browser-sandbox.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

MARK=/etc/apt/wren-enabled-contrib
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
TOR_PROFILE=/etc/apparmor.d/torbrowser.Tor.tor
TOR_LOCAL=/etc/apparmor.d/local/torbrowser.Tor.tor
DNS_BEGIN='# >>> Wren Linux: DNS through the resolv.conf symlink >>>'
DNS_END='# <<< Wren Linux <<<'
# Tor Browser 16 moved torrc-defaults, geoip and geoip6 from TorBrowser/Data/Tor
# to TorBrowser/Tor, where the package's profile (torbrowser-launcher 0.3.7)
# doesn't let Tor read them. torrc-defaults holds the ClientTransportPlugin
# lines, so every bridge then fails: "there is no configured transport called
# snowflake" (obfs4, webtunnel too). Only reading those three files is added.
TB16_BEGIN='# >>> Wren Linux: what Tor Browser 16 keeps in TorBrowser/Tor >>>'
TB16_RULES=('owner @{torbrowser_home_dir}/TorBrowser/Tor/torrc-defaults r,'
    'owner @{torbrowser_home_dir}/TorBrowser/Tor/geoip r,'
    'owner @{torbrowser_home_dir}/TorBrowser/Tor/geoip6 r,')

fix_apparmor_dns() {
    [ -f "$TOR_PROFILE" ] || return 0
    if ! sudo grep -qxF "$DNS_BEGIN" "$TOR_LOCAL" 2>/dev/null; then
        printf '%s\n' "$DNS_BEGIN" \
            '@{run}/resolvconf/resolv.conf r,' \
            '@{run}/NetworkManager/{,no-stub-}resolv.conf r,' \
            '@{run}/systemd/resolve/{,stub-}resolv.conf r,' \
            "$DNS_END" | sudo tee -a "$TOR_LOCAL" >/dev/null
        note "Let Tor's AppArmor profile read resolv.conf, for bridges given as hostnames."
    fi
    if ! sudo grep -qxF "$TB16_BEGIN" "$TOR_LOCAL" 2>/dev/null; then
        # (the same rules added by hand go: they would be there twice)
        for r in "${TB16_RULES[@]}"; do
            sudo sed -i "\\|^$r\$|d" "$TOR_LOCAL" 2>/dev/null || true
        done
        printf '%s\n' "$TB16_BEGIN" "${TB16_RULES[@]}" "$DNS_END" | sudo tee -a "$TOR_LOCAL" >/dev/null
        note "Let Tor's AppArmor profile read Tor Browser 16's torrc-defaults: its bridges' programs are named there."
    fi
    if [ -d /sys/kernel/security/apparmor ]; then
        sudo apparmor_parser -r "$TOR_PROFILE"
    fi
}

# Its profile lets the browser save only in its own Downloads, and reach sound only at the
# usual places: this lets it save in the folder you share with it, and reach its own sound
# server, in memory. Both are this user's alone.
BROWSER_PROFILE=/etc/apparmor.d/torbrowser.Browser.firefox
BROWSER_LOCAL=/etc/apparmor.d/local/torbrowser.Browser.firefox
SANDBOX_BEGIN='# >>> Wren Linux: Tor Browser as its own user >>>'
fix_apparmor_browser() {
    [ -f "$BROWSER_PROFILE" ] || return 0
    if ! sudo grep -qxF "$SANDBOX_BEGIN" "$BROWSER_LOCAL" 2>/dev/null; then
        printf '%s\n' "$SANDBOX_BEGIN" \
            "$BROWSER_FILES/tor-browser/ rw," "$BROWSER_FILES/tor-browser/** rwk," \
            'owner /dev/shm/tor-browser.*/run/pulse/ r,' 'owner /dev/shm/tor-browser.*/run/pulse/native rw,' \
            "$DNS_END" | sudo tee -a "$BROWSER_LOCAL" >/dev/null
    fi
    if [ -d /sys/kernel/security/apparmor ]; then
        sudo apparmor_parser -r "$BROWSER_PROFILE"
    fi
}

unfix_apparmor_browser() {
    [ -f "$BROWSER_LOCAL" ] || return 0
    sudo sed -i "\\|^$SANDBOX_BEGIN\$|,\\|^$DNS_END\$|d" "$BROWSER_LOCAL"
    if [ -f "$BROWSER_PROFILE" ] && [ -d /sys/kernel/security/apparmor ]; then
        sudo apparmor_parser -r "$BROWSER_PROFILE" || true
    fi
}

unfix_apparmor_dns() {
    [ -f "$TOR_LOCAL" ] || return 0
    sudo sed -i "\\|^$DNS_BEGIN\$|,\\|^$DNS_END\$|d" "$TOR_LOCAL"
    sudo sed -i "\\|^$TB16_BEGIN\$|,\\|^$DNS_END\$|d" "$TOR_LOCAL"
    # Loaded rules stay until the profile is read again: read it now, without them
    if [ -f "$TOR_PROFILE" ] && [ -d /sys/kernel/security/apparmor ]; then
        sudo apparmor_parser -r "$TOR_PROFILE" || true
    fi
}

NAME=tor-browser
# Where it lives. (Under /home, in the folder the launcher would use: that is where its AppArmor
# profile attaches. It isn't confined anywhere else.)
TB_BASE=/home/$NAME/.local/share/torbrowser/tbb/$(uname -m)
TBB=$TB_BASE/tor-browser
PROFILE=$TBB/Browser/TorBrowser/Data/Browser/profile.default
USERJS=$PROFILE/user.js
# A copy from before it had a user of its own, which ran as you
OLD_USERJS=$HOME/.local/share/torbrowser/tbb/$(uname -m)/tor-browser/Browser/TorBrowser/Data/Browser/profile.default/user.js
JS_BEGIN='// >>> Wren Linux extras/tor-browser.sh >>>'
JS_END='// <<< Wren Linux <<<'
OFFLINE="$OFFLINE_DIR/torbrowser"

# install_browser: unpacks the newest copy prep/fetch-tor-browser.sh saved, checked against the
# developers' key, as its user, from standard input: it can't reach your files, and nothing is
# written as root in its home. It fetches one if there is none. Once there, it updates itself.
install_browser() {
    local copies tarball
    if as_browser "$NAME" test -e "$TBB/Browser/start-tor-browser"; then
        note "Tor Browser is there already (it updates itself, through Tor)."
        return 0
    fi
    copies=("$OFFLINE"/tor-browser-linux-"$(uname -m)"-*.tar.xz)
    if [ ! -f "${copies[-1]}" ]; then
        note "Downloading Tor Browser from torproject.org, without Tor: your network can see that"
        note "you fetched it (not what you do with it). prep/fetch-tor-browser.sh on another"
        note "network, beforehand, saves a copy that is used instead."
        bash "$WREN_DIR/prep/fetch-tor-browser.sh" || die "Couldn't fetch Tor Browser. Nothing was started."
        copies=("$OFFLINE"/tor-browser-linux-"$(uname -m)"-*.tar.xz)
    fi
    tarball=$(printf '%s\n' "${copies[@]}" | sort -V | tail -1)
    verify_detached "$TB_FPR" "$OFFLINE/tor-browser-developers.asc" "$tarball.asc" "$tarball" ||
        die "The saved copy $tarball didn't pass its signature check. Run prep/fetch-tor-browser.sh again."
    as_browser "$NAME" mkdir -p "$TB_BASE"
    as_browser "$NAME" tar -xJ -C "$TB_BASE" <"$tarball" || die "Couldn't unpack $tarball."
    note "Installed Tor Browser from $(basename -- "$tarball"), checked against the developers' key."
}

tor_browser_running() { pgrep -u "$NAME" >/dev/null 2>&1; }

# our_block: what user.js holds from an earlier run: its own, or the copy that ran as you. It
# comes from a file a hacked browser could change, so the callers below take only what is
# shaped as it should be.
our_block() {
    { as_browser "$NAME" cat "$USERJS" 2>/dev/null || cat "$OLD_USERJS" 2>/dev/null || true; } |
        sed -n "\|^$JS_BEGIN\$|,\|^$JS_END\$|p"
}

# Our block's bridge lines, if any, from an earlier run
current_bridges() {
    local line
    our_block | sed -n 's/^user_pref("torbrowser\.settings\.bridges\.bridge_strings\.[0-9]*", "\(.*\)");$/\1/p' |
        while IFS= read -r line; do
            if [[ $line =~ ^(obfs4|webtunnel)\ [^\"\\[:cntrl:]]+$ ]]; then printf '%s\n' "$line"; fi
        done
}

# Our block's built-in bridge type (obfs4, snowflake, meek), if any
current_builtin() {
    case $(our_block | sed -n 's/^user_pref("torbrowser\.settings\.bridges\.builtin_type", "\(.*\)");$/\1/p' | head -1) in
        obfs4) echo obfs4 ;;
        snowflake) echo snowflake ;;
        meek) echo meek ;;
    esac
}

# Safest and JavaScript off (data/tor-browser-safest.js), plus bridges. Written by its user,
# from standard input.
write_userjs() {
    local i tmp
    tmp=$(mktemp)
    as_browser "$NAME" cat "$USERJS" 2>/dev/null | sed "\|^$JS_BEGIN\$|,\|^$JS_END\$|d" >"$tmp" || true
    {
        echo "$JS_BEGIN"
        cat "$WREN_DIR/data/tor-browser-safest.js"
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
    # shellcheck disable=SC2016  # expanded by the inner bash, on purpose
    as_browser "$NAME" bash -c 'umask 077; mkdir -p "$1"; cat >"$1/.user.js.wren"; mv -f "$1/.user.js.wren" "$1/user.js"' _ "$PROFILE" <"$tmp"
    rm -f "$tmp"
    # Bridges saved earlier from the browser's settings would be used too,
    # so drop them; Tor Browser rewrites prefs.js from user.js at start.
    if [ "$BRIDGE_TYPE" != none ]; then
        as_browser "$NAME" sed -i '/^user_pref("torbrowser\.settings\.bridges\.bridge_strings\./d' "$PROFILE/prefs.js" 2>/dev/null || true
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
    note "Tor Browser starts at the Safest level with JavaScript off."
    if [ "$BRIDGE_TYPE" != none ]; then
        note "Its first connection goes through a bridge: $(bridge_summary)."
    else
        note "No bridge: Tor Browser connects to Tor directly. Run this again to set one up,"
        note "or choose one in its settings before you click Connect."
    fi
}

if [ "${1:-}" = --remove ]; then
    browser_remove "$NAME"
    sudo rm -f /usr/local/bin/torbrowser-launcher
    remove_wayland_restrict
    remove_no_abstract
    remove_net_check
    unfix_apparmor_browser
    unfix_apparmor_dns
    apt_purge torbrowser-launcher
    disable_contrib
    # The copy from before it had a user of its own
    if [ -d "$HOME/.local/share/torbrowser" ] &&
        ask "Also delete the older Tor Browser that ran as you, and its bookmarks (~/.local/share/torbrowser)?" n; then
        rm -rf "$HOME/.local/share/torbrowser" "$HOME/.cache/torbrowser" "$HOME/.config/torbrowser"
        note "Deleted."
    elif [ -f "$OLD_USERJS" ]; then
        sed -i "\|^$JS_BEGIN\$|,\|^$JS_END\$|d" "$OLD_USERJS"
        note "Took the Wren Linux settings out of $OLD_USERJS; that copy keeps their last values."
    fi
    exit
fi

say "Debian contrib section"
enable_contrib
# A fresh update, so apt sees the contrib packages
unset WREN_APT_UPDATED

say "Installing what it needs"
# torbrowser-launcher: the AppArmor profiles; cage, xwayland: its window and private X server;
# xclip, wl-clipboard: browser-sandbox clip; acl: sharing the socket and the folder; nftables,
# python3: the firewall and its check, wayland-restrict; the pipewire ones: its sound server, and
# pw-cat, the player of yours that reads its one pipe; xz-utils: unpacking it
need_xwayland
apt_install torbrowser-launcher xz-utils cage xclip wl-clipboard acl nftables python3 \
    pipewire-bin pipewire-pulse wireplumber
fix_apparmor_dns

say "The $NAME user"
browser_user "$NAME" "Wren Linux sandboxed Tor Browser"
fix_apparmor_browser
browser_files "$NAME"

say "The commands"
install_bin wayland-restrict
install_no_abstract
install_net_check
browser_commands "$NAME"
# By the name you may know it from: /usr/local/bin comes first
sudo ln -sfn browser-sandbox /usr/local/bin/torbrowser-launcher
browser_allow "$NAME"

say "Keeping $NAME off this computer and your network"
browser_firewall "$NAME"
browser_clip_key

say "Tor Browser"
install_browser

say "Tor Browser's security level and bridges"
prepare_profile
if [ -d "$HOME/.local/share/torbrowser/tbb" ]; then
    note "You also have a Tor Browser that runs as you, in ~/.local/share/torbrowser: left alone, and no"
    note "longer started by name. To keep its bookmarks, export them to a file there, and import that"
    note "from ~/Browsers/tor-browser."
fi
note "Run it with: tor-browser   (or Super+d)"
note "Text in or out: Super+Ctrl+b, which shows it first. Files: ~/Browsers/tor-browser."
