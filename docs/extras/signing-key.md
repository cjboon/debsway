# Wren Linux's signing key, kept by a user of its own (`extras/signing-key.sh`)

## SYNOPSIS

```
wrenctl install signing-key                     set up the signer and the wren-key command
wrenctl remove signing-key                      take them out (asks before deleting the signing subkey)
wrenctl manual signing-key                      print the manual steps below

wren-key                    the first time: questions, the key, its backup on your stick
wren-key status             the key, until when it signs, and what uses it
wren-key git-setup [DIR]    git in DIR signs every commit and tag with it
wren-key pin [DIR]          DIR's pins.sh and data/ name the key (then commit and push)
wren-key sign-repo FOLDER DEB...   a signed apt repository of Wren Linux's packages
wren-key renew BACKUP       two more years for the signing subkey, from the backup
wren-key restore BACKUP [FINGERPRINT]   on a new computer: the key from its backup
```

On a new computer (or after reinstalling), don't make a second key: set up the extra, mount your
stick (`usb mount`), and run
`wren-key restore /media/$USER/STICK/wren-signing-key/wren-signing-key-backup.asc`.

It takes only the key `pins.sh` pins (or the one you name), asks the backup's passphrase, and keeps
only the signing subkey here, as the first run does. Then `wren-key git-setup ~/wren-linux` if git
should sign with it there.

To keep the backup on an encrypted stick, run `bash encrypt-usb.sh` first, and open it with
`usb mount`. This extra is only in a git copy of Wren Linux, not the package
(`wrenctl install wren-dev` gets one). Where the package is installed, run its `wrenctl` lines as
`WREN_DIR=~/wren-linux wrenctl ...`.

For the computer you publish Wren Linux from. Every Wren Linux computer checks its updates against
this one key (`update.sh` for commits, apt for the package), so whoever has it could put anything on
all of them, as root.

It is made in two parts: the primary key, which only vouches for the other, goes into an encrypted
backup on your USB stick and is then deleted from this computer; the signing subkey stays here, held
by `wren-signer`, a system user with no password, no login and no network (a firewall rule drops
everything it sends), whose files your own user can't read.

Your user may run one program as it, the signer, and only after typing your sudo password; the
signer signs, hands out the public key and makes, renews or restores the key, and never hands out a
secret key.

`wren-key` asks the signer for what it needs: on the first run it explains, asks your name, email,
where the backup goes and its passphrase, makes the key, writes the backup, a revocation certificate
and the public key to the stick, and offers to set up git signing and to pin the key.

## LIMITS

- The signing subkey is on this computer: root (or anyone who becomes root) can read it, and a
  program running as you can have something signed within the few minutes sudo remembers your
  password in that terminal. If you think it was taken, replace it from the backup and publish the
  revocation.
- The backup is only as safe as its passphrase and the stick: keep the passphrase on paper away from
  the stick, and a second stick in another place. Lose both the backup and the passphrase and the
  key can't be renewed: every Wren Linux computer then needs a new key by hand.
- The signing subkey stops signing after two years. Renew it well before (`wren-key status` warns 90
  days ahead) and publish the renewed public key while the old one still signs.
- The revocation certificate works without the passphrase: whoever has it can void your key (though
  not sign with it). Keep it apart from the sticks.
- It doesn't protect the computer it runs on; it keeps the key apart from your user on it.

## MANUAL INSTALL

```
# gpg, and nftables for the firewall rule
sudo apt install --no-install-recommends gpg gpg-agent nftables
# The firewall rule first: the user never has a moment on the network
sudo install -D -o root -g root -m 0644 @WREN_DIR@/data/signer-firewall.nft /etc/wren/signer.nft
printf '%s\n' '[Unit]' 'Description=Keep wren-signer off every network' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' 'ExecStart=/usr/sbin/nft -f /etc/wren/signer.nft' \
    'ExecStop=/usr/sbin/nft delete table inet wren_signer' '' '[Install]' 'WantedBy=multi-user.target' |
    sudo tee /etc/systemd/system/wren-signer-firewall.service
# The user: no password, no login, its home its own
sudo useradd --system --user-group --home-dir /var/lib/wren-signer --no-create-home --shell /usr/sbin/nologin --comment "Wren Linux signing key, off the network" wren-signer
sudo usermod --lock --shell /usr/sbin/nologin wren-signer
sudo install -d -o wren-signer -g wren-signer -m 0700 /var/lib/wren-signer
sudo systemctl daemon-reload
sudo systemctl enable --now wren-signer-firewall.service
# check it is loaded before going on: this prints the drop rule
sudo nft list table inet wren_signer
# The signer, root's
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/wren-signer /usr/local/libexec/wren-signer
# Your user may run the signer, and nothing else, as wren-signer, with your
# password (not NOPASSWD). visudo checks the rule first.
printf '%s ALL=(wren-signer) /usr/local/libexec/wren-signer\n' "$(id -un)" >/tmp/wren-signer
sudo visudo -cf /tmp/wren-signer
sudo install -o root -g root -m 0440 /tmp/wren-signer /etc/sudoers.d/wren-signer
rm /tmp/wren-signer
# The command, and its man page
install -D -m 0755 @WREN_DIR@/bin/wren-key ~/.local/bin/wren-key
install -D -m 0755 @WREN_DIR@/bin/wren-key-gpg ~/.local/bin/wren-key-gpg
install -D -m 0644 @WREN_DIR@/data/wren-key.1 ~/.local/share/man/man1/wren-key.1
# Then, with a USB stick mounted:
wren-key
```

To undo:

```
sudo rm /etc/sudoers.d/wren-signer /usr/local/libexec/wren-signer
rm ~/.local/bin/wren-key ~/.local/bin/wren-key-gpg ~/.local/share/man/man1/wren-key.1
# Only if your backup is safe: this deletes the signing subkey
sudo userdel wren-signer
sudo rm -rf /var/lib/wren-signer
sudo systemctl disable --now wren-signer-firewall.service
sudo rm /etc/systemd/system/wren-signer-firewall.service /etc/wren/signer.nft
sudo systemctl daemon-reload
```
