# Setting up the BIOS (UEFI firmware)

The BIOS, on any computer from the last ten years really UEFI firmware, is
what runs before any operating system: it decides what may start, from which
disk, and which devices exist at all. Wren Linux can't change these settings
from inside; you set them once, by hand. This page says which ones matter for
installing Wren Linux, and which make any computer harder to tamper with.

Every maker names and places these settings differently. The words below are
the common ones; look for something close. When unsure, leave a setting as it
is: none of them is worth a computer that won't start.

## Getting into it

Restart and press the setup key over and over as the maker's logo shows:
usually **F2** or **Del**; **F1** or **Enter** on Lenovo, **Esc** then **F10**
on HP, **F2** on Dell. A second key opens a **one-time boot menu** (often **F12**,
**F9**, **F11** or **Esc**) to start from a USB stick once, without changing the
boot order. If Windows is installed, Fast Startup can skip the keys: hold Shift
while choosing Restart, then Troubleshoot > UEFI Firmware Settings.

## For a Wren Linux install

In this order:

1. **Update the firmware first,** from the maker's support page for your exact
   model. Updates fix security holes that no operating system can, and a
   later update can reset your settings, so do it before the rest. (After
   the install Debian's `fwupd` can update many computers; not all makers
   support it.)
2. **Boot mode: UEFI only.** Switch off "CSM", "Legacy" or "Legacy boot
   support". Debian's installer, and Wren Linux's install stick, start in
   either mode, but Secure Boot needs UEFI, and so does the rest of this
   list.
3. **Secure Boot: on,** with the maker's own keys ("Standard" or "Factory"
   keys, not "Setup mode" or "Custom"). Debian's boot loader and kernel are
   signed for it, and Wren Linux uses them unchanged, so it starts as Debian
   does. A kernel module built on your computer (DKMS: some Wi-Fi drivers,
   NVIDIA's own driver) won't load with it on until you enroll a key for it
   (`mokutil`); Wren Linux's own scripts need none.
4. **Storage: AHCI,** not "RAID" or "Intel RST/VMD". With RST the installer
   often can't see the disk at all. (On a computer that also runs Windows,
   changing this makes Windows fail to start until it is set up for AHCI.)
5. **Virtualization: on.** "Intel VT-x" or "AMD-V" (sometimes "SVM"), and
   "VT-d" or "AMD-Vi"/"IOMMU". The first lets `claude-vm`, `whonix` and other
   virtual machines run; the second lets the kernel keep devices from reading
   memory they weren't given (see Thunderbolt below).
6. **Fast Boot: off,** at least for the install: with it on, many computers
   skip the USB ports and the keyboard before the boot loader, so the stick and
   the setup key go unseen.
7. **Start from the stick** with the one-time boot menu (choose the entry
   starting with "UEFI:"), and install.
8. **Afterwards, back in the BIOS:** put the internal disk first, switch off
   booting from USB and from the network, and set the supervisor password
   (below). From then on, starting from a stick needs that password.

Check from Wren Linux, in a terminal:

```bash
[ -d /sys/firmware/efi ] && echo "started with UEFI"
sudo dmesg | grep -i 'secure boot'      # "Secure boot enabled" when it is on
grep -cE 'vmx|svm' /proc/cpuinfo         # above 0: the CPU can run VMs
ls /dev/kvm                              # exists: virtualization is switched on
```

## For security, on any computer

**Passwords**

- **Supervisor (administrator, setup) password: yes.** Without it anyone
  at the keyboard can switch Secure Boot off, start their own system from a
  stick, or change any of this. Use a long one, write it down and keep that
  safe: on many laptops a forgotten supervisor password means a new
  mainboard.
- **Power-on password: optional.** It asks before anything starts. Your disk
  encryption passphrase already protects what is on the disk, so this mainly
  stops someone from using the computer's own boot menu.
- **Disk (HDD/NVMe) password: optional.** The disk asks for it itself. Wren
  Linux's disk encryption (LUKS) is what protects your files, whatever this
  is set to.

