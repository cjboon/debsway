# Bluetooth, off until you want it (`extras/bluetooth.sh`)

This installs Bluetooth support for headphones, keyboards, mice and a phone's connection, but sets the Bluetooth adapter to start switched off at every boot. You switch it on when you need it and off when you are done.

## The problem it solves

A Bluetooth radio that is on is a radio that other devices can try to talk to. Most of the time you do not need it. Many systems turn it on by default and leave it on. debsway turns it off by default so that nothing is listening when you are not using it.

## The ideas behind it

**Bluetooth.** A short-range radio link for small devices. Before two devices talk, they have to be paired: they exchange keys once and agree to trust each other.

**bluez.** Linux's Bluetooth software. `bluetoothctl` is its text tool for scanning and pairing.

**An adapter.** The Bluetooth chip or USB stick. It can be powered on or off.

**rfkill.** The kernel's switch for radios. When rfkill blocks Bluetooth, the radio is really off, not just ignored by a program. A hardware switch on a laptop can also block it.

**AutoEnable.** A bluez setting that decides whether the adapter powers on by itself when the service starts. The script sets it to `false`.

**PipeWire.** The sound system, if you installed sound (`extras/pipewire-audio.sh`). It needs an extra module to play sound over Bluetooth.

## How it works, step by step

1. Warns you if there is no Bluetooth adapter, then goes on anyway (a USB adapter works once plugged in).
2. Installs `bluez` and `rfkill`. If `pipewire-audio` is installed, it also installs `libspa-0.2-bluetooth` for sound over Bluetooth.
3. Installs `~/.local/bin/radios`, the command behind the debsway menu's switches and `debsway --bluetooth`.
4. Edits a copy of `/etc/bluetooth/main.conf` to set `AutoEnable=false # debsway` and installs it. If an `AutoEnable` line exists, it is changed; otherwise a `[Policy]` section with it is added.
5. Enables and starts `bluetooth.service`.
6. Switches Bluetooth off right away (not only at the next boot), using `radios bluetooth off`.

## What it changes on your computer

- Packages: `bluez`, `rfkill`, and `libspa-0.2-bluetooth` when sound is set up.
- `/etc/bluetooth/main.conf`: `AutoEnable=false`, marked `# debsway`.
- `bluetooth.service` enabled and started.
- `~/.local/bin/radios`.
- No firewall rules, no users.

## Using it

- `debsway --bluetooth on` (or debsway menu > Bluetooth) switches the radio on; `debsway --bluetooth off` switches it off.
- `radios bluetooth status|on|off|toggle` does the same directly, and `radios list` shows what is on.
- To pair, switch it on, then run `bluetoothctl` and type: `scan on` (wait for the device to show up), then `pair AA:BB:...`, `trust AA:BB:...`, `connect AA:BB:...`.
- Turning off runs `bluetoothctl power off` and then rfkill block.

## What it protects against

- **A radio listening when you are not using it.** It starts off at every boot (`THREAT-MODEL.md`).
- **Attacks on Bluetooth while it is switched off.** At boot the adapter only stays powered down (bluez's `AutoEnable=false`); switched off from the debsway menu or with `debsway --bluetooth off`, the radio itself is blocked (rfkill), which is off, not just quiet.

## What it doesn't protect against

- **Attacks while it is on.** Bluetooth software has had serious bugs. Keep it on only while you need it.
- **Programs running as you,** which could use the switch to turn it on.
- **Bluetooth tracking by device address** while on. The script does not change that.
- **Eavesdropping or pairing weaknesses** in the devices themselves, such as old keyboards.
- **Anything about sound privacy.** This extra does not touch the microphone setting; that is a separate software switch (`debsway --mic`).

## Removing it

`bash extras/bluetooth.sh --remove` puts bluez's own setting back (the line the script wrote is changed to `#AutoEnable=true`), then uninstalls `bluez`, `libspa-0.2-bluetooth` and (unless another script needs it) `rfkill`. It does not remove `~/.local/bin/radios`, which the debsway menu also uses.
