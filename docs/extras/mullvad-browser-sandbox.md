# Mullvad Browser as its own user (`extras/mullvad-browser-sandbox.sh`)

## SYNOPSIS

```
wrenctl install mullvad-browser-sandbox           install it
wrenctl remove mullvad-browser-sandbox            remove it (asks before deleting its settings)
wrenctl manual mullvad-browser-sandbox            print the manual steps below

mullvad-browser [URL]        start it (or Super+d); connect a VPN first
browser-sandbox clip         move one line of text in or out, after showing it to you (or Super+Ctrl+b)
~/Browsers/mullvad-browser   what it saves, and what you give it
```

Mullvad Browser is made by the Tor Project and Mullvad: Tor Browser's protections against tracking
and fingerprinting, without Tor. It is meant for use with a VPN, and forgets everything when closed.
It comes from Mullvad's own apt repository, whose signing key must be exactly the one pinned in
`pins.sh` (`MULLVAD_FPR`).

Here it runs as its own user, `mullvad-browser`, with no password, no login and none of your files,
so a hacked page doesn't reach your documents, keys or passwords. It opens in a window of its own
(cage) with a private X server, and a restricted socket keeps it from your screen.

A firewall rule (`data/mullvad-browser-firewall.nft`) keeps it off this computer and your local
network; it is checked from its own side at every start and while it runs. It reaches the internet
as your computer does: through your VPN, if one is connected.

Nothing crosses by itself. A line of plain text goes through `browser-sandbox clip`, which shows it
to you first; files go through `~/Browsers/mullvad-browser`, a link to a folder outside your home.

## LIMITS

- It doesn't hide your address: without a VPN, sites see it and your network sees where you go.
- It isn't Tor, and hiding your address doesn't hide who you are to a site you log in to.
- It shares your kernel: a kernel bug could let a page out of its user.
- It keeps its own DNS over HTTPS, which secure DNS (`parts/secure-dns.sh`) can't stop.
- `/usr/bin/mullvad-browser` by its full path runs as you, without any of this.
- Files in `~/Browsers` come from the web: treat them, and any link among them, as untrusted.

## MANUAL INSTALL

