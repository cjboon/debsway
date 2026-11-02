# Electrum (`extras/electrum.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/electrum.sh            install it
bash ~/debsway/extras/electrum.sh --remove   remove it (wallets in ~/.electrum stay)
bash ~/debsway/extras/electrum.sh --manual   print the manual steps below

electrum                                     start it (or Super+d, then electrum)
```

Electrum is a Bitcoin wallet, installed from Debian's own archive, which
keeps it patched along with the rest of the system. It runs on Wayland
through qtwayland5. Wallets are kept in `~/.electrum`: write down the seed it
shows when you make one, because nothing else can bring a lost wallet back.

## LIMITS

- It runs as you: anything that can read your files can read `~/.electrum`.
- It asks a server about your addresses to learn your balance; nothing here sets up Tor or your own server for it.
- debsway doesn't back up your seed, and can't.
- Debian's version can be a little behind the newest release.

## MANUAL INSTALL

```
# Electrum, and Qt's Wayland support so it runs without XWayland
sudo apt install --no-install-recommends electrum qtwayland5
electrum
```

To undo (your wallets stay in `~/.electrum`; back them up before deleting anything):

```
# Remove Electrum and its library
sudo apt purge electrum python3-electrum
sudo apt autoremove --purge
```
