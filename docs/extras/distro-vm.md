# Other distributions in VMs (`extras/distro-vm.sh`)

**Retired.** Kali, Tails and Arch VMs took a lot of root-run machinery for rare use. Tails is safer on a stick of its own: wrenctl install tails-usb. `update.sh` offers to take it out (`wrenctl remove distro-vm`); it is no longer offered to install.

## SYNOPSIS

```
wrenctl install distro-vm      choose Kali, Tails and Arch (and Tor only for Kali and Arch), then set them up
wrenctl remove distro-vm       remove it (asks before deleting each one's images and disk)
wrenctl manual distro-vm       print the manual steps below

distro-vm                      what is set up, and on which network
distro-vm NAME                 start it in a window; closing the window powers it off
distro-vm NAME update          download its newest image, checked against its signing key
distro-vm NAME stop | status
distro-vm NAME reset           throw its disk away (Kali and Arch; asks first)
```

Other Linux distributions, each in a throwaway VM on this computer (QEMU/KVM):
Kali Linux (security testing tools; you install it to the VM's own disk from
its installer), Tails (an amnesic desktop that goes through its own Tor) and
Arch Linux (minimal and rolling; you install it yourself). You tick which ones;
nothing is ticked for you. Each runs as its own locked user (`dvm-kali`,
`dvm-tails`, `dvm-arch`: no password, no login, in the kvm group only), and
QEMU's user-mode networking makes the guest's traffic that user's sockets, so a
firewall rule on it (`data/distro-vm-firewall.nft`) governs the guest: the
internet, but not your router, printers or this computer's services. For Kali
and Arch you're asked before anything is installed whether that VM goes
through **Tor only**: then every TCP connection it makes is sent into the
system Tor (its TransPort and DNSPort, on 127.0.0.1 only) and everything else
is refused, so with Tor down nothing gets out; then whether you need a bridge,
and which kind, unless another Wren Linux script already set the system Tor up.
Tails is never asked: it brings its own Tor, and Tor through Tor is advised
against. A VM won't start unless its firewall is really there, seen from its
user (`bin/distro-vm-net-check`), and it is ended within seconds if the rule
goes away while it runs (a `flush ruleset`, say). Images are downloaded as that
user too, through its firewall (through Tor, for a Tor-only VM), and kept only
if they are the newest in the project's own release list over https and signed
by its key, pinned in `pins.sh`: Kali's checksum list (`KALI_FPR`), Tails'
image (`TAILS_FPR`, with the SHA-256 and size from its release file), Arch's
image (`ARCH_ISO_FPR`, with the SHA-256 from its release list). The screen is a
SPICE socket that only you and that user can open, shown by `remote-viewer`;
no clipboard, files, sound or USB devices cross. Your user may run exactly one
thing as those users, `distro-vm-session`, through a rule in `/etc/sudoers.d`.
It needs KVM.

## LIMITS

- Tor only hides your address from what the VM connects to. Kali and Arch aren't made for anonymity: their browsers, updates and time zone can still tell sites who you are. For that, use Whonix (`wrenctl install whonix`).
- Tails in a VM is weaker than Tails on a USB stick, as Tails itself warns: this computer sees everything the VM does, and could keep traces of it. Use it to try Tails out; for real use, `wrenctl install tails-usb`.
- Tor only carries TCP and DNS: anything else in the VM (ping, UDP, QUIC) just fails.
- A bug in QEMU or KVM could reach this computer; a VM is a stronger wall than a user, not a perfect one. QEMU runs under its own syscall filter. The screen goes through `remote-viewer`, which runs as you.
- Treat what runs in the VM as untrusted, above all Kali's tools and anything you download in it. Nothing crosses back by itself; copy nothing out of it by hand without thinking.
- The newest version comes from each project's release list over https: someone who could change what tails.net, archlinux.org or cdimage.kali.org serves could hold an update back, but not slip in an image the project didn't sign.
- Kali's and Arch's disks keep what you install on them until `distro-vm NAME reset`; the images are kept until a newer one is downloaded.
- The VMs need memory: each gets a quarter of this computer's, 2 to 4 GB.

## MANUAL INSTALL

