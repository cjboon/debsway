#!/bin/bash
# retired: Whonix is the safer place for wallets (Feather and Electrum come in its Workstation, behind Tor): wrenctl install whonix. Feather and Sparrow also have a Tor setting of their own.
# Coin wallets kept apart from you, each other and the internet, for a computer
# that can't run VMs: Whonix (extras/whonix.sh) is the safer place for wallets,
# and this says so first when the computer could run it. It adds the command
# wallet, which opens Feather, Sparrow or Electrum:
#  - Each wallet runs as its own user (wallet-feather, wallet-sparrow,
#    wallet-electrum): no password, no login, and it can't read your files or
#    another wallet's. Its own files are in /var/lib/wren-wallet/NAME, which you
#    can't open either without sudo.
#  - A firewall rule (data/wallet-firewall.nft) lets those users reach Tor's port
#    on this computer and nothing else. It is checked from the wallet's side at
#    every start and while it runs (bin/wallet-net-check): no rule, no wallet.
#  - It opens inside cage, a tiny Wayland compositor shown as one window in your
#    sway, with a private X server, through a restricted socket
#    (bin/wayland-restrict), so it can't read your screen or your keys.
#  - Nothing crosses by itself. An address goes through wallet clip (Super+Ctrl+w),
#    which shows you the one line of text first (bin/wallet). Files go through
#    ~/Wallets/NAME, a link to a folder outside your home: the wallet gets no
#    passage through your home, unlike the sandboxed Firefox's ~/Downloads.
#  - Asked once for each wallet, off by default: a hardware wallet (a udev rule
#    gives that user those USB devices), and a camera for QR codes, only while
#    the wallet is open (bin/wallet-camera; the webcam switch still applies).
# It installs Tor if it is missing. It doesn't move wallets you already have, and
# feather, sparrow and electrum started by name still run as you, without any of
# this. See docs/extras/wallet-sandbox.md and THREAT-MODEL.md.
# Usage: bash wallet-sandbox.sh [--remove | --manual]
# summary: Wallets as their own users, on Tor only
# security: most
# status: file:/usr/local/bin/wallet
# files: bin/wallet bin/wallet-session bin/wallet-net-check bin/wallet-camera bin/wayland-restrict bin/no-abstract-sockets data/wallet-firewall.nft data/hardware-wallets.rules
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$WREN_DIR/lib/appimage.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

MARK=/etc/tor/.wren-wallet-sandbox
WALLETS=(feather sparrow electrum)
CMD=/usr/local/bin/wallet
SESSION=/usr/local/libexec/wallet-session
NETCHECK=/usr/local/libexec/wallet-net-check
CAMERA=/usr/local/libexec/wallet-camera
HOMES=/var/lib/wren-wallet
LIB=/usr/local/lib/wren-wallet
CONF=${WREN_WALLET_CONF:-/etc/wren/wallets}
SUDOERS=/etc/sudoers.d/wren-wallet
LIMITS=/etc/security/limits.d/50-wren-wallet.conf
FIREWALL=/etc/wren/wallet.nft
UNIT=/etc/systemd/system/wren-wallet-firewall.service
OWNER=$(id -un)

hw_rule() { echo "/etc/udev/rules.d/71-wren-wallet-$1.rules"; }
conf_says() { grep -qsx "$2=yes" "$CONF/$1.conf"; }

if [ "${1:-}" = --remove ]; then
    sudo systemctl disable --now wren-wallet-firewall.service >/dev/null 2>&1 || true
    sudo nft delete table inet wren_wallet 2>/dev/null || true
    remove_snippet wallet-sandbox
    sudo rm -f "$SUDOERS" "$LIMITS" "$CMD" "$SESSION" "$NETCHECK" "$CAMERA" "$FIREWALL" "$UNIT"
    for w in "${WALLETS[@]}"; do
        sudo rm -f "$(hw_rule "$w")" "$CONF/$w.conf"
    done
    sudo udevadm control --reload-rules 2>/dev/null || true
    sudo rm -rf "$LIB"
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo rmdir "$CONF" 2>/dev/null || true
    for w in "${WALLETS[@]}"; do
        if id "wallet-$w" >/dev/null 2>&1; then
            sudo pkill -KILL -u "wallet-$w" 2>/dev/null || true
            sudo userdel "wallet-$w"
            note "Removed the user wallet-$w."
        fi
    done
    sudo rm -f "$MARK"
    system_tor_wanted .wren-wallet-sandbox || tor_service_off
    if [ -L "$HOME/Wallets" ]; then rm -f "$HOME/Wallets"; fi
    remove_wayland_restrict
    remove_no_abstract
    apt_purge
    # Never deleted here: these can hold the only copy of a wallet
    warn "Your wallets are kept in $HOMES (only root can read them now). Back them up before deleting anything."
    exit
fi

first_time=true
[ ! -d "$CONF" ] || first_time=false

