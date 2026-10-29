#!/bin/bash
# Remote access: ssh into this computer from another one over a Tor onion
# service, with no port open on the firewall. sshd listens on 127.0.0.1
# only (key login only, your user only); Tor makes an outgoing connection to
# the Tor network and passes ssh through it to the address abcd...xyz.onion.
# The onion service also needs a client key (Tor's client authorization), so
# nobody without it can even see that the service exists. The private half is
# shown once, here, for you to copy to the computer you'll connect from.
# Like apt over Tor, it asks first whether you need a bridge to reach Tor.
# Run it again to repair it, see the address, or authorize another computer.
# Usage: bash remote-access.sh [--remove]
# summary: ssh in over a Tor onion service (no open port)
# status: file:/etc/tor/.debsway-remote-access
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

MARK=/etc/tor/.debsway-remote-access
TORRC=/etc/tor/torrc
SVC_DIR=/var/lib/tor/debsway-ssh
# 00-: sshd takes the first value it finds for a setting and reads the files in
# sshd_config.d in name order, so a drop-in named 60- lost to any earlier one
SSHD_CONF=/etc/ssh/sshd_config.d/00-debsway-remote-access.conf
OLD_SSHD_CONF=/etc/ssh/sshd_config.d/60-debsway-remote-access.conf
BEGIN='# >>> debsway remote-access >>>'
END='# <<< debsway remote-access <<<'
BR_BEGIN='# >>> debsway remote-access bridges >>>'
BR_END='# <<< debsway remote-access bridges <<<'

drop_torrc_blocks() {
    sudo sed -i "\\|^$BEGIN\$|,\\|^$END\$|d; \\|^$BR_BEGIN\$|,\\|^$BR_END\$|d" "$TORRC" 2>/dev/null || true
}

if [ "${1:-}" = --remove ]; then
    if sudo test -d "$SVC_DIR"; then
        warn "This deletes this computer's onion address for good: a new setup gets a different one,"
        warn "and every computer you set up to connect has to be given the new address and key."
        ask "Remove remote access and delete the onion address?" n || { note "Nothing was changed."; exit 1; }
    fi
    sudo rm -f "$SSHD_CONF" "$OLD_SSHD_CONF"
    drop_torrc_blocks
    sudo rm -rf "$SVC_DIR"
    sudo rm -f "$MARK"
    if system_tor_wanted .debsway-remote-access; then
        sudo systemctl restart tor@default.service >/dev/null 2>&1 || true
    else
        sudo systemctl disable --now tor@default.service >/dev/null 2>&1 || true
    fi
    # Takes sshd back off 127.0.0.1 if it stays installed (a bare restart is fine)
    if is_installed openssh-server; then sudo systemctl restart ssh.service >/dev/null 2>&1 || true; fi
    apt_purge openssh-server tor openssl obfs4proxy snowflake-client
    # OnionShare keeps the system tor service off
    if ! system_tor_wanted .debsway-remote-access && is_installed onionshare-cli; then
        sudo systemctl mask tor.service tor@default.service >/dev/null
    fi
    note "Remote access is off and its onion address is gone."
    exit
fi

say "Remote access over Tor"
note "ssh into this computer from another, through a Tor onion service. No port is"
note "opened on the firewall; ssh listens on this computer only (127.0.0.1) and Tor"
note "carries the connection. This is a service other computers can try to reach"
note "(only with your keys), so turn it on only if you need it."

# ---- Questions first; nothing is installed until they are answered ----
if [ -n "${SSH_CONNECTION:-}" ]; then
    warn "You are logged in over ssh right now. This moves ssh to 127.0.0.1, so you could"
    warn "not log in that way again: only through Tor, or at this computer's own screen."
    ask "Go on?" n || die "Stopped before changing anything."
