# KeePassXC (`extras/keepassxc.sh`)

## SYNOPSIS

```
wrenctl install keepassxc                     install it (switches a full build to the minimal one)
wrenctl remove keepassxc                      remove it (your .kdbx files stay)
wrenctl manual keepassxc                      print the manual steps below

keepassxc                                     start it (or Super+d, then keepassxc)
  Ctrl+C on an entry copies its password: paste it into the page
```

KeePassXC is a password manager that keeps all your passwords, and two-factor
codes (TOTP) if you like, in one encrypted file you control. Wren Linux installs
Debian's minimal build, `keepassxc-minimal`: no browser integration and no
KeePassXC-Browser add-on for Firefox, so no web page, and not the sandboxed
Firefox either, has a way to talk to it. You copy and paste a password, or use
auto-type. qtwayland5 lets it run on Wayland. On a computer with the full build
(`keepassxc-full`, with `webext-keepassxc-browser`), the script switches to the
minimal one. Whenever the screen locks (Super+Escape, the idle lock, the lid,
before sleep), it locks its open databases too: an on-lock program,
`~/.config/wren/on-lock.d/keepassxc`, runs `keepassxc --lock`. It asks once whether
KeePassXC should open on workspace 2 at every login; after that your list of what
opens at login says (`wren-autostart edit`).

## LIMITS

- Unlocked, while you use the computer, its passwords are one window away from anything running as you. Its own settings can lock it sooner: Settings, Security, lock databases after a few minutes of inactivity.

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
# Locked whenever the screen locks: an on-lock program (Wren Linux runs these at every lock)
mkdir -p ~/.config/wren/on-lock.d
printf '%s\n' '#!/bin/sh' 'pgrep -x -u "$(id -u)" keepassxc >/dev/null || exit 0' 'exec keepassxc --lock' >~/.config/wren/on-lock.d/keepassxc
chmod 755 ~/.config/wren/on-lock.d/keepassxc
# Optional: on workspace 2 at every login
# (with Wren Linux's parts/autostart.sh; or add the line to the file by hand)
wren-autostart add 2 keepassxc
keepassxc
```

To undo (your password databases, `.kdbx` files, stay where they are):

```
# Remove KeePassXC, its on-lock program and its start at login
rm -f ~/.config/wren/on-lock.d/keepassxc
wren-autostart remove keepassxc
sudo apt purge keepassxc-minimal
sudo apt autoremove --purge
```
