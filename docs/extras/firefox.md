# Firefox's hardening, and incognito (part of `extras/firefox-sandbox.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/firefox-sandbox.sh            sets these up, with the sandboxed Firefox
bash ~/debsway/parts/firefox-hardening.sh           only the hardening; --remove takes it out
bash ~/debsway/parts/incognito.sh                   only incognito; --remove takes it out
bash ~/debsway/extras/firefox-sandbox.sh --manual   print the manual steps below, then the sandbox's

ublock-allow example.com      let a site that breaks run scripts and frames from other sites
incognito [URL]               a throwaway Firefox that keeps nothing (incognito --no-audio: no sound)
```

The sandboxed Firefox sets up Firefox ESR the debsway way for every profile
(`parts/firefox-hardening.sh`): uBlock Origin from Debian in medium mode, so
scripts and frames from other sites are blocked, which is where most malicious
ads come from; the JavaScript JIT off, which most serious Firefox exploits
target; HTTPS-Only Mode; Firefox's own DNS over HTTPS off; a blank New Tab;
and a notice when Firefox was updated while running and needs a restart. The
prefs are `data/firefox-hardening.js`, the policies come from
`bin/ublock-allow`. It also sets up `incognito` (`parts/incognito.sh`): a
throwaway Firefox in cage, a tiny compositor shown as one window, as a locked
user with no home, no files of yours, no shared clipboard and only a
restricted Wayland socket; its profile lives in memory and is deleted when the
window closes. Its sound goes through a pipe into a player of yours, so it
can't hear your microphone, and a firewall rule on that user
(`data/incognito-firewall.nft`) keeps it off your network.

## LIMITS

- uBlock's medium mode breaks some sites until you allow them; the JIT being off makes heavy sites slower.
- `incognito` is still your network and your address: use Tor Browser or a VPN for that.
- Any window, `incognito` included, can be captured by screenshots.
- Both share your kernel: a kernel bug could get out of them.

## MANUAL INSTALL

```
# --- Firefox's hardening ---
# Firefox ESR, uBlock Origin, and notifications for the restart notice
sudo apt install --no-install-recommends firefox-esr webext-ublock-origin-firefox libnotify-bin
# The default prefs for every profile (Firefox reads /etc/firefox-esr/*.js)
sudo install -m 0644 @DEBSWAY_DIR@/data/firefox-hardening.js /etc/firefox-esr/debsway-hardening.js
# uBlock Origin in medium mode, DNS over HTTPS off: ublock-allow writes
# Firefox's policies.json, and adds sites you allow later
sudo install -m 0755 @DEBSWAY_DIR@/bin/ublock-allow /usr/local/bin/ublock-allow
sudo /usr/local/bin/ublock-allow --refresh
# The restart notice: a check every 10 minutes, as your user
install -D -m 0755 @DEBSWAY_DIR@/bin/firefox-restart-check ~/.local/bin/firefox-restart-check
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
# The incognito user: a system user with no home, no password and no login;
# render lets cage open the graphics card's render node (not the screen)
sudo useradd --system --user-group --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin --comment "debsway incognito Firefox" incognito
sudo usermod --lock --shell /usr/sbin/nologin incognito
sudo usermod -aG render incognito
# The restricted Wayland socket, the no-abstract-sockets wrapper, the command,
# its session script and its prefs
install -D -m 0755 @DEBSWAY_DIR@/bin/wayland-restrict ~/.local/bin/wayland-restrict
sudo install -d -o root -g root -m 0755 /usr/local/share/debsway /usr/local/libexec
sudo install -o root -g root -m 0755 @DEBSWAY_DIR@/bin/no-abstract-sockets /usr/local/libexec/debsway-no-abstract-sockets
sudo install -o root -g root -m 0755 @DEBSWAY_DIR@/bin/incognito /usr/local/bin/incognito
sudo install -o root -g root -m 0755 @DEBSWAY_DIR@/bin/incognito-session /usr/local/libexec/incognito-session
sudo install -o root -g root -m 0644 @DEBSWAY_DIR@/data/incognito-user.js /usr/local/share/debsway/incognito-user.js
# Your user may run the session script, and nothing else, as incognito. visudo
# checks the rule first: never put a rule in /etc/sudoers.d it hasn't passed.
printf '%s ALL=(incognito) NOPASSWD: /usr/local/libexec/incognito-session\n' "$(id -un)" >/tmp/debsway-incognito
sudo visudo -cf /tmp/debsway-incognito
sudo install -o root -g root -m 0440 /tmp/debsway-incognito /etc/sudoers.d/debsway-incognito
rm /tmp/debsway-incognito
# A limit on its processes, and no core dumps
printf '%s\n' 'incognito hard nproc 4096' 'incognito hard core 0' | sudo tee /etc/security/limits.d/50-debsway-incognito.conf
# The firewall rule: the internet only, not this computer or your network
sudo install -D -o root -g root -m 0644 @DEBSWAY_DIR@/data/incognito-firewall.nft /etc/debsway/incognito.nft
printf '%s\n' '[Unit]' 'Description=Keep the incognito user off the local network' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' 'ExecStart=/usr/sbin/nft -f /etc/debsway/incognito.nft' \
    'ExecStop=/usr/sbin/nft delete table inet debsway_incognito' '' '[Install]' 'WantedBy=multi-user.target' |
    sudo tee /etc/systemd/system/debsway-incognito-firewall.service
sudo systemctl daemon-reload
sudo systemctl enable --now debsway-incognito-firewall.service
incognito
```

To undo:

```
# --- incognito ---
sudo systemctl disable --now debsway-incognito-firewall.service
sudo rm /etc/systemd/system/debsway-incognito-firewall.service /etc/debsway/incognito.nft
sudo systemctl daemon-reload
sudo rm /etc/sudoers.d/debsway-incognito /etc/security/limits.d/50-debsway-incognito.conf
sudo rm /usr/local/bin/incognito /usr/local/libexec/incognito-session /usr/local/share/debsway/incognito-user.js
sudo pkill -KILL -u incognito
sudo userdel incognito
# (wayland-restrict only if the media extra and the PDF viewer don't use it;
# no-abstract-sockets only if no other sandbox does)
rm ~/.local/bin/wayland-restrict
sudo rm /usr/local/libexec/debsway-no-abstract-sockets
sudo apt purge cage
# --- the hardening ---
systemctl --user disable --now firefox-restart-check.timer
rm ~/.config/systemd/user/firefox-restart-check.service ~/.config/systemd/user/firefox-restart-check.timer ~/.local/bin/firefox-restart-check
sudo rm /etc/firefox-esr/debsway-hardening.js /usr/local/bin/ublock-allow
sudo rm /usr/share/firefox-esr/distribution/policies.json /etc/firefox-esr/debsway-ublock-allow
# The shared packages, marked "automatic": autoremove takes them out only if nothing needs them
sudo apt-mark auto acl nftables pipewire-bin pipewire-pulse wireplumber libnotify-bin
sudo apt autoremove --purge
```
