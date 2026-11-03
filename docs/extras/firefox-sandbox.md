# Firefox as its own user (`extras/firefox-sandbox.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/firefox-sandbox.sh            install it (with Firefox's hardening and incognito)
bash ~/debsway/extras/firefox-sandbox.sh --remove   remove it (asks about incognito and the profile)
bash ~/debsway/extras/firefox-sandbox.sh --manual   print the manual steps (firefox.md's, then these)

firefox [URL]       the sandboxed Firefox, as a normal window (links from other programs open in it)
firefox-esr         the same Firefox run as you, with everything you can reach
```

The `firefox` command opens Firefox as a normal window on your sway, but it
runs as a different user, `firefox`, with no password, no login and none of
your files, so a hacked page reaches only that user's own profile
(`/var/lib/debsway-firefox`: your logins, history and bookmarks), not your
documents, keys or passwords. The clipboard is shared while its window has
focus, and `~/Downloads` both ways. Its sound goes through a pipe into a
player of yours, so it can't hear your microphone, and it gets a restricted
Wayland socket. A firewall rule on its group, `debsway-fx`
(`data/firefox-firewall.nft`), keeps it off your router, printers and this
computer's own services; DNS stays open. Your user may run exactly one thing
as it, the session script `bin/firefox-session`, through a rule in
`/etc/sudoers.d`, and a limit on processes keeps a runaway page from filling
the machine. Its install asks six things, remembered in
`/etc/debsway/firefox.conf` (which only root can write) and asked again when
you run it again in a terminal: fast JavaScript (the JIT; default no, since
it is where many browser attacks happen), sound (default yes), whether it is
your default browser, so links from other programs open in it (default yes),
and uBlock Origin's mode: medium (default: other sites' scripts blocked too;
you allow sites with `ublock-allow`) or standard (ads, trackers and malware
sites blocked, sites work), and, for when the secure DNS extra isn't
installed, Firefox's own encrypted DNS to Quad9: strict (default: never plain
DNS) or with fallback to the network's; and whether its cookies, site data
and cache are deleted when it closes (default delete), so websites and the
ad and tracker companies behind them can't recognise you from one visit to
the next: you are then logged out of every site at each close, except sites
you allow under Firefox's Settings > Privacy & Security > Cookies and Site
Data > Manage Exceptions. History, bookmarks and saved passwords stay either
way (no website can read them), and saved passwords fill in when you click a
login box, not as the page loads (tracking scripts have read what Firefox
filled into hidden boxes). Per-site profiles keep their cookies: that is
what they are for. It follows debsway's light or dark theme
(`theme`), and a JPEG or PNG in `~/Pictures/debsway/firefox` replaces the fox
behind its New Tab page: your `firefox` command hands it a checked copy, which
only the `firefox` user can read, at each start, so it never sees your
pictures folder. It also sets up Firefox's
hardening and `incognito` ([firefox.md](firefox.md)), and the profiles made
with `extras/firefox-profiles/new-profile.sh` each get a user like it.

## LIMITS

- Without the secure DNS extra, and with strict DNS (the default), a Wi-Fi sign-in page (cafés, hotels) won't load in any of debsway's Firefoxes, and on a network that blocks encrypted DNS no site will: run this again and choose fallback, or install the secure DNS extra.
- What lands in `~/Downloads` comes from the web: treat it as untrusted.
- With cookies deleted on close (the default), every site logs you out when Firefox closes, and a few forget settings or ask about cookies again; allow the sites you want to stay logged in to under Manage Exceptions, or choose keep.
- The clipboard is shared while its window has focus.
- No WebRTC and no microphone or camera, here and in the profiles: video calls
  and browser-to-browser file transfers don't work.
- It shares your kernel: a kernel bug could let a page out of its user.
- It's your network and your address; and `firefox-esr` runs as you, without any of this.

## MANUAL INSTALL

Do the steps in [firefox.md](firefox.md) first: Firefox's hardening, then
incognito. (`--manual` prints them above these.)

```
# Firefox, video codecs, uBlock, acl for sharing the socket and ~/Downloads,
# nftables, its own audio server and player, dbus for links to the running Firefox
sudo apt install --no-install-recommends firefox-esr libavcodec61 webext-ublock-origin-firefox acl nftables python3 dbus-daemon \
    pipewire-bin pipewire-pulse wireplumber

# The group every sandboxed Firefox user is in (the firewall rule matches it)
sudo groupadd --system debsway-fx
# The firefox user: no password, no login shell, a home only it can enter;
# render lets Firefox open the GPU's render node (not the screen)
sudo useradd --system --gid debsway-fx --create-home --home-dir /var/lib/debsway-firefox --shell /usr/sbin/nologin --comment "debsway sandboxed Firefox" firefox
sudo usermod --lock --shell /usr/sbin/nologin firefox
sudo chmod 0700 /var/lib/debsway-firefox
sudo usermod -aG render firefox

# The command, its session script and prefs, the restricted Wayland socket
# and the no-abstract-sockets wrapper
sudo install -d -o root -g root -m 0755 /usr/local/share/debsway /usr/local/libexec
install -D -m 0755 @DEBSWAY_DIR@/bin/wayland-restrict ~/.local/bin/wayland-restrict
sudo install -o root -g root -m 0755 @DEBSWAY_DIR@/bin/no-abstract-sockets /usr/local/libexec/debsway-no-abstract-sockets
sudo install -o root -g root -m 0755 @DEBSWAY_DIR@/bin/firefox /usr/local/bin/firefox
sudo install -o root -g root -m 0755 @DEBSWAY_DIR@/bin/firefox-session /usr/local/libexec/firefox-session
sudo install -o root -g root -m 0644 @DEBSWAY_DIR@/data/firefox-user.js /usr/local/share/debsway/firefox-user.js
# Your choices: fast JavaScript (yes/no), sound, default browser; only root can change them
sudo install -d -o root -g root -m 0755 /etc/debsway
printf 'fast_js=no\nsound=yes\ndefault_browser=yes\nublock=medium\ndns=strict\ncookies=delete\n' | sudo tee /etc/debsway/firefox.conf
sudo /usr/local/bin/ublock-allow --mode medium

# Your user may run the session script, and nothing else, as firefox. visudo
# checks the rule first: never put a rule in /etc/sudoers.d it hasn't passed.
printf '%s ALL=(firefox) NOPASSWD: /usr/local/libexec/firefox-session\n' "$(id -un)" >/tmp/debsway-firefox
sudo visudo -cf /tmp/debsway-firefox
sudo install -o root -g root -m 0440 /tmp/debsway-firefox /etc/sudoers.d/debsway-firefox
rm /tmp/debsway-firefox
# A limit on processes for every sandboxed Firefox user, and no core dumps
printf '%s\n' '@debsway-fx hard nproc 4096' '@debsway-fx hard core 0' | sudo tee /etc/security/limits.d/50-debsway-firefox.conf

# The firewall rule, loaded at every boot before the network comes up
sudo install -D -o root -g root -m 0644 @DEBSWAY_DIR@/data/firefox-firewall.nft /etc/debsway/firefox.nft
printf '%s\n' '[Unit]' 'Description=Keep the firefox user off the local network' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' 'ExecStart=/usr/sbin/nft -f /etc/debsway/firefox.nft' \
    'ExecStop=/usr/sbin/nft delete table inet debsway_firefox' '' '[Install]' 'WantedBy=multi-user.target' |
    sudo tee /etc/systemd/system/debsway-firefox-firewall.service
sudo systemctl daemon-reload
sudo systemctl enable --now debsway-firefox-firewall.service

# The default browser: links from other programs open in it
install -D -m 0644 @DEBSWAY_DIR@/data/debsway-firefox.desktop ~/.local/share/applications/debsway-firefox.desktop
mkdir -p ~/.config && touch ~/.config/mimeapps.list
grep -qx '\[Default Applications\]' ~/.config/mimeapps.list || echo '[Default Applications]' >>~/.config/mimeapps.list
for t in x-scheme-handler/http x-scheme-handler/https; do
    sed -i "\\|^$t=|d; /^\\[Default Applications\\]\$/a $t=debsway-firefox.desktop" ~/.config/mimeapps.list
done
firefox
```

To undo (remove each profile made with new-profile.sh first):

```
# The firewall rule
sudo systemctl disable --now debsway-firefox-firewall.service
sudo rm /etc/systemd/system/debsway-firefox-firewall.service /etc/debsway/firefox.nft
sudo systemctl daemon-reload
# The sudo rule, the limits, the command, its session script and prefs
sudo rm /etc/sudoers.d/debsway-firefox /etc/security/limits.d/50-debsway-firefox.conf
sudo rm /usr/local/bin/firefox /usr/local/libexec/firefox-session /usr/local/share/debsway/firefox-user.js /etc/debsway/firefox.conf
sudo rm -rf /dev/shm/firefox-run
# Links open in firefox-esr again
sed -i '/=debsway-firefox\.desktop$/d' ~/.config/mimeapps.list
rm ~/.local/share/applications/debsway-firefox.desktop
# The user and its group
sudo pkill -KILL -u firefox
sudo userdel firefox
sudo groupdel debsway-fx
# Its profile: your logins, history and bookmarks in it (only if you want them gone)
sudo rm -rf /var/lib/debsway-firefox
```

Then undo [firefox.md](firefox.md)'s steps, unless you keep incognito.
