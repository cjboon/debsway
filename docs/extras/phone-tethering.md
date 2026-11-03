# Phone tethering over USB (`extras/phone-tethering.sh`)

## SYNOPSIS

```
debsway install phone-tethering                     install it
debsway remove phone-tethering                      remove it
debsway manual phone-tethering                      print the manual steps below

Android: plug it in, then Settings > Network > Hotspot & tethering > USB tethering
iPhone:  plug it in, tap Trust, then Settings > Personal Hotspot
         (if the computer doesn't see it: idevicepair pair)
debsway --wifi off     use only the phone's data
```

This uses a phone's mobile data on this computer through the USB cable. An
Android phone needs nothing but NetworkManager, already in the base install.
An iPhone also needs usbmuxd and the pairing tools this installs from Debian.
Either way, a new wired connection then appears (`nmtui` shows it). A phone's
Wi-Fi hotspot is just a Wi-Fi network, with nothing to install.

## LIMITS

- Your mobile provider sees where your traffic goes, as a home provider would; use a VPN or Tor on top for that.
- The phone sees all your traffic: it's a computer you have to trust.
- Tapping Trust lets this computer talk to the iPhone: don't tether through a port or charger you don't trust.

## MANUAL INSTALL

```
# usbmuxd and the pairing tools, for an iPhone (Android needs nothing)
sudo apt install --no-install-recommends usbmuxd libimobiledevice-utils
# NetworkManager brings the phone's connection up: this must say "running"
nmcli general status
```

To undo:

```
# The iPhone tools (usbmuxd marked "automatic" instead of purged: other
# programs can need it, and autoremove takes it out only if nothing does)
sudo apt purge libimobiledevice-utils
sudo apt-mark auto usbmuxd
sudo apt autoremove --purge
```
