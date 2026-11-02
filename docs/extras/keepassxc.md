# KeePassXC (`extras/keepassxc.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/keepassxc.sh            install it (switches a full build to the minimal one)
bash ~/debsway/extras/keepassxc.sh --remove   remove it (your .kdbx files stay)
bash ~/debsway/extras/keepassxc.sh --manual   print the manual steps below

keepassxc                                     start it (or Super+d, then keepassxc)
  Ctrl+C on an entry copies its password: paste it into the page
```

KeePassXC is a password manager that keeps all your passwords, and two-factor
codes (TOTP) if you like, in one encrypted file you control. debsway installs
Debian's minimal build, `keepassxc-minimal`: no browser integration and no
KeePassXC-Browser add-on for Firefox, so no web page, and not the sandboxed
Firefox either, has a way to talk to it. You copy and paste a password, or use
auto-type. qtwayland5 lets it run on Wayland. On a computer with the full build
(`keepassxc-full`, with `webext-keepassxc-browser`), the script switches to the
minimal one.

## LIMITS

- Anything running as you can read the database file, watch the clipboard and log your master password as you type it.
- A copied password stays on the clipboard until something replaces it.
- While the database is open, its contents are in memory; lock it when you step away.
- A weak or lost master password, or a lost file (back it up), can't be helped by it.

## MANUAL INSTALL

```
# Take out the full build and its Firefox add-on, if they are there
sudo apt purge keepassxc-full keepassxc webext-keepassxc-browser
# The minimal build, and Qt's Wayland support so it runs without XWayland
sudo apt install --no-install-recommends keepassxc-minimal qtwayland5
keepassxc
```

To undo (your password databases, `.kdbx` files, stay where they are):

```
# Remove KeePassXC
sudo apt purge keepassxc-minimal
sudo apt autoremove --purge
```
