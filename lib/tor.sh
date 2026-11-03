# shellcheck shell=bash
# lib/tor.sh: bridges, for Tor Browser, Whonix, OnionShare and apt over Tor.
# Sourced by lib.sh.
#
# Everything that connects to Tor asks the same way, with pick_bridges:
# first whether a bridge is needed at all, then which kind, out of the kinds
# that work in that place. Afterwards:
#   BRIDGE_TYPE  none | obfs4 | obfs4-builtin | webtunnel | snowflake | meek
#   BRIDGES      the lines the user pasted (obfs4 and webtunnel only)
#   BRIDGE_WANTED  true if the user said they need a bridge (even if none
#                  was chosen in the end, say no lines were pasted)

BRIDGE_TYPE=none
BRIDGES=()
BRIDGE_WANTED=false

# bridge_kinds CONTEXT: the kinds that work there, in the order offered
#   tor-browser   Tor Browser: has all of them built in
#   system-tor    Debian's tor (apt over Tor, remote access, the onion site):
#                 obfs4proxy, lyrebird (webtunnel) and snowflake-client
#   onionshare    OnionShare's own tor: its built-in lists, obfs4proxy, snowflake-client
#   whonix        the Whonix Gateway: obfs4proxy and snowflake-client
bridge_kinds() {
    case $1 in
        tor-browser) echo "obfs4-builtin obfs4 webtunnel snowflake meek" ;;
        system-tor) echo "obfs4 webtunnel snowflake" ;;
        whonix) echo "obfs4 snowflake" ;;
        onionshare) echo "obfs4-builtin obfs4 snowflake" ;;
        *) echo "obfs4" ;;
    esac
}

# bridge_unavailable CONTEXT: kinds that don't work there, and why
bridge_unavailable() {
    case $1 in
        system-tor) echo "meek: no client program for it here" ;;
        onionshare) echo "webtunnel, meek: OnionShare and Debian have no client for them" ;;
        whonix) echo "webtunnel, meek: the Whonix Gateway has no client for them" ;;
    esac
}

# bridge_describe KIND: one line on what it is
bridge_describe() {
    case $1 in
        obfs4-builtin) echo "obfs4, Tor's own public list: nothing to fetch; often blocked where Tor is" ;;
        obfs4) echo "obfs4, bridge lines you get yourself: makes Tor look like random data; fast" ;;
        webtunnel) echo "webtunnel, bridge lines you get yourself: looks like a visit to a website" ;;
        snowflake) echo "Snowflake: no lines needed; borrows volunteers' browsers; slower, works where obfs4 is blocked" ;;
        meek) echo "meek (Azure): looks like a visit to Microsoft's cloud; slowest, a last resort" ;;
    esac
}

# bridge_explain KIND: where to get bridge lines of that kind
bridge_explain() {
    case $1 in
        obfs4)
            note "obfs4 bridge lines come from Tor's BridgeDB. Any of these:"
            note "  - the website https://bridges.torproject.org/options (choose obfs4, solve the captcha)"
            note "  - email bridges@torproject.org from a Gmail or Riseup address (any text will do)"
            note "  - the Telegram bot @GetBridgesBot"
            note "  - a friend outside the network that blocks Tor"
            note "A line looks like: obfs4 ADDRESS:PORT FINGERPRINT cert=... iat-mode=0"
            ;;
        webtunnel)
            note "webtunnel bridge lines come from Tor's BridgeDB. Any of these:"
            note "  - the website https://bridges.torproject.org/options (choose webtunnel)"
            note "  - the Telegram bot @GetBridgesBot"
            note "  - email bridges@torproject.org with the text: get transport webtunnel"
            note "    (if it answers with obfs4 only, use the website)"
            note "A line looks like: webtunnel ADDRESS:PORT FINGERPRINT url=https://... ver=..."
            ;;
    esac
}

