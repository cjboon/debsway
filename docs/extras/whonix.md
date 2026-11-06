# Whonix (`extras/whonix.sh`)

## SYNOPSIS

```
wrenctl install whonix                     download (if needed), check and install both VMs (asks about a bridge)
wrenctl install whonix --bridges           installed already: choose the Gateway's bridge again
wrenctl install whonix --fetch             only download and check it, for later
wrenctl remove whonix                      remove the VMs (asks before deleting their disks)
wrenctl manual whonix                      print the manual steps below

whonix             start both VMs and open both, each on an empty workspace (or Super+d)
whonix gateway     start the Gateway and open it (Tor settings, bridges)
whonix stop        shut both down, right away and cleanly: save your work inside first
whonix stop --force   the same, and one still running after 30 seconds is switched off
```

Whonix runs Tor in one virtual machine, the Gateway, and your programs in
another, the Workstation, whose only network is the Gateway, so even a hacked
browser in the Workstation can't learn your real address. Everything runs as
your user under KVM (libvirt's `qemu:///session`), with no root daemon or host
network setup. The download (about 1.9 GB) is checked against Whonix's signing
key, pinned in `pins.sh` (`WHONIX_FPR`), and kept in `offline/whonix`. Before
the first boot, Wren Linux writes into the images, without mounting them (with
qemu-img and debugfs): in both, a rule for acpid so that the power button, which
`whonix stop` presses, shuts the VM down cleanly (left to Whonix's desktop, it
opens a dialog); a bridge for the Gateway if you need one (obfs4 or
webtunnel lines you paste, or Snowflake), so its very first connection uses it, or Tor kept
off until you turn it on (`--bridges` chooses again later); and in the Workstation, Tor Browser at Safest with
JavaScript off (`data/tor-browser-safest.js`) and the Feather wallet for Monero:
Feather's own build for Tails and Whonix, which has no Tor of its own and uses
the Gateway's, checked against the hash list signed by Feather's key
(`FEATHER_FPR`), as the Feather extra checks it. Electrum, for Bitcoin, comes
with Whonix. If Feather can't be downloaded or checked, Whonix is installed
without it. For wallets, Whonix is the safest choice Wren Linux has: a wallet in
the Workstation can't reach this computer's files or its real address, even if
it is hacked.

The Gateway's way out is a network card of Wren Linux's, joined to a passt that
`whonix` starts before the Gateway. Whonix's own file gives it libvirt's, and
libvirt can't give passt any option: with passt's defaults the Gateway's address
for your router leads to this computer's own loopback instead (every port of it:
Tor's port, the VMs' consoles, a local server), and nothing answers DNS, so
Snowflake never gets past "broker failure" at 10%. Wren Linux's passt has
Whonix's fixed addresses (the Gateway 10.0.2.15, its gateway 10.0.2.2), IPv4
only, no DHCP, nothing of this computer mapped in (`--no-map-gw`), and one
address, 10.0.2.3, where only DNS goes on, to the resolver this computer uses
(Unbound with secure DNS on, so encrypted). The Gateway's own DNS stays off, as
Whonix ships it, except for a bridge that has to look names up (Snowflake,
webtunnel): then its `/etc/resolv.conf.whonix` gets `nameserver 10.0.2.3`.
webtunnel is experimental here: Whonix ships no program for it, so Wren Linux
installs lyrebird on this computer from the Tor Project's repository (its key
pinned, `TORPROJECT_FPR`, and an apt pin that lets nothing else come from
there), where its updates install themselves, and copies it into the Gateway
as `/usr/bin/lyrebird`; Tor's AppArmor profile in Whonix 18 already lets Tor
run it. Installed before
this? Running `wrenctl install whonix` again (with the Gateway shut down)
gives it the new card; `--bridges` then sets the DNS for the bridge you choose.

## LIMITS