if $first_time && [ -e "${WREN_KVM:-/dev/kvm}" ]; then
    say "This computer can run Whonix, the safer place for wallets"
    note "In Whonix a wallet runs in a virtual machine, and a separate one forces all of it"
    note "through Tor. A hacked wallet would have to break out of the VM. This sandbox is"
    note "weaker: the wallet shares this computer's kernel. It is for computers that can't"
    note "run VMs. Whonix comes with Electrum and Feather: wrenctl install whonix"
    ask "Set up the sandbox anyway?" n || { note "Nothing was changed."; exit 0; }
fi

# Asked once, and kept: update.sh runs this again, and a choice isn't to be asked
# about again. (Change a line in $CONF and run this again.)
sudo install -d -o root -g root -m 0755 "${CONF%/*}" "$CONF"
for w in "${WALLETS[@]}"; do
    [ ! -f "$CONF/$w.conf" ] || continue
    enabled=no hardware=no camera=no
    if ask "Set up $w in the sandbox?" y; then
        enabled=yes
        note "These two haven't been tried with real devices yet. Each gives this wallet more."
        if ask "Let it use a hardware wallet over USB?" n; then hardware=yes; fi
        if ask "Let it use the camera for QR codes, while it is open?" n; then camera=yes; fi
    fi
    printf 'enabled=%s\nhardware=%s\ncamera=%s\n' "$enabled" "$hardware" "$camera" |
        sudo tee "$CONF/$w.conf" >/dev/null
done

# The wallets themselves, each from its own script, which checks its signature
enabled=()
for w in "${WALLETS[@]}"; do
    if conf_says "$w" enabled; then enabled+=("$w"); fi
done
[ ${#enabled[@]} -gt 0 ] || warn "No wallet is chosen. To add one, say enabled=yes in $CONF and run this again."
for w in "${enabled[@]}"; do
    case $w in
        feather) [ -x "$OPT/feather/usr/bin/feather" ] || bash "$WREN_DIR/extras/feather-wallet.sh" ;;
        sparrow) is_installed sparrowwallet || bash "$WREN_DIR/extras/sparrow-wallet.sh" ;;
        electrum) is_installed electrum || bash "$WREN_DIR/extras/electrum.sh" ;;
    esac
done

say "Installing cage, XWayland, xclip, Tor and the firewall's tools"
if ! is_installed tor; then
    # Debian starts tor the moment it is installed; held until the rest is in place
    sudo systemctl mask tor.service tor@default.service >/dev/null
fi
# acl: what opens the shared folder and the restricted socket to one user;
# python3: wayland-restrict, no-abstract-sockets and wallet-net-check;
# xclip: the clipboard inside the wallet's window (cage has no other way in)
apt_install cage xwayland xclip acl nftables python3 tor wl-clipboard

say "The wallets' users"
# All three, chosen or not: the firewall names them, and has to load at boot
wallet_user() {
    local user=wallet-$1
    if id "$user" >/dev/null 2>&1; then
        [ "$(id -u "$user")" -lt 1000 ] ||
            die "A regular user account called $user already exists; this needs a system user. Rename or remove it first."
    else
        sudo useradd --system --user-group --no-create-home --home-dir "$HOMES/$1" \
            --shell /usr/sbin/nologin --comment "Wren Linux $1 wallet sandbox" "$user"
    fi
    sudo usermod --lock --shell /usr/sbin/nologin "$user"
    # cage's Wayland backend opens the GPU's render node even with the software
    # renderer. Only the render group: the firewall goes by user, so no group matters.
    if getent group render >/dev/null; then sudo usermod -aG render "$user"; fi
}
for w in "${WALLETS[@]}"; do
    wallet_user "$w"
done

sudo install -d -o root -g root -m 0755 "$HOMES" "$HOMES/files"
for w in "${enabled[@]}"; do
    user=wallet-$w
    if sudo test -d "$HOMES/$w"; then
        # After a --remove and a new install it may have another user number.
        # (-h: a link in there is changed itself, not what it points at)
        sudo chown -Rh "$user:$user" "$HOMES/$w"
    fi
    sudo install -d -o "$user" -g "$user" -m 0700 "$HOMES/$w"
    # You and that wallet, nobody else; root's, so the wallet can't change that.
    # Treat what lands here as untrusted, and a link in it too.
    sudo install -d -o root -g root -m 0770 "$HOMES/files/$w"
    sudo setfacl -P -m "u:$OWNER:rwx,u:$user:rwx" "$HOMES/files/$w"
    sudo setfacl -P -d -m "u:$OWNER:rwx,u:$user:rwx" "$HOMES/files/$w"
done
if [ -e "$HOME/Wallets" ] && [ ! -L "$HOME/Wallets" ]; then
    warn "$HOME/Wallets is already there, so the folders you share with wallets are only at $HOMES/files."
else
    ln -sfn "$HOMES/files" "$HOME/Wallets"
fi

# Feather's copy: yours is in your home, which its user can't enter
if conf_says feather enabled; then
    say "Feather for the sandbox"
    sudo rm -rf "$LIB/feather.new"
    sudo install -d -o root -g root -m 0755 "$LIB"
    sudo cp -r --no-preserve=all "$OPT/feather" "$LIB/feather.new"
    sudo chown -R root:root "$LIB/feather.new"
    sudo chmod -R u+rwX,go+rX,go-w "$LIB/feather.new"
    sudo rm -rf "$LIB/feather"
    sudo mv "$LIB/feather.new" "$LIB/feather"