```
# KVM must be on: this must list /dev/kvm (if not, turn on VT-x / AMD-V in the firmware settings)
ls -l /dev/kvm
# QEMU with its SPICE screen, the viewer, the firewall, ACLs for the screen's
# socket, python3 for the net check, wget and gpg for the downloads; tor only
# if a VM goes through Tor
sudo apt install --no-install-recommends qemu-system-x86 qemu-utils qemu-system-modules-spice virt-viewer \
    nftables acl python3 wget gpg

# The signing keys, each only if it is exactly the pinned fingerprint (gpg shows
# it: compare it by eye), exported alone into root's files
sudo install -d -o root -g root -m 0755 /etc/wren/distro-vm
G=$(mktemp -d)
wget -qO- @KALI_KEY_URL@ | gpg --homedir "$G" --import
gpg --homedir "$G" --export @KALI_FPR@ | sudo tee /etc/wren/distro-vm/kali.gpg >/dev/null
echo @KALI_FPR@ | sudo tee /etc/wren/distro-vm/kali.fpr
wget -qO- @TAILS_KEY_URL@ | gpg --homedir "$G" --import
gpg --homedir "$G" --export @TAILS_FPR@ | sudo tee /etc/wren/distro-vm/tails.gpg >/dev/null
echo @TAILS_FPR@ | sudo tee /etc/wren/distro-vm/tails.fpr
wget -qO- @ARCH_ISO_KEY_URL@ | gpg --homedir "$G" --import
gpg --homedir "$G" --export @ARCH_ISO_FPR@ | sudo tee /etc/wren/distro-vm/arch.gpg >/dev/null
echo @ARCH_ISO_FPR@ | sudo tee /etc/wren/distro-vm/arch.fpr
rm -rf "$G"

# One locked system user per distribution, in the kvm group only (kali shown;
# the same for tails and arch)
sudo install -d -o root -g root -m 0755 /var/lib/wren-distro-vm
sudo useradd --system --user-group --no-create-home --home-dir /var/lib/wren-distro-vm/kali \
    --shell /usr/sbin/nologin --comment "Wren Linux kali VM" dvm-kali
sudo usermod --lock dvm-kali
sudo usermod -G kvm dvm-kali
sudo install -d -o dvm-kali -g dvm-kali -m 0700 /var/lib/wren-distro-vm/kali

# Which VM may reach what (direct: the internet, not your network; tor: Tor
# only; Tails always direct), and whose screen it is
printf 'owner %s\nkali direct\ntails direct\narch tor\n' "$(id -un)" | sudo tee /etc/wren/distro-vm.conf

# The firewall rule, with each user in its set, loaded at every boot
{ cat @WREN_DIR@/data/distro-vm-firewall.nft
  echo 'add element inet wren_distro_vm direct { "dvm-kali", "dvm-tails" }'
  echo 'add element inet wren_distro_vm tor { "dvm-arch" }'; } >/tmp/wren-distro-vm.nft
sudo nft -c -f /tmp/wren-distro-vm.nft
sudo install -o root -g root -m 0644 /tmp/wren-distro-vm.nft /etc/wren/distro-vm.nft
rm /tmp/wren-distro-vm.nft
printf '%s\n' '[Unit]' 'Description=Keep the distro-vm VMs off the local network' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' 'ExecStart=/usr/sbin/nft -f /etc/wren/distro-vm.nft' \
    'ExecStop=/usr/sbin/nft delete table inet wren_distro_vm' '' '[Install]' 'WantedBy=multi-user.target' |
    sudo tee /etc/systemd/system/wren-distro-vm-firewall.service
sudo systemctl daemon-reload
sudo systemctl enable --now wren-distro-vm-firewall.service
# Its DNS set, filled from /etc/resolv.conf (parts/sandbox-dns.sh does this at
# every change; add wren-distro-vm-firewall to its list for that)
sudo /usr/local/libexec/wren-sandbox-dns

# Only if a VM goes through Tor: the system Tor's TransPort and DNSPort
# (with your bridge lines below them, if you need a bridge), then restart it
sudo apt install --no-install-recommends tor
printf '%s\n' '# >>> Wren Linux distro-vm >>>' 'TransPort 127.0.0.1:@TRANS_PORT@' 'DNSPort 127.0.0.1:@DNS_PORT@' \
    'VirtualAddrNetworkIPv4 10.192.0.0/10' 'AutomapHostsOnResolve 1' '# <<< Wren Linux distro-vm <<<' |
    sudo tee -a /etc/tor/torrc
echo 'Written by Wren Linux extras/distro-vm.sh' | sudo tee /etc/tor/.wren-distro-vm
sudo systemctl restart tor@default.service

# The session script, the net check and the no-abstract-sockets wrapper, as root's files
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/distro-vm-session /usr/local/libexec/distro-vm-session
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/distro-vm-net-check /usr/local/libexec/distro-vm-net-check
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/no-abstract-sockets /usr/local/libexec/wren-no-abstract-sockets

# Your user may run the session script, and nothing else, as the VMs' users.
# visudo checks the rule first: never put a rule in /etc/sudoers.d it hasn't passed.
printf '%s ALL=(dvm-kali,dvm-tails,dvm-arch) NOPASSWD: /usr/local/libexec/distro-vm-session\n' "$(id -un)" >/tmp/wren-distro-vm
sudo visudo -cf /tmp/wren-distro-vm
sudo install -o root -g root -m 0440 /tmp/wren-distro-vm /etc/sudoers.d/wren-distro-vm
rm /tmp/wren-distro-vm

# The command
install -D -m 0755 @WREN_DIR@/bin/distro-vm ~/.local/bin/distro-vm
```

To undo it:

```
distro-vm kali stop; distro-vm tails stop; distro-vm arch stop
sudo systemctl disable --now wren-distro-vm-firewall.service
sudo rm -f /etc/systemd/system/wren-distro-vm-firewall.service /etc/wren/distro-vm.nft /etc/wren/distro-vm.conf \
    /etc/sudoers.d/wren-distro-vm /usr/local/libexec/distro-vm-session /usr/local/libexec/distro-vm-net-check \
    ~/.local/bin/distro-vm
sudo rm -rf /etc/wren/distro-vm
# The Tor block, if you added it, and Tor itself if nothing else uses it
sudo sed -i '/^# >>> Wren Linux distro-vm >>>$/,/^# <<< Wren Linux distro-vm <<<$/d' /etc/tor/torrc
sudo rm -f /etc/tor/.wren-distro-vm
# Each user, with its images and disk (kali shown)
sudo userdel dvm-kali && sudo rm -rf /var/lib/wren-distro-vm/kali
sudo apt-mark auto qemu-system-x86 qemu-utils qemu-system-modules-spice virt-viewer nftables
```
