# Feather Wallet (`extras/feather-wallet.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/feather-wallet.sh            install it, or update to the newest release
bash ~/debsway/extras/feather-wallet.sh --remove   remove it (your wallet files stay)
bash ~/debsway/extras/feather-wallet.sh --manual   print the manual steps below

feather                                            start it (or Super+d, then feather)
bash ~/debsway/test.sh                             says when a newer release is out
```

Feather is a Monero wallet. debsway installs the official AppImage from
featherwallet.org only if it matches the list of SHA-256 checksums that
Feather signs with its key, pinned in `pins.sh` (`FEATHER_FPR`). The newest
version is read from GitHub and must be plain numbers. The AppImage is
unpacked into `~/.local/opt/feather` (no FUSE needed), and `feather` starts
it. Feather uses X11 itself, so XWayland is installed.

## LIMITS

- It runs as you: anything that can read your files can read your wallet files.
- It isn't updated by apt: run the script again (`test.sh` says when).
- The server it connects to sees your address unless you set Tor in Feather's settings.
- Write the seed down: nothing else can bring a lost wallet back.

## MANUAL INSTALL

```
# XWayland (Feather uses X11), and gpg to check the signature
sudo apt install --no-install-recommends xwayland gpg
# If XWayland was new: log out and back in once, so sway starts it

# A folder of its own for the download
mkdir -p ~/feather-download && cd ~/feather-download
# The newest version: the tag in the "Location:" line (e.g. 2.8.1)
wget --max-redirect=0 -S -O /dev/null https://github.com/feather-wallet/feather/releases/latest 2>&1 | grep -i location
VER=2.8.1

# The signed checksum list and the AppImage
wget https://featherwallet.org/files/releases/hashes-$VER.txt https://featherwallet.org/files/releases/linux-appimage/feather-$VER.AppImage

# Feather's key, in a keyring of its own. This must show the fingerprint
# @FEATHER_FPR@
mkdir -m 700 gpg
wget -O feather.asc @FEATHER_KEY_URL@
gpg --homedir gpg --import feather.asc
gpg --homedir gpg --fingerprint @FEATHER_FPR@
# The list is signed by it: this must say "Good signature" with
# "Primary key fingerprint" @FEATHER_FPR@. Stop here if not.
gpg --homedir gpg --output sums.txt --decrypt hashes-$VER.txt

# The AppImage is the one in the list: this must print "OK"
awk -v n="feather-$VER.AppImage" '$2 == n || $2 == "*" n { print $1 "  " n }' sums.txt | sha256sum -c

# Unpack it (no FUSE needed) and put it in place, replacing an older copy
chmod +x feather-$VER.AppImage
./feather-$VER.AppImage --appimage-extract >/dev/null
mkdir -p ~/.local/opt && rm -rf ~/.local/opt/feather
mv squashfs-root ~/.local/opt/feather

# The command: its binary, on X11 as Feather wants
mkdir -p ~/.local/bin
printf '%s\n' '#!/bin/sh' 'dir="$HOME/.local/opt/feather"' \
    'exec env APPDIR="$dir" QT_QPA_PLATFORM=xcb "$dir/usr/bin/feather" "$@"' >~/.local/bin/feather
chmod +x ~/.local/bin/feather

# The download isn't needed any more
cd ~ && rm -rf ~/feather-download
feather
```

To undo (your wallet files stay where you saved them):

```
# The app and its command
rm -rf ~/.local/opt/feather ~/.local/bin/feather
# XWayland, marked "automatic": autoremove takes it out only if nothing needs it
sudo apt-mark auto xwayland
sudo apt autoremove --purge
```
