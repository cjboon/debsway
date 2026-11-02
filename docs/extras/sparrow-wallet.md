# Sparrow Wallet (`extras/sparrow-wallet.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/sparrow-wallet.sh            install it, or update to the newest release
bash ~/debsway/extras/sparrow-wallet.sh --remove   remove it (wallets in ~/.sparrow stay)
bash ~/debsway/extras/sparrow-wallet.sh --manual   print the manual steps below

sparrow                                            start it (or Super+d, then sparrow)
bash ~/debsway/test.sh                             says when a newer release is out
```

Sparrow is a Bitcoin wallet with better privacy tools than Electrum (coin
control, built-in Tor) and good hardware wallet support. debsway installs the
official .deb from its GitHub releases only if it matches the release's list
of SHA-256 checksums (its manifest), signed by Craig Raw's key, pinned in
`pins.sh` (`SPARROW_FPR`). The package puts Sparrow in `/opt`, so a `sparrow`
command is added to `~/.local/bin`. It is a JavaFX program, which is X11-only,
so XWayland is installed. Wallets live in `~/.sparrow`.

## LIMITS

- It runs as you: anything that can read your files can read `~/.sparrow`.
- It isn't updated by apt (it isn't from a repository): run the script again.
- A public server sees your wallet's addresses; Sparrow's Tor setting hides your address from it, your own node is the most private.

## MANUAL INSTALL

```
# XWayland (JavaFX is X11-only), and gpg to check the signature
sudo apt install --no-install-recommends xwayland gpg
# If XWayland was new: log out and back in once, so sway starts it

# A folder of its own for the download
mkdir -p ~/sparrow-download && cd ~/sparrow-download
# The newest version: the tag in the "Location:" line (e.g. 2.3.0)
wget --max-redirect=0 -S -O /dev/null https://github.com/sparrowwallet/sparrow/releases/latest 2>&1 | grep -i location
VER=2.3.0
URL=https://github.com/sparrowwallet/sparrow/releases/download/$VER

# The .deb, the manifest and its signature
wget $URL/sparrowwallet_$VER-1_amd64.deb $URL/sparrow-$VER-manifest.txt $URL/sparrow-$VER-manifest.txt.asc

# Craig Raw's key, in a keyring of its own. This must show the fingerprint
# @SPARROW_FPR@
mkdir -m 700 gpg
wget -O sparrow.asc @SPARROW_KEY_URL@
gpg --homedir gpg --import sparrow.asc
gpg --homedir gpg --fingerprint @SPARROW_FPR@
# The manifest is signed by it: this must say "Good signature" with
# "Primary key fingerprint" @SPARROW_FPR@. Stop here if not.
gpg --homedir gpg --verify sparrow-$VER-manifest.txt.asc sparrow-$VER-manifest.txt

# The .deb is the one in the manifest: this must print "OK"
awk -v n="sparrowwallet_$VER-1_amd64.deb" '$2 == n || $2 == "*" n { print $1 "  " n }' sparrow-$VER-manifest.txt | sha256sum -c

# Its install script needs this folder, which a sway-only system lacks
sudo mkdir -p /usr/share/desktop-directories
# Install it (apt reads the file as its own user, so it must be readable)
chmod 755 . && chmod 644 sparrowwallet_$VER-1_amd64.deb
sudo apt install ./sparrowwallet_$VER-1_amd64.deb

# A sparrow command, since the package puts it in /opt
install -D -m 0755 @DEBSWAY_DIR@/bin/sparrow ~/.local/bin/sparrow

# The download isn't needed any more
cd ~ && rm -rf ~/sparrow-download
sparrow
```

To undo (your wallets stay in `~/.sparrow`; back them up before deleting anything):

```
# Its removal script needs the same folder
sudo mkdir -p /usr/share/desktop-directories
sudo apt purge sparrowwallet
rm ~/.local/bin/sparrow
# XWayland, marked "automatic": autoremove takes it out only if nothing needs it
sudo apt-mark auto xwayland
sudo apt autoremove --purge
```
