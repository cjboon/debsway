# Hardware wallets (`extras/hardware-wallet.sh`)

## SYNOPSIS

```
wrenctl install hardware-wallet     let you use a Trezor, Ledger, Coldcard, BitBox02 or KeepKey over USB
wrenctl remove hardware-wallet      take the rule out
wrenctl manual hardware-wallet      print the manual steps below
```

A hardware wallet keeps the coins' keys on the device: the computer prepares a
transaction, and the device shows its address and amount on its own screen and
signs only when you agree there, so a hacked computer can't spend the coins or
quietly change where they go. Sparrow and Electrum (Bitcoin) and Feather
(Monero) talk to these devices themselves, so no maker's app is installed. Most
of them need a udev rule before a user may reach them; this one
(`data/hardware-wallets.rules`) gives Trezor, Ledger, Coldcard, BitBox02 and
KeepKey devices to the person at the keyboard only (`uaccess`): no group, no
other user and none of Wren Linux's sandbox users get them. Safer still is a
device that never connects at all: Coldcard, Jade, Keystone and SeedSigner can
sign from a QR code or a microSD card, which Sparrow does (the webcam extra for
QR codes, `usb mount` for a card).

## LIMITS

- The recovery words are the real key: anyone who sees them has the coins. Keep them on paper or metal, never typed into a computer or photographed.
- Check the address and amount on the device's screen: the computer's screen can lie.
- A fake or tampered device can't be detected by this: buy from the maker, and check it the way the maker says.
- The rule lists makers' USB numbers (in the file); a model with a new number isn't covered until it is added. Blockstream Jade over USB is a serial port, not covered: use its QR mode.
- Anything running as you while it is plugged in can talk to the device; it still can't sign without your agreement on the device.

## MANUAL INSTALL

```
# The rule: these devices for the person at the keyboard (uaccess)
sudo install -D -o root -g root -m 0644 @WREN_DIR@/data/hardware-wallets.rules /etc/udev/rules.d/60-wren-hardware-wallets.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=usb --subsystem-match=hidraw --action=change
```

To undo:

```
sudo rm /etc/udev/rules.d/60-wren-hardware-wallets.rules
sudo udevadm control --reload-rules
```
