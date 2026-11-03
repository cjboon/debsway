# Autologin on tty1 (`extras/autologin.sh`)

## SYNOPSIS

```
debsway install autologin                     log in on tty1 without the password, from the next boot
debsway remove autologin                      tty1 asks for the password again
debsway manual autologin                      print the manual steps below

bash ~/debsway/prep/make-install-iso.sh --autologin   an install stick that sets this up
```

The computer starts straight into sway without asking for your password: tty1's
login prompt (its getty) is started with `--autologin` for your user, through a
systemd drop-in (`data/autologin-getty.conf`), and the login loop debsway put
in `~/.profile` starts sway on tty1. The other text consoles still ask. The
disk passphrase at boot (on an encrypted disk), the screen lock and sudo all
still ask for theirs, so with an encrypted disk someone holding the laptop
while it is off still can't get in. On a disk that isn't encrypted the script
warns that switching the computer on is then enough to be you, and asks first.

## LIMITS

- Anyone at the computer between the disk passphrase and your screen lock is you: lock it (Super+Escape) or shut it down when you step away.
- Without disk encryption, it adds nothing to protect: the disk could be read without logging in at all.
- The screen lock still asks for your password; a weak one is still weak.

## MANUAL INSTALL

```
# The drop-in for tty1's getty, with your user name in it
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d
sed "s|[@]USER@|$(id -un)|g" @DEBSWAY_DIR@/data/autologin-getty.conf |
    sudo tee /etc/systemd/system/getty@tty1.service.d/50-debsway-autologin.conf
# systemd reads it; it applies from the next boot
sudo systemctl daemon-reload
```

To undo:

```
# tty1 asks for the password again, from the next boot
sudo rm /etc/systemd/system/getty@tty1.service.d/50-debsway-autologin.conf
sudo rmdir /etc/systemd/system/getty@tty1.service.d
sudo systemctl daemon-reload
```
