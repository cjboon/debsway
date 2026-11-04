#!/bin/bash
# vps-client.sh: your computer's side of tools/setup-vps.sh. As you; it runs
# no sudo, and prints the few root commands that need it for you to run.
#   keygen [NAME]          the onion client key: only a computer that has its
#                          private half can even find the server's SSH onion
#                          address. Keeps that half in ~/.config/wren/vps/NAME.key
#                          (yours alone) and prints the public half, for
#                          setup-vps.sh's VPS_ONION_SSH_CLIENT.
#   ssh-key [--security-key]   an SSH key for the server, ~/.ssh/wren-vps (it
#                          asks a passphrase for it), and prints its public
#                          line. --security-key: one that needs your hardware
#                          key and a touch for every login (extras/security-key.sh)
#   tor-auth ONION [NAME]  Tor's client file for that onion address, and the
#                          root commands that give it to this computer's Tor
#   ssh-config USER ONION [HOST]   the ~/.ssh/config entry that reaches the server
#                          through Tor (ssh HOST then works; HOST: wren-vps)
# NAME is the server's name for the key files (default: wren-vps).
# Usage: bash tools/vps-client.sh keygen | ssh-key [--security-key] | tor-auth ONION | ssh-config USER ONION
set -euo pipefail
umask 077

die() { printf 'vps-client: %s\n' "$*" >&2; exit 1; }
note() { printf '    %s\n' "$*"; }
DIR=${XDG_CONFIG_HOME:-$HOME/.config}/wren/vps
name_ok() { [[ $1 =~ ^[a-z][a-z0-9-]{0,30}$ ]] || die "a name is small letters, digits and dashes: \"$1\" isn't one."; }
onion_ok() { [[ $1 =~ ^[a-z2-7]{56}(\.onion)?$ ]] || die "\"$1\" isn't an onion address (56 letters and digits 2-7, then .onion)."; }
b32() { python3 -I -c 'import base64,sys; print(base64.b32encode(sys.stdin.buffer.read()[-32:]).decode().rstrip("="))'; }

keygen() {
    local name=${1:-wren-vps} der pub
    name_ok "$name"
    command -v openssl >/dev/null || die "openssl is missing (sudo apt install openssl)."
    mkdir -p "$DIR"
    chmod 700 "$DIR"
    [ ! -e "$DIR/$name.key" ] || die "$DIR/$name.key exists already; its public half: bash $0 keygen-show $name"
    der=$(mktemp)
    openssl genpkey -algorithm X25519 -outform DER -out "$der" 2>/dev/null || { rm -f "$der"; die "openssl couldn't make the key."; }
    b32 <"$der" >"$DIR/$name.key"
    pub=$(openssl pkey -inform DER -in "$der" -pubout -outform DER | b32)
    rm -f "$der"
    printf '%s\n' "$pub" >"$DIR/$name.pub"
    note "The private half is in $DIR/$name.key (yours alone): back it up with your other keys."
    note "For setup-vps.sh, VPS_ONION_SSH_CLIENT:"
    echo "$pub"
}
keygen_show() { local name=${1:-wren-vps}; name_ok "$name"; cat "$DIR/$name.pub" 2>/dev/null || die "no key called $name: bash $0 keygen $name"; }

ssh_key() {
    local f=$HOME/.ssh/wren-vps type=ed25519
    case ${1:-} in
        "") ;;
        --security-key) type=ed25519-sk ;;
        *) die "ssh-key takes only --security-key." ;;
    esac
    if [ -f "$f" ] && [ "$type" = ed25519-sk ] && ! grep -q '^sk-ssh-ed25519@openssh.com ' "$f.pub"; then
        die "$f is a plain key already; move it away first (and remove it from the server once the new one works)."
    fi
    if [ ! -f "$f" ]; then
        command -v ssh-keygen >/dev/null || die "ssh-keygen is missing (sudo apt install openssh-client)."
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        if [ "$type" = ed25519-sk ]; then
            note "Plug the key in and touch it when it blinks. The file is only a handle: every login"
            note "needs the key too. A passphrase on the file is optional then (it asks twice):"
        else
            note "A passphrase protects the key if this computer is ever lost (it asks twice):"
        fi
        ssh-keygen -q -t "$type" -a 100 -C "wren-vps" -f "$f"
    fi
    note "For setup-vps.sh, VPS_SSH_KEY:"
    cat "$f.pub"
}

tor_auth() {
    local onion=${1:-} name=${2:-wren-vps}
    onion_ok "$onion"
    name_ok "$name"
    onion=${onion%.onion}
    [ -s "$DIR/$name.key" ] || die "no client key called $name yet: bash $0 keygen $name"
    printf '%s:descriptor:x25519:%s\n' "$onion" "$(cat "$DIR/$name.key")" >"$DIR/$name.auth_private"
    note "Tor's client file: $DIR/$name.auth_private"
    note "This computer's Tor (the system one, which ssh goes through) needs it. As your user, run:"
    cat <<EOF
sudo apt install tor netcat-openbsd
sudo install -d -m 0700 -o debian-tor -g debian-tor /var/lib/tor/onion_auth
sudo install -m 0600 -o debian-tor -g debian-tor $DIR/$name.auth_private /var/lib/tor/onion_auth/
grep -qx 'ClientOnionAuthDir /var/lib/tor/onion_auth' /etc/tor/torrc || echo 'ClientOnionAuthDir /var/lib/tor/onion_auth' | sudo tee -a /etc/tor/torrc
sudo systemctl restart tor
EOF
}

ssh_config() {
    local user=${1:-} onion=${2:-} host=${3:-wren-vps}
    [[ $user =~ ^[a-z][a-z0-9-]{0,30}$ ]] || die "\"$user\" isn't a user name (the one setup-vps.sh made, e.g. wren)."
    onion_ok "$onion"
    name_ok "$host"
    onion=${onion%.onion}.onion
    note "Add this to ~/.ssh/config, then: ssh $host"
    cat <<EOF
Host $host
    HostName $onion
    User $user
    IdentityFile ~/.ssh/wren-vps
    IdentitiesOnly yes
    # through this computer's Tor (tor-auth sets it up)
    ProxyCommand nc -X 5 -x 127.0.0.1:9050 %h %p
    ServerAliveInterval 30
EOF
}

case ${1:-} in
    keygen) keygen "${2:-}" ;;
    keygen-show) keygen_show "${2:-}" ;;
    ssh-key) ssh_key "${2:-}" ;;
    tor-auth) tor_auth "${2:-}" "${3:-}" ;;
    ssh-config) ssh_config "${2:-}" "${3:-}" "${4:-}" ;;
    -h | --help | "") sed -n '2,/^set -euo/{ /^set -euo/d; s/^# \{0,1\}//; p }' "$0" ;;
    *) die "unknown command \"$1\" (--help)." ;;
esac
