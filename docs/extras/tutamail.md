# Tuta Mail, encrypted email (`extras/tutamail.sh`)

You get the Tuta Mail desktop app (Tuta was called Tutanota until 2023), an end-to-end encrypted email client, as the official AppImage from Tuta's own server. debsway installs it only after checking Tuta's digital signature on it. The command is `tuta`.

## The problem it solves

Tuta's desktop app is not in Debian's archive. It is one large file (about 150 MB) on `app.tuta.com`. Downloading and running it by hand means trusting that nobody swapped it on the way or on the server. This script checks the file against Tuta's signature first.

## The ideas behind it

**End-to-end encrypted email.** Tuta encrypts your mailbox, contacts and calendar so that its servers store them scrambled. Mail between two Tuta users is end-to-end encrypted; mail to other providers is not, unless you send it password-protected. The script does not set up or check any of that. It only installs the app.

**An AppImage** is a program packed into one file. debsway runs the file's own `--appimage-extract` option and keeps the result in `~/.local/opt/tuta`, so FUSE (a helper some AppImages need) is not needed.

**A signature** is a mathematical seal made with a developer's secret key. A changed file fails the check. Think of a wax seal on a letter. Tuta signs its installers with `openssl` (RSA with SHA-512), not with gpg as most makers do.

**The pinned key.** debsway ships Tuta's public code-signing key as `data/tuta-pub.pem` (a copy of `tutao-pub.pem` from Tuta's GitHub repository, unchanged there since 2019). `pins.sh` records its SHA-256 (`TUTA_KEY_SHA256`); the script refuses the key file if it doesn't match, and `bash test.sh` checks that the copy on GitHub is still that key.

**Version checks.** Tuta's release file (`latest-linux.yml`), which names the newest version, is not signed itself. So after unpacking, the script checks that the signed app inside really is that version (its `package.json`), and it never replaces your version with an older one. An old release, signed back then, can't be passed off as an update.

**Electron's sandbox.** The app is an Electron program (a browser engine with Tuta's web app inside). Electron keeps the part that shows mail in a sandbox. The AppImage's own start script (`AppRun`) quietly switches that sandbox off when the system can't make a user namespace, so debsway's launcher starts the app directly instead: if the sandbox can't start, the app doesn't either. It runs on Wayland itself, so no XWayland is needed.

## How it works, step by step

1. `openssl` and `wget` are installed if missing, then the system libraries the app's Electron binary links to (GTK, NSS, ALSA and others; the full list is `LIBS` in the script), `libsecret` for saving your login in a keyring, and `xdg-utils` so links in mails open in your browser.
2. It downloads `latest-linux.yml` from `https://app.tuta.com/desktop` and reads the version from it. A version that isn't plain numbers and dots stops the script.
3. If that version is already in `~/.local/opt/tuta/.debsway-version`, it skips the download and goes to step 7. If the server offers an older version than the installed one, it stops.
4. Otherwise it downloads `linux-sig.bin` and `tutanota-desktop-linux.AppImage`.
5. `verify_rsa_sha512` checks that `data/tuta-pub.pem` is the pinned key, then that it signed the AppImage. Failure stops the install.
6. `install_appimage` unpacks it, checks the app inside is the version named in step 2, and only then replaces the older version in `~/.local/opt/tuta`.
7. `write_launcher` writes `~/.local/bin/tuta`, which runs the app on Wayland.

## What it changes on your computer

- Packages: `openssl` and `wget` if missing, and the libraries listed above, under the marker package `debsway-tutamail`.
- `~/.local/opt/tuta/` with a `.debsway-version` file.
- `~/.local/bin/tuta`.
- Later, the app's own settings and offline data in `~/.config/tutanota-desktop`.

## Using it

- `tuta` or Super+d, then `tuta`: start the app.
- To stay logged in between starts, Tuta stores a key in your keyring. It won't put it in a plain file, so without a keyring (`bash ~/debsway/extras/seahorse.sh`) you log in each time.
- `bash extras/tutamail.sh` again: update to the newest release. The app's own updater doesn't update the unpacked copy.
- `bash test.sh` tells you when a newer release is out.

## What it protects against

- **A swapped or corrupted download.** Nothing is unpacked into place until the signature, by the pinned key, passes.
- **A fake key.** The key file must have the pinned SHA-256.
- **Being sent back to an old release** (one with known bugs) by a changed release file. The version must match the signed app, and an older one is refused.
- **The sandbox being switched off without a word** by the AppImage's start script.

## What it doesn't protect against

- **Anything running as you.** The app and your other programs share one user. Anything that can read your files can read the app's data, including mail it keeps offline (`THREAT-MODEL.md`).
- **Automatic updates.** The app is not updated by apt. Run the script again; `test.sh` says when to.
- **A first install that is an old release.** On the first install there is no version to compare with: an old release, signed back then and served with a matching release file, would be taken. Tuta's server is reached over HTTPS, which makes that hard.
- **Hiding your network address.** The script sets up no Tor or VPN for the app. Tuta's servers and your network see that you connect.
- **Bugs in the app**, or a compromised Tuta signing key.
- **Someone with your unlocked laptop.**

## Removing it

`bash extras/tutamail.sh --remove` deletes `~/.local/opt/tuta` and `~/.local/bin/tuta` (only if debsway wrote it), then removes the packages this script added that nothing else needs. The app's data in `~/.config/tutanota-desktop` is left in place.
