# The webcam switch (`extras/webcam.sh`)

## SYNOPSIS

```
wrenctl install webcam                     set it up (the webcam is off at every boot and when plugged in)
wrenctl remove webcam                      take it out (the webcam is on again)
wrenctl manual webcam                      print the manual steps below

wrenctl --camera on|off     switch it (or the Wren menu > Webcam)
```

A USB camera (most laptops' built-in ones, and plugged-in ones) starts
switched off at every boot and whenever one is plugged in. Off means its USB
device is disconnected, as if unplugged, so no program can open it at all;
a webcam's own microphone goes with it. The root helper `bin/wren-camera`,
installed as `/usr/local/libexec/wren-camera`, does it by writing the
kernel's `authorized` switch of the camera's USB device. A rule in
`/etc/sudoers.d` lets your user run it with `off` freely and `on` with your password, and nothing
else, so a program running as you can't switch it on, and a udev rule
(`data/webcam-off.rules`) switches each camera off as it appears.

## LIMITS

- A program running as you can switch it on the same way you do; a cover over the lens is stronger.
- A camera that isn't on USB (some new laptops' MIPI cameras) isn't seen.
- The laptop's own microphone isn't affected (`wrenctl --mic off` mutes that).

## MANUAL INSTALL

```
# The root helper that switches the camera's USB device
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/wren-camera /usr/local/libexec/wren-camera
# The switch the Wren menu uses (wrenctl --camera calls it)
install -D -m 0755 @WREN_DIR@/bin/radios ~/.local/bin/radios

# Your user may run the helper with "off", and with the password "on", and
# nothing else, as root. visudo checks the rule before it goes in: never put a
# rule in /etc/sudoers.d that visudo hasn't passed.
printf '%s ALL=(root) NOPASSWD: /usr/local/libexec/wren-camera off\n%s ALL=(root) /usr/local/libexec/wren-camera on\n' "$(id -un)" "$(id -un)" >/tmp/wren-camera
sudo visudo -cf /tmp/wren-camera
sudo install -o root -g root -m 0440 /tmp/wren-camera /etc/sudoers.d/wren-camera
rm /tmp/wren-camera

# Off whenever a USB device is added (at boot too)
sudo install -o root -g root -m 0644 @WREN_DIR@/data/webcam-off.rules /etc/udev/rules.d/90-wren-webcam.rules
sudo udevadm control --reload-rules
# Is there a camera? Then switch it off now
/usr/local/libexec/wren-camera status
sudo /usr/local/libexec/wren-camera off
```

To undo:

```
# No longer switched off when it appears
sudo rm /etc/udev/rules.d/90-wren-webcam.rules
sudo udevadm control --reload-rules
# On again, as it was
sudo /usr/local/libexec/wren-camera on
# The sudo rule and the helper
sudo rm /etc/sudoers.d/wren-camera /usr/local/libexec/wren-camera
```