fi
AUTH_KEYS="$HOME/.ssh/authorized_keys"
if ! grep -qE '^(ssh-|ecdsa-|sk-)' "$AUTH_KEYS" 2>/dev/null; then
    say "Your ssh key"
    note "ssh here accepts keys only, no passwords. On the computer you'll connect from, run:"
    note "  ssh-keygen -t ed25519      then show the public half:  cat ~/.ssh/id_ed25519.pub"
    note "and paste that one line (it starts with ssh-ed25519)."
    tty_read pubkey "    public key> "
    pubkey=${pubkey%$'\r'}
    [ -n "$pubkey" ] || die "No key given. Run this again when you have one."
    keytmp=$(mktemp)
    printf '%s\n' "$pubkey" >"$keytmp"
    ssh-keygen -l -f "$keytmp" >/dev/null 2>&1 || { rm -f "$keytmp"; die "That doesn't look like an ssh public key."; }
    rm -f "$keytmp"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"
    printf '%s\n' "$pubkey" >>"$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
    note "Added it to $AUTH_KEYS"
fi

new_install=false
[ -f "$MARK" ] || new_install=true
bridge_block=false
# (a tor that another script set up already has its bridges)
if $new_install && ! system_tor_wanted .debsway-remote-access && ! is_installed tor; then
    say "Bridges"
    pick_bridges system-tor
    if $BRIDGE_WANTED && [ "$BRIDGE_TYPE" = none ]; then
        warn "You said you need a bridge, but none was set up: Tor would connect to the Tor"
        warn "network directly, and your network could see that you use Tor."
        ask "Go on without a bridge?" n || die "Stopped before changing anything. Run this again with a bridge."
    fi
    bridge_block=true
fi

# ---- sshd first, so that it never listens on anything but 127.0.0.1 ----
say "Setting up ssh"
sudo mkdir -p "${SSHD_CONF%/*}"
sudo rm -f "$OLD_SSHD_CONF"
sudo tee "$SSHD_CONF" >/dev/null <<EOF
# Written by debsway extras/remote-access.sh
ListenAddress 127.0.0.1
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers $USER
EOF

# Debian starts tor the moment it is installed; hold it until its bridge is in place
if ! is_installed tor; then sudo systemctl mask tor.service tor@default.service >/dev/null; fi
pkgs=(openssh-server tor openssl)
if $bridge_block; then
    case $BRIDGE_TYPE in
        obfs4) pkgs+=(obfs4proxy) ;;
        snowflake) pkgs+=(snowflake-client) ;;
    esac
fi
say "Installing ${pkgs[*]}"
apt_install "${pkgs[@]}"

# Debian can run sshd from a socket, which ignores ListenAddress
if systemctl is-enabled ssh.socket >/dev/null 2>&1; then
    sudo systemctl disable --now ssh.socket >/dev/null 2>&1 || true
    sudo systemctl enable ssh.service >/dev/null 2>&1 || true
fi
sudo sshd -t || { sudo rm -f "$SSHD_CONF"; die "sshd didn't accept its settings, so they were removed. Nothing is open."; }
# Ask sshd what it will really do: another file could still override ours
problems=$(sudo sshd -T 2>/dev/null | sshd_problems "$USER") || problems="could not read sshd's settings (sshd -T)"
if [ -n "$problems" ]; then
    sudo systemctl stop ssh.service ssh.socket >/dev/null 2>&1 || true
    warn "sshd would not do what this needs:"
    while IFS= read -r line; do warn "  $line"; done <<<"$problems"
    die "ssh was stopped. Find what sets these first (grep -ri -e PasswordAuthentication -e ListenAddress -e AllowUsers /etc/ssh/), then run this again."
fi
sudo systemctl restart ssh.service
listening=$(ss -Hltn 'sport = :22' | awk '{ print $4 }' | grep -vE '^(127\.0\.0\.1|\[::1\]):22$' || true)
if [ -n "$listening" ]; then
    warn "ssh also listens on: $(paste -sd" " <<<"$listening")"
    warn "Another sshd setting overrides the one debsway wrote. The firewall still blocks it,"
    warn "but fix it (ListenAddress in /etc/ssh/sshd_config) before using this."
else
    note "ssh listens on 127.0.0.1 only, key login only, for $USER only."
fi

