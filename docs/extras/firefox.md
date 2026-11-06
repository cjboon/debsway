# Firefox's hardening, and incognito (part of `extras/firefox-sandbox.sh`)

## SYNOPSIS

```
wrenctl install firefox-sandbox                     sets these up, with the sandboxed Firefox
bash ~/wren/parts/firefox-hardening.sh           only the hardening; --remove takes it out
bash ~/wren/parts/incognito.sh                   only incognito; --remove takes it out
wrenctl manual firefox-sandbox                      print the manual steps below, then the sandbox's

ublock-allow example.com      let a site that breaks run scripts and frames from other sites
incognito [URL]               a throwaway Firefox that keeps nothing (incognito --no-audio: no sound)
wifi-signin                   the Wi-Fi sign-in window: the same, for a café's or hotel's sign-in page
```

The sandboxed Firefox sets up Firefox ESR the Wren Linux way for every profile
(`parts/firefox-hardening.sh`): uBlock Origin from Debian, in the mode chosen at install: standard
(ads, trackers and known malware sites blocked) or medium (scripts and frames from other sites
blocked too, which is where most malicious ads come from); the JavaScript JIT off, which most
serious Firefox exploits target; HTTPS-Only Mode; Firefox's DNS encrypted (the system's while secure
DNS is on, else its own to Quad9, strict or with fallback); a New Tab with no shortcuts, sponsored
items or weather; and a notice when Firefox was updated while running and needs a restart.

The prefs are `data/firefox-hardening.js`, the policies come from `bin/ublock-allow`.

It also sets up `incognito` (`parts/incognito.sh`): a throwaway Firefox in cage, a tiny compositor
shown as one window, as a locked user with no home, no files of yours, no shared clipboard and only
a restricted Wayland socket; its profile lives in memory and is deleted when the window closes.

Its sound goes through a pipe into a player of yours, so it can't hear your microphone, and a
firewall rule on that user (`data/incognito-firewall.nft`) keeps it off your network.

The Wi-Fi sign-in window (`wifi-signin`) is the same throwaway Firefox as a second such user,
`wifi-signin`, with the network's own DNS and plain http allowed; its rule
(`data/wifi-signin-firewall.nft`) lets it reach the local network, where sign-in pages often are,
but not this computer.

That user runs only that window.

## LIMITS

- uBlock's medium mode, if chosen, breaks some sites until you allow them; the JIT being off makes
  heavy sites slower.
- `incognito` is still your network and your address: use Tor Browser or a VPN for that.
- The Wi-Fi sign-in window can reach your local network (router, printers, other computers) while it
  is open: use it for sign-in pages only.
- `incognito` has no WebRTC: video calls and browser-to-browser file transfers don't work there.
- Any window, `incognito` included, can be captured by screenshots.
- Both share your kernel: a kernel bug could get out of them.

## MANUAL INSTALL

