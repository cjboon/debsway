# Compressed memory (`extras/zram.sh`)

## SYNOPSIS

```
wrenctl install zram                          turn it on, now and at every boot
wrenctl remove zram                           turn it off
wrenctl manual zram                           print the manual steps below

zramctl                                       how much it holds, and in how little
```

zram is swap kept in memory, compressed: what hasn't been used for a while is squeezed, which leaves
room for everything else. It covers all of this computer, your VMs' memory included, so it is
worth having if you run VMs on a laptop short of memory. Nothing goes to disk, and it is gone at
power off, unlike a swap file, which can leave passwords and keys on the disk for a while.

## LIMITS

- It isn't free memory: expect perhaps two to three times the room for what it holds, less for video
  and anything encrypted, and it takes some CPU.
- When memory really runs out, things can get slow before anything is killed. The bar still warns.
- Someone able to read this computer's memory can read this too, as with everything else in memory.
- Set it up on this computer, not inside a VM, where the same memory would be squeezed twice.
- A VM that locks its memory isn't helped.
- With it on, the computer can't hibernate into it (Wren Linux doesn't offer hibernation).

## MANUAL INSTALL

```
sudo apt install systemd-zram-generator
printf '%s\n' '[zram0]' 'zram-size = ram / 2' 'compression-algorithm = zstd' |
    sudo tee /etc/systemd/zram-generator.conf
sudo systemctl daemon-reload
sudo systemctl restart systemd-zram-setup@zram0.service
sudo systemctl start dev-zram0.swap
# It is in use if this shows /dev/zram0
swapon --show
```

To undo:

```
sudo swapoff /dev/zram0
sudo systemctl stop systemd-zram-setup@zram0.service
sudo rm /etc/systemd/zram-generator.conf
sudo apt-mark auto systemd-zram-generator
sudo systemctl daemon-reload
sudo apt autoremove --purge
```
