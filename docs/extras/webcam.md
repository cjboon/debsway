# The webcam switch (`extras/webcam.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/webcam.sh            set it up (the webcam is off at every boot and when plugged in)
bash ~/debsway/extras/webcam.sh --remove   take it out (the webcam is on again)
bash ~/debsway/extras/webcam.sh --manual   print the manual steps below

debsway --camera on|off     switch it (or the debsway menu > Webcam)
```

A USB camera (most laptops' built-in ones, and plugged-in ones) starts
switched off at every boot and whenever one is plugged in. Off means its USB
device is disconnected, as if unplugged, so no program can open it at all;
a webcam's own microphone goes with it. The root helper `bin/debsway-camera`,
installed as `/usr/local/libexec/debsway-camera`, does it by writing the
kernel's `authorized` switch of the camera's USB device. A rule in
`/etc/sudoers.d` lets your user run it with `on` or `off` and nothing else, so
the debsway menu needs no password, and a udev rule
(`data/webcam-off.rules`) switches each camera off as it appears.

## LIMITS

- A program running as you can switch it on the same way you do; a cover over the lens is stronger.
- A camera that isn't on USB (some new laptops' MIPI cameras) isn't seen.
- The laptop's own microphone isn't affected (`debsway --mic off` mutes that).

## MANUAL INSTALL

```
# The root helper that switches the camera's USB device
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 @DEBSWAY_DIR@/bin/debsway-camera /usr/local/libexec/debsway-camera
# The switch the debsway menu uses (debsway --camera calls it)
install -D -m 0755 @DEBSWAY_DIR@/bin/radios ~/.local/bin/radios

# Your user may run the helper with "on" or "off" and nothing else, as root,
# without a password. visudo checks the rule before it goes in: never put a
# rule in /etc/sudoers.d that visudo hasn't passed.
printf '%s ALL=(root) NOPASSWD: /usr/local/libexec/debsway-camera on, /usr/local/libexec/debsway-camera off\n' "$(id -un)" >/tmp/debsway-camera
sudo visudo -cf /tmp/debsway-camera
sudo install -o root -g root -m 0440 /tmp/debsway-camera /etc/sudoers.d/debsway-camera
rm /tmp/debsway-camera

# Off whenever a USB device is added (at boot too)
sudo install -o root -g root -m 0644 @DEBSWAY_DIR@/data/webcam-off.rules /etc/udev/rules.d/90-debsway-webcam.rules
sudo udevadm control --reload-rules
# Is there a camera? Then switch it off now
/usr/local/libexec/debsway-camera status
sudo /usr/local/libexec/debsway-camera off
```

To undo:

```
# No longer switched off when it appears
sudo rm /etc/udev/rules.d/90-debsway-webcam.rules
sudo udevadm control --reload-rules
# On again, as it was
sudo /usr/local/libexec/debsway-camera on
# The sudo rule and the helper
sudo rm /etc/sudoers.d/debsway-camera /usr/local/libexec/debsway-camera
```