- A bug in KVM or QEMU could reach this computer from a VM.
- What you type into a site still identifies you if it's about you; Tor hides the address, not the person.
- `whonix stop` doesn't ask inside the VMs: what isn't saved there is lost. The same goes for the power button of a VM's own window. Tried here on Whonix 18.2.4.2, without a Tor connection or programs open: both VMs were off in 5 seconds, their disks clean.
- VMs installed before this have no such rule: `whonix stop` opens their shutdown dialog and leaves them running until you choose Shutdown there. `--bridges` gives the Gateway the rule, but nothing gives it to a Workstation that is already installed: back up what you keep in it, then `wrenctl remove whonix` (saying yes to deleting the disks) and `wrenctl install whonix`.
- `whonix stop --force` switches off a VM still running after 30 seconds, as if its power button were held, which can leave its disk needing repair at the next boot.
- Wren Linux doesn't update Feather in the Workstation after the install: Feather says when a newer version is out, and its guide for Whonix (docs.featherwallet.org) shows how to replace it. Whonix updates Electrum with its other packages.
- Feather inside the Workstation hasn't been tried in a real Whonix VM yet: the files are put in place and checked, but not run there.
- Whonix's own updates run inside the VMs: update them there.
- With Snowflake, the Gateway looks up its broker and STUN servers through this computer's resolver (encrypted, with secure DNS on); the resolver sees those names, and your network sees you reach them, as with Snowflake anywhere. Whonix's page on Gateway DNS knows of no risk in having it on.
- Started any other way than `whonix` (virt-manager, `virsh start`), the Gateway has no network: its passt isn't running.
- webtunnel's copy of lyrebird in the Gateway isn't updated by Whonix. `whonix` says when the one on this computer is newer; then `whonix stop` and `wrenctl install whonix --bridges` copy it in again. Until you do, the Gateway runs the older one.
- A disk switched off without shutting down (as `whonix stop --force` can do) isn't edited: `--bridges` asks you to start the Gateway once and shut it down from inside first, so its journal is replayed.
- The Gateway's own network was tried here with Whonix 18.2.4.2 under passt (its outside card is eth0, Tor reaches its relays), and Snowflake through it connected on a real install. webtunnel was tried here only up to lyrebird starting and looking up a bridge's address: a real webtunnel bridge (from bridges.torproject.org) is yours to try.

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
cp @WREN_DIR@/data/tor-browser-safest.js user.js
# Feather, its build for Tails and Whonix (the newest version: the tag in the
# "Location:" line, e.g. 2.9.1), checked as in: wrenctl manual feather-wallet
wget --max-redirect=0 -S -O /dev/null https://github.com/feather-wallet/feather/releases/latest 2>&1 | grep -i location
VER=2.9.1
wget https://featherwallet.org/files/releases/hashes-$VER.txt https://featherwallet.org/files/releases/linux-appimage-a/feather-$VER-a.AppImage
mkdir -m 700 fgpg
wget -O feather.asc @FEATHER_KEY_URL@
gpg --homedir fgpg --import feather.asc
# This must say "Good signature" with "Primary key fingerprint"
# @FEATHER_FPR@. Stop here if not.
gpg --homedir fgpg --output sums.txt --decrypt hashes-$VER.txt
# This must print "OK"
awk -v n="feather-$VER-a.AppImage" '$2 == n || $2 == "*" n { print $1 "  " n }' sums.txt | sha256sum -c
mv feather-$VER-a.AppImage feather.AppImage
cp @WREN_DIR@/data/whonix-feather @WREN_DIR@/data/whonix-feather.desktop .
# A bridge for the Gateway, if you need one, in 50_user.conf: obfs4 lines
# from bridges.torproject.org (for Snowflake, put "ClientTransportPlugin
# snowflake exec /usr/bin/snowflake-client" and the Snowflake "Bridge" lines
# from data/snowflake-bridges.txt instead)
printf '%s\n' 'UseBridges 1' 'ClientTransportPlugin obfs4 exec /usr/bin/obfs4proxy' \
    'Bridge obfs4 1.2.3.4:443 FINGERPRINT cert=... iat-mode=0' >50_user.conf
