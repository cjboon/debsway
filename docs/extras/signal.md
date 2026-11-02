# Signal Desktop (`extras/signal.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/signal.sh            install it
bash ~/debsway/extras/signal.sh --remove   remove it (your messages stay in ~/.config/Signal)
bash ~/debsway/extras/signal.sh --manual   print the manual steps below

signal-desktop     start it (or Super+d, or the debsway menu > Signal)
                   the first time: scan its QR code with Signal on your phone
                   (Settings > Linked devices)
```

Signal Desktop, for end-to-end encrypted messages and calls, linked to the
Signal account on your phone. It comes from Signal's own apt repository,
whose signing key must be exactly the one pinned in `pins.sh` (`SIGNAL_FPR`,
the Open Whisper Systems key, checked against two public keyservers too), and
unattended-upgrades installs its updates. Signal needs a phone number; SimpleX
Chat (`extras/simplex-chat.sh`) doesn't. Signal is an Electron app, and its
package makes Electron's sandbox helper, `/opt/Signal/chrome-sandbox`, setuid
root; Debian lets Electron sandbox itself without that, so the setuid bit is
taken off, for good: a `dpkg-statoverride` keeps it off through updates.

## LIMITS

- It runs as you: anything that can read your files can read `~/.config/Signal`, your messages.
- Signal's servers see your phone number and when you are online, not what you write.
- The people you write to can keep, copy or forward what you send.
- Signal's repository is Signal's: debsway checks its key, not its packages' contents.

## MANUAL INSTALL

```
# Signal's signing key. Check it is exactly the pinned one: this must
# print one "pub" key with the fingerprint @SIGNAL_FPR@
wget -O /tmp/signal.asc @SIGNAL_KEY_URL@
gpg --show-keys --with-fingerprint /tmp/signal.asc
sudo install -D -m 0644 /tmp/signal.asc /usr/share/keyrings/signal-desktop-keyring.asc
rm /tmp/signal.asc

# The repository, trusted with that key only, and its updates installed by unattended-upgrades
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/signal-desktop-keyring.asc] https://updates.signal.org/desktop/apt xenial main" |
    sudo tee /etc/apt/sources.list.d/signal-desktop.list
echo 'Unattended-Upgrade::Origins-Pattern:: "site=updates.signal.org";' |
    sudo tee /etc/apt/apt.conf.d/52debsway-signal

# Its sandbox helper not setuid root, now and through every update
sudo dpkg-statoverride --add root root 0755 /opt/Signal/chrome-sandbox

# Signal
sudo apt update
sudo apt install --no-install-recommends signal-desktop
# This must show -rwxr-xr-x (no "s")
ls -l /opt/Signal/chrome-sandbox
signal-desktop
```

To undo (your messages stay in `~/.config/Signal`; delete it to unlink this computer):

```
# Signal, the sandbox helper's override, the repository, its key and the update rule
sudo apt purge signal-desktop
sudo dpkg-statoverride --remove /opt/Signal/chrome-sandbox
sudo rm /etc/apt/sources.list.d/signal-desktop.list /usr/share/keyrings/signal-desktop-keyring.asc
sudo rm /etc/apt/apt.conf.d/52debsway-signal
sudo apt update
```
