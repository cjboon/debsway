#!/bin/bash
# Connect to Wi-Fi using whatever this system has, from a bare Debian
# install upward. Asks for the network and password, connects, and sets
# it up to reconnect at boot.
#
#   bash wifi.sh            (uses sudo, or run it as root after: su -)
#   bash wifi.sh --remove   undo it: remove the Wi-Fi settings wifi.sh wrote, and
#                           offer to remove NetworkManager and the random Wi-Fi
#                           address too, for a computer that doesn't need Wi-Fi
#
# Backends, first one usable wins:
#   NetworkManager -> iwd -> wpa_supplicant (+ ifupdown or systemd-networkd)
# If none is installed, it installs wpasupplicant from offline/debs (made by
# prep/fetch-offline-debs.sh), or over Ethernet / USB tethering.
#
# Passwords are never put on a command line, where any user on the machine
# could read them. If your nmcli doesn't take one on its standard input,
# DEBSWAY_PASSWORD_ON_COMMAND_LINE=1 bash wifi.sh uses the old way.
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
. "$DEBSWAY_DIR/lib/offline.sh"

if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null; then
        exec sudo bash "$DEBSWAY_DIR/wifi.sh" "$@"
    fi
    die "Needs root. Run: su -   then: bash $DEBSWAY_DIR/wifi.sh"
fi

# ------------------------------------------------------------------ --remove