# Only for Snowflake: the Gateway's own DNS, at 10.0.2.3 (passt hands it to this
# computer's resolver). Take Whonix's file out of the image first: copy it from
# "debugfs -R 'cat /etc/resolv.conf.whonix'" (see put below), then
#   sed -i 's/^#nameserver 10\.0\.2\.3$/nameserver 10.0.2.3/' resolv.conf.whonix
# and put it back as /etc/resolv.conf.whonix (for webtunnel too)
# Only for webtunnel: lyrebird, from the Tor Project's repository (as
# parts/apt-tor.sh adds it: key @TORPROJECT_FPR@, pinned to lyrebird only),
# and in 50_user.conf "ClientTransportPlugin webtunnel exec /usr/bin/lyrebird"
# with your "Bridge webtunnel ..." lines; then, with put below:
#   put gw.qcow2 /usr/bin/lyrebird /usr/bin/lyrebird 755

# put IMAGE FILE DEST [MODE]: write FILE into the image's root file system as
# DEST (root's, mode 0644 or MODE), checked, without mounting it
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
sif $3 mode 0100${4:-644}
EOF
    # It must be there, as written, and the file system must check out;
    # if not, the image is left as it was
    if ! debugfs -R "cat $3" "$fs" | cmp -s - "$2" || ! e2fsck -fn "$fs"; then
        echo "Couldn't write $3 into $1; it is unchanged." >&2
        rm "$1.raw"
        return 1
    fi
    # (a write that fails, on a full disk, must never take the image's place)
    qemu-img convert -O qcow2 -o cluster_size=2M,extended_l2=on "$1.raw" "$1.new" ||
        { echo "Couldn't write $1 back; it is unchanged." >&2; rm -f "$1.raw" "$1.new"; return 1; }
    rm "$1.raw" && mv "$1.new" "$1"
}
put ws.qcow2 @WREN_DIR@/data/whonix-power-button /etc/acpi/events/wren-power-button
put gw.qcow2 @WREN_DIR@/data/whonix-power-button /etc/acpi/events/wren-power-button
put ws.qcow2 user.js /usr/local/etc/torbrowser.d/user.js
put ws.qcow2 feather.AppImage /usr/local/lib/feather/feather.AppImage 755
put ws.qcow2 whonix-feather /usr/local/bin/feather 755
put ws.qcow2 whonix-feather.desktop /usr/local/share/applications/feather.desktop
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
# The Gateway's outside card: in Whonix-Gateway.xml, delete the block
# <interface type='user'> ... </interface>, add xmlns:qemu to its first line, so
# it reads <domain xmlns:qemu='http://libvirt.org/schemas/domain/qemu/1.0' type='kvm'>,
# and put this just before </domain> (with your home folder in the path; slot
# 0x1e must be free on bus 0x00: virsh dumpxml shows the slots in use)
#   <qemu:commandline>
#     <qemu:arg value='-netdev'/>
#     <qemu:arg value='{"type": "stream", "id": "wren-gw-netdev", "server": false, "reconnect-ms": 1000, "addr": {"type": "unix", "path": "/home/YOU/.local/state/wren/whonix-gateway-net.sock"}}'/>
#     <qemu:arg value='-device'/>
#     <qemu:arg value='{"driver": "virtio-net-pci", "netdev": "wren-gw-netdev", "id": "wren-gw-net", "mac": "@GW_NET_MAC@", "bus": "pcie.0", "addr": "0x1e"}'/>
#   </qemu:commandline>
virsh -c qemu:///session define Whonix-Gateway.xml
virsh -c qemu:///session define Whonix-Workstation.xml
# Its network, before every start of the Gateway (the whonix command does this)
mkdir -p ~/.local/state/wren && chmod 700 ~/.local/state/wren
passt --quiet --one-off --socket ~/.local/state/wren/whonix-gateway-net.sock \
    --pid ~/.local/state/wren/whonix-gateway-net.pid --ipv4-only --address 10.0.2.15 \
    --netmask 24 --gateway 10.0.2.2 --no-map-gw --dns-forward 10.0.2.3 --no-dhcp

# The whonix command
install -D -m 0755 @WREN_DIR@/bin/whonix ~/.local/bin/whonix
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
