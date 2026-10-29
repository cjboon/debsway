# Tails on a USB stick (`extras/tails-usb.sh`)

Tails is a whole operating system that runs from a USB stick, sends everything through Tor and forgets everything when you shut it down. This extra gives you a command, `tails-usb`, that downloads the newest Tails, checks it, and writes it to a USB stick you choose.

## The problem it solves

Making a Tails stick by hand means downloading a 2 GB file, checking its signature with gpg, and writing it with `dd`. The easy mistakes are skipping the check and writing to the wrong disk. `tails-usb` does the check every time and only offers USB sticks.

## How it works, step by step

1. It reads Tails' own release file (tails.net) for the newest version, its image address, SHA-256 and size.
2. It downloads the image, its signature and the Tails signing key. When the system tor service runs here (apt over Tor, remote access, the onion site), it downloads through Tor (`torsocks`), so your network can't see you fetch Tails; otherwise it asks before downloading directly.
3. It uses the image only if the signature is good and made by the Tails signing key (fingerprint pinned in `pins.sh`, `TAILS_FPR`), **and** the image is exactly the one the release file names (size and SHA-256). The second check stops an older, genuinely signed Tails with known holes from being slipped in. A download that fails is deleted.
4. It keeps the newest checked copy in `offline/tails/` and checks it again before each use, so the next stick needs no download.
5. It lists only USB disks: never the disk the system runs from, never one holding `/`, `/boot`, `/home` or swap. You pick one and type its name to confirm. Sticks under 8 GB are refused. Mounted partitions on it are unmounted.
6. It writes the image, flushes the stick's cache, reads it back and compares, so a failed write or a faulty stick is caught.

## Using it

- `tails-usb`: make a stick (everything on it is erased, Persistent Storage included).
- Start the computer from the stick through its boot menu (often F12, F9, F10, F11 or Esc; on a Mac hold Option), connect to Tor in the Tor Connection window (with a bridge if needed), and shut down from the menu when done. Tails' own guide: https://tails.net/doc/

## What it protects against

- A tampered or swapped download, and an outdated image passed off as the newest.
- Writing to the wrong disk: only USB disks are offered, and you type the name.
- Your network seeing you download Tails, when Tor runs here.

## What it doesn't protect against

- Anything about how you use Tails afterwards: see Tails' documentation and `docs/opsec.md`.
- A compromised Tails release or signing key; debsway trusts the pinned key.
- Without Tor set up here, your network sees the download from tails.net.

## Removing it

`bash extras/tails-usb.sh --remove` removes the `tails-usb` command and `torsocks` (unless something else needs it) and asks whether to delete the saved image in `offline/tails/`. Sticks you made keep working; Tails updates itself.
