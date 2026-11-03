# debsway's signing key, kept by a user of its own (`extras/signing-key.sh`)

## SYNOPSIS

```
debsway install signing-key                     set up the signer and the debsway-key command
debsway remove signing-key                      take them out (asks before deleting the signing subkey)
debsway manual signing-key                      print the manual steps below

debsway-key                    the first time: questions, the key, its backup on your stick
debsway-key status             the key, until when it signs, and what uses it
debsway-key git-setup [DIR]    git in DIR signs every commit and tag with it
debsway-key pin [DIR]          DIR's pins.sh and data/ name the key (then commit and push)
debsway-key sign-repo FOLDER DEB...   a signed apt repository of debsway's packages
debsway-key renew BACKUP       two more years for the signing subkey, from the backup
```

For the computer you publish debsway from. Every debsway computer checks its
updates against this one key (`update.sh` for commits, apt for the package),
so whoever has it could put anything on all of them, as root. It is made in
two parts: the primary key, which only vouches for the other, goes into an
encrypted backup on your USB stick and is then deleted from this computer;
the signing subkey stays here, held by `debsway-signer`, a system user with no
password, no login and no network (a firewall rule drops everything it sends),
whose files your own user can't read. Your user may run one program as it,
the signer, and only after typing your sudo password; the signer signs, hands
out the public key and makes or renews the key, and never hands out a secret
key. `debsway-key` asks the signer for what it needs: on the first run it
explains, asks your name, email, where the backup goes and its passphrase,
makes the key, writes the backup, a revocation certificate and the public key
to the stick, and offers to set up git signing and to pin the key.

## LIMITS

- The signing subkey is on this computer: root (or anyone who becomes root) can read it, and a program running as you can have something signed within the few minutes sudo remembers your password in that terminal. If you think it was taken, replace it from the backup and publish the revocation.
- The backup is only as safe as its passphrase and the stick: keep the passphrase on paper away from the stick, and a second stick in another place. Lose both the backup and the passphrase and the key can't be renewed: every debsway computer then needs a new key by hand.
- The signing subkey stops signing after two years. Renew it well before (`debsway-key status` warns 90 days ahead) and publish the renewed public key while the old one still signs.
- The revocation certificate works without the passphrase: whoever has it can void your key (though not sign with it). Keep it apart from the sticks.
- It doesn't protect the computer it runs on; it keeps the key apart from your user on it.

## MANUAL INSTALL

```
# gpg, and nftables for the firewall rule
sudo apt install --no-install-recommends gpg gpg-agent nftables
# The firewall rule first: the user never has a moment on the network
sudo install -D -o root -g root -m 0644 @DEBSWAY_DIR@/data/signer-firewall.nft /etc/debsway/signer.nft
printf '%s\n' '[Unit]' 'Description=Keep debsway-signer off every network' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' 'ExecStart=/usr/sbin/nft -f /etc/debsway/signer.nft' \
    'ExecStop=/usr/sbin/nft delete table inet debsway_signer' '' '[Install]' 'WantedBy=multi-user.target' |
    sudo tee /etc/systemd/system/debsway-signer-firewall.service
# The user: no password, no login, its home its own
sudo useradd --system --user-group --home-dir /var/lib/debsway-signer --no-create-home --shell /usr/sbin/nologin --comment "debsway signing key, off the network" debsway-signer
sudo usermod --lock --shell /usr/sbin/nologin debsway-signer
sudo install -d -o debsway-signer -g debsway-signer -m 0700 /var/lib/debsway-signer
sudo systemctl daemon-reload
sudo systemctl enable --now debsway-signer-firewall.service
# check it is loaded before going on: this prints the drop rule
sudo nft list table inet debsway_signer
# The signer, root's
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 @DEBSWAY_DIR@/bin/debsway-signer /usr/local/libexec/debsway-signer
# Your user may run the signer, and nothing else, as debsway-signer, with your
# password (not NOPASSWD). visudo checks the rule first.
printf '%s ALL=(debsway-signer) /usr/local/libexec/debsway-signer\n' "$(id -un)" >/tmp/debsway-signer
sudo visudo -cf /tmp/debsway-signer
sudo install -o root -g root -m 0440 /tmp/debsway-signer /etc/sudoers.d/debsway-signer
rm /tmp/debsway-signer
# The command, and its man page
install -D -m 0755 @DEBSWAY_DIR@/bin/debsway-key ~/.local/bin/debsway-key
install -D -m 0755 @DEBSWAY_DIR@/bin/debsway-key-gpg ~/.local/bin/debsway-key-gpg
install -D -m 0644 @DEBSWAY_DIR@/data/debsway-key.1 ~/.local/share/man/man1/debsway-key.1
# Then, with a USB stick mounted:
debsway-key
```

To undo:

```
sudo rm /etc/sudoers.d/debsway-signer /usr/local/libexec/debsway-signer
rm ~/.local/bin/debsway-key ~/.local/bin/debsway-key-gpg ~/.local/share/man/man1/debsway-key.1
# Only if your backup is safe: this deletes the signing subkey
sudo userdel debsway-signer
sudo rm -rf /var/lib/debsway-signer
sudo systemctl disable --now debsway-signer-firewall.service
sudo rm /etc/systemd/system/debsway-signer-firewall.service /etc/debsway/signer.nft
sudo systemctl daemon-reload
```
