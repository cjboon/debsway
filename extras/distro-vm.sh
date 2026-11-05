#!/bin/bash
# retired: Kali, Tails and Arch VMs took a lot of root-run machinery for rare use. Tails is safer on a stick of its own: wrenctl install tails-usb.
# Other Linux distributions in throwaway VMs on this computer: Kali (security
# testing), Tails (an amnesic desktop on Tor) and Arch (minimal, rolling; you
# install it yourself). You tick which ones; nothing is ticked for you.
#  - Each runs as its own locked user (dvm-kali, dvm-tails, dvm-arch: no
#    password, no login), in the kvm group only. QEMU's user-mode networking
#    makes the guest's traffic that user's sockets, so a firewall rule on it
#    (data/distro-vm-firewall.nft) governs the guest: the internet, but not your
#    router, printers or this computer's services.
#  - Asked for Kali and Arch, before anything is installed: Tor only. Then every
#    connection of that VM goes into the system Tor (its TransPort and DNSPort,
#    on 127.0.0.1 only) and everything else is refused; with Tor down, nothing
#    gets out. Then whether you need a bridge, and which kind (lib/tor.sh),
#    unless another Wren Linux script already set the system Tor up. Tails is
#    never asked: it brings its own Tor.
#  - The VM won't start unless that firewall is really there, seen from the VM's
#    user (bin/distro-vm-net-check), and is ended if it goes away while it runs.
#  - Images are downloaded as that user too, through its firewall, and kept only
#    if they are the newest in the project's own release list and signed by its
#    key, pinned in pins.sh (Kali's, Tails', Arch's).
#  - Its screen is a SPICE socket only you can open, shown by remote-viewer; no
#    clipboard, files, sound or USB devices cross.
#  - Your user may run exactly one thing as those users, distro-vm-session (a
#    rule in /etc/sudoers.d). The distro-vm command calls it.
# Needs KVM. See docs/extras/distro-vm.md and THREAT-MODEL.md.
# Usage: bash distro-vm.sh [--remove | --manual]
# summary: Kali, Tails and Arch in VMs kept off your network
# security: most
# status: bin:distro-vm file:/usr/local/libexec/distro-vm-session
# files: bin/distro-vm-session bin/distro-vm-net-check bin/no-abstract-sockets data/distro-vm-firewall.nft
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$WREN_DIR/lib/appimage.sh"
# The system Tor's ports for the VMs set to Tor only (data/distro-vm-firewall.nft has them too)
TRANS_PORT=9041
DNS_PORT=9054
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

DISTROS=(kali tails arch)
HOMES=/var/lib/wren-distro-vm
SESSION=/usr/local/libexec/distro-vm-session
NETCHECK=/usr/local/libexec/distro-vm-net-check
# (a test points WREN_ETC elsewhere)
CONF=${WREN_ETC:-/etc}/wren/distro-vm.conf
KEYS=/etc/wren/distro-vm
SUDOERS=/etc/sudoers.d/wren-distro-vm
FIREWALL=/etc/wren/distro-vm.nft
UNIT=/etc/systemd/system/wren-distro-vm-firewall.service
MARK=/etc/tor/.wren-distro-vm
TORRC=/etc/tor/torrc
BEGIN='# >>> Wren Linux distro-vm >>>'
END='# <<< Wren Linux distro-vm <<<'
OWNER=$(id -un)

describe() {
    case $1 in
        kali) echo "Kali Linux: security testing tools, you install it (~4.4 GB)" ;;
        tails) echo "Tails: amnesic desktop, all through its own Tor (~1.9 GB)" ;;
        arch) echo "Arch Linux: minimal and rolling, you install it (~1.3 GB)" ;;
    esac
}
key_of() {
    case $1 in
        kali) echo "$KALI_FPR $KALI_KEY_URL" ;;
        tails) echo "$TAILS_FPR $TAILS_KEY_URL" ;;
        arch) echo "$ARCH_ISO_FPR $ARCH_ISO_KEY_URL" ;;
    esac
}
set_up() { awk -v n="$1" '$1 == n { f = 1 } END { exit !f }' "$CONF" 2>/dev/null; }