# read_bridges obfs4|webtunnel: reads bridge lines from the terminal into
# BRIDGES, until an empty line. A leading "Bridge" is dropped.
read_bridges() {
    local kind=$1 line ok
    BRIDGES=()
    bridge_explain "$kind"
    note "Paste your $kind bridge lines, one per line, then press Enter on an empty line."
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

# pick_bridges CONTEXT: asks whether a bridge is needed and which kind, then
# reads the lines if the kind needs them. Sets BRIDGE_TYPE and BRIDGES.
pick_bridges() {
    local context=$1 kinds=() kind i choice un
    BRIDGE_TYPE=none
    BRIDGES=()
    BRIDGE_WANTED=false
    note "A bridge is a relay that isn't listed publicly. You need one if your network blocks"
    note "Tor, or if you don't want it to see that you use Tor. Most people on an ordinary"
    note "home connection don't need one."
    ask "Do you need a bridge to reach the Tor network?" n || return 0
    BRIDGE_WANTED=true

    read -ra kinds <<<"$(bridge_kinds "$context")"
    note "Kinds of bridge that work here:"
    for i in "${!kinds[@]}"; do
        printf '    %d) %s\n' $((i + 1)) "$(bridge_describe "${kinds[i]}")"
    done
    un=$(bridge_unavailable "$context")
    [ -z "$un" ] || note "Not offered here ($un)."
    note "If you don't know which: Snowflake needs nothing from you, and obfs4 is the usual."
    while :; do
        tty_read choice "Which one (1-${#kinds[@]}, Enter for no bridge)? "
        [ -n "$choice" ] || { note "No bridge."; return 0; }
        if [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#kinds[@]} ]; then
            kind=${kinds[choice - 1]}
            break
        fi
        warn "Type a number from the list, or press Enter for no bridge."
    done

    case $kind in
        obfs4 | webtunnel)
            read_bridges "$kind"
            if [ ${#BRIDGES[@]} -eq 0 ]; then
                warn "No $kind bridge lines were given, so no bridge will be used."
                return 0
            fi
            ;;
    esac
    BRIDGE_TYPE=$kind
}

# bridge_summary: a few words on what pick_bridges chose
bridge_summary() {
    case $BRIDGE_TYPE in
        none) echo "no bridge" ;;
        obfs4 | webtunnel) echo "${#BRIDGES[@]} $BRIDGE_TYPE bridge(s)" ;;
        obfs4-builtin) echo "built-in obfs4 bridges" ;;
        snowflake) echo "Snowflake" ;;
        meek) echo "meek-azure" ;;
    esac
}

# snowflake_lines: the "snowflake ..." bridge lines for Debian's snowflake-client
snowflake_lines() {
    grep -E '^snowflake ' "$WREN_DIR/data/snowflake-bridges.txt"
}

# tor_bridge_config: torrc lines for the chosen bridges, for a tor that runs
# obfs4proxy, lyrebird and snowflake-client from /usr/bin (Debian's AppArmor
# profile for tor already lets it run all three). Nothing is printed for
# none, or for kinds that aren't set up in torrc (the built-in ones).
tor_bridge_config() {
    local b
    case $BRIDGE_TYPE in
        obfs4)
            echo "UseBridges 1"
            echo "ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy"
            for b in "${BRIDGES[@]}"; do echo "Bridge $b"; done
            ;;
        webtunnel)
            echo "UseBridges 1"
            echo "ClientTransportPlugin webtunnel exec /usr/bin/lyrebird"
            for b in "${BRIDGES[@]}"; do echo "Bridge $b"; done
            ;;
        snowflake)
            echo "UseBridges 1"
            echo "ClientTransportPlugin snowflake exec /usr/bin/snowflake-client"
            snowflake_lines | sed 's/^/Bridge /'
            ;;
    esac
}

# bridge_packages: what the system tor needs for the chosen bridge (lyrebird
# comes from the Tor Project's repository: add_torproject_repo first)
bridge_packages() {
    case $BRIDGE_TYPE in
        obfs4) echo obfs4proxy ;;
        webtunnel) echo lyrebird ;;
        snowflake) echo snowflake-client ;;
    esac
}

