# Feather, a Monero wallet (`extras/feather-wallet.sh`)

You get Feather, a graphical wallet for Monero, a privacy-focused digital currency. It is the official AppImage from featherwallet.org, installed only after debsway checks a digital signature and a checksum. The command is `feather`.

## The problem it solves

Feather is not in Debian's archive, and it is released as a single downloaded file. If you fetched that file by hand, you would have no way to know it was the real one. This script does the downloading and the checking for you, and refuses to install anything that fails.

## The ideas behind it

**Monero** is a digital currency like Bitcoin, but built to hide who paid whom and how much. A **wallet** is the program that holds the secret keys proving which coins are yours and that builds payments.

**A seed** is a list of words from which all your keys can be rebuilt. Anyone who has the words can take the money, and if you lose them and the wallet file, nobody can recover it. Write them on paper and keep them safe.

**An AppImage** is a whole program packed into one file, so it does not need installing through apt. debsway unpacks it with the file's own `--appimage-extract` option into `~/.local/opt/feather`. Because it is unpacked, the system does not need FUSE (a piece of software some AppImages need to run directly).

**A signature** is a mathematical seal made with a developer's secret key. Anyone with the matching public key can check it, and a changed file fails the check. Think of a wax seal on a letter.

**A fingerprint** is a short code identifying a public key. debsway keeps Feather's in `pins.sh` (`FEATHER_FPR`). It downloads the key, then accepts it only if the fingerprint is exactly that one.

**A checksum** (SHA-256) is a short code worked out from a file's contents. Feather publishes a signed list of them. If your download gives the same code as the list, it is the file that was listed.

**XWayland.** Feather asks for the older X11 window system (`QT_QPA_PLATFORM=xcb`), while sway uses Wayland. XWayland is a translation layer that lets X11 programs run inside sway.

## How it works, step by step

1. XWayland is installed if missing (`need_xwayland`). If it is the first X11 program, log out and back in once, so sway notices it. `gpg` is installed if missing.
2. It reads the newest release number from GitHub (`feather-wallet/feather`).
3. If that version is already recorded in `~/.local/opt/feather/.debsway-version`, it skips the download and goes to step 8.
4. Otherwise it downloads the hash list and the AppImage from `featherwallet.org/files/releases`.
5. `verify_clearsigned` fetches Feather's key into a throwaway keyring, checks it has the pinned fingerprint, then checks that the hash list is validly signed by that key. Only the signed text is kept.
6. `check_sha256` checks the AppImage against its line in that list. Any failure stops the install.
7. `install_appimage` unpacks it and moves it into `~/.local/opt/feather`. The old version is replaced.
8. `write_launcher` writes `~/.local/bin/feather`, a small script that runs `~/.local/opt/feather/usr/bin/feather` with `QT_QPA_PLATFORM=xcb`. (The AppImage's own start script only works under the AppImage runtime, so the launcher runs the program directly.)

## What it changes on your computer

- Package `xwayland` (if missing) and `gpg` (if missing), under the marker package `debsway-feather-wallet`.
- `~/.local/opt/feather/`, the unpacked program, with a `.debsway-version` file.
- `~/.local/bin/feather`.
- Later, wallet files wherever you choose to save them.

## Using it

- `feather` or Super+d, then `feather`: start the wallet.
- `bash extras/feather-wallet.sh` again: update to the newest release.
- `bash test.sh` tells you when a newer release is out.

## What it protects against

- **A swapped or corrupted download.** Nothing is unpacked until the signature and the checksum both pass.
- **A fake key.** The key must have the pinned fingerprint.

## What it doesn't protect against

- **Anything running as you.** debsway does not sandbox your user. Feather and any other program you run can read the same files, including wallets (`THREAT-MODEL.md`).
- **Automatic updates.** AppImages are not updated by apt. `THREAT-MODEL.md` lists Feather by name as one you must update yourself by running the script again.
- **Bugs in Feather**, or a compromised developer key. The signature shows who published it, not that it is flawless.
- **A lost seed.**
- **Privacy at the network level.** The script sets up no Tor or VPN.

## Removing it

`bash extras/feather-wallet.sh --remove` deletes `~/.local/opt/feather` and `~/.local/bin/feather` (only if debsway wrote it), then removes the packages this script added that nothing else needs. Your wallet files are left where you saved them.