# remove_distro NAME: its VM off, its sudo right gone, and (if you say so) its
# user with the images and disk in its home
remove_distro() {
    local user=dvm-$1
    if id "$user" >/dev/null 2>&1; then
        sudo -u "$user" "$SESSION" stop >/dev/null 2>&1 || true
        sudo pkill -KILL -u "$user" 2>/dev/null || true
        if ask "Delete $1's images and disk ($HOMES/$1), with anything saved in the VM?" n; then
            sudo userdel -r "$user" 2>/dev/null || sudo userdel "$user"
            sudo rm -rf "${HOMES:?}/$1"
            note "Removed $1."
        else
            sudo userdel "$user"
            note "Kept $HOMES/$1 (root's now: nothing can start it)."
        fi
    fi
}

# tor_block: what this adds to torrc, the bridge lines too when asked here
tor_block() {
    echo "$BEGIN"
    echo "# Tor only for the distro-vm VMs (data/distro-vm-firewall.nft sends them here)"
    echo "TransPort 127.0.0.1:$TRANS_PORT"
    echo "DNSPort 127.0.0.1:$DNS_PORT"
    echo "VirtualAddrNetworkIPv4 10.192.0.0/10"
    echo "AutomapHostsOnResolve 1"
    tor_bridge_config
    echo "$END"
}

if [ "${1:-}" = --remove ]; then
    for d in "${DISTROS[@]}"; do remove_distro "$d"; done
    remove_bin distro-vm
    sudo systemctl disable --now wren-distro-vm-firewall.service >/dev/null 2>&1 || true
    sudo nft delete table inet wren_distro_vm 2>/dev/null || true
    sudo rm -f "$SUDOERS" "$SESSION" "$NETCHECK" "$FIREWALL" "$UNIT" "$CONF"
    sudo rm -rf "$KEYS"
    sudo rmdir "$HOMES" 2>/dev/null || true
    if [ -e "$MARK" ]; then
        sudo sed -i "\\|^$BEGIN\$|,\\|^$END\$|d" "$TORRC"
        sudo rm -f "$MARK"
        if system_tor_wanted .wren-distro-vm; then
            sudo systemctl reload tor@default.service >/dev/null 2>&1 || true
        else
            tor_service_off
        fi
    fi
    remove_no_abstract
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    apt_purge qemu-system-x86 qemu-utils qemu-system-modules-spice virt-viewer nftables tor obfs4proxy lyrebird snowflake-client
    remove_torproject_repo_if_unused
    note "Removed distro-vm."
    exit
fi

[ -e /dev/kvm ] || die "No /dev/kvm: turn on virtualization (VT-x / AMD-V) in the firmware settings."

# ---- the questions, all before anything is installed
say "Which distributions?"
chosen=()
if [ -n "${DISTRO_VM_CHOOSE+x}" ]; then
    read -ra chosen <<<"$DISTRO_VM_CHOOSE"
else
    . "$WREN_DIR/lib/checklist.sh"
    ITEMS=()
    for d in "${DISTROS[@]}"; do
        ITEMS+=("$d" "$(describe "$d")" "$(set_up "$d" && echo ON || echo OFF)")
    done
    CL_TITLE="Distributions in VMs" CL_OK=Continue CL_CANCEL=Cancel
    CL_TEXT="Each runs as its own user, off your computer and your local network.\nUntick one that is set up to remove it (you're asked about its files).\nFor real anonymity use Whonix (wrenctl install whonix); Tails on a USB stick is safer than Tails here."
    checklist || die "Nothing changed."
fi
for d in "${chosen[@]}"; do
    case $d in kali | tails | arch) ;; *) die "Not one of these: $d (kali, tails, arch)" ;; esac