if [ "${1:-}" = --remove ]; then
    say "Removing the Wi-Fi setup"
    remove_wifi_config
    # NetworkManager and the random address are parts, run as your own user
    pieces=()
    is_installed network-manager && pieces+=(network-manager)
    [ -e /etc/NetworkManager/conf.d/90-debsway-random-mac.conf ] && pieces+=(random-mac)
    if [ ${#pieces[@]} -gt 0 ]; then
        note "Also set up by debsway for Wi-Fi: ${pieces[*]}"
        if [ -n "${SUDO_USER:-}" ] && ask "Remove those too? (This computer will then have only its wired connection.)" n; then
            for p in random-mac network-manager; do
                case " ${pieces[*]} " in *" $p "*) sudo -u "$SUDO_USER" bash "$DEBSWAY_DIR/parts/$p.sh" --remove ;; esac
            done
        else
            note "To remove them later, as your own user: bash parts/random-mac.sh --remove, then bash parts/network-manager.sh --remove"
        fi
    fi
    exit 0
fi

IF=
SSID=
PASS=
HIDDEN=false
WPA_CONF=

has_ipv4() { ip -4 -o addr show dev "$1" scope global 2>/dev/null | grep -q inet; }

# ---------------------------------------------------------------- hardware

reload_wifi_drivers() {
    local dev mod
    for dev in /sys/bus/pci/devices/*; do
        case $(cat "$dev/class") in 0x0280*) ;; *) continue ;; esac
        [ -e "$dev/driver/module" ] || continue
        mod=$(basename "$(readlink -f "$dev/driver/module")")
        note "Reloading driver $mod"
        modprobe -r "$mod" 2>/dev/null && modprobe "$mod" || true
    done
    sleep 3
}

# Install Wi-Fi packages from offline/debs, a local apt repo made by
# prep/fetch-offline-debs.sh. apt picks only what this system is missing.
# These packages arrive on a USB stick and go in as root, so each one is
# first matched to Debian's signed package lists (lib/offline.sh).
install_offline_debs() {
    local tmp p want=() rc=0
    [ -f "$DEBSWAY_DIR/offline/debs/Packages" ] || return 1
    tmp=$(mktemp -d)
    # Check and install the same copy
    cp -r "$DEBSWAY_DIR/offline/debs" "$tmp/repo"
    if [ ! -d "$tmp/repo/verify" ] ||
        ! verify_offline_lists "$tmp/repo/verify" "$tmp/sums" ||
        ! check_offline_debs "$tmp/repo" "$tmp/sums"; then
        warn "The packages in $DEBSWAY_DIR/offline/debs can't be matched to Debian's signed"
        warn "lists, so they were not installed. Make them again on a machine you trust:"
        warn "  bash prep/fetch-offline-debs.sh"
        rm -rf "$tmp"
        return 1
    fi
    mkdir -p "$tmp/lists/partial" "$tmp/parts"
    # trusted=yes: the index is local and unsigned, but every file in it
    # was checked against Debian's signed lists above
    echo "deb [trusted=yes] file:$tmp/repo ./" >"$tmp/sources.list"
    local opts=(-o "Dir::Etc::SourceList=$tmp/sources.list" -o "Dir::Etc::SourceParts=$tmp/parts"
        -o "Dir::State::Lists=$tmp/lists")
    for p in wpasupplicant iw wireless-regdb $(awk '/^Package: firmware-/ { print $2 }' "$tmp/repo/Packages"); do
        is_installed "$p" || want+=("$p")
    done
    if [ ${#want[@]} -eq 0 ]; then
        rm -rf "$tmp"
        return 1
    fi
    say "Installing from $DEBSWAY_DIR/offline/debs: ${want[*]}"
    apt-get "${opts[@]}" update >/dev/null &&
        apt-get "${opts[@]}" install -y --no-install-recommends "${want[@]}" || rc=$?
    rm -rf "$tmp"
    return "$rc"
}

find_iface() {
    local list
    mapfile -t list < <(wifi_ifaces)
    if [ ${#list[@]} -eq 0 ]; then
        warn "No Wi-Fi device found. This usually means missing firmware."
        if install_offline_debs; then
            reload_wifi_drivers
            mapfile -t list < <(wifi_ifaces)
        fi
    fi
    if [ ${#list[@]} -eq 0 ]; then
        command -v lspci >/dev/null && lspci -nnk | grep -iA3 'network controller' >&2
        dmesg 2>/dev/null | grep -i 'firmware' | grep -iE 'fail|error' | tail -5 >&2 || true
        die "Still no Wi-Fi device. Check for a hardware Wi-Fi switch, or copy the
   firmware package for your card (e.g. firmware-iwlwifi, firmware-realtek)
   into $DEBSWAY_DIR/offline/debs and run this again. A reboot may also be needed."
    fi
    IF=${list[0]}
    if [ ${#list[@]} -gt 1 ]; then
        read -r -p "Wi-Fi devices: ${list[*]}. Use which? [$IF] " pick </dev/tty || pick=
        IF=${pick:-$IF}
    fi
    [ -e "/sys/class/net/$IF" ] || die "No device called $IF."

    say "Using Wi-Fi device $IF"
}

unblock_wifi() {
    local r
    for r in /sys/class/rfkill/rfkill*; do
        [ "$(cat "$r/type" 2>/dev/null)" = wlan ] || continue
        if [ "$(cat "$r/hard")" = 1 ]; then
            die "Wi-Fi is switched off in hardware. Use the switch or Fn key, then run this again."
        fi
        if [ "$(cat "$r/soft")" = 1 ]; then
            echo 0 >"$r/soft" 2>/dev/null || rfkill unblock wifi 2>/dev/null || true
            note "Turned Wi-Fi on (was blocked in software)."
        fi
    done
    ip link set "$IF" up 2>/dev/null || true
}

# --------------------------------------------------------------- IP + DNS

set_dns() {
    [ $# -gt 0 ] || return 0
    # A symlinked resolv.conf belongs to resolved or similar; leave it
    [ -L /etc/resolv.conf ] && return 0
    if command -v resolvconf >/dev/null; then
        printf 'nameserver %s\n' "$@" | resolvconf -a "$IF.debsway"
        return 0
    fi
    [ -e /etc/resolv.conf.debsway.bak ] || cp -a /etc/resolv.conf /etc/resolv.conf.debsway.bak 2>/dev/null || true
    printf 'nameserver %s\n' "$@" >/etc/resolv.conf
}

# DHCP through systemd-networkd, which every Debian has. "persist" keeps
# the config across reboots; otherwise it lives in /run.
networkd_dhcp() {
    local ifc=$1 dir=/run/systemd/network lease dns i
    [ "${2:-}" = persist ] && dir=/etc/systemd/network
    mkdir -p "$dir"
    printf '[Match]\nName=%s\n\n[Network]\nDHCP=yes\n' "$ifc" >"$dir/50-debsway-$ifc.network"
    if [ "${2:-}" = persist ]; then
        systemctl enable systemd-networkd >/dev/null 2>&1 || true
        systemctl disable systemd-networkd-wait-online.service >/dev/null 2>&1 || true
    fi
    systemctl restart systemd-networkd || return 1
    for i in $(seq 30); do has_ipv4 "$ifc" && break; sleep 1; done
    has_ipv4 "$ifc" || return 1
    lease=/run/systemd/netif/leases/$(cat "/sys/class/net/$ifc/ifindex")
    for i in $(seq 5); do [ -f "$lease" ] && break; sleep 1; done
    dns=$(sed -n 's/^DNS=//p' "$lease" 2>/dev/null)
    # Home routers usually answer DNS themselves
    [ -n "$dns" ] || dns=$(ip -4 route show default dev "$ifc" | awk '{ print $3; exit }')
    # shellcheck disable=SC2086
    set_dns $dns
}

busybox_dhcp() {
    local ifc=$1 script=/run/debsway-udhcpc.sh
    command -v busybox >/dev/null || return 1
    cat >"$script" <<'EOF'
#!/bin/sh
case "$1" in
    deconfig) ip -4 addr flush dev "$interface"; ip link set "$interface" up ;;
    bound|renew)
        ip -4 addr flush dev "$interface"
        ip addr add "$ip/${mask:-24}" dev "$interface"
        if [ -n "$router" ]; then
            ip route del default dev "$interface" 2>/dev/null
            ip route add default via "${router%% *}" dev "$interface"
        fi
        if [ -n "$dns" ] && [ ! -L /etc/resolv.conf ]; then
            : >/etc/resolv.conf
            for d in $dns; do echo "nameserver $d" >>/etc/resolv.conf; done
        fi ;;
esac
EOF
    chmod 755 "$script"
    busybox udhcpc -i "$ifc" -s "$script" -n -q -t 10
}

# Get an address on $1 right now with any DHCP client there is
dhcp_now() {
    local ifc=$1
    ip link set "$ifc" up
    if command -v dhcpcd >/dev/null && dhcpcd -4 -w -t 30 "$ifc"; then return 0; fi
    if command -v dhclient >/dev/null && dhclient -4 -1 "$ifc"; then return 0; fi
    if networkd_dhcp "$ifc"; then return 0; fi
    busybox_dhcp "$ifc"
}

# ------------------------------------------------- getting wpa_supplicant

wired_ifaces() {
    local d n
    for d in /sys/class/net/*; do
        n=${d##*/}
        [ "$n" = lo ] && continue
        [ -e "$d/device" ] || continue
        if [ -d "$d/wireless" ] || [ -e "$d/phy80211" ]; then continue; fi
        echo "$n"
    done
}

