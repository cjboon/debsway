#!/bin/bash
# Your own onion site (a Tor .onion address), able to run more than static
# files: nginx in front, and either your own app server ("any") or a Python
# (Flask) app run by gunicorn ("python"). It runs on this computer, but in a
# VM with no network at all, so whatever the site does it can't give away
# this computer's address:
#  - The VM (built with the bundled mockvps-kvm, run by a locked user,
#    onion-site) can't send a packet out (QEMU's restrict=on). Two loopback
#    ports lead in: its SSH console, and its nginx, which Tor's onion service
#    points at. Its time zone is UTC; nginx shows no version and keeps no log.
#  - Tor runs on this computer (the system tor service, shared with apt over
#    Tor and remote access), with its defences against floods of visits.
#  - Public (anyone with the address) or private (only visitors you give a
#    client key; without one the site can't even be found): you choose.
#  - Security updates for the VM: onion-site update, which lends the VM this
#    computer's Tor for apt, and takes it away again.
#  - No shared folder: onion-site upload static|app FOLDER sends files in.
# What it can't hide: the site is only up while this computer is on and the VM
# runs, which can link it to you; and a hole in your app still gets the VM and
# the site's data (not this computer). See THREAT-MODEL.md. Needs KVM.
# Usage: bash onion-site.sh [--remove]
# summary: Your own onion site, in a VM with no network
# files: bin/no-abstract-sockets
# status: bin:onion-site file:/usr/local/libexec/onion-site-session
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$DEBSWAY_DIR/lib/onion-site.sh"
need_user

AGENT=$ONION_SITE_USER
AGENT_HOME=/home/$AGENT
SESSION=/usr/local/libexec/onion-site-session
MOCKVPS=/usr/local/libexec/onion-site-mockvps-kvm
SUDOERS=/etc/sudoers.d/debsway-onion-site
FIREWALL=/etc/debsway/onion-site.nft
UNIT=/etc/systemd/system/debsway-onion-site-firewall.service
SETTINGS=/etc/debsway/onion-site.conf
PROVISION_DST=$AGENT_HOME/.config/onion-site/provision.sh
TORRC=/etc/tor/torrc
SVC_DIR=$ONION_SITE_SVC_DIR
MARK=$ONION_SITE_MARK
ADDRESS=${XDG_STATE_HOME:-$HOME/.local/state}/debsway/onion-site-address

drop_torrc_block() {
    sudo sed -i "\\|^$ONION_SITE_BEGIN\$|,\\|^$ONION_SITE_END\$|d" "$TORRC" 2>/dev/null || true
}

# tor_config_ok: what Debian's tor service checks before it starts (as root,
# with Debian's defaults), so a setting tor won't take never reaches a restart
tor_config_ok() {
    sudo tor --defaults-torrc /usr/share/tor/tor-service-defaults-torrc -f "$TORRC" \
        --RunAsDaemon 0 --verify-config
}

