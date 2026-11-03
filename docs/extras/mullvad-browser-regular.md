# Mullvad Browser, as you (`extras/mullvad-browser-regular.sh`)

## SYNOPSIS

```
wrenctl install mullvad-browser-regular                     install it
wrenctl remove mullvad-browser-regular                      remove it (and Mullvad's repository, if Mullvad VPN isn't installed)
wrenctl manual mullvad-browser-regular                      print the manual steps below

mullvad-browser                                     start it (or Super+d); connect a VPN first
```

Mullvad Browser is made by the Tor Project and Mullvad: Tor Browser's
protections against tracking and fingerprinting, without Tor. It is meant for
use with a VPN, and forgets everything when closed. It comes from Mullvad's
own apt repository, whose signing key must be exactly the one pinned in
`pins.sh` (`MULLVAD_FPR`), and unattended-upgrades is told to install its
updates. It runs on X11, so XWayland is installed.

## LIMITS

- It doesn't hide your address: without a VPN, sites see it and your network sees where you go.
- It isn't Tor, and hiding your address doesn't hide who you are to a site you log in to.
- It runs as you, with no sandbox from Wren Linux (the sandboxed Firefox and `incognito` are that).
- It keeps its own DNS over HTTPS, which secure DNS (`parts/secure-dns.sh`) can't stop.

## MANUAL INSTALL

```
# Mullvad's signing key. Check it is exactly the pinned one: this must
# print one "pub" key with the fingerprint @MULLVAD_FPR@
wget -O /tmp/mullvad-keyring.asc @MULLVAD_KEY_URL@
gpg --show-keys --with-fingerprint /tmp/mullvad-keyring.asc
sudo install -D -m 0644 /tmp/mullvad-keyring.asc /usr/share/keyrings/mullvad-keyring.asc
rm /tmp/mullvad-keyring.asc

# The repository, trusted with that key only
echo "deb [signed-by=/usr/share/keyrings/mullvad-keyring.asc arch=$(dpkg --print-architecture)] https://repository.mullvad.net/deb/stable stable main" |
    sudo tee /etc/apt/sources.list.d/mullvad.list

# Let unattended-upgrades install its updates too (it takes only Debian's otherwise)
echo 'Unattended-Upgrade::Origins-Pattern:: "site=repository.mullvad.net";' |
    sudo tee /etc/apt/apt.conf.d/52wren-mullvad

# XWayland (it runs on X11) and the browser
sudo apt update
sudo apt install --no-install-recommends xwayland mullvad-browser
# If XWayland was new: log out and back in once, so sway starts it
```

To undo:

```
# Remove the browser
sudo apt purge mullvad-browser
# Only if Mullvad VPN isn't installed either: the repository, its key and the update rule
sudo rm /etc/apt/sources.list.d/mullvad.list /usr/share/keyrings/mullvad-keyring.asc
sudo rm /etc/apt/apt.conf.d/52wren-mullvad
sudo apt update
```