online_via_wire() {
    local n reply
    while :; do
        for n in $(wired_ifaces); do
            ip link set "$n" up 2>/dev/null || true
        done
        sleep 3
        for n in $(wired_ifaces); do
            [ "$(cat "/sys/class/net/$n/carrier" 2>/dev/null)" = 1 ] || continue
            note "Cable or tether found on $n, getting an address"
            if dhcp_now "$n" && have_internet; then return 0; fi
        done
        echo
        echo "  Plug in an Ethernet cable, or connect your phone by USB and turn on"
        echo "  USB tethering (Android: Settings > Network > Hotspot > USB tethering)."
        read -r -p "  Press Enter to try again, or q to quit: " reply </dev/tty || reply=q
        [ "$reply" != q ] || die "No way to install wpasupplicant. See README.md, 'Before you reinstall'."
    done
}

get_wpa_supplicant() {
    warn "No Wi-Fi software is installed (no NetworkManager, iwd or wpa_supplicant)."
    if install_offline_debs && command -v wpa_supplicant >/dev/null; then
        return 0
    fi
    if ! have_internet; then
        online_via_wire
    fi
    say "Installing wpasupplicant and iw"
    apt-get update
    apt-get install -y --no-install-recommends wpasupplicant iw wireless-regdb
}

# ----------------------------------------------------------- choose backend

