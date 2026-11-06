# Phone tethering over USB (`extras/phone-tethering.sh`)

## SYNOPSIS

```
wrenctl install phone-tethering                     install it
wrenctl remove phone-tethering                      remove it
wrenctl manual phone-tethering                      print the manual steps below

Android: plug it in, then Settings > Network > Hotspot & tethering > USB tethering
iPhone:  plug it in, tap Trust, then Settings > Personal Hotspot
         (if the computer doesn't see it: idevicepair pair)
tether                 find the phone, ask, and connect (a window asks by itself, while offline)
tether --list          only show what it finds
wrenctl --wifi off     use only the phone's data
```

This uses a phone's mobile data on this computer through the USB cable. An Android
phone needs nothing extra: the `tether` command is in the base install
(`parts/tether.sh`), with or without NetworkManager. An iPhone also needs usbmuxd and the
pairing tools this installs from Debian. While you are offline in sway, a phone appearing
opens a window that asks whether to connect; it connects only if you say so. Otherwise, type
`tether`. It uses NetworkManager if that is running, else `dhcpcd`, `dhclient` or busybox,
whichever is there, with your sudo password. It sends no name for this computer, and leaves
secure DNS alone. A phone's Wi-Fi hotspot is just a Wi-Fi network, with nothing to install.

## LIMITS

- Your mobile provider sees where your traffic goes, as a home provider would; use a VPN or Tor on top for that.
- The phone sees all your traffic: it's a computer you have to trust.
- Tapping Trust lets this computer talk to the iPhone: don't tether through a port or charger you don't trust.
- `tether` can't tell a phone from another USB device with the same driver, and USB network adapters use some of them too. It shows what it found: if you didn't just plug in a phone, say no. Whoever runs that network sees where your traffic goes, and can choose your route.
- NetworkManager still connects a new USB device by itself if its driver isn't one phones use (`parts/tether.sh` names `rndis_host`, `cdc_ether`, `cdc_ncm` and `ipheth`). So a USB device that pretends to be some other network card still gets a connection: don't plug in USB devices you don't trust.
- `tether`'s connection steps were tried with real DHCP clients and a real NetworkManager on stand-in network devices, and its window in a headless sway. It hasn't been tried with a real phone by these tests.

## MANUAL INSTALL

```
# usbmuxd and the pairing tools, for an iPhone (Android needs nothing)
sudo apt install --no-install-recommends usbmuxd libimobiledevice-utils
# Then the tether command connects it (parts/tether.sh, in the base install)
tether
```

To undo:

```
# The iPhone tools (usbmuxd marked "automatic" instead of purged: other
# programs can need it, and autoremove takes it out only if nothing does)
sudo apt purge libimobiledevice-utils
sudo apt-mark auto usbmuxd
sudo apt autoremove --purge
```
