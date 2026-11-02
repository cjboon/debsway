#!/bin/bash
# An encrypted folder in your home, ~/Vault, that locks itself. Its files are
# kept encrypted by gocryptfs (from Debian; independently audited) in
# ~/.local/share/debsway-vault, and appear in ~/Vault only while it is open,
# with a password of its own. Closed, its key isn't in memory: a laptop taken
# while it is switched on and locked doesn't give those files away, though the
# disk's own encryption is unlocked by then.
#  - vault open: open for an hour (vault open --for 2h, or --no-timeout).
#  - It closes itself when its time is up, and whenever the screen locks:
#    debsway's idle lock and the lock before sleep run it first
#    (~/.config/debsway/on-lock.d/vault), and its timer notices Super+Escape,
#    the lid or the power menu within seconds.
#  - It needs fuse3, whose fusermount3 is setuid root: one small, widely used
#    program from Debian, the price of an encrypted folder you open without sudo.
# Usage: bash vault.sh [--remove | --manual]
# summary: An encrypted ~/Vault that locks itself
# security: most
# status: bin:vault
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

CIPHER=$HOME/.local/share/debsway-vault
MNT=$HOME/Vault
HOOK=${XDG_CONFIG_HOME:-$HOME/.config}/debsway/on-lock.d/vault

if [ "${1:-}" = --remove ]; then
    if [ -x "$BIN/vault" ]; then "$BIN/vault" close quiet || true; fi
    rm -f "$HOOK"
    remove_bin vault
    apt_purge gocryptfs
    note "The encrypted files stay in $CIPHER; nothing was deleted."
    note "To open them again later: gocryptfs $CIPHER $MNT"
    exit
fi

say "Installing gocryptfs"
apt_install gocryptfs
install_bin vault
mkdir -p "${HOOK%/*}"
# shellcheck disable=SC2016  # $HOME is for the hook to expand
printf '#!/bin/sh\n# Written by debsway extras/vault.sh: the screen is about to lock, so the vault closes\nexec "$HOME/.local/bin/vault" close quiet\n' >"$HOOK"
chmod 755 "$HOOK"

if [ -f "$CIPHER/gocryptfs.conf" ]; then
    note "The vault is already made ($CIPHER)."
else
    say "Making the vault"
    note "Choose its password: a long one you don't use anywhere else (diceware -n 6 makes one)."
    note "gocryptfs then shows a master key: write it down and keep it apart from the laptop."
    note "It opens the vault if you forget the password; anyone who has it can too."
    mkdir -p "$CIPHER"
    chmod 700 "$CIPHER"
    # (without -q, which may hide the master key it prints)
    gocryptfs -init "$CIPHER" </dev/tty || { rmdir "$CIPHER" 2>/dev/null || true; die "The vault wasn't made."; }
fi
mkdir -p "$MNT"
chmod 700 "$MNT"
note "Open it with: vault open   (for an hour; vault open --for 2h, or --no-timeout)"
note "It closes itself when its time is up or the screen locks. vault close closes it now."
if [ ! -x "$HOME/.local/bin/debsway-idle" ] || ! grep -q 'on-lock.d' "$HOME/.local/bin/debsway-idle"; then
    warn "debsway's idle lock here doesn't run on-lock programs yet: run bash ~/debsway/update.sh"
    warn "(until then the vault closes within seconds of the lock, but not before the laptop sleeps)."
fi