if [ "${1:-}" = --remove ]; then
    if sudo -n -u "$AGENT" -l "$SESSION" >/dev/null 2>&1; then
        sudo -u "$AGENT" "$SESSION" stop >/dev/null 2>&1 || true
    fi
    drop_torrc_block
    sudo sed -i "\\|^# >>> debsway onion-site bridges >>>\$|,\\|^# <<< debsway onion-site bridges <<<\$|d" "$TORRC" 2>/dev/null || true
    sudo rm -f "$MARK"
    if sudo test -d "$SVC_DIR"; then
        warn "The site's .onion address lives in $SVC_DIR. Deleted, it is gone for good:"
        warn "a new site gets a different address, and visitors' client keys stop working."
        if ask "Delete the .onion address too?" n; then
            sudo rm -rf "$SVC_DIR"
            rm -f "$ADDRESS"
        else
            note "Kept $SVC_DIR (back it up as root to keep the address)."
        fi
    fi
    if system_tor_wanted .debsway-onion-site; then
        sudo systemctl restart tor@default.service >/dev/null 2>&1 || true
    else
        sudo systemctl disable --now tor@default.service >/dev/null 2>&1 || true
    fi
    remove_bin onion-site
    sudo systemctl disable --now debsway-onion-site-firewall.service >/dev/null 2>&1 || true
    sudo nft delete table inet debsway_onion_site 2>/dev/null || true
    sudo rm -f "$SUDOERS" "$SESSION" "$MOCKVPS" "$FIREWALL" "$UNIT" "$SETTINGS"
    remove_no_abstract
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo rmdir /usr/local/libexec /etc/debsway 2>/dev/null || true
    if id "$AGENT" >/dev/null 2>&1; then
        if ask "Delete the user $AGENT and its home $AGENT_HOME (the VM, with the site's files and data)?" n; then
            sudo pkill -KILL -u "$AGENT" 2>/dev/null || true
            sudo userdel -r "$AGENT" 2>/dev/null || sudo userdel "$AGENT"
            note "Removed the user $AGENT and its VM."
        else
            note "Kept the user $AGENT and $AGENT_HOME (the VM is still there)."
        fi
    fi
    apt_purge qemu-system-x86 qemu-utils socat nftables tor openssl obfs4proxy snowflake-client
    if ! system_tor_wanted && is_installed onionshare-cli; then
        sudo systemctl mask tor.service tor@default.service >/dev/null
    fi
    note "The onion site is gone."
    exit
fi

[ -e /dev/kvm ] || die "No /dev/kvm: turn on virtualization (VT-x / AMD-V) in the firmware settings."

say "Your onion site"
note "A site at a .onion address, served from a VM on this computer that has no network:"
note "only Tor reaches it. It is up while this computer is on and the VM runs (onion-site"
note "start); someone watching when it is up could link it to you. Turn it on only if you"
note "need it: it is a service strangers can send requests to."

# ---- Questions first; nothing is installed until they are answered ----
app='' access='' choice=''
if sudo test -f "$SETTINGS"; then
    app=$(sudo sed -n 's/^app=//p' "$SETTINGS")
    access=$(sudo sed -n 's/^access=//p' "$SETTINGS")
    note "Set up before: a ${access:-?} site, app: ${app:-?}. (Change it: --remove, then again.)"
fi
if [ -z "$app" ]; then
    note "What runs behind nginx:"
    note "  1) any     your own app server, listening on 127.0.0.1:8000 in the VM"
    note "  2) python  a Python (Flask) app, run by gunicorn; a small one to start from"
    tty_read choice "Which (1 or 2)? "
    case $choice in 1 | any) app=any ;; 2 | python) app=python ;; *) die "Nothing chosen, so nothing was changed." ;; esac
fi
if [ -z "$access" ]; then
    note "Who can reach it:"
    note "  1) public   anyone who has the .onion address"
    note "  2) private  only visitors you give a client key (without one it can't be found)"
    tty_read choice "Which (1 or 2)? "
    case $choice in 1 | public) access=public ;; 2 | private) access=private ;; *) die "Nothing chosen, so nothing was changed." ;; esac
fi
bridge_block=false
if ! system_tor_wanted .debsway-onion-site && ! is_installed tor; then
    say "Bridges"
    pick_bridges system-tor
    if $BRIDGE_WANTED && [ "$BRIDGE_TYPE" = none ]; then
        ask "You said you need a bridge, but none was set up. Go on without one?" n ||
            die "Stopped before changing anything. Run this again with a bridge."
    fi
    bridge_block=true
fi

say "Installing what the site needs"
# qemu + qemu-utils: the VM. socat: clean power-off, and the relay to Tor during
# updates. nftables: the rule for the onion-site user. openssh-client: into the
# VM. cpio/gzip/wget/gpgv/keyring: the checked Debian installer. tor + openssl:
# the onion service and its client keys.
# Debian starts tor the moment it is installed; hold it until its settings are in
if ! is_installed tor; then sudo systemctl mask tor.service tor@default.service >/dev/null; fi
pkgs=(qemu-system-x86 qemu-utils socat nftables openssh-client cpio gzip wget gpgv
    debian-archive-keyring tor openssl)
