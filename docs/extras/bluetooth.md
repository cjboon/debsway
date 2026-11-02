# Bluetooth (`extras/bluetooth.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/bluetooth.sh            install it (the adapter is off at every boot)
bash ~/debsway/extras/bluetooth.sh --remove   remove it
bash ~/debsway/extras/bluetooth.sh --manual   print the manual steps below

debsway --bluetooth on|off     switch the adapter (or the debsway menu > Bluetooth)
bluetoothctl                   pair a device: type
  scan on                      (wait until the device shows up)
  pair AA:BB:...   trust AA:BB:...   connect AA:BB:...
```

Bluetooth for headphones, keyboards, mice and a phone's connection: bluez
from Debian (its `bluetoothctl` pairs devices in a terminal), rfkill to switch
the radio, and, if sound is set up (`extras/pipewire-audio.sh`), the part of
PipeWire that plays sound over Bluetooth. The adapter starts switched off at
every boot (`AutoEnable=false` in `/etc/bluetooth/main.conf`), so no radio
listens while you aren't using it; switch it on from the debsway menu, and off
again when you are done.

## LIMITS

- While it's on, devices nearby can see this computer and try to talk to it, and Bluetooth has had serious bugs.
- A paired device you trust can connect again whenever the adapter is on.
- Bluetooth keyboards and headphones can be listened to from nearby, more easily than a cable.

## MANUAL INSTALL

```
# bluez, and rfkill to switch the radio
sudo apt install --no-install-recommends bluez rfkill
# Only with sound set up: PipeWire's Bluetooth sound
sudo apt install --no-install-recommends libspa-0.2-bluetooth
# The switch the debsway menu uses (debsway --bluetooth calls it)
install -D -m 0755 @DEBSWAY_DIR@/bin/radios ~/.local/bin/radios

# Off at every boot: set AutoEnable=false (add a [Policy] section with it if
# the file has no AutoEnable line), then check it shows "AutoEnable=false"
sudo sed -i -E 's/^[#[:space:]]*AutoEnable=.*/AutoEnable=false/' /etc/bluetooth/main.conf
grep -q '^AutoEnable=' /etc/bluetooth/main.conf || printf '\n[Policy]\nAutoEnable=false\n' | sudo tee -a /etc/bluetooth/main.conf
grep -n '^AutoEnable' /etc/bluetooth/main.conf

# The service, and the radio off now too
sudo systemctl enable --now bluetooth.service
~/.local/bin/radios bluetooth off
```

To undo:

```
# Back to Debian's default (the adapter on at boot)
sudo sed -i 's/^AutoEnable=false$/#AutoEnable=true/' /etc/bluetooth/main.conf
# bluez and PipeWire's Bluetooth part (marked "automatic" instead of purged:
# autoremove takes it out only if nothing needs it)
sudo apt purge bluez
sudo apt-mark auto libspa-0.2-bluetooth
sudo apt autoremove --purge
```
