# Tuta Mail (`extras/tutamail.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/tutamail.sh            install it, or update to the newest release
bash ~/debsway/extras/tutamail.sh --remove   remove it (its data stays)
bash ~/debsway/extras/tutamail.sh --manual   print the manual steps below

tuta                                         start it (or Super+d, then tuta)
bash ~/debsway/test.sh                       says when a newer release is out
```

Tuta Mail (Tutanota until 2023) is the desktop app of Tuta, an end-to-end
encrypted email service: your mailbox, contacts and calendar are stored
encrypted on Tuta's servers, and mail between Tuta users is end-to-end
encrypted. debsway installs the official AppImage from `app.tuta.com` only if
it is signed by Tuta's code-signing key, a copy of which is in
`data/tuta-pub.pem` (its SHA-256 is pinned in `pins.sh` as `TUTA_KEY_SHA256`).
Tuta signs with openssl rather than gpg. Its release file isn't signed, so the
app inside must be the version it names, and an older version than yours is
refused. The AppImage is unpacked into `~/.local/opt/tuta`, and `tuta` starts
the app directly, on Wayland, with Electron's sandbox on (the AppImage's own
start script would switch the sandbox off when it can't make a user namespace).
It stays logged in only with a keyring (`extras/seahorse.sh`).

## LIMITS

- It runs as you: anything that can read your files can read the mail it keeps offline.
- It isn't updated by apt and doesn't update itself: run the script again.
- The first install has no older version to compare with, so an old signed
  release with a matching release file would be taken (the server is reached over HTTPS).
- Tuta and your network see that you connect; no Tor or VPN is set up for it.
- Mail to and from other providers is not end-to-end encrypted.

## MANUAL INSTALL

```
# The libraries the app's Electron binary needs, openssl to check the
# signature, wget to download, libsecret for the keyring, xdg-utils for links
sudo apt install --no-install-recommends openssl wget @LIBS@

# A folder of its own for the download
mkdir -p ~/tuta-download && cd ~/tuta-download

# The release file (names the version), the signature and the AppImage
wget @TUTA_DESKTOP_URL@/latest-linux.yml @TUTA_DESKTOP_URL@/linux-sig.bin @TUTA_DESKTOP_URL@/tutanota-desktop-linux.AppImage
grep '^version:' latest-linux.yml

# Tuta's key is the pinned one: this must print @TUTA_KEY_SHA256@
openssl pkey -pubin -in @DEBSWAY_DIR@/data/tuta-pub.pem -outform DER | sha256sum

# Tuta signed the AppImage: this must print "Verified OK". Stop here if not.
openssl dgst -sha512 -verify @DEBSWAY_DIR@/data/tuta-pub.pem -signature linux-sig.bin tutanota-desktop-linux.AppImage

# Unpack it (no FUSE needed), and check the app inside is the version the
# release file named (the release file itself isn't signed)
chmod +x tutanota-desktop-linux.AppImage
./tutanota-desktop-linux.AppImage --appimage-extract >/dev/null
grep -a -o '"version": "[0-9.]*"' squashfs-root/resources/app.asar | head -1

# Put it in place, replacing an older copy
mkdir -p ~/.local/opt
rm -rf ~/.local/opt/tuta
mv squashfs-root ~/.local/opt/tuta

# The command: the app itself (not AppRun, which can turn the sandbox off), on Wayland
mkdir -p ~/.local/bin
printf '%s\n' '#!/bin/sh' 'dir="$HOME/.local/opt/tuta"' \
    'exec env APPDIR="$dir" ELECTRON_OZONE_PLATFORM_HINT=wayland "$dir/tutanota-desktop" "$@"' >~/.local/bin/tuta
chmod +x ~/.local/bin/tuta

# The download isn't needed any more
cd ~ && rm -rf ~/tuta-download
tuta
```

To undo: `rm -rf ~/.local/opt/tuta ~/.local/bin/tuta`, then remove the
libraries above with `sudo apt purge` if nothing else uses them. The app's
data stays in `~/.config/tutanota-desktop`.