# ---- Tor and the onion service ----
say "Setting up the onion service"
if $bridge_block; then
    sudo sed -i "\\|^$BR_BEGIN\$|,\\|^$BR_END\$|d" "$TORRC"
    if [ "$BRIDGE_TYPE" != none ]; then
        { echo "$BR_BEGIN"; tor_bridge_config; echo "$BR_END"; } | sudo tee -a "$TORRC" >/dev/null
    fi
fi
sudo sed -i "\\|^$BEGIN\$|,\\|^$END\$|d" "$TORRC"
{
    echo "$BEGIN"
    echo "HiddenServiceDir $SVC_DIR/"
    echo "HiddenServiceVersion 3"
    echo "HiddenServicePort 22 127.0.0.1:22"
    echo "$END"
} | sudo tee -a "$TORRC" >/dev/null
sudo install -d -m 0700 -o debian-tor -g debian-tor "$SVC_DIR" "$SVC_DIR/authorized_clients"
printf '%s\n' 'Written by debsway extras/remote-access.sh: ssh over a Tor onion service.' | sudo tee "$MARK" >/dev/null

# A client key: its public half goes to Tor here, the private half is
# shown once for the computer that will connect (the x25519 keys Tor wants,
# as base32 without padding)
add_client() {
    local tmp pub priv name
    tmp=$(mktemp)
    openssl genpkey -algorithm x25519 -outform DER -out "$tmp"
    priv=$(tail -c 32 "$tmp" | base32 | tr -d =)
    pub=$(openssl pkey -inform DER -in "$tmp" -pubout -outform DER | tail -c 32 | base32 | tr -d =)
    rm -f "$tmp"
    name=client-$(date +%Y%m%d-%H%M%S)
    printf 'descriptor:x25519:%s\n' "$pub" | sudo tee "$SVC_DIR/authorized_clients/$name.auth" >/dev/null
    sudo chown debian-tor:debian-tor "$SVC_DIR/authorized_clients/$name.auth"
    sudo chmod 600 "$SVC_DIR/authorized_clients/$name.auth"
    CLIENT_PRIV=$priv
}

if ! sudo ls "$SVC_DIR/authorized_clients" 2>/dev/null | grep -q '\.auth$'; then
    add_client
    show_client=true
elif ask "Authorize another computer (makes a new client key)?" n; then
    add_client
    show_client=true
else
    show_client=false
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
if ! $connected; then
    sudo journalctl _COMM=tor -n 5 --no-pager 2>/dev/null | sed 's/^/    /' >&2 || true
    die "Tor didn't connect in 3 minutes (a bridge that is down or wrong is the usual reason). Run this again."
fi
onion=$(sudo cat "$SVC_DIR/hostname")
note "Tor is connected."

say "Done"
cat <<EOF
    This computer's address:  $onion
    Back up $SVC_DIR (as root): whoever has it can be this address;
    without it a reinstall gets a new one.
EOF
if $show_client; then
    cat <<EOF

    CLIENT KEY, shown once and not stored here. On the computer you'll connect
    from, which needs Tor and netcat-openbsd (sudo apt install tor netcat-openbsd), do:

      sudo install -d -m 0700 -o debian-tor -g debian-tor /var/lib/tor/onion_auth
      echo '${onion%.onion}:descriptor:x25519:$CLIENT_PRIV' | \\
        sudo tee /var/lib/tor/onion_auth/debsway.auth_private
      echo 'ClientOnionAuthDir /var/lib/tor/onion_auth' | sudo tee -a /etc/tor/torrc
      sudo systemctl restart tor@default

    then add this to ~/.ssh/config there:

      Host debsway
        HostName $onion
        User $USER
        ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p

    and connect with:  ssh debsway
    (The first connection through Tor can take a few seconds.)
EOF
else
    cat <<EOF

    Connect from a computer set up with its client key:  ssh debsway
    (Run this again to authorize another computer.)
EOF
fi
cat <<'EOF'

    The firewall is unchanged: nothing is open for it. Turn it off with:
      bash extras/remote-access.sh --remove
EOF
