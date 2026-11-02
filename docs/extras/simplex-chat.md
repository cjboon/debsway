# SimpleX Chat (`extras/simplex-chat.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/simplex-chat.sh            install it, or update to the newest release
bash ~/debsway/extras/simplex-chat.sh --remove   remove it (your chats stay)
bash ~/debsway/extras/simplex-chat.sh --manual   print the manual steps below

simplex                                          start it (or Super+d, then simplex)
bash ~/debsway/test.sh                           says when a newer release is out
```

SimpleX Chat is an end-to-end encrypted messenger without user accounts or
phone numbers. debsway installs the official desktop AppImage from GitHub
(about 350 MB) only if it matches the list of SHA-256 checksums signed by
SimpleX's release key (`build@simplex.chat`, pinned in `pins.sh` as
`SIMPLEX_FPR`). It is unpacked into `~/.local/opt/simplex` (no FUSE needed),
and `simplex` starts it. It is a Java program, and Java's windows are X11, so
XWayland is installed, with the system libraries its Java and media code use;
the command tells Java that sway puts no frames around windows, so its
window fills its space and takes clicks.

## LIMITS

- It runs as you: anything that can read your files can read your chats.
- It isn't updated by apt: run the script again (`test.sh` says when).
- Your network sees that you connect; nothing here sets up Tor for it.

## MANUAL INSTALL

```
# XWayland (Java's windows are X11), gpg to check the signature, and the
# libraries its Java and media code use
sudo apt install --no-install-recommends xwayland gpg @LIBS@
# If XWayland was new: log out and back in once, so sway starts it

# A folder of its own for the download
mkdir -p ~/simplex-download && cd ~/simplex-download
# The newest release: the tag in the "Location:" line (e.g. v6.4.5)
wget --max-redirect=0 -S -O /dev/null https://github.com/simplex-chat/simplex-chat/releases/latest 2>&1 | grep -i location
TAG=v6.4.5
URL=https://github.com/simplex-chat/simplex-chat/releases/download/$TAG

# The checksum list, its signature and the AppImage
wget $URL/_sha256sums $URL/_sha256sums.asc $URL/simplex-desktop-x86_64.AppImage

# SimpleX's key, in a keyring of its own. This must show the fingerprint
# @SIMPLEX_FPR@
mkdir -m 700 gpg
wget -O simplex.asc @SIMPLEX_KEY_URL@
gpg --homedir gpg --import simplex.asc
gpg --homedir gpg --fingerprint @SIMPLEX_FPR@
# The list is signed by it: this must say "Good signature" with
# "Primary key fingerprint" @SIMPLEX_FPR@. Stop here if not.
gpg --homedir gpg --verify _sha256sums.asc _sha256sums

# The AppImage is the one in the list (named TAG/NAME there): this must print "OK"
awk -v n="$TAG/simplex-desktop-x86_64.AppImage" '$2 == n { print $1 "  simplex-desktop-x86_64.AppImage" }' _sha256sums | sha256sum -c

# Unpack it (no FUSE needed) and put it in place, replacing an older copy
chmod +x simplex-desktop-x86_64.AppImage
./simplex-desktop-x86_64.AppImage --appimage-extract >/dev/null
mkdir -p ~/.local/opt && rm -rf ~/.local/opt/simplex
mv squashfs-root ~/.local/opt/simplex

# The command, running its AppRun start script; the Java setting makes its
# window fill the space sway gives it (else it is drawn in the top-left corner)
mkdir -p ~/.local/bin
printf '%s\n' '#!/bin/sh' 'dir="$HOME/.local/opt/simplex"' \
    'exec env APPDIR="$dir" _JAVA_AWT_WM_NONREPARENTING=1 "$dir/AppRun" "$@"' >~/.local/bin/simplex
chmod +x ~/.local/bin/simplex

# The download isn't needed any more
cd ~ && rm -rf ~/simplex-download
simplex
```

To undo (your chats and profile stay):

```
# The app and its command
rm -rf ~/.local/opt/simplex ~/.local/bin/simplex
# XWayland and the libraries: other programs use many of them, so they are
# marked "automatic" for autoremove to take out only if nothing needs them
sudo apt-mark auto xwayland @LIBS@
sudo apt autoremove --purge
```