```
# --- Firefox's hardening ---
# Firefox ESR, uBlock Origin, and notifications for the restart notice
sudo apt install --no-install-recommends firefox-esr webext-ublock-origin-firefox libnotify-bin
# The default prefs for every profile (Firefox reads /etc/firefox-esr/*.js)
sudo install -m 0644 @WREN_DIR@/data/firefox-hardening.js /etc/firefox-esr/wren-hardening.js
# uBlock Origin (medium mode, or standard) and Firefox's DNS: ublock-allow
# writes Firefox's policies.json, and adds sites you allow later
sudo install -m 0755 @WREN_DIR@/bin/ublock-allow /usr/local/bin/ublock-allow
sudo /usr/local/bin/ublock-allow --mode medium
# The restart notice: a check every 10 minutes, as your user
install -D -m 0755 @WREN_DIR@/bin/firefox-restart-check ~/.local/bin/firefox-restart-check
mkdir -p ~/.config/systemd/user
printf '%s\n' '[Unit]' 'Description=Tell me when Firefox needs a restart after an update' \
    '[Service]' 'Type=oneshot' "ExecStart=$HOME/.local/bin/firefox-restart-check" \
    >~/.config/systemd/user/firefox-restart-check.service
printf '%s\n' '[Unit]' 'Description=Check every 10 minutes whether Firefox needs a restart' \
    '[Timer]' 'OnStartupSec=2min' 'OnUnitActiveSec=10min' '[Install]' 'WantedBy=timers.target' \
    >~/.config/systemd/user/firefox-restart-check.timer
systemctl --user daemon-reload
systemctl --user enable --now firefox-restart-check.timer

# --- incognito ---
# cage, acl, its own audio server and player, nftables, python3 for wayland-restrict
sudo apt install --no-install-recommends cage acl firefox-esr libavcodec61 pipewire-bin pipewire-pulse wireplumber nftables python3
# The incognito user, and wifi-signin for the Wi-Fi sign-in window: system
# users with no home, no password and no login; render lets cage open the
# graphics card's render node (not the screen)
sudo useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin --comment "Wren Linux incognito Firefox" incognito
sudo useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin --comment "Wren Linux Wi-Fi sign-in window" wifi-signin
for u in incognito wifi-signin; do
    sudo usermod --lock --shell /usr/sbin/nologin "$u"
    sudo usermod -aG render "$u"
done
# The restricted Wayland socket, the no-abstract-sockets wrapper, the command,
# its session script and its prefs
install -D -m 0755 @WREN_DIR@/bin/wayland-restrict ~/.local/bin/wayland-restrict
sudo install -d -o root -g root -m 0755 /usr/local/share/wren /usr/local/libexec
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/no-abstract-sockets /usr/local/libexec/wren-no-abstract-sockets
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/incognito /usr/local/bin/incognito
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/wifi-signin /usr/local/bin/wifi-signin
sudo install -o root -g root -m 0755 @WREN_DIR@/bin/incognito-session /usr/local/libexec/incognito-session
sudo install -o root -g root -m 0644 @WREN_DIR@/data/incognito-user.js /usr/local/share/wren/incognito-user.js
# Your user may run the session script, and nothing else, as incognito or
# wifi-signin. visudo checks the rule first: never put a rule in
# /etc/sudoers.d it hasn't passed.
printf '%s ALL=(incognito, wifi-signin) NOPASSWD: /usr/local/libexec/incognito-session\n' "$(id -un)" >/tmp/wren-incognito
sudo visudo -cf /tmp/wren-incognito
sudo install -o root -g root -m 0440 /tmp/wren-incognito /etc/sudoers.d/wren-incognito
rm /tmp/wren-incognito
# A limit on its processes, and no core dumps
printf '%s\n' 'incognito hard nproc 4096' 'incognito hard core 0' 'wifi-signin hard nproc 4096' 'wifi-signin hard core 0' |
    sudo tee /etc/security/limits.d/50-wren-incognito.conf
# The firewall rules: incognito the internet only, not this computer or your
# network; wifi-signin the internet and your network, not this computer
sudo install -D -o root -g root -m 0644 @WREN_DIR@/data/incognito-firewall.nft /etc/wren/incognito.nft
sudo install -D -o root -g root -m 0644 @WREN_DIR@/data/wifi-signin-firewall.nft /etc/wren/wifi-signin.nft
printf '%s\n' '[Unit]' 'Description=Keep the incognito user off the local network' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' 'ExecStart=/usr/sbin/nft -f /etc/wren/incognito.nft' \
    'ExecStart=/usr/sbin/nft -f /etc/wren/wifi-signin.nft' \
    'ExecStop=/usr/sbin/nft delete table inet wren_incognito' \
    'ExecStop=-/usr/sbin/nft delete table inet wren_wifi_signin' '' '[Install]' 'WantedBy=multi-user.target' |
    sudo tee /etc/systemd/system/wren-incognito-firewall.service
sudo systemctl daemon-reload
sudo systemctl enable --now wren-incognito-firewall.service
incognito
```

To undo:

```
# --- incognito ---
sudo systemctl disable --now wren-incognito-firewall.service
sudo rm /etc/systemd/system/wren-incognito-firewall.service /etc/wren/incognito.nft /etc/wren/wifi-signin.nft
sudo systemctl daemon-reload
sudo rm /etc/sudoers.d/wren-incognito /etc/security/limits.d/50-wren-incognito.conf
sudo rm /usr/local/bin/incognito /usr/local/bin/wifi-signin /usr/local/libexec/incognito-session /usr/local/share/wren/incognito-user.js
for u in incognito wifi-signin; do sudo pkill -KILL -u "$u"; sudo userdel "$u"; done
# (wayland-restrict only if the media extra and the PDF viewer don't use it;
# no-abstract-sockets only if no other sandbox does)
rm ~/.local/bin/wayland-restrict
sudo rm /usr/local/libexec/wren-no-abstract-sockets
sudo apt purge cage
# --- the hardening ---
systemctl --user disable --now firefox-restart-check.timer
rm ~/.config/systemd/user/firefox-restart-check.service ~/.config/systemd/user/firefox-restart-check.timer ~/.local/bin/firefox-restart-check
sudo rm /etc/firefox-esr/wren-hardening.js /usr/local/bin/ublock-allow
sudo rm /usr/share/firefox-esr/distribution/policies.json /etc/firefox-esr/wren-ublock-allow
# The shared packages, marked "automatic": autoremove takes them out only if nothing needs them
sudo apt-mark auto acl nftables pipewire-bin pipewire-pulse wireplumber libnotify-bin
sudo apt autoremove --purge
```