pick_backend() {
    local state
    if command -v nmcli >/dev/null && systemctl is-active --quiet NetworkManager; then
        state=$(nmcli -t -f DEVICE,STATE device 2>/dev/null | awk -F: -v i="$IF" '$1 == i { print $2 }')
        # unmanaged = ifupdown owns it (installer setup); use that instead
        if [ -n "$state" ] && [ "$state" != unmanaged ]; then echo nm; return; fi
    fi
    if command -v iwctl >/dev/null; then
        systemctl is-active --quiet iwd || systemctl start iwd 2>/dev/null || true
        if systemctl is-active --quiet iwd; then echo iwd; return; fi
    fi
    if command -v wpa_supplicant >/dev/null; then echo wpa; return; fi
    echo none
}

# ----------------------------------------------------------- scan + prompt

scan_ssids() {
    case $BACKEND in
        nm)
            nmcli --escape no -t -f SSID device wifi list ifname "$IF" --rescan yes 2>/dev/null ;;
        iwd)
            iwctl station "$IF" scan >/dev/null 2>&1 || true
            sleep 4
            iwctl station "$IF" get-networks 2>/dev/null |
                sed 's/\x1b\[[0-9;]*m//g' |
                grep -vE '^[[:space:]]*$|^[[:space:]-]+$|Available networks|Network name' |
                sed -E 's/^[[:space:]>]+//; s/[[:space:]]+(psk|open|8021x|wep)[[:space:]]+[*]*[[:space:]]*$//' ;;
        *)
            if command -v iw >/dev/null; then
                iw dev "$IF" scan 2>/dev/null |
                    awk '/^[[:space:]]*signal:/ { s = $2 }
                         /^[[:space:]]*SSID: / { sub(/^[[:space:]]*SSID: /, ""); print s "\t" $0 }' |
                    sort -t "$(printf '\t')" -k1,1 -gr | cut -f2-
            fi ;;
    esac | awk 'NF && !seen[$0]++' | head -20
}