fi

say "The wallet command"
sudo install -d -o root -g root -m 0755 /usr/local/libexec
install_bin wayland-restrict
install_no_abstract
sudo install -o root -g root -m 0755 "$WREN_DIR/bin/wallet" "$CMD"
sudo install -o root -g root -m 0755 "$WREN_DIR/bin/wallet-session" "$SESSION"
sudo install -o root -g root -m 0755 "$WREN_DIR/bin/wallet-net-check" "$NETCHECK"
sudo install -o root -g root -m 0755 "$WREN_DIR/bin/wallet-camera" "$CAMERA"

say "What your user may run as the wallets' users"
rule=$(mktemp)
{
    printf '# Written by Wren Linux extras/wallet-sandbox.sh. %s may run the wallet session script,\n# and nothing else, as the wallets chosen.\n' "$OWNER"
    if [ ${#enabled[@]} -gt 0 ]; then
        printf '%s ALL=(%s) NOPASSWD: %s\n' "$OWNER" "$(printf 'wallet-%s,' "${enabled[@]}" | sed 's/,$//')" "$SESSION"
    fi
    # Only if a wallet has the camera: the one thing here that runs as root
    for w in "${enabled[@]}"; do
        if conf_says "$w" camera; then
            printf '%s ALL=(root) NOPASSWD: %s\n' "$OWNER" "$CAMERA"
            break
        fi
    done
} >"$rule"
# A broken sudoers file locks you out of sudo, so it is checked first
if ! sudo visudo -cf "$rule" >/dev/null; then
    rm -f "$rule"
    die "The sudoers rule didn't pass visudo's check, so it wasn't installed."
fi
sudo install -o root -g root -m 0440 "$rule" "$SUDOERS"
rm -f "$rule"

for w in "${WALLETS[@]}"; do
    printf 'wallet-%s hard nproc 4096\nwallet-%s hard core 0\n' "$w" "$w"
done | sudo tee "$LIMITS" >/dev/null

# The hardware wallets' list, for this user instead of the person at the keyboard
for w in "${WALLETS[@]}"; do
    if conf_says "$w" enabled && conf_says "$w" hardware; then
        { echo "# Written by Wren Linux extras/wallet-sandbox.sh: hardware wallets, for wallet-$w"
          grep -v '^#' "$WREN_DIR/data/hardware-wallets.rules" |
              sed "s|TAG+=\"uaccess\"|RUN+=\"/usr/bin/setfacl -m u:wallet-$w:rw- \$devnode\"|"
        } | sudo tee "$(hw_rule "$w")" >/dev/null
    else
        sudo rm -f "$(hw_rule "$w")"
    fi
done
sudo udevadm control --reload-rules 2>/dev/null || true
sudo udevadm trigger --subsystem-match=usb --subsystem-match=hidraw --action=change 2>/dev/null || true

say "Keeping the wallets on Tor"
sudo install -d -o root -g root -m 0755 "${FIREWALL%/*}"
sudo install -o root -g root -m 0644 "$WREN_DIR/data/wallet-firewall.nft" "$FIREWALL"
# Loaded before the network comes up, at every boot
printf '%s\n' '# Written by Wren Linux extras/wallet-sandbox.sh' '[Unit]' \
    'Description=Keep the sandboxed wallets on Tor (Wren Linux)' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' \
    "ExecStart=/usr/sbin/nft -f $FIREWALL" \
    'ExecStop=/usr/sbin/nft delete table inet wren_wallet' '' '[Install]' \
    'WantedBy=multi-user.target' | sudo tee "$UNIT" >/dev/null
sudo systemctl daemon-reload
# Restart, not just enable --now: the unit stays "active" after it first ran,
# so a rule file changed by an update would otherwise not be loaded
sudo systemctl enable wren-wallet-firewall.service >/dev/null &&
    sudo systemctl restart wren-wallet-firewall.service ||
    warn "Couldn't load the firewall rule, so wallets won't open; check: systemctl status wren-wallet-firewall"

printf '%s\n' 'Written by Wren Linux extras/wallet-sandbox.sh: wallets connect through the system tor service.' |
    sudo tee "$MARK" >/dev/null
# Not a restart if it runs: it may be carrying apt or remote access right now
if ! systemctl is-active --quiet tor@default.service; then
    say "Starting Tor"
    tor_service_on
fi

put_snippet wallet-sandbox <<EOF
# Move one line of text in or out of a sandboxed wallet (Wren Linux extras/wallet-sandbox.sh)
bindsym \$mod+Ctrl+w exec foot -e $CMD clip-window
EOF

for w in "${enabled[@]}"; do
    note "Open it with: wallet $w"
done
note "Set each wallet to use Tor at 127.0.0.1:9050 if it asks; it can't connect any other way."
note "Addresses: wallet clip (Super+Ctrl+w), which shows the text first. Files: ~/Wallets/NAME."
warn "A wallet's files are in $HOMES, which your backup doesn't cover: write down each seed."
