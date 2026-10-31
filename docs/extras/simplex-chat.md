# SimpleX Chat, a private messenger (`extras/simplex-chat.sh`)

You get the SimpleX Chat desktop app, an end-to-end encrypted messenger, as the official AppImage from GitHub. debsway installs it only after checking a digital signature and a checksum. The command is `simplex`.

## The problem it solves

SimpleX is not in Debian's archive. It is a large single file (about 350 MB), released on GitHub. Downloading and running it by hand means trusting that nobody swapped it. This script checks the file against the developers' signed list first.

## The ideas behind it

**A messenger with end-to-end encryption** scrambles a message on your device so only the person you send it to can read it, and not the servers in between. SimpleX describes itself as a messenger without user accounts or phone numbers. The script itself does not set up, change or verify any of that. It only installs the app.

**An AppImage** is a program packed into one file. debsway runs the file's own `--appimage-extract` option and keeps the result in `~/.local/opt/simplex`, so FUSE (a helper some AppImages need) is not needed.

**A signature** is a mathematical seal made with a developer's secret key. A changed file fails the check. Think of a wax seal on a letter.

**A fingerprint** identifies a public key by a short code. debsway pins SimpleX's release key (`build@simplex.chat`, `SIMPLEX_FPR` in `pins.sh`), downloads it and accepts it only if the fingerprint matches.

**A checksum** (SHA-256) is a short code worked out from a file's contents. SimpleX publishes a signed list of them in `_sha256sums`.

**XWayland.** The app is a Java program, and Java's windows use the older X11 system. sway uses Wayland, so XWayland translates.

## How it works, step by step

1. XWayland is installed if missing (`need_xwayland`). If it is new, log out and back in once so sway notices it. `gpg` is installed if missing.
2. It installs a list of system libraries that the app's bundled Java and media code use (`libx11-6`, `libasound2t64`, `libgl1`, `libusb-1.0-0` and others; the full list is `LIBS` in the script).
3. It reads the newest release tag from GitHub (`simplex-chat/simplex-chat`).
4. If that tag is already recorded in `~/.local/opt/simplex/.debsway-version`, it skips the download and goes to step 9.
5. Otherwise it downloads `_sha256sums`, `_sha256sums.asc` and `simplex-desktop-x86_64.AppImage`.
6. `verify_detached` checks the key's fingerprint and then the signature on `_sha256sums`.
7. `check_sha256` checks the AppImage against its line in that list (named as `TAG/simplex-desktop-x86_64.AppImage`). Failure stops the install.
8. `install_appimage` unpacks it into `~/.local/opt/simplex`, replacing the older version.
9. `write_launcher` writes `~/.local/bin/simplex`, which runs the unpacked `AppRun` start script.

## What it changes on your computer

- Packages: `xwayland`, `gpg` if missing, and the libraries listed above, under the marker package `debsway-simplex-chat`.
- `~/.local/opt/simplex/` with a `.debsway-version` file.
- `~/.local/bin/simplex`.
- Later, your chats and profile data, which the app creates itself.

## Using it

- `simplex` or Super+d, then `simplex`: start the app.
- `bash extras/simplex-chat.sh` again: update to the newest release.
- `bash test.sh` tells you when a newer release is out.

## What it protects against

- **A swapped or corrupted download.** Nothing is unpacked until the signature and the checksum both pass.
- **A fake key.** The key must have the pinned fingerprint.

## What it doesn't protect against

- **Anything running as you.** The app and your other programs share one user. Anything that can read your files can read your chats (`THREAT-MODEL.md`).
- **Automatic updates.** AppImages are not updated by apt. `THREAT-MODEL.md` names SimpleX as one to update by running the script again.
- **Hiding your network address.** The script configures no Tor or VPN for the app. Your network sees that you are connecting, as for any app.
- **Bugs in the app**, or a compromised release key.
- **Someone with your unlocked laptop.**

## Removing it

`bash extras/simplex-chat.sh --remove` deletes `~/.local/opt/simplex` and `~/.local/bin/simplex` (only if debsway wrote it), then removes the packages this script added that nothing else needs. Your chats and profile data are left in place.
