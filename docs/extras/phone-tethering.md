# Phone tethering over USB (`extras/phone-tethering.sh`)

This lets your computer use a phone's mobile data through the USB cable. For an Android phone it installs nothing important, because the phone does the work. For an iPhone it installs two small packages that let the computer talk to it.

## The problem it solves

You are somewhere with no Wi-Fi you trust, or none at all, but your phone has mobile data. Tethering means sharing the phone's connection with your computer. A cable is more private than Wi-Fi: no one nearby can see the radio signal or try to join your network.

## The ideas behind it

**Tethering.** Using your phone as the "modem" for another device.

**USB tethering vs a Wi-Fi hotspot.** USB tethering uses the cable. A hotspot makes the phone a Wi-Fi network. A hotspot is just a Wi-Fi network: pick it in `nmtui`, nothing to install.

**NetworkManager.** The program that manages connections on debsway. When the phone appears as a network card, NetworkManager brings the connection up. `nmtui` is its text menu.

**usbmuxd.** A helper that lets a computer talk to an iPhone over USB. **libimobiledevice** is a set of tools for that; its `idevicepair` command pairs the computer with the phone. **Pairing** means the phone agrees to trust this computer; you tap Trust on the phone.

## How it works, step by step

1. Installs `usbmuxd` and `libimobiledevice-utils` with apt.
2. Checks that NetworkManager is installed. If not, it warns you and names `parts/network-manager.sh`.
3. Prints instructions.

Nothing else happens. Later, when you plug the phone in and turn on tethering on the phone, a new wired connection appears by itself.

## What it changes on your computer

- Packages: `usbmuxd`, `libimobiledevice-utils`.
- Nothing else: no files of its own, no users, no firewall rules, nothing in `~/.local/bin`.

## Using it

- **Android:** plug the phone in, then Settings > Network > Hotspot & tethering > USB tethering.
- **iPhone:** plug it in, tap Trust on the phone, then Settings > Personal Hotspot. If the computer does not see it, run `idevicepair pair`.
- A new wired connection appears; `nmtui` shows it.
- To use only the phone's data, switch Wi-Fi off: `debsway --wifi off` (or the debsway menu > Wi-Fi).

## What it protects against

- **People near you on a shared Wi-Fi.** Your traffic does not cross a Wi-Fi network you do not control.
- **Wi-Fi radio exposure,** since you can switch Wi-Fi off while using the cable (`debsway --wifi off` uses the system's radio switch, rfkill).

## What it doesn't protect against

- **Your mobile provider seeing your traffic's destinations,** just as a home provider would. It is another network, not a private one.
- **The phone itself.** It can see your traffic and is a computer you have to trust.
- **Anything a VPN or Tor does.** Use `extras/mullvad-vpn.sh` or Tor Browser on top.
- **Plugging into untrusted USB.** Tapping Trust on an iPhone lets this computer talk to it; do not tether through a charger or port you do not trust (the script does nothing about that).
- **Data costs and limits** from your phone plan.

## Removing it

`bash extras/phone-tethering.sh --remove` uninstalls `usbmuxd` and `libimobiledevice-utils`. NetworkManager and any saved connection stay.