**What may start**

- Secure Boot on, UEFI only, boot from USB and from the network (PXE, "UEFI
  network stack") off, internal disk first, as above.
- **BIOS updates only with the supervisor password,** and **rollback
  protection** ("BIOS downgrade", "Secure rollback prevention") on, so nobody can
  put back an older firmware with known holes.

**Devices you don't use: off in the firmware**

The firmware's switch makes the device absent: nothing running on the
computer can switch it back on, unlike Wren Linux's microphone and webcam
switches, which are software (see `THREAT-MODEL.md`). Common ones: the
**webcam**, the **microphone**, **Bluetooth**, a **mobile broadband** (WWAN) card,
the **fingerprint reader**, the **SD card reader**, **Wake on LAN**, and
**Thunderbolt** if you never use it.

**Thunderbolt and other ports that can read memory**

A Thunderbolt (or USB4) device can ask to read the computer's memory directly.
If you use the port, set its security to "User Authorization" or "Secure
Connect" rather than "No security", and switch on **"Kernel DMA protection"**
or **"Pre-boot DMA protection"** with the IOMMU (VT-d/AMD-Vi, above).
`parts/boot-hardening.sh` then has Linux use the IOMMU in its strict mode. Wren
Linux already blocks FireWire, the older port that could do the same.

**Remote management and tracking agents**

- **Intel AMT** ("vPro", "Active Management Technology", "MEBx"), on business
  laptops: off, unless an IT department runs it. It can manage the computer
  over the network beneath the operating system.
- **Absolute / Computrace** ("Absolute Persistence"), an anti-theft agent built
  into many Dell, HP and Lenovo laptops: off. Some offer "Permanently disable",
  which can't be undone: fine if you don't use that service.
- Intel's Management Engine and AMD's PSP themselves can't be switched off;
  firmware updates are what keep them patched.

**Tamper signs**

- **Chassis intrusion** or "bottom cover tamper" detection, where there is
  one: on. It warns at the next start when the case was opened.
- Keep a photo of the BIOS settings pages. If one is ever different when you
  didn't change it, someone else did.

## A checklist

| Setting | Wren Linux install | Notes |
| --- | --- | --- |
| Firmware updated | first | from the maker, for this model |
| Boot mode | UEFI only | CSM / Legacy off |
| Secure Boot | on | factory keys |
| Storage mode | AHCI | not RAID / RST |
| VT-x / AMD-V, VT-d / IOMMU | on | VMs; DMA protection |
| Fast Boot | off | the stick and keys are seen |
| Boot order | internal disk first | USB and network boot off after the install |
| Supervisor password | set | written down, kept safe |
| BIOS updates | password-protected | rollback protection on |
| Thunderbolt | User Authorization, or off | Kernel DMA protection on |
| Unused devices | off | webcam, mic, Bluetooth, WWAN, ... |
| Intel AMT, Absolute | off | |
| Wake on LAN | off | |
| Chassis intrusion | on | where there is one |

## What this doesn't protect

- **Someone with time and a screwdriver.** On most desktops, and some laptops,
  removing a battery or setting a jumper clears the BIOS password. A firmware
  chip can be rewritten with a clip and another computer. The settings above
  slow an attacker and make tampering easier to notice; they don't stop one.
- **The unencrypted boot partition.** Secure Boot checks the boot loader and
  the kernel, but Debian's initramfs (what asks for your disk passphrase) isn't
  signed, and Wren Linux doesn't measure the boot with the TPM. Someone who
  changes it while you're away isn't detected: see "Physical tampering" in
  `THREAT-MODEL.md`, and shut down rather than leave the computer asleep.
- **The TPM** is neither used nor needed by Wren Linux; leaving it on is fine.
- **Holes in the firmware itself,** until the maker fixes them and you install
  the update.

More on the physical side, and the rest: [opsec.md](opsec.md).