if $bridge_block; then
    case $BRIDGE_TYPE in
        obfs4) pkgs+=(obfs4proxy) ;;
        snowflake) pkgs+=(snowflake-client) ;;
    esac
fi
apt_install "${pkgs[@]}"

say "The $AGENT user"
if ! id "$AGENT" >/dev/null 2>&1; then
    sudo useradd --create-home --home-dir "$AGENT_HOME" --shell /bin/bash --user-group \
        --comment "debsway onion site VM" "$AGENT"
fi
sudo usermod --lock "$AGENT"
sudo chmod 700 "$AGENT_HOME"
if ! id -nG "$AGENT" | grep -qw kvm; then sudo usermod -aG kvm "$AGENT"; fi
note "$AGENT: no password, no login, in the kvm group only."

say "Keeping $AGENT off your network"
sudo install -d -o root -g root -m 0755 "${FIREWALL%/*}"
sudo install -o root -g root -m 0644 "$DEBSWAY_DIR/data/onion-site-firewall.nft" "$FIREWALL"
printf '%s\n' '# Written by debsway extras/onion-site.sh' '[Unit]' \
    'Description=Keep the onion-site user (and its VM) off the local network (debsway)' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' \
    "ExecStart=/usr/sbin/nft -f $FIREWALL" \
    'ExecStop=/usr/sbin/nft delete table inet debsway_onion_site' '' '[Install]' \
    'WantedBy=multi-user.target' | sudo tee "$UNIT" >/dev/null
sudo systemctl daemon-reload
sudo systemctl enable debsway-onion-site-firewall.service >/dev/null &&
    sudo systemctl restart debsway-onion-site-firewall.service ||
    warn "Couldn't load the firewall rule; check: systemctl status debsway-onion-site-firewall"

say "The VM engine and the onion-site command"
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 "$DEBSWAY_DIR/vendor/mockvps-kvm/mockvps-kvm.sh" "$MOCKVPS"
sudo install -o root -g root -m 0755 "$DEBSWAY_DIR/bin/onion-site-session" "$SESSION"
install_no_abstract
printf '# Written by debsway extras/onion-site.sh\napp=%s\naccess=%s\n' "$app" "$access" |
    sudo install -o root -g root -m 0644 /dev/stdin "$SETTINGS"
sudo install -d -o "$AGENT" -g "$AGENT" -m 0700 "$AGENT_HOME/.config" "$AGENT_HOME/.config/onion-site"
prov=$(mktemp)
sed -e "s|@APP@|$app|g" -e "s|@VM_USER@|site|g" "$DEBSWAY_DIR/data/onion-site-provision.sh" >"$prov"
sudo install -o "$AGENT" -g "$AGENT" -m 0600 "$prov" "$PROVISION_DST"
rm -f "$prov"
rule=$(mktemp)
printf '# Written by debsway extras/onion-site.sh. %s may run the onion-site-session script,\n# and nothing else, as the user %s.\n%s ALL=(%s) NOPASSWD: %s\n' \
    "$(id -un)" "$AGENT" "$(id -un)" "$AGENT" "$SESSION" >"$rule"
if ! sudo visudo -cf "$rule" >/dev/null; then
    rm -f "$rule"
    die "The sudoers rule didn't pass visudo's check, so it wasn't installed."
fi
sudo install -o root -g root -m 0440 "$rule" "$SUDOERS"
rm -f "$rule"
install_bin onion-site

say "The onion service"
if $bridge_block; then
    sudo sed -i "\\|^# >>> debsway onion-site bridges >>>\$|,\\|^# <<< debsway onion-site bridges <<<\$|d" "$TORRC"
    if [ "$BRIDGE_TYPE" != none ]; then
        { echo "# >>> debsway onion-site bridges >>>"; tor_bridge_config; echo "# <<< debsway onion-site bridges <<<"; } |
            sudo tee -a "$TORRC" >/dev/null
    fi
