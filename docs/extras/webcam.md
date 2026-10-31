# A webcam switch (`extras/webcam.sh`)

Your webcam starts switched off at every boot and whenever one is plugged in, and the debsway menu gets a Webcam line to switch it on and off. Off means the camera is disconnected, as if it were unplugged, so no program can open it.

## The problem it solves

On a normal Linux desktop the person at the screen can use the webcam, and so can any program running as them, at any time. A camera you only need for the odd video call is better off until you ask for it.

## The ideas behind it

**USB.** Almost every laptop's built-in camera, and every plug-in webcam, is a USB device, even when it sits inside the lid.

**The kernel's "authorized" switch.** Each USB device has a file, `/sys/bus/usb/devices/DEVICE/authorized`. Writing 0 there makes the kernel disconnect the device, as if it were unplugged; writing 1 connects it again. Only root may write it.

**Finding the camera.** A camera is a USB device with a *video interface* (USB class 0x0e). Once disconnected, a device no longer lists its interfaces, so the helper reads the device's raw descriptors (the description every USB device gives of itself) to find it again.

**A sudoers rule.** Your user may run exactly two commands as root without a password: `debsway-camera on` and `debsway-camera off`. Nothing else.

**A udev rule.** udev is the part of the system that reacts when a device appears. The rule runs the helper when a whole USB device is added (at boot, or when you plug one in), and a camera is switched off then. Switching a camera on doesn't count as a new device, so it stays on until the next boot or until it is plugged in again.

## How it works, step by step

1. It installs `bin/debsway-camera` as `/usr/local/libexec/debsway-camera`, owned by root, and `radios` (which the menu uses for its switches) in `~/.local/bin`.
2. It writes the sudoers rule `/etc/sudoers.d/debsway-camera`, checked with `visudo` first.
3. It installs the udev rule `/etc/udev/rules.d/90-debsway-webcam.rules` and reloads udev's rules.
4. It switches a camera that is there now off.

## What it changes on your computer

- `/usr/local/libexec/debsway-camera`, `/etc/sudoers.d/debsway-camera`, `/etc/udev/rules.d/90-debsway-webcam.rules`.
- `~/.local/bin/radios`.
- No packages.

## Using it

- The debsway menu: **Webcam: on/off**, shown when a USB camera is found. Choose it to switch.
- `debsway --camera on`, `debsway --camera off`, `debsway --camera` (whether it is on).

## What it protects against

- **A program, or a website in a browser running as you, using the camera without you switching it on first.** While it is off the camera isn't there at all.
- **Forgetting to switch it off:** it is off again at every boot.

## What it doesn't protect against

- **A program running as you switching it on.** It can run the same helper, as the menu does. A cover over the lens is the stronger kind, as the hardware switch is for the microphone.
- **A camera that isn't on USB.** Some new laptops have MIPI cameras (often not working on Linux anyway); they aren't seen or switched.
- **Root.** Anything with root can switch it on.

A webcam often holds a microphone as well: switched off, that goes too. The laptop's own microphone isn't part of the camera, and has its own switch (Microphone in the menu, with the sound extra).

## Removing it

`bash extras/webcam.sh --remove` switches the camera on again, removes the udev rule, the sudoers rule and the helper. `radios` stays, since the menu uses it.
