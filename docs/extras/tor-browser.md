# Tor Browser (`extras/tor-browser.sh`)

## SYNOPSIS

```
wrenctl install tor-browser                     install it, or change its bridge (asks if you need one)
wrenctl remove tor-browser                      remove it (asks before deleting its bookmarks)
wrenctl manual tor-browser                      print the manual steps below

tor-browser [URL]          start Tor Browser (or Super+d); torbrowser-launcher by name does the same
browser-sandbox clip       move one line of text in or out, after showing it to you (or Super+Ctrl+b)
~/Browsers/tor-browser     what it saves, and what you give it
```

Tor Browser sends what you browse through three Tor relays, so the sites can't see your address and
your network can't see where you go.

Here it runs as its own user, `tor-browser`, with no password, no login and none of your files, so a
hacked page reaches that user's bookmarks and settings, not your documents, keys or passwords.

It opens in a window of its own (cage) with a private X server. Tor Browser runs on X11 on purpose
(it's less fingerprintable), and on X11 any program can read every window and key: this way there is
nothing else on its X server, and a restricted socket keeps it from your screen.

A firewall rule (`data/tor-browser-firewall.nft`) keeps it off this computer and your local network.
It may reach only itself on this computer: its browser and its Tor, and its Tor and a bridge's
program. Each such connection is marked, and a listener's answer gets out only if that listener is
the same user, so no program of yours can be reached that way. The rule is checked from its own side
at every start and while it runs: without the rule it won't open, and it closes if the rule goes.

Nothing crosses by itself. A line of plain text goes through `browser-sandbox clip`, which shows it
to you first; files go through `~/Browsers/tor-browser`, a link to a folder outside your home.

The browser is the Tor Project's own, checked against their signing key (`TB_FPR` in `pins.sh`) and
unpacked by its user. It updates itself, through Tor. Debian's `torbrowser-launcher` is installed for
the AppArmor profiles it brings, which confine the browser and its Tor; it is in Debian's contrib
section, so contrib is turned on.

Before its first start, Wren Linux writes a `user.js` into its profile: the Safest security level
with JavaScript off (`data/tor-browser-safest.js`), and a bridge if you need one (obfs4, webtunnel,
Snowflake or meek), so its very first connection already goes through it; Firefox applies `user.js`
at every start. Tor's AppArmor profile is fixed so bridges given as host names can be looked up.

If `prep/fetch-tor-browser.sh` saved a checked copy in `offline/torbrowser`, that is unpacked
instead, and torproject.org is never contacted.

## LIMITS

- **It doesn't force the browser through Tor.** Browser and Tor are one user, so a hacked browser
  could go straight out and show your address. Whonix is what stops that; if that matters, use Whonix
  or Tails.
- A hacked browser can change its own program files, as it has to be able to update itself. That
  stays inside this user: not your files, and not after you delete its home.
- It shares your kernel: a kernel bug could let a page out of its user.
- From inside, a hacked browser can tell whether a port on this computer has a listener (it gets no
  answer, rather than a refusal). It can't connect to it or send it anything.
- The first start downloads Tor Browser without Tor: your network sees that you fetched it (not what
  you do with it).
- Logging in to a site tells it who you are, Tor or not.
- Safest breaks many sites; lowering it gives attackers more to work with.
- `/usr/bin/torbrowser-launcher` by its full path runs as you, without any of this. A Tor Browser you
  already had there is left alone, and `wrenctl remove tor-browser` asks about it. Its bookmarks
  aren't moved: export them there, and import that file from `~/Browsers/tor-browser`.
- Files in `~/Browsers` come from the web: treat them, and any link among them, as untrusted.
- A backup doesn't cover it: `/home/tor-browser` is that user's, and only root can read it.

## MANUAL INSTALL

```
# Debian's contrib section, where torbrowser-launcher is: add "contrib" after
# "main" on Debian's lines (in /etc/apt/sources.list, or the Components: lines
# of /etc/apt/sources.list.d/debian.sources), then check
sudo sed -i -E '/^deb(-src)?[[:space:]].*debian/ { /[[:space:]]contrib([[:space:]]|$)/! s/[[:space:]]main([[:space:]]|$)/ main contrib\1/ }' /etc/apt/sources.list
grep -n contrib /etc/apt/sources.list /etc/apt/sources.list.d/*.sources

# The launcher, for its AppArmor profiles; its window, private X server and clipboard tools;
# what shares the socket and the folder; the firewall; its sound server and your player
sudo apt update
sudo apt install --no-install-recommends xwayland torbrowser-launcher xz-utils cage xclip wl-clipboard \
    acl nftables python3 pipewire-bin pipewire-pulse wireplumber
# If XWayland was new: log out and back in once, so sway starts it

# Let Tor's AppArmor profile read resolv.conf through its symlink, for
# bridges given as host names (webtunnel), then reload the profile
printf '%s\n' '# >>> Wren Linux: DNS through the resolv.conf symlink >>>' \
    '@{run}/resolvconf/resolv.conf r,' '@{run}/NetworkManager/{,no-stub-}resolv.conf r,' \
    '@{run}/systemd/resolve/{,stub-}resolv.conf r,' '# <<< Wren Linux <<<' | sudo tee -a /etc/apparmor.d/local/torbrowser.Tor.tor
# Tor Browser 16 keeps torrc-defaults (where its bridges' programs are named),
# geoip and geoip6 in TorBrowser/Tor, which the package's profile doesn't let Tor
# read: without this, every bridge fails ("there is no configured transport")
printf '%s\n' "# >>> Wren Linux: what Tor Browser 16 keeps in TorBrowser/Tor >>>" \
    'owner @{torbrowser_home_dir}/TorBrowser/Tor/torrc-defaults r,' \
    'owner @{torbrowser_home_dir}/TorBrowser/Tor/geoip r,' \
    'owner @{torbrowser_home_dir}/TorBrowser/Tor/geoip6 r,' '# <<< Wren Linux <<<' | sudo tee -a /etc/apparmor.d/local/torbrowser.Tor.tor
sudo apparmor_parser -r /etc/apparmor.d/torbrowser.Tor.tor

# Its user: no password, no login, a home only it can enter. In /home: the
# AppArmor profiles attach only under it. render: cage opens the GPU's render node
sudo useradd --system --user-group --create-home --home-dir /home/tor-browser \
    --shell /usr/sbin/nologin --comment "Wren Linux sandboxed Tor Browser" tor-browser
sudo usermod --lock tor-browser
sudo chmod 0700 /home/tor-browser
sudo usermod -aG render tor-browser

# Let the browser save in the folder you share with it, and reach its own sound server
printf '%s\n' '# >>> Wren Linux: Tor Browser as its own user >>>' \
    '/var/lib/wren-browsers/tor-browser/ rw,' '/var/lib/wren-browsers/tor-browser/** rwk,' \
    'owner /dev/shm/tor-browser.*/run/pulse/ r,' 'owner /dev/shm/tor-browser.*/run/pulse/native rw,' \
    '# <<< Wren Linux <<<' | sudo tee -a /etc/apparmor.d/local/torbrowser.Browser.firefox
sudo apparmor_parser -r /etc/apparmor.d/torbrowser.Browser.firefox

# The folder you and it share: root's, you and it, nobody else
sudo install -d -o root -g root -m 0755 /var/lib/wren-browsers
sudo install -d -o root -g root -m 0770 /var/lib/wren-browsers/tor-browser
sudo setfacl -P -m "u:$USER:rwx,u:tor-browser:rwx" /var/lib/wren-browsers/tor-browser
sudo setfacl -P -d -m "u:$USER:rwx,u:tor-browser:rwx" /var/lib/wren-browsers/tor-browser
ln -sfn /var/lib/wren-browsers ~/Browsers

# The programs, root's
install -D -m 0755 @WREN_DIR@/bin/wayland-restrict ~/.local/bin/wayland-restrict
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/no-abstract-sockets /usr/local/libexec/wren-no-abstract-sockets
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/sandbox-net-check /usr/local/libexec/wren-sandbox-net-check
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/browser-sandbox /usr/local/bin/browser-sandbox
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/browser-session /usr/local/libexec/browser-session
sudo ln -sfn browser-sandbox /usr/local/bin/tor-browser
sudo ln -sfn browser-sandbox /usr/local/bin/torbrowser-launcher

# What your user may run as it: only the session script. visudo checks it first
echo "$USER ALL=(tor-browser) NOPASSWD: /usr/local/libexec/browser-session" >/tmp/wren-tb.rule
sudo visudo -cf /tmp/wren-tb.rule
sudo install -o root -g root -m 0440 /tmp/wren-tb.rule /etc/sudoers.d/wren-tor-browser
rm /tmp/wren-tb.rule
printf '%s\n' 'tor-browser hard nproc 4096' 'tor-browser hard core 0' | sudo tee /etc/security/limits.d/50-wren-tor-browser.conf

# The firewall, at every boot
sudo install -d -o root -g root -m 0755 /etc/wren
sudo install -o root -g root -m 0644 @WREN_DIR@/data/tor-browser-firewall.nft /etc/wren/tor-browser.nft
printf '%s\n' '[Unit]' 'Description=Keep the tor-browser user off this computer and your network' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' 'Type=oneshot' 'RemainAfterExit=yes' \
    'ExecStart=/usr/sbin/nft -f /etc/wren/tor-browser.nft' 'ExecStartPost=-/usr/local/libexec/wren-sandbox-dns' \
    'ExecStop=/usr/sbin/nft delete table inet wren_tor_browser' '' '[Install]' 'WantedBy=multi-user.target' |
    sudo tee /etc/systemd/system/wren-tor-browser-firewall.service
sudo systemctl daemon-reload
sudo systemctl enable --now wren-tor-browser-firewall.service

# Tor Browser, checked against its developers' key: this must say "Saved and verified"
bash @WREN_DIR@/prep/fetch-tor-browser.sh
# Unpacked by its user, from standard input (use the name fetch-tor-browser.sh printed)
B=/home/tor-browser/.local/share/torbrowser/tbb/$(uname -m)
(cd / && sudo -u tor-browser mkdir -p "$B")
sudo -u tor-browser tar -xJ -C "$B" <@WREN_DIR@/offline/torbrowser/tor-browser-linux-$(uname -m)-VERSION.tar.xz

# Safest, JavaScript off, before its first start. A bridge, if you need one: add
# ONE of these blocks to a copy of the file first
#  Tor Browser's built-in bridges (TYPE is obfs4, snowflake or meek):
#    user_pref("torbrowser.settings.bridges.enabled", true);
#    user_pref("torbrowser.settings.bridges.source", 0);
#    user_pref("torbrowser.settings.bridges.builtin_type", "TYPE");
#  your own obfs4 or webtunnel lines from bridges.torproject.org, numbered from 0:
#    user_pref("torbrowser.settings.bridges.enabled", true);
#    user_pref("torbrowser.settings.bridges.source", 2);
#    user_pref("torbrowser.settings.bridges.bridge_strings.0", "obfs4 1.2.3.4:443 ...");
P=$B/tor-browser/Browser/TorBrowser/Data/Browser/profile.default
(cd / && sudo -u tor-browser mkdir -p "$P")
sudo -u tor-browser tee "$P/user.js" <@WREN_DIR@/data/tor-browser-safest.js >/dev/null

# The key that moves a line of text, in ~/.config/sway/config.d/browser-sandbox.conf:
#   bindsym $mod+Ctrl+b exec foot -e /usr/local/bin/browser-sandbox clip-window

tor-browser
```

To undo (a copy from before, in `~/.local/share/torbrowser`, is yours to delete):

```
sudo systemctl disable --now wren-tor-browser-firewall.service
sudo rm -f /etc/sudoers.d/wren-tor-browser /etc/security/limits.d/50-wren-tor-browser.conf \
    /usr/local/bin/tor-browser /usr/local/bin/torbrowser-launcher /etc/wren/tor-browser.nft \
    /etc/systemd/system/wren-tor-browser-firewall.service
sudo systemctl daemon-reload
# With the sandboxed Mullvad Browser gone too: the shared command, session and link
sudo rm -f /usr/local/bin/browser-sandbox /usr/local/libexec/browser-session
rm -f ~/Browsers ~/.config/sway/config.d/browser-sandbox.conf
# The user, and its bookmarks and settings
sudo pkill -KILL -u tor-browser
sudo userdel -r tor-browser
# The launcher
sudo apt purge torbrowser-launcher
# The AppArmor lines added above (between the Wren Linux marker lines)
sudo sed -i '/^# >>> Wren Linux: DNS through the resolv.conf symlink >>>$/,/^# <<< Wren Linux <<<$/d' /etc/apparmor.d/local/torbrowser.Tor.tor
sudo sed -i '/^# >>> Wren Linux: Tor Browser as its own user >>>$/,/^# <<< Wren Linux <<<$/d' /etc/apparmor.d/local/torbrowser.Browser.firefox
# contrib off again, if nothing else needs it
sudo sed -i -E 's/ main contrib([[:space:]]|$)/ main\1/' /etc/apt/sources.list
sudo apt update
# What it saved, when you don't need it
sudo rm -rf /var/lib/wren-browsers/tor-browser
```
