# Sparrow, a Bitcoin wallet with extra privacy tools (`extras/sparrow-wallet.sh`)

You get Sparrow, a Bitcoin wallet with finer control over which coins you spend, built-in Tor support and good support for hardware wallets. It comes from Sparrow's official download, and debsway checks a digital signature before installing it. The command is `sparrow`.

## The problem it solves

Sparrow is not in Debian's archive, so apt cannot fetch it. You would have to download a file from the internet and install it as root. If that file were swapped on the way, you would be giving a stranger's program full control of your computer. This script downloads it and proves it came from the developer first.

## The ideas behind it

**A Bitcoin wallet and a seed.** A wallet holds secret keys that prove which Bitcoin entries are yours. A seed is a list of words from which all those keys can be rebuilt. Whoever has the words has the money, and if you lose them, nobody can recover it. Keep them on paper, somewhere safe.

**Coin control** means choosing which individual coins a payment spends, instead of letting the wallet pick. It matters for privacy, because coins spent together are visible together in the public record.

**A hardware wallet** is a small device that holds your keys and signs payments itself, so the keys never touch the computer. Sparrow can work with these.

**A digital signature** is a mathematical seal that only the holder of a secret key can make, and anyone with the matching public key can check. If the file is changed by even one letter, the check fails. It works like a wax seal on a letter.

**A fingerprint** is a short code that identifies a public key. debsway keeps Craig Raw's fingerprint in `pins.sh` (`SPARROW_FPR`). It downloads his key, and refuses it unless its fingerprint is exactly that. This stops someone handing you a different key.

**A checksum** (SHA-256) is a short code worked out from a file's contents. The developer publishes a signed list of them (the "manifest"). If your download gives the same code, it is the file the developer listed.

**XWayland.** Sparrow is a Java program with a JavaFX window, which only knows the older X11 window system. sway uses Wayland, so XWayland, a translation layer, runs X11 programs inside it.

## How it works, step by step

1. It asks GitHub what the newest Sparrow version is, and refuses to go on unless the answer looks like a version number (such as `2.0.0`).
2. If that version is already installed as a complete package, it says so and skips ahead to the command.
3. Otherwise it downloads three files into a temporary folder: the `.deb` package, the manifest, and the manifest's signature (`.asc`).
4. `verify_detached` (in `lib/appimage.sh`) fetches Craig Raw's key from keybase into a throwaway keyring, checks its fingerprint, and checks the manifest's signature. A valid signature from any other key does not count.
5. `check_sha256` compares the package's checksum with the line for it in the signed manifest. A mismatch stops the install.
6. It installs XWayland if missing (`need_xwayland`). On a fresh install you must log out and back in once, so sway notices it.
7. It makes the folder `/usr/share/desktop-directories`, because the package's install script fails without it, then installs the `.deb` with apt.
8. `install_bin sparrow` copies `bin/sparrow` to `~/.local/bin/sparrow`, a one-line launcher for `/opt/sparrowwallet/bin/Sparrow`.

On first start Sparrow asks which server to use. A public server sees your wallet's addresses. Sparrow's Tor (proxy) setting hides your IP address from it. Your own Bitcoin node is the most private choice.

## What it changes on your computer

- Package `sparrowwallet`, in `/opt/sparrowwallet`, plus `xwayland` if it was missing. Both are recorded under the marker package `debsway-sparrow-wallet`.
- `/usr/share/desktop-directories` (an empty folder).
- `~/.local/bin/sparrow`.
- Later, when you use it, your wallets in `~/.sparrow`.

## Using it

- `sparrow` or Super+d, then `sparrow`: start the wallet.
- `bash extras/sparrow-wallet.sh` again: install a newer release if there is one.
- `bash test.sh` tells you when a newer release exists.

## What it protects against

- **A swapped or corrupted download.** The package must match a list signed by the pinned key before it is installed as root.
- **A fake key.** The key is accepted only if its fingerprint is the pinned one.
- **Your IP address being seen by the server**, if you turn on Sparrow's Tor setting. That is Sparrow's feature. The script does not switch it on.

## What it doesn't protect against

- **Anything running as you.** debsway does not sandbox your user, and `~/.sparrow` is readable by any program you run (`THREAT-MODEL.md`).
- **A bug in Sparrow itself.** The signature proves who published it, not that it is free of bugs or honest.
- **Automatic updates.** This package does not update itself through apt. You must run the script again.
- **A compromised developer key or release.** debsway only trusts the pinned key.
- **A public server learning your addresses**, unless you use your own node.
- **A lost seed.**

## Removing it

`bash extras/sparrow-wallet.sh --remove` recreates `/usr/share/desktop-directories` (the package's removal script needs it), purges `sparrowwallet`, removes `~/.local/bin/sparrow`, and lets apt remove what only it needed. It keeps `~/.sparrow`, with your wallets. Back them up before deleting anything.
