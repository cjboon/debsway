# wifi.sh

It finds your Wi-Fi card, turns it on if it's blocked in software, shows
nearby networks, asks for the name and password, connects, and saves the
network so it reconnects at boot. Wrong passwords are caught and you get
three tries. Once `install-base.sh` has run, NetworkManager takes over
and `nmtui` is the everyday tool; wifi.sh is for getting online the
first time, or rescuing a broken setup.

It uses the first of these that works:

| What's installed | How it connects | Saved for boot by |
|---|---|---|
| NetworkManager (running) | `nmcli` | NetworkManager |
| iwd | `iwctl` | iwd (it also enables iwd's own DHCP) |
| wpa_supplicant + ifupdown + dhcpcd/dhclient | checks the password, then `ifup` | `/etc/network/interfaces.d/debsway-wifi-<dev>` |
| wpa_supplicant without a DHCP client | `wpa_supplicant@<dev>` service | that service + systemd-networkd |
| nothing | installs wpasupplicant from `offline/debs/`, then as above | |
| nothing, and no `offline/debs/` | asks for Ethernet or USB tethering, installs wpasupplicant with apt | |

It also handles a missing firmware (installs it from `offline/debs/` and reloads
the driver), Wi-Fi switched off in hardware, hidden and open networks,
an installer that already set up Wi-Fi (asks first, keeps a backup of
`/etc/network/interfaces`), and getting an address without any DHCP
client (systemd-networkd, or busybox). USB tethering from a phone shows
up as a wired network, so it works with no Wi-Fi software at all.

## Packages from the USB stick are checked

Debian's packages aren't signed one by one. The archive signs a list of
the packages' hashes instead, so `prep/fetch-offline-debs.sh` saves those
signed lists in `offline/debs/verify/` next to the `.deb` files. Before
`wifi.sh` installs anything from the stick (as root), it checks the lists
against Debian's archive keyring, which is already on every Debian system,
and then every package against the lists. A package that was changed, or
added, or that isn't Debian's, stops the installation. `bash
prep/fetch-offline-debs.sh --check` refreshes the lists and checks what you
have saved; `bash test.sh` also checks it, without internet.

## Passwords

`wifi.sh` never puts your Wi-Fi password on a command line, where any
program running on the computer could read it: NetworkManager gets it on
its standard input, iwd from a file only root can read, and wpa_supplicant
from a config file only root can read. If your `nmcli` doesn't accept the
password that way, `DEBSWAY_PASSWORD_ON_COMMAND_LINE=1 bash wifi.sh` uses
the old way.