done
# None ticked: nothing is installed, and what was set up before goes (as --remove)
if [ ${#chosen[@]} -eq 0 ]; then
    if [ -f "$CONF" ]; then
        note "None ticked: removing what was set up (you're asked about each one's files)."
        exec bash "$0" --remove
    fi
    note "None ticked, so nothing was installed."
    exit 0
fi

declare -A mode
any_tor=false
for d in "${chosen[@]}"; do
    mode[$d]=direct
    if [ "$d" = tails ]; then
        note "Tails connects through its own Tor; it isn't asked."
        continue
    fi
    if [ -n "${DISTRO_VM_TOR+x}" ]; then
        if [[ " $DISTRO_VM_TOR " == *" $d "* ]]; then mode[$d]=tor; fi
    elif ask "Send $d's internet through Tor only? (hides your address from what it connects to; slower, TCP only)" n; then
        mode[$d]=tor
    fi
    if [ "${mode[$d]}" = tor ]; then any_tor=true; fi
done

BRIDGE_TYPE=none BRIDGES=()
tor_shared=false
if $any_tor; then
    note "Tor only hides your address. Kali and Arch aren't made for anonymity: their"
    note "browsers and updates can still tell sites who you are. That is Whonix's job."
    if system_tor_wanted .wren-distro-vm; then
        tor_shared=true
        note "The system Tor is already set up here (with its own bridges, if any); the VMs use it."
    else
        say "Bridges"
        pick_bridges system-tor
        if $BRIDGE_WANTED && [ "$BRIDGE_TYPE" = none ]; then
            warn "You said you need a bridge, but none was set up: your network could see that you use Tor."
            ask "Go on without a bridge?" n || die "Stopped before changing anything. Run this again with a bridge."
        fi
    fi
fi

# Those set up before and now unticked go first
for d in "${DISTROS[@]}"; do
    if set_up "$d" && [[ " ${chosen[*]} " != *" $d "* ]]; then remove_distro "$d"; fi
done

# ---- installing
say "Installing QEMU, its screen viewer and the firewall"
pkgs=(qemu-system-x86 qemu-utils qemu-system-modules-spice virt-viewer nftables acl python3 wget gpg)
if $any_tor; then
    # Debian starts tor the moment it is installed; held until its settings are in
    if ! $tor_shared; then sudo systemctl mask tor.service tor@default.service >/dev/null; fi
    pkgs+=(tor)
    [ "$BRIDGE_TYPE" != webtunnel ] || add_torproject_repo
    b=$(bridge_packages)
    [ -z "$b" ] || pkgs+=("$b")
fi
apt_install "${pkgs[@]}"

say "The pinned signing keys"
sudo install -d -o root -g root -m 0755 "$KEYS"
for d in "${chosen[@]}"; do
    read -r fpr url <<<"$(key_of "$d")"
    home=$(_keyring "$fpr" "$url") || die "Couldn't get $d's signing key ($fpr); nothing of $d was set up."
    gpg --homedir "$home" --batch --export "$fpr" | sudo tee "$KEYS/$d.gpg" >/dev/null
    _keyring_done "$home"
    echo "$fpr" | sudo tee "$KEYS/$d.fpr" >/dev/null
    sudo chmod 0644 "$KEYS/$d.gpg" "$KEYS/$d.fpr"
    note "$d: $fpr"
done

say "The VMs' users"
sudo install -d -o root -g root -m 0755 "$HOMES"
for d in "${chosen[@]}"; do
    user=dvm-$d
    if id "$user" >/dev/null 2>&1; then
        [ "$(id -u "$user")" -lt 1000 ] ||
            die "A regular user account called $user already exists; this needs a system user. Rename or remove it first."
    else
        sudo useradd --system --user-group --no-create-home --home-dir "$HOMES/$d" \
            --shell /usr/sbin/nologin --comment "Wren Linux $d VM" "$user"
    fi
    sudo usermod --lock --shell /usr/sbin/nologin "$user"
    sudo usermod -G kvm "$user"
    # (-h: a link in there is changed itself, not what it points at)
    if sudo test -d "$HOMES/$d"; then sudo chown -Rh "$user:$user" "$HOMES/$d"; fi
    sudo install -d -o "$user" -g "$user" -m 0700 "$HOMES/$d"
    note "$user: no password, no login, in the kvm group only."
done

say "What each VM may reach"
conf=$(mktemp)
{
    echo "# Written by Wren Linux extras/distro-vm.sh: each VM and its network (direct: the"
    echo "# internet, not your network; tor: Tor only), and whose screen it is"
    echo "owner $OWNER"
    for d in "${chosen[@]}"; do echo "$d ${mode[$d]}"; done
} >"$conf"
sudo install -d -o root -g root -m 0755 /etc/wren
sudo install -o root -g root -m 0644 "$conf" "$CONF"
rm -f "$conf"
rules=$(mktemp)
{
    cat "$WREN_DIR/data/distro-vm-firewall.nft"
    for d in "${chosen[@]}"; do echo "add element inet wren_distro_vm ${mode[$d]} { \"dvm-$d\" }"; done
} >"$rules"
sudo nft -c -f "$rules" >/dev/null || { rm -f "$rules"; die "nft didn't accept the firewall rule, so nothing was started."; }
sudo install -o root -g root -m 0644 "$rules" "$FIREWALL"
rm -f "$rules"
printf '%s\n' '# Written by Wren Linux extras/distro-vm.sh' '[Unit]' \
    'Description=Keep the distro-vm VMs off the local network (Wren Linux)' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' \
    "ExecStart=/usr/sbin/nft -f $FIREWALL" \
    'ExecStop=/usr/sbin/nft delete table inet wren_distro_vm' '' '[Install]' \
    'WantedBy=multi-user.target' | sudo tee "$UNIT" >/dev/null
sudo systemctl daemon-reload
# Restart, not just enable --now: the unit stays "active" after it first ran
sudo systemctl enable wren-distro-vm-firewall.service >/dev/null &&
    sudo systemctl restart wren-distro-vm-firewall.service ||
    warn "Couldn't load the firewall rule, so no VM will start; check: systemctl status wren-distro-vm-firewall"
# Loading it empties its resolvers set (parts/sandbox-dns.sh refills it from now on)
if [ -x /usr/local/libexec/wren-sandbox-dns ]; then
    sudo /usr/local/libexec/wren-sandbox-dns || true
else
    # Without that part (a base part, so rare) the set is filled once, now
    sudo bash "$WREN_DIR/bin/sandbox-dns-update" || true
    warn "The sandbox-dns part isn't set up: after a reboot, VMs on the internet can't look"
    warn "names up until you run: wrenctl part sandbox-dns"
fi
for d in "${chosen[@]}"; do
    note "$d: $([ "${mode[$d]}" = tor ] && echo "Tor only" || echo "the internet, not your network")"
done

if $any_tor; then
    say "Tor for the VMs"
    sudo sed -i "\\|^$BEGIN\$|,\\|^$END\$|d" "$TORRC"
    # (the bridges only when asked here: a Tor that others set up keeps its own)
    if $tor_shared; then BRIDGE_TYPE=none; fi
    tor_block | sudo tee -a "$TORRC" >/dev/null
    printf '%s\n' 'Written by Wren Linux extras/distro-vm.sh: the VMs set to Tor only use the system tor service.' |
        sudo tee "$MARK" >/dev/null
    if $tor_shared && systemctl is-active --quiet tor@default.service; then
        # A reload opens the new ports without dropping what else uses it
        sudo systemctl reload tor@default.service
    else
        tor_service_on
        for i in $(seq 90); do
            if tor_connected "$TOR_SINCE"; then break; fi
            [ $((i % 10)) -ne 0 ] || note "Waiting for Tor ($((i * 2))s)..."
            sleep 2
        done
        tor_connected "$TOR_SINCE" && note "Tor is connected." ||
            warn "Tor didn't connect in 3 minutes; VMs set to Tor only won't reach anything until it does."
    fi
elif [ -e "$MARK" ]; then
    # No VM on Tor any more
    sudo sed -i "\\|^$BEGIN\$|,\\|^$END\$|d" "$TORRC"
    sudo rm -f "$MARK"
    if system_tor_wanted .wren-distro-vm; then sudo systemctl reload tor@default.service || true; else tor_service_off; fi
fi

say "The distro-vm command"
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 "$WREN_DIR/bin/distro-vm-session" "$SESSION"
sudo install -o root -g root -m 0755 "$WREN_DIR/bin/distro-vm-net-check" "$NETCHECK"
install_no_abstract
rule=$(mktemp)
printf '# Written by Wren Linux extras/distro-vm.sh. %s may run distro-vm-session,\n# and nothing else, as the VMs'"'"' users.\n%s ALL=(%s) NOPASSWD: %s\n' \
    "$OWNER" "$OWNER" "$(printf 'dvm-%s,' "${chosen[@]}" | sed 's/,$//')" "$SESSION" >"$rule"
sudo visudo -cf "$rule" >/dev/null || { rm -f "$rule"; die "The sudoers rule didn't pass visudo's check, so it wasn't installed."; }
sudo install -o root -g root -m 0440 "$rule" "$SUDOERS"
rm -f "$rule"
install_bin distro-vm

if ask "Download the images now (it can take a while)?" y; then
    for d in "${chosen[@]}"; do
        say "$d"
        sudo -u "dvm-$d" "$SESSION" fetch || warn "$d wasn't downloaded; try again with: distro-vm $d update"
    done
fi

cat <<'EOF'

    distro-vm               what is set up
    distro-vm NAME          start it in a window (closing the window powers it off)
    distro-vm NAME update   its newest image, checked against its signing key
    distro-vm NAME reset    throw its disk away (Kali and Arch)

    The VMs reach the internet (or Tor only, as you chose), never your
    computer or your local network. No clipboard, files or USB cross.
EOF