```
# Mullvad's signing key. Check it is exactly the pinned one: this must
# print @MULLVAD_FPR@
wget -O /tmp/mullvad-keyring.asc @MULLVAD_KEY_URL@
gpg --show-keys --with-colons /tmp/mullvad-keyring.asc | awk -F: '/^fpr:/ { print $10; exit }'
sudo install -m 0644 /tmp/mullvad-keyring.asc /usr/share/keyrings/mullvad-keyring.asc
rm /tmp/mullvad-keyring.asc
echo "deb [signed-by=/usr/share/keyrings/mullvad-keyring.asc arch=$(dpkg --print-architecture)] https://repository.mullvad.net/deb/stable stable main" |
    sudo tee /etc/apt/sources.list.d/mullvad.list

# The browser; its window, private X server and clipboard tools; what shares the
# socket and the folder; the firewall; its sound server and your player
sudo apt update
sudo apt install --no-install-recommends mullvad-browser xwayland cage xclip wl-clipboard acl nftables \
    python3 pipewire-bin pipewire-pulse wireplumber
# If XWayland was new: log out and back in once, so sway starts it

# Its user: no password, no login, a home only it can enter. render: cage opens the GPU's render node
sudo useradd --system --user-group --create-home --home-dir /home/mullvad-browser \
    --shell /usr/sbin/nologin --comment "Wren Linux sandboxed Mullvad Browser" mullvad-browser
sudo usermod --lock mullvad-browser
sudo chmod 0700 /home/mullvad-browser
sudo usermod -aG render mullvad-browser

# The folder you and it share: root's, you and it, nobody else
sudo install -d -o root -g root -m 0755 /var/lib/wren-browsers
sudo install -d -o root -g root -m 0770 /var/lib/wren-browsers/mullvad-browser
sudo setfacl -P -m "u:$USER:rwx,u:mullvad-browser:rwx" /var/lib/wren-browsers/mullvad-browser
sudo setfacl -P -d -m "u:$USER:rwx,u:mullvad-browser:rwx" /var/lib/wren-browsers/mullvad-browser
ln -sfn /var/lib/wren-browsers ~/Browsers

# The programs, root's
install -D -m 0755 @WREN_DIR@/bin/wayland-restrict ~/.local/bin/wayland-restrict
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/no-abstract-sockets /usr/local/libexec/wren-no-abstract-sockets
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/sandbox-net-check /usr/local/libexec/wren-sandbox-net-check
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/browser-sandbox /usr/local/bin/browser-sandbox
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/browser-session /usr/local/libexec/browser-session
sudo ln -sfn browser-sandbox /usr/local/bin/mullvad-browser

# What your user may run as it: only the session script. visudo checks it first
echo "$USER ALL=(mullvad-browser) NOPASSWD: /usr/local/libexec/browser-session" >/tmp/wren-mb.rule
sudo visudo -cf /tmp/wren-mb.rule
sudo install -o root -g root -m 0440 /tmp/wren-mb.rule /etc/sudoers.d/wren-mullvad-browser
rm /tmp/wren-mb.rule
printf '%s\n' 'mullvad-browser hard nproc 4096' 'mullvad-browser hard core 0' | sudo tee /etc/security/limits.d/50-wren-mullvad-browser.conf

# The firewall, at every boot
sudo install -d -o root -g root -m 0755 /etc/wren
sudo install -o root -g root -m 0644 @WREN_DIR@/data/mullvad-browser-firewall.nft /etc/wren/mullvad-browser.nft
printf '%s\n' '[Unit]' 'Description=Keep the mullvad-browser user off this computer and your network' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' 'Type=oneshot' 'RemainAfterExit=yes' \
    'ExecStart=/usr/sbin/nft -f /etc/wren/mullvad-browser.nft' 'ExecStartPost=-/usr/local/libexec/wren-sandbox-dns' \
    'ExecStop=/usr/sbin/nft delete table inet wren_mullvad_browser' '' '[Install]' 'WantedBy=multi-user.target' |
    sudo tee /etc/systemd/system/wren-mullvad-browser-firewall.service
sudo systemctl daemon-reload
sudo systemctl enable --now wren-mullvad-browser-firewall.service

# The key that moves a line of text, in ~/.config/sway/config.d/browser-sandbox.conf:
#   bindsym $mod+Ctrl+b exec foot -e /usr/local/bin/browser-sandbox clip-window

mullvad-browser
```

To undo:

```
sudo systemctl disable --now wren-mullvad-browser-firewall.service
sudo rm -f /etc/sudoers.d/wren-mullvad-browser /etc/security/limits.d/50-wren-mullvad-browser.conf \
    /usr/local/bin/mullvad-browser /etc/wren/mullvad-browser.nft \
    /etc/systemd/system/wren-mullvad-browser-firewall.service
sudo systemctl daemon-reload
# With the sandboxed Tor Browser gone too: the shared command, session and link
sudo rm -f /usr/local/bin/browser-sandbox /usr/local/libexec/browser-session
rm -f ~/Browsers ~/.config/sway/config.d/browser-sandbox.conf
# The user, and its settings
sudo pkill -KILL -u mullvad-browser
sudo userdel -r mullvad-browser
# The browser, marked "automatic": autoremove takes it only if nothing else needs it
sudo apt-mark auto mullvad-browser cage xclip wl-clipboard
sudo apt autoremove --purge
# Mullvad's repository, if Mullvad VPN and the browser as you aren't installed either
sudo rm -f /etc/apt/sources.list.d/mullvad.list /usr/share/keyrings/mullvad-keyring.asc
# What it saved, when you don't need it
sudo rm -rf /var/lib/wren-browsers/mullvad-browser
```
