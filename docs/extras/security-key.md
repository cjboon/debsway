# Hardware security keys (`extras/security-key.sh`)

## SYNOPSIS

```
wrenctl install security-key            set it up (asks about the sandboxed Firefox, and sudo)
wrenctl install security-key --sudo     sudo takes your password and a touch of the key
wrenctl install security-key --sudo-off sudo takes your password alone again
wrenctl remove security-key             take it all out (the keys themselves are untouched)
wrenctl manual security-key             print the manual steps below

ssh-keygen -t ed25519-sk -f ~/.ssh/NAME   an SSH key that needs the security key for every login
fido2-token -L                            the keys plugged in
```

A FIDO2 security key (YubiKey, Nitrokey, SoloKey, Google Titan and others)
makes its secret inside the chip and never lets it out, and signs only when you
touch it: malware on the computer can neither copy it nor use it for you, and a
fake website gets nothing, because the key signs only for the site it was
registered with. Linux (udev 244 and later) lets you, at the keyboard, use such
a key by itself, so no rules from its maker are needed, and other users get
none. The script installs `libfido2` and its tools, and asks two things. First,
whether the sandboxed Firefox may use the key for website logins (WebAuthn):
its users are others than you, so a udev rule (`data/security-key-firefox.rules`)
lets the group `wren-fx` reach the key; `firefox-esr`, which runs as you, can
anyway. Second, whether sudo should take your password and a touch of the key
(`pam_u2f`). The keys it accepts are listed in `/etc/wren/u2f_keys`, which only
root can change, so nothing running as you can add one of its own; the setting
is tried in a PAM service of its own first, and the change to sudo undoes itself
after three minutes unless a new sudo, with your password and a touch, works.
SSH keys of the `ed25519-sk` kind need the key for every login;
`tools/vps-client.sh ssh-key --security-key` makes one for the Wren Linux VPS.

## LIMITS

- Lose the key and what needs it is closed to you: register a second key as a backup everywhere (sites, SSH servers, sudo), and keep it somewhere else.
- With sudo taking the key, losing every registered key means no sudo. To get back in: at the boot menu press `e`, add `init=/bin/bash` to the line that starts with `linux`, press Ctrl+X, type the disk passphrase, then `mount -o remount,rw /`, take the two lines marked "Wren Linux extras/security-key.sh" out of `/etc/pam.d/sudo`, and restart.
- It protects logging in, not what happens after: a program running as you can use a session that is already open (a sudo still remembered, a site you are logged in to).
- Letting the sandboxed Firefox use the key means a hacked page in any of its profiles can ask for a login with it; each still needs your touch, and the key still signs only for the site Firefox names.
- The disk passphrase isn't replaced: unlocking the disk with the key isn't set up.

## MANUAL INSTALL

```
# The key's library and tools; pam_u2f for sudo, and pamtester to try it first
sudo apt install --no-install-recommends libfido2-1 fido2-tools libpam-u2f pamu2fcfg pamtester acl
fido2-token -L        # the key is there, and yours to use without sudo

# Optional: the sandboxed Firefox's users may use the key for website logins
sudo install -o root -g root -m 0644 @WREN_DIR@/data/security-key-firefox.rules /etc/udev/rules.d/72-wren-security-key-firefox.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=hidraw --action=change

# Optional: sudo takes your password and the key. Register it (touch it), and a
# backup key too (-n, the other key plugged in), into a list only root changes
pamu2fcfg -u "$USER" -o pam://wren -i pam://wren >/tmp/u2f
pamu2fcfg -n -o pam://wren -i pam://wren >>/tmp/u2f
tr -d '\n' </tmp/u2f | sudo install -D -o root -g root -m 0644 /dev/stdin /etc/wren/u2f_keys; rm /tmp/u2f
# Try it in a service of its own first: this must succeed (touch the key)
printf 'auth required pam_u2f.so authfile=/etc/wren/u2f_keys origin=pam://wren appid=pam://wren cue\naccount required pam_permit.so\n' | sudo tee /etc/pam.d/wren-u2f-test
pamtester wren-u2f-test "$USER" authenticate
sudo rm /etc/pam.d/wren-u2f-test
# Keep a root shell open in another terminal (sudo -i) while you change sudo,
# then add, right after "@include common-auth" in /etc/pam.d/sudo:
#   # Wren Linux extras/security-key.sh: sudo takes your password and a touch of your key
#   auth required pam_u2f.so authfile=/etc/wren/u2f_keys origin=pam://wren appid=pam://wren cue nouserok
sudo -k; sudo true    # your password, then a touch: if it fails, undo it in the root shell
```

To undo:

```
# Take the two lines out of /etc/pam.d/sudo first, then
sudo rm -f /etc/wren/u2f_keys /etc/udev/rules.d/72-wren-security-key-firefox.rules
sudo udevadm control --reload-rules
sudo apt purge fido2-tools pamu2fcfg libpam-u2f pamtester
sudo apt-mark auto libfido2-1 acl
sudo apt autoremove --purge
```
