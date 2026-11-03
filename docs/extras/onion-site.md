# Your own onion site (`extras/onion-site.sh`)

## SYNOPSIS

```
debsway install onion-site                     set it up and build its VM (asks: which kind, public or private, a bridge)
debsway remove onion-site                      take it out (asks before deleting the address and the VM)
debsway manual onion-site                      print the manual steps below

onion-site start | stop | status    the site is up while its VM runs (it starts at every boot)
onion-site upload static FOLDER     your files, served as they are
onion-site upload app FOLDER        your app (python: a Flask app.py; any: run it on 127.0.0.1:8000)
onion-site shell                    a shell in the VM (as the user "site")
onion-site update                   the VM's security updates, through Tor
onion-site address                  the address again
```

Your own onion site, a Tor .onion address, able to run more than static files:
nginx in front, and either your own app server ("any") or a Python (Flask)
app run by gunicorn ("python"). It runs on this computer, but in a VM with no
network at all (QEMU's `restrict=on`), so whatever the site does it can't
give away this computer's address. The VM is built with the bundled
mockvps-kvm and run by a locked user, `onion-site`, whose firewall rule
(`data/onion-site-firewall.nft`) also governs it; two loopback ports lead in,
its ssh console and its nginx, which Tor's onion service points at. Tor runs
on this computer (the system tor service, shared with apt over Tor and remote
access), with its defences against floods of visits. The site is public, or
private: only visitors you give a client key can even find it. The VM starts
at every boot, and gets security updates through this computer's Tor with
`onion-site update`. Your user may run exactly one thing as `onion-site`, the
`onion-site-session` script, through a rule in `/etc/sudoers.d`.

## LIMITS

- The site is up only while this computer is on: that pattern can link it to you.
- A hole in your app gets the VM and the site's data (not this computer).
- The app has no network: no fonts, images or email from the internet.
- Whoever has `/var/lib/tor/debsway-onion-site` can be this address: back it up as root, and keep it private.

## MANUAL INSTALL

```
# KVM must be on: this must list /dev/kvm
ls -l /dev/kvm
# Your choices: APP is python (Flask with gunicorn) or any (your own app
# server); a private site gets a client key further down
APP=python

# Debian starts tor the moment it is installed: hold it until it is set up
# (skip this if apt over Tor or remote access already runs tor)
sudo systemctl mask tor.service tor@default.service
# The VM, socat, nftables, ssh into the VM, the checked Debian installer, tor
# and openssl (add obfs4proxy or snowflake-client for a bridge; for webtunnel,
# lyrebird: see docs/install-base.md, "webtunnel for the system Tor")
sudo apt install --no-install-recommends qemu-system-x86 qemu-utils socat nftables openssh-client cpio gzip wget gpgv \
    debian-archive-keyring tor openssl

# The onion-site user, locked, with /dev/kvm as its only extra group
sudo useradd --create-home --home-dir /home/onion-site --shell /bin/bash --user-group --comment "debsway onion site VM" onion-site
sudo usermod --lock onion-site
sudo chmod 700 /home/onion-site
sudo usermod -aG kvm onion-site

# The firewall rule on that user (and so its VM), loaded at every boot
sudo install -D -o root -g root -m 0644 @DEBSWAY_DIR@/data/onion-site-firewall.nft /etc/debsway/onion-site.nft
printf '%s\n' '[Unit]' 'Description=Keep the onion-site user (and its VM) off the local network' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' 'ExecStart=/usr/sbin/nft -f /etc/debsway/onion-site.nft' \
    'ExecStop=/usr/sbin/nft delete table inet debsway_onion_site' '' '[Install]' 'WantedBy=multi-user.target' |
    sudo tee /etc/systemd/system/debsway-onion-site-firewall.service
sudo systemctl daemon-reload
sudo systemctl enable --now debsway-onion-site-firewall.service

# The VM engine, the session script and the no-abstract-sockets wrapper, as root's files
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 @DEBSWAY_DIR@/vendor/mockvps-kvm/mockvps-kvm.sh /usr/local/libexec/onion-site-mockvps-kvm
sudo install -o root -g root -m 0755 @DEBSWAY_DIR@/bin/onion-site-session /usr/local/libexec/onion-site-session
sudo install -o root -g root -m 0755 @DEBSWAY_DIR@/bin/no-abstract-sockets /usr/local/libexec/debsway-no-abstract-sockets
# Your choices, and the provisioning script with them filled in
printf 'app=%s\naccess=%s\n' "$APP" public | sudo install -o root -g root -m 0644 /dev/stdin /etc/debsway/onion-site.conf
sudo install -d -o onion-site -g onion-site -m 0700 /home/onion-site/.config /home/onion-site/.config/onion-site
sed -e "s|[@]APP@|$APP|g" -e 's|[@]VM_USER@|site|g' @DEBSWAY_DIR@/data/onion-site-provision.sh |
    sudo install -o onion-site -g onion-site -m 0600 /dev/stdin /home/onion-site/.config/onion-site/provision.sh

# Your user may run the session script, and nothing else, as onion-site. visudo
# checks the rule first: never put a rule in /etc/sudoers.d it hasn't passed.
printf '%s ALL=(onion-site) NOPASSWD: /usr/local/libexec/onion-site-session\n' "$(id -un)" >/tmp/debsway-onion-site
sudo visudo -cf /tmp/debsway-onion-site
sudo install -o root -g root -m 0440 /tmp/debsway-onion-site /etc/sudoers.d/debsway-onion-site
rm /tmp/debsway-onion-site
install -D -m 0755 @DEBSWAY_DIR@/bin/onion-site ~/.local/bin/onion-site

# A bridge, if you need one, at the end of /etc/tor/torrc (as in remote-access.md)
# The onion service: port 80 of the address leads to the VM's nginx on
# 127.0.0.1:@ONION_SITE_WEB_PORT@, with Tor's limits on floods of visits
sudo install -d -m 0700 -o debian-tor -g debian-tor @ONION_SITE_SVC_DIR@ @ONION_SITE_SVC_DIR@/authorized_clients
printf '%s\n' '# >>> debsway onion-site >>>' 'HiddenServiceDir @ONION_SITE_SVC_DIR@/' 'HiddenServiceVersion 3' \
    'HiddenServicePort 80 127.0.0.1:@ONION_SITE_WEB_PORT@' 'HiddenServiceEnableIntroDoSDefense 1' \
    'HiddenServicePoWDefensesEnabled 1' '# <<< debsway onion-site <<<' | sudo tee -a /etc/tor/torrc
# tor must accept it ("Configuration was valid"); if it names
# HiddenServicePoWDefensesEnabled, this tor lacks that defence: delete that line
sudo tor --defaults-torrc /usr/share/tor/tor-service-defaults-torrc -f /etc/tor/torrc --RunAsDaemon 0 --verify-config
# A mark that tells debsway's other scripts this uses the system tor
echo 'Written by debsway extras/onion-site.sh: the system tor service runs the onion site.' | sudo tee @ONION_SITE_MARK@

# For a private site: a client key (tor gets the public half; give the
# private half to the visitor, whose Tor Browser asks for it)
openssl genpkey -algorithm x25519 -outform DER -out /tmp/client.der
PRIV=$(tail -c 32 /tmp/client.der | base32 | tr -d =)
PUB=$(openssl pkey -inform DER -in /tmp/client.der -pubout -outform DER | tail -c 32 | base32 | tr -d =)
rm /tmp/client.der
echo "descriptor:x25519:$PUB" | sudo install -o debian-tor -g debian-tor -m 0600 /dev/stdin @ONION_SITE_SVC_DIR@/authorized_clients/client.auth
sudo sed -i 's/^access=public$/access=private/' /etc/debsway/onion-site.conf
echo "the visitor's key: $PRIV"

# Start tor now and at every boot, and show the address
sudo systemctl unmask tor.service tor@default.service
sudo systemctl enable tor.service tor@default.service
sudo systemctl restart tor@default.service
sleep 30
sudo cat @ONION_SITE_SVC_DIR@/hostname

# Build the VM (unattended, 10-20 minutes)
sudo -u onion-site /usr/local/libexec/onion-site-session install

# Start it at every boot, after its firewall rule, and power it off cleanly at shutdown
printf '%s\n' '[Unit]' "Description=The onion site's VM" 'Requires=debsway-onion-site-firewall.service' \
    'After=debsway-onion-site-firewall.service tor@default.service' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' 'User=onion-site' \
    'ExecStart=/usr/local/libexec/onion-site-session start' 'ExecStop=/usr/local/libexec/onion-site-session stop' \
    'TimeoutStartSec=600' 'TimeoutStopSec=120' '' '[Install]' 'WantedBy=multi-user.target' |
    sudo tee /etc/systemd/system/debsway-onion-site.service
sudo systemctl daemon-reload
sudo systemctl enable --now debsway-onion-site.service
onion-site status
```

To undo:

```
# The VM off, and no longer started at boot
sudo systemctl disable --now debsway-onion-site.service
sudo systemctl disable --now debsway-onion-site-firewall.service
sudo rm /etc/systemd/system/debsway-onion-site.service /etc/systemd/system/debsway-onion-site-firewall.service /etc/debsway/onion-site.nft
sudo systemctl daemon-reload
# The onion service's lines in torrc, its mark, and its address (gone for good)
sudo sed -i '/^# >>> debsway onion-site >>>$/,/^# <<< debsway onion-site <<<$/d' /etc/tor/torrc
sudo rm @ONION_SITE_MARK@
sudo rm -rf @ONION_SITE_SVC_DIR@
# Stop tor (unless apt over Tor or remote access uses it)
sudo systemctl disable --now tor@default.service tor.service
# The command, the sudo rule, root's scripts and the settings
rm ~/.local/bin/onion-site
sudo rm /etc/sudoers.d/debsway-onion-site /usr/local/libexec/onion-site-session /usr/local/libexec/onion-site-mockvps-kvm /etc/debsway/onion-site.conf
# (the no-abstract-sockets wrapper only if no other sandbox uses it)
sudo rm /usr/local/libexec/debsway-no-abstract-sockets
# The user, its home and the VM (with the site's files and data)
sudo pkill -KILL -u onion-site
sudo userdel -r onion-site
# The packages, marked "automatic": autoremove takes them out only if nothing needs them
sudo apt-mark auto qemu-system-x86 qemu-utils socat nftables tor openssl
# (and the bridge program, if you set one up: obfs4proxy, lyrebird or snowflake-client)
sudo apt autoremove --purge
# Once lyrebird is gone (webtunnel), the Tor Project's repository too
dpkg -s lyrebird >/dev/null 2>&1 || sudo rm -f /etc/apt/sources.list.d/debsway-torproject.list \
    /etc/apt/preferences.d/debsway-torproject.pref /usr/share/keyrings/debsway-torproject.asc /etc/apt/apt.conf.d/52debsway-torproject
```
