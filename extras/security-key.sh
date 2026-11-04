#!/bin/bash
# A hardware security key (YubiKey, Nitrokey, SoloKey, Google Titan, any FIDO2
# key): its secret is made inside the chip and never leaves it, and it answers
# only when you touch it, so malware can neither copy it nor use it for you.
#  - Linux (udev 244 and later) lets you, at the keyboard, use such a key by
#    itself: no rules from the maker are needed. Other users get none.
#  - SSH: a key whose file is only a handle, every login needing the key and a
#    touch (ssh-keygen -t ed25519-sk; tools/vps-client.sh ssh-key --security-key).
#  - Websites: two-factor login (WebAuthn) works in firefox-esr. The sandboxed
#    Firefox runs as other users; if you say yes, a udev rule lets them (the
#    group wren-fx) reach the key too (data/security-key-firefox.rules).
#  - sudo, if you say yes (or later: --sudo): your password AND a touch of the
#    key (pam_u2f). The keys it takes are listed in /etc/wren/u2f_keys, a file
#    only root can change, so nothing running as you can add one of its own. It
#    is tried in a PAM service of its own first, and the change to sudo undoes
#    itself after 3 minutes unless sudo then works with your password and a
#    touch. Register a second key as a backup: lose them all and sudo is closed
#    to you (docs/extras/security-key.md says how to get back in).
# Usage: bash security-key.sh [--remove | --manual | --sudo | --sudo-off]
# summary: Hardware security keys (FIDO2): SSH, web, sudo
# security: most
# files: data/security-key-firefox.rules
# status: apt:fido2-tools apt:pamu2fcfg
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

# (a test puts these in a folder of its own)
ROOT=${WREN_SK_ROOT:-}
RULE=$ROOT/etc/udev/rules.d/72-wren-security-key-firefox.rules
KEYS=$ROOT/etc/wren/u2f_keys
TEST_PAM=$ROOT/etc/pam.d/wren-u2f-test
SUDO_PAM=$ROOT/etc/pam.d/sudo
PENDING=$ROOT/run/wren-u2f-pending
MARK='# Wren Linux extras/security-key.sh: sudo takes your password and a touch of your key'
U2F="auth required pam_u2f.so authfile=$KEYS origin=pam://wren appid=pam://wren cue nouserok"
ME=$(id -un)