fi
sudo install -d -m 0700 -o debian-tor -g debian-tor "$SVC_DIR" "$SVC_DIR/authorized_clients"
# Tor's proof-of-work defence only where this tor has it: the config is checked
# before tor is restarted, since apt over Tor or remote access may use it too
drop_torrc_block
onion_site_torrc yes | sudo tee -a "$TORRC" >/dev/null
if ! tor_config_ok >/dev/null 2>&1; then
    drop_torrc_block
    onion_site_torrc no | sudo tee -a "$TORRC" >/dev/null
    if tor_config_ok >/dev/null 2>&1; then
        note "This tor has no proof-of-work defence; the other limits on floods are on."
    else
        drop_torrc_block
        tor_config_ok 2>&1 | tail -3 | sed 's/^/    /' >&2
        die "tor didn't accept the onion service's settings, so they were taken out again."
    fi
fi
printf '%s\n' 'Written by debsway extras/onion-site.sh: the system tor service runs the onion site.' |
    sudo tee "$MARK" >/dev/null

show_client=false
if [ "$access" = private ]; then
    if ! sudo ls "$SVC_DIR/authorized_clients" 2>/dev/null | grep -q '\.auth$' ||
        ask "Make a client key for another visitor?" n; then
        onion_add_client "$SVC_DIR"
        show_client=true
    fi
else
    if sudo ls "$SVC_DIR/authorized_clients" 2>/dev/null | grep -q '\.auth$'; then
        warn "There are client keys in $SVC_DIR/authorized_clients, so the site stays private."
    fi
fi

say "Starting Tor"
sudo systemctl unmask tor.service tor@default.service >/dev/null
sudo systemctl enable tor@default.service >/dev/null 2>&1
since=$(date '+%Y-%m-%d %H:%M:%S')
sudo systemctl restart tor@default.service
connected=false
for i in $(seq 90); do
    if tor_connected "$since" && sudo test -s "$SVC_DIR/hostname"; then connected=true; break; fi
    [ $((i % 10)) -ne 0 ] || note "Waiting for Tor ($((i * 2))s)..."
    sleep 2
done
$connected || die "Tor didn't connect in 3 minutes (a bridge that is down or wrong is the usual reason). Run this again."
onion=$(sudo cat "$SVC_DIR/hostname")
mkdir -p "${ADDRESS%/*}"
(umask 077 && printf '%s\n' "$onion" >"$ADDRESS")
note "Tor is connected. The site's address: $onion"

say "Building the VM"
if sudo test -s "$AGENT_HOME/vm/onion-site.qcow2"; then
    note "The VM is already built; kept as it is (with the site's files). For a fresh one: onion-site rebuild"
else
    what=nginx
    [ "$app" != python ] || what="nginx and gunicorn"
    note "This installs Debian and $what in the VM; it takes 5-15 minutes and"
    note "downloads a few hundred MB, without Tor. After that the VM has no network."
    if ask "Build the VM now?" y; then
        sudo -u "$AGENT" "$SESSION" install || warn "The build didn't finish. Try again with: onion-site rebuild"
    else
        note "Build it when you're ready with: onion-site rebuild"
    fi
fi

cat <<EOF

    The site:  http://$onion   (open it in Tor Browser)

    onion-site start | stop | status   the site is up while its VM runs
    onion-site upload static FOLDER    your files: they're served as they are
    onion-site upload app FOLDER       your app: $([ "$app" = python ] && echo "a Flask app, app.py with app = Flask(...)" || echo "run it on 127.0.0.1:8000 (onion-site shell)")
    onion-site shell                   a shell in the VM (as the user "site")
    onion-site update                  the VM's security updates, through Tor
    onion-site address                 the address again

    The VM has no network: the app can't fetch anything from the internet (no
    images, fonts, email or updates of its own). Anything it needs goes in with
    upload, or with apt during onion-site update.
EOF
if $show_client; then
    cat <<EOF

    CLIENT KEY, shown once and not stored here. Give it to the visitor; Tor
    Browser asks for it the first time they open the address:

      $CLIENT_PRIV

    (Run this again to make a key for another visitor.)
EOF
fi
