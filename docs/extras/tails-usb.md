# Tails on a USB stick (`extras/tails-usb.sh`)

## SYNOPSIS

```
wrenctl install tails-usb                     set up the tails-usb command, and say how to use it
wrenctl remove tails-usb                      remove it (offers to delete the saved image)
wrenctl manual tails-usb                      print the manual steps below

tails-usb          download (or reuse) the newest Tails, check it, write it to a stick you pick
```

Tails is a whole operating system that runs from a USB stick, sends everything through Tor and
forgets everything when you shut it down.

The `tails-usb` command (`bin/tails-usb`) finds the newest Tails in Tails' own release file and
downloads the USB image, through Tor when the system tor service runs here (apt over Tor, remote
access, the onion site), so your network can't see you fetch it.

It uses the image only if it is signed by the Tails signing key, pinned in `pins.sh` (`TAILS_FPR`),
and is exactly the image the release file names for the newest version, so an older signed Tails
can't be slipped in.

The verified copy is kept in `offline/tails` for the next stick. It lists only USB sticks, never the
disk this system runs from, asks you to type the stick's name, writes Tails onto it and reads it
back to check.

Writing a stick erases everything on it, Persistent Storage included.

## LIMITS

- Without Tor here, your network sees you download Tails (not what you do with it later).
- Tails protects what you do while running it, not this computer.
- A stick left with someone can be swapped or changed: keep it with you, and remake it from a
  checked image if in doubt.

## MANUAL INSTALL

These are the steps tails-usb takes to make a stick.

```
# wget and gpg to download and check it; torsocks to download through Tor
# (only if the system tor service runs here); python3 reads the release file
sudo apt install --no-install-recommends wget gpg python3 torsocks util-linux
# A folder of its own
mkdir -p ~/tails-download && cd ~/tails-download

# Tails' release file: the newest version, the image's address, its SHA-256 and size
# (put "torsocks" in front of each wget to download through Tor)
wget -O latest.json @TAILS_LATEST_URL@
python3 -c 'import json; f=[p for p in json.load(open("latest.json"))["installations"][0]["installation-paths"] if p["type"]=="img"][0]["target-files"][0]; print(f["url"], f["sha256"], f["size"])'
V=7.2

# The signing key, the signature and the image
wget -O tails-signing.key @TAILS_KEY_URL@
wget @TAILS_SIG_BASE@/tails-amd64-$V.img.sig
wget https://download.tails.net/tails/stable/tails-amd64-$V/tails-amd64-$V.img

# The key, in a keyring of its own. This must show the fingerprint @TAILS_FPR@
mkdir -m 700 gpg
gpg --homedir gpg --import tails-signing.key
gpg --homedir gpg --fingerprint @TAILS_FPR@
# The image is signed by it: this must say "Good signature" with
# "Primary key fingerprint" @TAILS_FPR@. Stop here if not.
gpg --homedir gpg --verify tails-amd64-$V.img.sig tails-amd64-$V.img
# And it is the image the release file names: the SHA-256 the python line
# printed goes here, and this must print "OK"
echo "SHA256-FROM-ABOVE  tails-amd64-$V.img" | sha256sum -c

# The stick: find it by its size and name (TRAN usb). Make very sure it is
# the stick and not your disk: everything on it is erased.
lsblk -d -o NAME,SIZE,TRAN,MODEL
DEV=/dev/sdX
# Unmount anything mounted from it, then write Tails onto it
for p in $(lsblk -lnpo NAME,MOUNTPOINTS $DEV | awk 'NF > 1 { print $1 }'); do sudo umount $p; done
sudo dd if=tails-amd64-$V.img of=$DEV bs=16M conv=fsync status=progress
sync
# Read it back: the two hashes must be the same
sha256sum tails-amd64-$V.img
sudo head -c $(stat -c %s tails-amd64-$V.img) $DEV | sha256sum
```

Then shut down, start the computer from the stick (its boot menu key is often F12, F9 or Esc), and
choose Tails.

To undo:

```
# The downloads
rm -rf ~/tails-download
# torsocks, marked "automatic": autoremove takes it out only if nothing needs it
sudo apt-mark auto torsocks
sudo apt autoremove --purge
```
