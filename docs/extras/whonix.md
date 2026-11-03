# Whonix (`extras/whonix.sh`)

## SYNOPSIS

```
debsway install whonix                     download (if needed), check and install both VMs (asks about a bridge)
debsway install whonix --fetch             only download and check it, for later
debsway remove whonix                      remove the VMs (asks before deleting their disks)
debsway manual whonix                      print the manual steps below

whonix             start both VMs and open the Workstation (or Super+d)
whonix gateway     start the Gateway and open it (Tor settings, bridges)
whonix stop        shut both down (one still running after 20 seconds is switched off)
```

Whonix runs Tor in one virtual machine, the Gateway, and your programs in
another, the Workstation, whose only network is the Gateway, so even a hacked
browser in the Workstation can't learn your real address. Everything runs as
your user under KVM (libvirt's `qemu:///session`), with no root daemon or host
network setup. The download (about 1.9 GB) is checked against Whonix's signing
key, pinned in `pins.sh` (`WHONIX_FPR`), and kept in `offline/whonix`. Before
the first boot, debsway writes into the images, without mounting them (with
qemu-img and debugfs): a bridge for the Gateway if you need one (obfs4 lines
you paste, or Snowflake), so its very first connection uses it, or Tor kept
off until you turn it on; and Tor Browser at Safest with JavaScript off in the
Workstation (`data/tor-browser-safest.js`).

## LIMITS

- A bug in KVM or QEMU could reach this computer from a VM.
- What you type into a site still identifies you if it's about you; Tor hides the address, not the person.
- `whonix stop` switches off a VM that doesn't shut down in 20 seconds: save your work inside first.
- Whonix's own updates run inside the VMs: update them there.

## MANUAL INSTALL

```
# KVM must be on: this must list /dev/kvm (if not, turn on VT-x / AMD-V in the firmware settings)
ls -l /dev/kvm
# KVM, libvirt and virt-manager (from whonix.org/wiki/KVM, for Debian trixie),
# and the tools to unpack and edit the images
sudo apt install --no-install-recommends qemu-system-x86 qemu-system-gui qemu-system-modules-spice qemu-utils \
    libvirt-daemon libvirt-daemon-driver-qemu libvirt-daemon-driver-storage libvirt-daemon-driver-nodedev \
    libvirt-clients virt-manager gir1.2-spiceclientgtk-3.0 passt ovmf swtpm swtpm-tools \
    xz-utils e2fsprogs fdisk acl
# Your user may use KVM and libvirt (in full from your next login)
sudo adduser "$(id -un)" kvm
sudo adduser "$(id -un)" libvirt
# No core dumps, and no limits libvirt can't set as a normal user
mkdir -p ~/.config/libvirt
printf 'max_core = 0\nmax_processes = 0\nmax_files = 0\n' >~/.config/libvirt/qemu.conf

# The newest version: the highest number on whonix.org's KVM page
wget -qO- https://www.whonix.org/wiki/KVM | grep -o 'download/libvirt/[0-9.]*/Whonix-LXQt-[0-9.]*\.Intel_AMD64' | sort -uV | tail -1
V=18.2.4.2
F=Whonix-LXQt-$V.Intel_AMD64.qcow2.libvirt.xz
mkdir -p ~/whonix-download && cd ~/whonix-download
# The image (about 1.9 GB), its signature and the signing key
wget -c https://www.whonix.org/download/libvirt/$V/$F https://www.whonix.org/download/libvirt/$V/$F.asc
wget -O derivative.asc @WHONIX_KEY_URL@
# The key, in a keyring of its own. This must show the fingerprint @WHONIX_FPR@
mkdir -m 700 gpg
gpg --homedir gpg --import derivative.asc
gpg --homedir gpg --fingerprint @WHONIX_FPR@
# The image is signed by it: this must say "Good signature" with
# "Primary key fingerprint" @WHONIX_FPR@. Stop here if not.
gpg --homedir gpg --verify $F.asc $F

# Unpack it, and read Whonix's license and disclaimer before going on
tar -xSf $F
less WHONIX_BINARY_LICENSE_AGREEMENT WHONIX_DISCLAIMER
mv Whonix-Gateway-*.qcow2 gw.qcow2 && mv Whonix-Workstation-*.qcow2 ws.qcow2

# Files to put into the images before their first boot:
# the Workstation's Tor Browser at Safest, JavaScript off
cp @DEBSWAY_DIR@/data/tor-browser-safest.js user.js
# A bridge for the Gateway, if you need one, in 50_user.conf: obfs4 lines
# from bridges.torproject.org (for Snowflake, put "ClientTransportPlugin
# snowflake exec /usr/bin/snowflake-client" and the Snowflake "Bridge" lines
# from data/snowflake-bridges.txt instead)
printf '%s\n' 'UseBridges 1' 'ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy' \
    'Bridge obfs4 1.2.3.4:443 FINGERPRINT cert=... iat-mode=0' >50_user.conf

# put IMAGE FILE DEST: write FILE into the image's root file system as DEST
# (root's, mode 0644), checked, without mounting it
put() {
    qemu-img convert -O raw "$1" "$1.raw"
    start=$(sfdisk -d "$1.raw" | sed -n 's/.*start= *\([0-9]*\),.*name="primary".*/\1/p')
    fs="$1.raw?offset=$((start * 512))"
    dir=$(dirname "$3")
    debugfs -w -R "mkdir $dir" "$fs"
    debugfs -w -f - "$fs" <<EOF
sif $dir uid 0
sif $dir gid 0
sif $dir mode 040755
rm $3
write $2 $3
sif $3 uid 0
sif $3 gid 0
sif $3 mode 0100644
EOF
    # It must be there, as written, and the file system must check out;
    # if not, the image is left as it was
    if ! debugfs -R "cat $3" "$fs" | cmp -s - "$2" || ! e2fsck -fn "$fs"; then
        echo "Couldn't write $3 into $1; it is unchanged." >&2
        rm "$1.raw"
        return 1
    fi
    qemu-img convert -O qcow2 -o cluster_size=2M,extended_l2=on "$1.raw" "$1.new"
    rm "$1.raw" && mv "$1.new" "$1"
}
put ws.qcow2 user.js /usr/local/etc/torbrowser.d/user.js
put gw.qcow2 50_user.conf /usr/local/etc/torrc.d/50_user.conf
# (each must end without "Couldn't write"; stop here if one does)

# The VMs, as your user: the storage pool, the disks, the definitions
mkdir -p ~/.local/share/libvirt/images
virsh -c qemu:///session pool-define-as default dir --target ~/.local/share/libvirt/images
virsh -c qemu:///session pool-autostart default
virsh -c qemu:///session pool-start default
mv gw.qcow2 ~/.local/share/libvirt/images/Whonix-Gateway.qcow2
mv ws.qcow2 ~/.local/share/libvirt/images/Whonix-Workstation.qcow2
virsh -c qemu:///session pool-refresh default
virsh -c qemu:///session define Whonix-Gateway.xml
virsh -c qemu:///session define Whonix-Workstation.xml

# The whonix command
install -D -m 0755 @DEBSWAY_DIR@/bin/whonix ~/.local/bin/whonix
cd ~ && rm -rf ~/whonix-download
whonix
```

To undo:

```
# Switch the VMs off and forget them
virsh -c qemu:///session destroy Whonix-Workstation
virsh -c qemu:///session destroy Whonix-Gateway
virsh -c qemu:///session undefine Whonix-Workstation
virsh -c qemu:///session undefine Whonix-Gateway
# Their disks, and everything saved inside the VMs
rm ~/.local/share/libvirt/images/Whonix-Gateway.qcow2 ~/.local/share/libvirt/images/Whonix-Workstation.qcow2
# The command
rm ~/.local/bin/whonix
# KVM, libvirt and virt-manager, marked "automatic": autoremove takes them out
# only if nothing (mockvps-kvm, claude-vm, the onion site) needs them
sudo apt-mark auto qemu-system-x86 qemu-system-gui qemu-system-modules-spice qemu-utils libvirt-daemon \
    libvirt-daemon-driver-qemu libvirt-daemon-driver-storage libvirt-daemon-driver-nodedev libvirt-clients \
    virt-manager gir1.2-spiceclientgtk-3.0 passt ovmf swtpm swtpm-tools
sudo apt autoremove --purge
```