# sudo_on: the key for sudo, after registering it and trying it
sudo_on() {
    command -v pamu2fcfg >/dev/null || die "pamu2fcfg is missing: run this script without --sudo first."
    if sudo grep -qxF "$MARK" "$SUDO_PAM" 2>/dev/null; then
        note "sudo takes your key already. To register another (a backup) key, run --sudo-off, then --sudo."
        return 0
    fi
    say "sudo: your password and a touch of your key"
    note "Every sudo then needs both, so a program that learned your password still can't"
    note "use it. Lose every registered key and sudo is closed to you: register a backup key"
    note "now if you have one (docs/extras/security-key.md says how to get back in without)."
    ask "Set it up now (plug the key in first)?" n || { note "Later: wrenctl install security-key --sudo"; return 0; }
    local line more new
    note "Touch the key when it blinks."
    line=$(pamu2fcfg -u "$ME" -o pam://wren -i pam://wren) || die "The key didn't answer; nothing was changed."
    [[ $line == "$ME:"* ]] || die "pamu2fcfg said something unexpected; nothing was changed."
    while ask "Register another key, as a backup (swap the keys now)?" y; do
        note "Touch the other key when it blinks."
        more=$(pamu2fcfg -n -o pam://wren -i pam://wren) && line+=$more || warn "That key didn't answer; it wasn't added."
    done
    # The list, root's: your line replaced, other users' kept
    new=$(mktemp)
    { sudo cat "$KEYS" 2>/dev/null | grep -v "^$ME:" || true; printf '%s\n' "$line"; } >"$new"
    sudo install -d -o root -g root -m 0755 "${KEYS%/*}"
    sudo install -o root -g root -m 0644 "$new" "$KEYS"
    rm -f "$new"

    say "Trying it, in a PAM service of its own (sudo isn't changed yet)"
    printf '# Written by Wren Linux extras/security-key.sh, to try the key before sudo uses it\n%s\naccount required pam_permit.so\n' \
        "${U2F% nouserok}" | sudo tee "$TEST_PAM" >/dev/null
    note "Touch the key when it blinks."
    if ! pamtester wren-u2f-test "$ME" authenticate; then
        sudo rm -f "$TEST_PAM"
        die "The key wasn't accepted, so sudo was left as it was."
    fi
    sudo rm -f "$TEST_PAM"

    say "sudo takes it now; it undoes itself in 3 minutes unless sudo works with it"
    sudo cp -p "$SUDO_PAM" "$SUDO_PAM.wren-old"
    sudo touch "$PENDING"
    sudo systemd-run --quiet --unit=wren-u2f-rollback --on-active=3min \
        /bin/sh -c "if [ -e $PENDING ]; then cp -p $SUDO_PAM.wren-old $SUDO_PAM; rm -f $PENDING; logger -t wren 'security key: sudo put back, not confirmed'; fi"
    new=$(mktemp)
    # right after the password (common-auth): both are needed
    awk -v mark="$MARK" -v line="$U2F" '{ print } /^@include common-auth/ && !done { print mark; print line; done = 1 }' "$SUDO_PAM" >"$new"
    grep -qxF "$U2F" "$new" || { rm -f "$new"; sudo rm -f "$PENDING"; die "$SUDO_PAM has no @include common-auth line; it was left as it was."; }
    sudo install -o root -g root -m 0644 "$new" "$SUDO_PAM"
    rm -f "$new"
    note "Now sudo asks your password, then wants a touch of the key:"
    sudo -k
    if sudo rm -f "$PENDING"; then
        sudo systemctl stop wren-u2f-rollback.timer 2>/dev/null || true
        sudo rm -f "$SUDO_PAM.wren-old"
        note "Confirmed: sudo takes your password and your key."
    else
        warn "That didn't work: in 3 minutes sudo takes your password alone again, by itself."
        exit 1
    fi
}

sudo_off() {
    if ! sudo grep -qxF "$MARK" "$SUDO_PAM" 2>/dev/null; then note "sudo doesn't take the key; nothing to undo."; return 0; fi
    local new
    new=$(mktemp)
    grep -vxF -e "$MARK" -e "$U2F" "$SUDO_PAM" >"$new"
    sudo install -o root -g root -m 0644 "$new" "$SUDO_PAM"
    rm -f "$new"
    # your keys out of the list (other users' stay)
    new=$(mktemp)
    sudo cat "$KEYS" 2>/dev/null | grep -v "^$ME:" >"$new" || true
    if [ -s "$new" ]; then sudo install -o root -g root -m 0644 "$new" "$KEYS"; else sudo rm -f "$KEYS"; fi
    rm -f "$new"
    note "sudo takes your password alone again."
}

case ${1:-} in
    --sudo) sudo_on; exit ;;
    --sudo-off) sudo_off; exit ;;
    --remove)
        sudo_off
        sudo rm -f "$RULE" "$TEST_PAM"
        sudo udevadm control --reload-rules 2>/dev/null || true
        apt_purge fido2-tools pamu2fcfg libpam-u2f pamtester
        note "The keys themselves are untouched; SSH keys made with them stay in ~/.ssh."
        exit ;;
    "") ;;
    *) die "Usage: bash security-key.sh [--remove | --manual | --sudo | --sudo-off]" ;;
esac

say "Security keys (FIDO2)"
# libfido2: what ssh and the tools talk to the key with; pamtester: tries
# the sudo setting before sudo uses it
apt_install libfido2-1 fido2-tools libpam-u2f pamu2fcfg pamtester acl
note "Linux lets you, at the keyboard, use the key by itself; other users get none."

say "Website logins in the sandboxed Firefox"
note "Two-factor login with the key (WebAuthn) works in firefox-esr. The sandboxed Firefox"
note "runs as other users, which can't reach the key unless you let them: then any of its"
note "profiles can ask for a login with it, and each one still needs a touch."
if ask "Let the sandboxed Firefox use the key for website logins?" y; then
    sudo install -o root -g root -m 0644 "$WREN_DIR/data/security-key-firefox.rules" "$RULE"
    sudo udevadm control --reload-rules 2>/dev/null || true
    sudo udevadm trigger --subsystem-match=hidraw --action=change 2>/dev/null || true
    note "Done: plug the key in (again) and it works there too."
else
    sudo rm -f "$RULE"
    sudo udevadm control --reload-rules 2>/dev/null || true
fi

say "SSH with the key"
note "ssh-keygen -t ed25519-sk -f ~/.ssh/NAME   (the file is only a handle: every login needs the key)"
note "For the Wren Linux VPS: bash ~/wren-linux/tools/vps-client.sh ssh-key --security-key"

sudo_on