# The Tor Project's apt repository, for one package: lyrebird, the Tor
# Project's own bridge program (the one Tor Browser carries), which speaks
# webtunnel; Debian has no webtunnel client. Its key must be exactly
# TORPROJECT_FPR (pins.sh). An apt pin makes everything else in it
# uninstallable (priority -1), so Debian's tor and every other package stay
# Debian's; lyrebird is one program and a man page, with no install scripts.
# Its updates install themselves (unattended-upgrades). Through Tor when apt
# goes through Tor (apt-tor.sh), once lyrebird is there to connect with.
TORPROJECT_KEY=/usr/share/keyrings/wren-torproject.asc
TORPROJECT_LIST=/etc/apt/sources.list.d/wren-torproject.list
TORPROJECT_PREF=/etc/apt/preferences.d/wren-torproject.pref
torproject_pref() {
    cat <<'EOF'
# Written by Wren Linux (lib/tor.sh): from the Tor Project's repository,
# lyrebird only. Nothing else there can be installed.
Package: lyrebird
Pin: origin deb.torproject.org
Pin-Priority: 500

Package: *
Pin: origin deb.torproject.org
Pin-Priority: -1
EOF
}
add_torproject_repo() {
    local cn proto=https
    cn=$(. /etc/os-release && echo "${VERSION_CODENAME:-}")
    [ -n "$cn" ] || die "Can't tell which Debian this is (no VERSION_CODENAME), so not adding the Tor Project's repository."
    install_apt_key "$TORPROJECT_FPR" "$TORPROJECT_KEY_URL" "$TORPROJECT_KEY"
    torproject_pref | sudo tee "$TORPROJECT_PREF" >/dev/null
    # apt over Tor, with lyrebird already here: this repository through Tor too
    if [ -e "${WREN_ETC:-/etc}/tor/.wren-apt-tor" ] && is_installed lyrebird; then proto=tor+https; fi
    echo "deb [signed-by=$TORPROJECT_KEY arch=$(dpkg --print-architecture)] $proto://deb.torproject.org/torproject.org $cn main" |
        sudo tee "$TORPROJECT_LIST" >/dev/null
    allow_unattended_updates torproject deb.torproject.org
    unset WREN_APT_UPDATED
}
# Only once lyrebird is gone
remove_torproject_repo_if_unused() {
    local had=false
    is_installed lyrebird && return 0
    [ ! -e "$TORPROJECT_LIST" ] || had=true
    sudo rm -f "$TORPROJECT_LIST" "$TORPROJECT_KEY" "$TORPROJECT_PREF"
    forget_unattended_updates torproject
    ! $had || note "Removed the Tor Project's apt repository."
}

# The Wren Linux scripts that use the system tor service (tor@default), each
# marked by a file in /etc/tor. OnionShare runs its own tor and masks the system
# one, but only while none of these needs it.
TOR_SERVICE_MARKS=".wren-apt-tor .wren-remote-access .wren-onion-site"

# system_tor_wanted [MARK]: one of them, other than MARK (the script asking,
# while it removes itself), is set up. WREN_ETC is where /etc is, for tests.
system_tor_wanted() {
    local m
    for m in $TOR_SERVICE_MARKS; do
        [ "$m" != "${1:-}" ] || continue
        [ ! -e "${WREN_ETC:-/etc}/tor/$m" ] || return 0
    done
    return 1
}

# tor_service_on: the system tor service runs now and at every boot. Debian
# starts tor@default at boot only as part of tor.service (tor's systemd
# generator puts it in tor.service.wants), so enabling tor@default alone is
# not enough: tor.service has to be enabled too. It isn't, after OnionShare
# masked it, or when tor was installed while it was masked (as these scripts
# do, to hold tor until its settings are in), and then Tor is gone after the
# next reboot. TOR_SINCE is when it was (re)started, for tor_connected.
tor_service_on() {
    sudo systemctl unmask tor.service tor@default.service >/dev/null
    sudo systemctl enable tor.service tor@default.service >/dev/null 2>&1 || true
    TOR_SINCE=$(date '+%Y-%m-%d %H:%M:%S')
    sudo systemctl restart tor@default.service
}

# tor_service_off: stopped, and not started at boot
tor_service_off() {
    sudo systemctl disable --now tor@default.service tor.service >/dev/null 2>&1 || true
}

# onion_add_client SVC_DIR: a client key for the onion service in SVC_DIR
# (Tor's client authorization). Its public half goes to Tor here, as
# SVC_DIR/authorized_clients/client-DATE.auth; the private half is left in
# CLIENT_PRIV, to be shown once for the computer or Tor Browser that will
# connect (the x25519 keys Tor wants, as base32 without padding).
onion_add_client() {
    local dir=$1 tmp pub priv name
    tmp=$(mktemp)
    openssl genpkey -algorithm x25519 -outform DER -out "$tmp"
    priv=$(tail -c 32 "$tmp" | base32 | tr -d =)
    pub=$(openssl pkey -inform DER -in "$tmp" -pubout -outform DER | tail -c 32 | base32 | tr -d =)
    rm -f "$tmp"
    name=client-$(date +%Y%m%d-%H%M%S)
    printf 'descriptor:x25519:%s\n' "$pub" | sudo tee "$dir/authorized_clients/$name.auth" >/dev/null
    sudo chown debian-tor:debian-tor "$dir/authorized_clients/$name.auth"
    sudo chmod 600 "$dir/authorized_clients/$name.auth"
    CLIENT_PRIV=$priv
}

# tor_connected [SINCE]: tor writes "Bootstrapped 100%" to the journal when it
# is connected. SINCE ("YYYY-MM-DD HH:MM:SS") ignores lines from before a restart.
tor_connected() {
    sudo journalctl _COMM=tor -n 200 --no-pager ${1:+--since "$1"} 2>/dev/null | grep -q 'Bootstrapped 100%'
}
