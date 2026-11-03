#!/bin/bash
# debsway's signing key, held by a user of its own. For the computer you
# publish debsway from: every debsway computer checks updates against this
# key (update.sh, and apt for the package), so it is kept the careful way:
#  - debsway-signer, a system user with no password, no login and no network
#    (a firewall rule drops everything it sends), holds the signing subkey in
#    /var/lib/debsway-signer, which your own user can't read: a program running
#    as you can't copy the key.
#  - Your user may run one program as debsway-signer, the signer
#    (/usr/local/libexec/debsway-signer), and only after your sudo password,
#    so that program can't sign without you either. It signs, gives the public
#    key, and makes or renews the key; it never hands out a secret key.
#  - The primary key, which vouches for the signing subkey, lives only in the
#    backup the first run of debsway-key writes to your USB stick, encrypted
#    with a passphrase of yours.
#  - debsway-key (the command): the first run asks its questions and makes the
#    key and its backup; then git signs every commit (debsway-key git-setup),
#    pins.sh names the key (debsway-key pin), and debsway-key sign-repo signs
#    the apt repository. man debsway-key has the rest.
# Usage: bash signing-key.sh [--remove | --manual]
# summary: debsway's signing key, kept by a user of its own
# security: most
# status: file:/usr/local/libexec/debsway-signer
# files: bin/debsway-signer bin/debsway-key bin/debsway-key-gpg data/signer-firewall.nft data/debsway-key.1
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

NAME=debsway-signer
HOME_DIR=/var/lib/debsway-signer
SIGNER=/usr/local/libexec/debsway-signer
SUDOERS=/etc/sudoers.d/debsway-signer
FIREWALL=/etc/debsway/signer.nft
UNIT=/etc/systemd/system/debsway-signer-firewall.service
MAN=$HOME/.local/share/man/man1/debsway-key.1

if [ "${1:-}" = --remove ]; then
    $SUDO rm -f "$SUDOERS" "$SIGNER"
    remove_bin debsway-key
    remove_bin debsway-key-gpg
    rm -f "$MAN"
    note "debsway-key and the signer are gone; nothing can sign with the key now."
    if id "$NAME" >/dev/null 2>&1; then
        warn "The signing subkey is still in $HOME_DIR (the user $NAME, off the network)."
        warn "Delete it only if your backup is safe: without the subkey you sign nothing until"
        warn "you install this again and renew it from the backup (debsway-key renew)."
        if ask "Delete the user $NAME and the signing subkey in $HOME_DIR?" n; then
            $SUDO pkill -KILL -u "$NAME" 2>/dev/null || true
            $SUDO userdel "$NAME"
            $SUDO rm -rf "$HOME_DIR"
            $SUDO systemctl disable --now debsway-signer-firewall.service >/dev/null 2>&1 || true
            $SUDO nft delete table inet debsway_signer 2>/dev/null || true
            $SUDO rm -f "$FIREWALL" "$UNIT"
            $SUDO systemctl daemon-reload >/dev/null 2>&1 || true
            note "Deleted. The key lives on in your backup only."
        else
            note "Kept, still off the network. This again brings the rest back."
        fi
    fi
    apt_purge
    exit
fi

say "debsway's signing key, kept by a user of its own"
# gpg makes and uses the key; nftables keeps its user off every network
apt_install gpg gpg-agent nftables

# The firewall first, so the user never has a moment on the network
$SUDO install -D -o root -g root -m 0644 "$DEBSWAY_DIR/data/signer-firewall.nft" "$FIREWALL"
printf '%s\n' '# Written by debsway extras/signing-key.sh' '[Unit]' \
    'Description=Keep debsway-signer, which holds the signing key, off every network (debsway)' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' \
    "ExecStart=/usr/sbin/nft -f $FIREWALL" \
    'ExecStop=/usr/sbin/nft delete table inet debsway_signer' '' '[Install]' \
    'WantedBy=multi-user.target' | $SUDO tee "$UNIT" >/dev/null

say "The $NAME user"
if id "$NAME" >/dev/null 2>&1; then
    [ "$(id -u "$NAME")" -lt 1000 ] ||
        die "A regular user account called $NAME already exists; this needs a system user. Rename or remove it first."
else
    $SUDO useradd --system --user-group --home-dir "$HOME_DIR" --no-create-home \
        --shell /usr/sbin/nologin --comment "debsway signing key, off the network" "$NAME"
fi
# No password to guess, no shell to log in with, no group but its own
$SUDO usermod --lock --shell /usr/sbin/nologin "$NAME"
$SUDO install -d -o "$NAME" -g "$NAME" -m 0700 "$HOME_DIR"
# (the rule names the user, so it can load only once the user exists)
$SUDO systemctl daemon-reload
$SUDO systemctl enable debsway-signer-firewall.service >/dev/null &&
    $SUDO systemctl restart debsway-signer-firewall.service ||
    die "The firewall rule for $NAME didn't load (systemctl status debsway-signer-firewall), so the signer isn't installed: it must never be on the network."
note "$NAME: no password, no login, no network; $HOME_DIR is its alone."

say "The signer, and what your user may run as $NAME"
$SUDO install -d -o root -g root -m 0755 /usr/local/libexec
$SUDO install -o root -g root -m 0755 "$DEBSWAY_DIR/bin/debsway-signer" "$SIGNER"
rule=$(mktemp)
# Not NOPASSWD: signing asks for your password (sudo remembers it for a few
# minutes in that terminal), so a program running as you can't sign
printf '# Written by debsway extras/signing-key.sh. %s may run the signer, and nothing\n# else, as debsway-signer, after typing the password.\n%s ALL=(%s) %s\n' \
    "$(id -un)" "$(id -un)" "$NAME" "$SIGNER" >"$rule"
if ! $SUDO visudo -cf "$rule" >/dev/null; then
    rm -f "$rule"
    die "The sudoers rule didn't pass visudo's check, so it wasn't installed."
fi
$SUDO install -o root -g root -m 0440 "$rule" "$SUDOERS"
rm -f "$rule"

say "The debsway-key command"
install_bin debsway-key
install_bin debsway-key-gpg
install -D -m 0644 "$DEBSWAY_DIR/data/debsway-key.1" "$MAN"
note "Run debsway-key to make the key and its backup (have a USB stick ready)."
note "man debsway-key says what else it does."
