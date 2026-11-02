# yt-dlp, as its own user (`extras/yt-dlp.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/yt-dlp.sh            install it, or update yt-dlp to the newest release
bash ~/debsway/extras/yt-dlp.sh --remove   remove it
bash ~/debsway/extras/yt-dlp.sh --manual   print the manual steps below

yt-dlp URL                      download a video into ~/Downloads
yt-dlp -x --audio-format mp3 URL     only the sound
yt-dlp -F URL / -f 22 URL       list the formats / pick one
```

yt-dlp downloads videos from YouTube and many other sites. Here it runs as
its own locked-down user, `ytdlp`, with no password, no login and none of
your files. It is the official release, checked against yt-dlp's signing
key, pinned in `pins.sh` (`YTDLP_FPR`), and installed as root's file, so
`ytdlp` can run it but not change or update it; running the script again
updates it, checked the same way. YouTube's own JavaScript, which yt-dlp has
to run, runs in Debian's QuickJS, and ffmpeg joins video and sound. Files go
one way: yt-dlp writes into a folder of its own for each run, and the
`yt-dlp` command (`bin/yt-dlp`) copies them into `~/Downloads` as you
afterwards. A firewall rule (`data/yt-dlp-firewall.nft`) keeps `ytdlp` off
your router, printers and this computer's services. yt-dlp's config files are
ignored, so give options on the command line.

## LIMITS

- The site sees your address; nothing here routes yt-dlp through Tor or a VPN.
- A downloaded file can be crafted against the player that opens it: open it with the sandboxed `mpv` (`extras/media.sh`).
- It shares your kernel: a kernel bug could let it out of its user.
- Sites change often; an old yt-dlp stops working: run the script again.

## MANUAL INSTALL

```
# Python runs yt-dlp, QuickJS YouTube's JavaScript, ffmpeg joins video and
# sound; nftables for the firewall rule; gpg to check the release
sudo apt install --no-install-recommends python3 quickjs ffmpeg nftables gpg

# The newest release: the tag in the "Location:" line (e.g. 2026.10.26)
wget --max-redirect=0 -S -O /dev/null https://github.com/yt-dlp/yt-dlp/releases/latest 2>&1 | grep -i location
TAG=2026.10.26
mkdir -p ~/yt-dlp-download && cd ~/yt-dlp-download
for f in SHA2-256SUMS SHA2-256SUMS.sig yt-dlp; do wget https://github.com/yt-dlp/yt-dlp/releases/download/$TAG/$f; done

# yt-dlp's signing key, in a keyring of its own. This must show the
# fingerprint @YTDLP_FPR@
mkdir -m 700 gpg
wget -O ytdlp.asc @YTDLP_KEY_URL@
gpg --homedir gpg --import ytdlp.asc
gpg --homedir gpg --fingerprint @YTDLP_FPR@
# The checksum list is signed by it: this must say "Good signature" with
# "Primary key fingerprint" @YTDLP_FPR@. Stop here if not.
gpg --homedir gpg --verify SHA2-256SUMS.sig SHA2-256SUMS
# The yt-dlp file is the one in the list: this must print "OK"
awk '$2 == "yt-dlp" { print $1 "  yt-dlp" }' SHA2-256SUMS | sha256sum -c

# It goes in as root's file, so the ytdlp user can run it but not change it
sudo install -d -o root -g root -m 0755 /usr/local/lib/debsway/yt-dlp
sudo install -o root -g root -m 0755 yt-dlp /usr/local/lib/debsway/yt-dlp/yt-dlp
echo "$TAG" | sudo tee /usr/local/lib/debsway/yt-dlp/VERSION
cd ~ && rm -rf ~/yt-dlp-download

# The ytdlp user: no password, no login shell, a home only it can enter
sudo useradd --system --user-group --create-home --home-dir /var/lib/debsway-ytdlp --shell /usr/sbin/nologin --comment "debsway sandboxed yt-dlp" ytdlp
sudo usermod --lock --shell /usr/sbin/nologin ytdlp
sudo chmod 0700 /var/lib/debsway-ytdlp
# The folder each run writes into: ytdlp writes, your group reads and deletes
sudo install -d -o ytdlp -g "$(id -gn)" -m 2770 /var/lib/debsway-ytdlp-out

# The command and its session script, as root's files
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 @DEBSWAY_DIR@/bin/yt-dlp-session /usr/local/libexec/yt-dlp-session
sudo install -o root -g root -m 0755 @DEBSWAY_DIR@/bin/yt-dlp /usr/local/bin/yt-dlp
# Your user may run the session script, and nothing else, as ytdlp. visudo
# checks the rule first: never put a rule in /etc/sudoers.d it hasn't passed.
printf '%s ALL=(ytdlp) NOPASSWD: /usr/local/libexec/yt-dlp-session\n' "$(id -un)" >/tmp/debsway-ytdlp
sudo visudo -cf /tmp/debsway-ytdlp
sudo install -o root -g root -m 0440 /tmp/debsway-ytdlp /etc/sudoers.d/debsway-ytdlp
rm /tmp/debsway-ytdlp
# A limit on its processes, and no core dumps
printf '%s\n' 'ytdlp hard nproc 512' 'ytdlp hard core 0' | sudo tee /etc/security/limits.d/50-debsway-ytdlp.conf

# The firewall rule, loaded at every boot before the network comes up
sudo install -D -o root -g root -m 0644 @DEBSWAY_DIR@/data/yt-dlp-firewall.nft /etc/debsway/yt-dlp.nft
printf '%s\n' '[Unit]' 'Description=Keep the ytdlp user off the local network' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' 'ExecStart=/usr/sbin/nft -f /etc/debsway/yt-dlp.nft' \
    'ExecStop=/usr/sbin/nft delete table inet debsway_ytdlp' '' '[Install]' 'WantedBy=multi-user.target' |
    sudo tee /etc/systemd/system/debsway-ytdlp-firewall.service
sudo systemctl daemon-reload
sudo systemctl enable --now debsway-ytdlp-firewall.service
yt-dlp --version
```

To undo:

```
# The firewall rule
sudo systemctl disable --now debsway-ytdlp-firewall.service
sudo rm /etc/systemd/system/debsway-ytdlp-firewall.service /etc/debsway/yt-dlp.nft
sudo systemctl daemon-reload
# The sudo rule, the limits, the command, its session script, yt-dlp and the run folder
sudo rm /etc/sudoers.d/debsway-ytdlp /etc/security/limits.d/50-debsway-ytdlp.conf
sudo rm /usr/local/bin/yt-dlp /usr/local/libexec/yt-dlp-session
sudo rm -rf /usr/local/lib/debsway/yt-dlp /var/lib/debsway-ytdlp-out
# The user and its home (only yt-dlp's cache is there)
sudo pkill -KILL -u ytdlp
sudo userdel ytdlp
sudo rm -rf /var/lib/debsway-ytdlp
# QuickJS and ffmpeg, marked "automatic": autoremove takes them out only if nothing needs them
sudo apt-mark auto quickjs ffmpeg nftables
sudo apt autoremove --purge
```
