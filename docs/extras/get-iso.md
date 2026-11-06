# Other systems' install images (`extras/get-iso.sh`)

## SYNOPSIS

```
wrenctl install get-iso                       set up the get-iso command
wrenctl remove get-iso                        remove it (offers to delete the images kept in ~/ISOs)
wrenctl manual get-iso                        print the manual steps below

get-iso                 pick a system, download (or reuse) and check it, then offer a USB stick
get-iso NAME            the same for NAME: debian, tails, kicksecure, qubes, kali, parrot-security, parrot-home, arch
get-iso --list          what each is
```

The `get-iso` command (`bin/get-iso`) fetches the install image of another system: Debian 13's
network installer, Tails, Kicksecure, Qubes OS 4.3, Kali (the installer), Parrot Security and Parrot
Home, and Arch.

It finds the newest release in the project's own release list or folder over HTTPS, and downloads it
through Tor when the system tor service runs here (apt over Tor, remote access, the onion site), so
your network can't see which one you fetch.

It keeps the image only if it is that newest release and either its own signature or a signed list
of checksums that names it is by the project's key pinned in `pins.sh`: Debian's CD key
(`DEBIAN_CD_FPR`), the Tails signing key (`TAILS_FPR`), Patrick Schleizer's for Kicksecure
(`WHONIX_FPR`), the Qubes 4.3 release key (`QUBES_FPR`, certified by the Qubes master key), Kali's
(`KALI_FPR`), the Parrot Project's (`PARROT_FPR`) and Arch's release signer (`ARCH_ISO_FPR`).

A download that fails the checks is deleted. The checked image is kept in `~/ISOs/NAME` (the newest
only) and checked again before every use, for a VM in virt-manager or the next stick.

If you say so it lists only USB sticks, never the disk this system runs from, asks you to type the
stick's name, writes the image and reads it back to check (the same code as `tails-usb`). Nothing it
fetches is run on this computer.

## LIMITS

- Without Tor here, your network sees which system you download (not what you do with it later).
- A good signature says the project made the image, not that the system is safe to use: each has its
  own threat model (Kali and Parrot Security are toolboxes, not private desktops).
- Kali's live image comes only as a torrent, so get-iso fetches Kali's installer.
- Qubes signs each release series (4.3, 4.4...) with a key of its own: get-iso fetches only the
  series whose key is pinned (`QUBES_SERIES`), until a Wren Linux update pins the next one.
- Writing a stick erases everything on it.
- A stick left with someone can be swapped or changed: keep it with you, and remake it from a
  checked image if in doubt.

## MANUAL INSTALL

These are the steps get-iso takes, here for Debian; the others differ only in where the list and the
key are (see `lib/get-iso.sh`).

```
# wget and gpg to download and check it; torsocks to download through Tor
# (only if the system tor service runs here)
sudo apt install --no-install-recommends wget gpg python3 torsocks util-linux
mkdir -p ~/ISOs/debian && cd ~/ISOs/debian

# The signed checksum list of the current release, and the Debian CD key
# (put "torsocks" in front of each wget to download through Tor)
B=https://cdimage.debian.org/debian-cd/current/amd64/iso-cd
wget $B/SHA512SUMS $B/SHA512SUMS.sign
wget -O key.asc '@DEBIAN_CD_KEY_URL@'

# The key, in a keyring of its own. This must show the fingerprint @DEBIAN_CD_FPR@
mkdir -m 700 gpg
gpg --homedir gpg --import key.asc
gpg --homedir gpg --fingerprint @DEBIAN_CD_FPR@
# The list is signed by it: this must say "Good signature" with
# "Primary key fingerprint" @DEBIAN_CD_FPR@. Stop here if not.
gpg --homedir gpg --verify SHA512SUMS.sign SHA512SUMS

# The installer the list names, and its checksum: this must print "OK"
F=$(grep -o 'debian-[0-9.]*-amd64-netinst\.iso' SHA512SUMS)
wget $B/$F
grep " $F\$" SHA512SUMS | sha512sum -c

# The stick: find it by its size and name (TRAN usb). Make very sure it is
# the stick and not your disk: everything on it is erased.
lsblk -d -o NAME,SIZE,TRAN,MODEL
DEV=/dev/sdX
for p in $(lsblk -lnpo NAME,MOUNTPOINTS $DEV | awk 'NF > 1 { print $1 }'); do sudo umount $p; done
sudo dd if=$F of=$DEV bs=16M conv=fsync status=progress
sync
# Read it back: the two hashes must be the same
sha256sum $F
sudo head -c $(stat -c %s $F) $DEV | sha256sum
```

Then start the computer from the stick (its boot menu key is often F12, F9 or Esc).
