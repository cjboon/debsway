# Mullvad VPN (`extras/mullvad-vpn.sh`)

## SYNOPSIS

```
wrenctl install mullvad-vpn                     install it
wrenctl remove mullvad-vpn                      disconnect and remove it (and Mullvad's repository, if Mullvad Browser isn't installed)
wrenctl manual mullvad-vpn                      print the manual steps below

mullvad account login 1234123412341234    log in with your account number
mullvad relay set location se [mma]       a country (se = Sweden), or a city in it
mullvad connect / status / disconnect
mullvad auto-connect set on               connect whenever the laptop starts
mullvad lockdown-mode set on              no internet while the VPN is off (Tor Browser too)
mullvad lan set allow                     still reach printers etc. at home
mullvad-vpn                               the graphical app (or Super+d)
```

Mullvad VPN sends all of this computer's traffic through an encrypted tunnel
to a Mullvad server, so your network and ISP see only that you use Mullvad,
and sites see the server's address instead of yours. You need a Mullvad
account number (mullvad.net; it can be paid anonymously). It comes from
Mullvad's own apt repository, whose signing key must be exactly the one pinned
in `pins.sh` (`MULLVAD_FPR`), and unattended-upgrades installs its updates.
You get the `mullvad` command, the service it talks to, and the graphical app
(its `mullvad-vpn` command is added to `~/.local/bin`, since the app lives in
`/opt`).

## LIMITS

- Mullvad sees where your traffic goes instead of your ISP: you trust Mullvad.
- A site you log in to still knows who you are.
- Without lockdown mode, traffic goes out unprotected while the VPN is off or reconnecting.
- It isn't Tor: one company, one hop. With Tor and Whonix: [A VPN before Tor](../vpn-before-tor.md).

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

# The VPN
sudo apt update
sudo apt install --no-install-recommends mullvad-vpn

# A command for the app, which lives in /opt, so Super+d finds it
install -D -m 0755 @WREN_DIR@/bin/mullvad-vpn ~/.local/bin/mullvad-vpn
```

To undo:

```
# Disconnect, then remove the VPN and its command
mullvad disconnect
sudo apt purge mullvad-vpn
rm ~/.local/bin/mullvad-vpn
# Only if Mullvad Browser isn't installed either: the repository, its key and the update rule
sudo rm /etc/apt/sources.list.d/mullvad.list /usr/share/keyrings/mullvad-keyring.asc
sudo rm /etc/apt/apt.conf.d/52wren-mullvad
sudo apt update
```