ask_network() {
    local ssids=() i choice
    say "Scanning for networks"
    mapfile -t ssids < <(scan_ssids || true)
    if [ ${#ssids[@]} -gt 0 ]; then
        for i in "${!ssids[@]}"; do printf '  %2d) %s\n' $((i + 1)) "${ssids[i]}"; done
    else
        note "Couldn't scan (or nothing found). Type the network name."
    fi
    while [ -z "$SSID" ]; do
        read -r -p "Network number or name: " choice </dev/tty || die "No input."
        if [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#ssids[@]} ]; then
            SSID=${ssids[choice - 1]}
        else
            SSID=$choice
        fi
    done
    HIDDEN=false
    if ! printf '%s\n' "${ssids[@]}" | grep -qxF -- "$SSID"; then
        if ask "\"$SSID\" wasn't in the scan. Is it a hidden network?" y; then HIDDEN=true; fi
    fi
}

ask_password() {
    while :; do
        read -r -s -p "Password for \"$SSID\" (Enter if it has none): " PASS </dev/tty || PASS=
        echo
        local n=${#PASS}
        if [ "$n" -eq 0 ] || { [ "$n" -ge 8 ] && [ "$n" -le 63 ]; } ||
            [[ $PASS =~ ^[0-9A-Fa-f]{64}$ ]]; then
            return 0
        fi
        warn "Wi-Fi passwords are 8 to 63 characters. Try again."
    done
}

# ----------------------------------------------------------------- connect

connect_nm() {
    local args=(device wifi connect "$SSID" ifname "$IF")
    $HIDDEN && args+=(hidden yes)
    nmcli connection delete id "$SSID" >/dev/null 2>&1 || true
    if [ -z "$PASS" ]; then
        nmcli --wait 45 "${args[@]}"
    elif [ -n "${DEBSWAY_PASSWORD_ON_COMMAND_LINE:-}" ]; then
        nmcli --wait 45 "${args[@]}" password "$PASS"
    else
        # --ask takes the password from standard input
        printf '%s\n' "$PASS" | nmcli --ask --wait 45 "${args[@]}"
    fi
}

# iwd reads a known network's password from a file in /var/lib/iwd, so it
# is written there instead of being given to iwctl on the command line.
# The old file, if any, is kept until the new password has worked.
iwd_profile() {
    local dir=/var/lib/iwd name
    if [[ $SSID =~ ^[A-Za-z0-9\ _-]+$ ]]; then
        name=$SSID
    else
        name="=$(printf '%s' "$SSID" | od -An -tx1 -v | tr -d ' \n')"
    fi
    echo "$dir/$name.psk"
}

write_iwd_profile() {
    local file=$1
    mkdir -p "${file%/*}"
    (
        umask 077
        {
            echo "[Security]"
            if [[ $PASS =~ ^[0-9A-Fa-f]{64}$ ]]; then
                echo "PreSharedKey=$PASS"
            else
                echo "Passphrase=$PASS"
            fi
            if $HIDDEN; then printf '\n[Settings]\nHidden=true\n'; fi
        } >"$file"
    )
}

connect_iwd() {
    local cmd=connect i file='' old=''
    $HIDDEN && cmd=connect-hidden
    if [ -n "$PASS" ]; then
        file=$(iwd_profile)
        if [ -f "$file" ]; then
            old=$(mktemp)
            cp -p "$file" "$old"
        fi
        write_iwd_profile "$file"
    fi
    if ! iwctl station "$IF" "$cmd" "$SSID"; then
        if [ -n "$file" ]; then
            if [ -n "$old" ]; then mv "$old" "$file"; else rm -f "$file"; fi
        fi
        return 1
    fi
    if [ -n "$old" ]; then rm -f "$old"; fi
    for i in $(seq 20); do
        iwctl station "$IF" show 2>/dev/null | grep -q 'State.*connected' && break
        sleep 1
    done
    for i in $(seq 10); do has_ipv4 "$IF" && return 0; sleep 1; done
    # iwd remembers the network; give it an address at boot as well
    mkdir -p /etc/iwd
    if ! grep -qs '^EnableNetworkConfiguration=true' /etc/iwd/main.conf; then
        printf '[General]\nEnableNetworkConfiguration=true\n' >>/etc/iwd/main.conf
    fi
    dhcp_now "$IF"
}

write_wpa_conf() {
    local hex group=
    WPA_CONF=/etc/wpa_supplicant/wpa_supplicant-$IF.conf
    getent group netdev >/dev/null && group=" GROUP=netdev"
    hex=$(printf '%s' "$SSID" | od -An -tx1 | tr -d ' \n')
    mkdir -p /etc/wpa_supplicant
    (
        umask 077
        {
            echo "# Written by debsway wifi.sh"
            echo "ctrl_interface=DIR=/run/wpa_supplicant$group"
            echo "update_config=1"
            echo "network={"
            echo "    ssid=$hex"
            $HIDDEN && echo "    scan_ssid=1"
            if [ -z "$PASS" ]; then
                echo "    key_mgmt=NONE"
            elif [[ $PASS =~ ^[0-9A-Fa-f]{64}$ ]]; then
                echo "    psk=$PASS"
            elif [[ $PASS == *\"* ]]; then
                # The file can't quote a password that has a " in it, so it
                # gets the key derived from it (which WPA3 networks can't use)
                echo "    psk=$(printf '%s\n' "$PASS" | wpa_passphrase "$SSID" | sed -n 's/^[[:space:]]*psk=//p')"
                echo "    key_mgmt=WPA-PSK WPA-PSK-SHA256"
                echo "    ieee80211w=1"
            else
                echo "    psk=\"$PASS\""
                echo "    key_mgmt=WPA-PSK WPA-PSK-SHA256 SAE"
                echo "    ieee80211w=1"
            fi
            echo "}"
        } >"$WPA_CONF"
    )
}

stop_wpa_on_iface() {
    ifdown --force "$IF" >/dev/null 2>&1 || true
    systemctl stop "wpa_supplicant@$IF.service" >/dev/null 2>&1 || true
    wpa_cli -i "$IF" terminate >/dev/null 2>&1 || true
    pkill -f "wpa_supplicant.*-i ?$IF( |$)" 2>/dev/null || true
    sleep 1
}

# Try the password with a throwaway wpa_supplicant: 0 ok, 2 wrong password
test_credentials() {
    local log pid i rc=1
    log=$(mktemp)
    wpa_supplicant -i "$IF" -c "$WPA_CONF" -D nl80211,wext >"$log" 2>&1 &
    pid=$!
    for i in $(seq 30); do
        sleep 1
        if grep -q CTRL-EVENT-CONNECTED "$log"; then rc=0; break; fi
        if grep -qE 'WRONG_KEY|pre-shared key may be incorrect' "$log"; then rc=2; break; fi
        if ! kill -0 "$pid" 2>/dev/null; then rc=3; break; fi
    done
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    [ "$rc" -ne 3 ] || tail -5 "$log" >&2
    rm -f "$log"
    return "$rc"
}

connect_wpa() {
    local rc
    stop_wpa_on_iface
    write_wpa_conf
    note "Checking the password"
    rc=0
    test_credentials || rc=$?
    case $rc in
        0) ;;
        2) warn "Wrong password."; return 2 ;;
        *) warn "Couldn't connect to \"$SSID\" (out of range, or wrong name?)."; return 1 ;;
    esac
    sleep 1

    if command -v ifup >/dev/null && { command -v dhcpcd || command -v dhclient; } >/dev/null; then
        # Debian's own way: ifupdown starts wpa_supplicant and DHCP at boot
        drop_ifupdown_iface "$IF"
        grep -Eqs '^[[:space:]]*source(-directory)?[[:space:]]+/etc/network/interfaces\.d' \
            /etc/network/interfaces ||
            printf '\nsource /etc/network/interfaces.d/*\n' >>/etc/network/interfaces
        mkdir -p /etc/network/interfaces.d
        cat >"/etc/network/interfaces.d/debsway-wifi-$IF" <<EOF
# Written by debsway wifi.sh
allow-hotplug $IF
iface $IF inet dhcp
    wpa-conf $WPA_CONF
EOF
        note "Saved for boot in /etc/network/interfaces.d/debsway-wifi-$IF"
        ifup "$IF"
    else
        # No ifupdown DHCP client: systemd units instead
        systemctl enable --now "wpa_supplicant@$IF.service"
        note "Saved for boot: wpa_supplicant@$IF.service + systemd-networkd"
        networkd_dhcp "$IF" persist
    fi
}

# -------------------------------------------------------------------- main

find_iface
unblock_wifi

if has_ipv4 "$IF" && have_internet; then
    say "Already online through $IF."
    ask "Connect to a different network?" n || exit 0
fi

BACKEND=$(pick_backend)
if [ "$BACKEND" = none ]; then
    get_wpa_supplicant
    BACKEND=$(pick_backend)
    [ "$BACKEND" != none ] || die "wpa_supplicant still isn't available."
    ip link set "$IF" up 2>/dev/null || true
fi
note "Connecting with: $BACKEND"

ask_network
for attempt in 1 2 3; do
    ask_password
    rc=0
    case $BACKEND in
        nm) connect_nm || rc=$? ;;
        iwd) connect_iwd || rc=$? ;;
        wpa) connect_wpa || rc=$? ;;
    esac
    [ "$rc" -eq 0 ] && break
    [ "$attempt" -lt 3 ] || die "Giving up after 3 tries."
    if ! ask "Try again?" y; then exit 1; fi
    if ask "Pick a different network?" n; then SSID=; ask_network; fi
done

say "Checking the connection"
for i in $(seq 15); do
    if has_ipv4 "$IF" && have_internet; then
        say "Online: $SSID on $IF ($(ip -4 -o addr show dev "$IF" scope global | awk '{ print $4; exit }'))"
        exit 0
    fi
    sleep 1
done
if has_ipv4 "$IF"; then
    die "Connected with an address, but names don't resolve. Check /etc/resolv.conf."
fi
die "Joined \"$SSID\" but got no address from it."
