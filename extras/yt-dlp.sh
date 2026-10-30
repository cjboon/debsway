#!/bin/bash
# yt-dlp, the video downloader, run as its own locked-down user ("ytdlp") that
# has no password, no login and none of your files. The yt-dlp command works
# as usual (yt-dlp URL); what it downloads lands in ~/Downloads.
#  - yt-dlp is the official release (the zipimport file, run by Python),
#    checked against its signing key (pinned in pins.sh) and installed as
#    root's file: ytdlp can run it but not change it, so it can't update or
#    alter itself. Running this script again updates it, checked the same way.
#  - YouTube's own JavaScript (which yt-dlp has to run) runs in Debian's
#    QuickJS, and the video and sound are joined by Debian's ffmpeg, all as
#    ytdlp.
#  - Files go one way: yt-dlp writes into a folder of its own for each run, and
#    the yt-dlp command copies them into ~/Downloads as you afterwards. ytdlp
#    never gets into your home.
#  - A firewall rule keeps ytdlp off your router, printers and this computer's
#    own services (data/yt-dlp-firewall.nft). DNS stays open.
#  - Your user may run exactly one thing as ytdlp (a rule in /etc/sudoers.d).
#  - yt-dlp's config files are ignored, so a run can't leave settings behind
#    for the next one: give options on the command line.
# Usage: bash yt-dlp.sh [--remove]   (run it again to update yt-dlp)
# summary: yt-dlp video downloader, as its own locked user
# status: file:/usr/local/bin/yt-dlp
# files: bin/yt-dlp bin/yt-dlp-session data/yt-dlp-firewall.nft
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$DEBSWAY_DIR/lib/appimage.sh"
need_user

NAME=ytdlp
HOME_DIR=/var/lib/debsway-ytdlp
OUT=/var/lib/debsway-ytdlp-out
LIBDIR=/usr/local/lib/debsway/yt-dlp
CMD=/usr/local/bin/yt-dlp
SESSION=/usr/local/libexec/yt-dlp-session
SUDOERS=/etc/sudoers.d/debsway-$NAME
LIMITS=/etc/security/limits.d/50-debsway-ytdlp.conf
FIREWALL=/etc/debsway/yt-dlp.nft
UNIT=/etc/systemd/system/debsway-ytdlp-firewall.service
REPO=yt-dlp/yt-dlp

if [ "${1:-}" = --remove ]; then
    sudo systemctl disable --now debsway-ytdlp-firewall.service >/dev/null 2>&1 || true
    sudo nft delete table inet debsway_ytdlp 2>/dev/null || true
    sudo rm -f "$SUDOERS" "$LIMITS" "$CMD" "$SESSION" "$FIREWALL" "$UNIT"
    sudo rm -rf "$LIBDIR" "$OUT"
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo rmdir /usr/local/lib/debsway /usr/local/libexec /etc/debsway 2>/dev/null || true
    if id "$NAME" >/dev/null 2>&1; then
        sudo pkill -KILL -u "$NAME" 2>/dev/null || true
        sudo userdel "$NAME"
        note "Removed the user $NAME."
    fi
    if getent group "$NAME" >/dev/null; then sudo groupdel "$NAME" 2>/dev/null || true; fi
    # Only yt-dlp's cache is in its home
    sudo rm -rf "$HOME_DIR"
    # what this script installed and nothing else needs (python3 was there before)
    apt_purge
    note "Your downloads in ~/Downloads are yours and stay."
    exit
fi

say "What yt-dlp needs"
# python3 runs yt-dlp, qjs (quickjs) YouTube's JavaScript, ffmpeg joins video
# and sound; nftables: the firewall rule
apt_install python3 quickjs ffmpeg nftables
if is_installed yt-dlp; then
    note "Debian's own yt-dlp package is installed too (/usr/bin/yt-dlp, run as you, and"
    note "too old to keep working). The yt-dlp command finds debsway's first."
fi

say "The newest yt-dlp, checked"
tag=$(latest_github_tag "$REPO")
[ -n "$tag" ] || die "Couldn't find yt-dlp's newest release on GitHub. Nothing was changed."
have=$(cat "$LIBDIR/VERSION" 2>/dev/null || true)
if [ "$have" = "$tag" ] && [ -f "$LIBDIR/yt-dlp" ]; then
    note "yt-dlp $tag is installed, the newest."
else
    tmp=$(mktemp -d)
    base=https://github.com/$REPO/releases/download/$tag
    for f in SHA2-256SUMS SHA2-256SUMS.sig yt-dlp; do
        wget -q -O "$tmp/$f" "$base/$f" || { rm -rf "$tmp"; die "Couldn't download $f of yt-dlp $tag. Nothing was changed."; }
    done
    if ! verify_detached "$YTDLP_FPR" "$YTDLP_KEY_URL" "$tmp/SHA2-256SUMS.sig" "$tmp/SHA2-256SUMS"; then
        rm -rf "$tmp"
        die "yt-dlp $tag's list of checksums isn't signed by yt-dlp's signing key. Nothing was installed."
    fi
    want=$(awk '$2 == "yt-dlp" { print $1; exit }' "$tmp/SHA2-256SUMS")
    if ! [[ $want =~ ^[0-9a-f]{64}$ ]] || ! echo "$want  $tmp/yt-dlp" | sha256sum -c --quiet - >/dev/null 2>&1; then
        rm -rf "$tmp"
        die "The yt-dlp file doesn't have the checksum in the signed list. Nothing was installed."
    fi
    sudo install -d -o root -g root -m 0755 "$LIBDIR"
    sudo install -o root -g root -m 0755 "$tmp/yt-dlp" "$LIBDIR/yt-dlp"
    echo "$tag" | sudo tee "$LIBDIR/VERSION" >/dev/null
    rm -rf "$tmp"
    note "yt-dlp $tag${have:+ (was $have)}: signed by yt-dlp's key, checksum matches."
fi

say "The $NAME user"
if id "$NAME" >/dev/null 2>&1; then
    [ "$(id -u "$NAME")" -lt 1000 ] ||
        die "A regular user account called $NAME already exists; this needs a system user. Rename or remove it first."
else
    sudo mkdir -p "${HOME_DIR%/*}"
    sudo useradd --system --user-group --create-home --home-dir "$HOME_DIR" \
        --shell /usr/sbin/nologin --comment "debsway sandboxed yt-dlp" "$NAME"
fi
sudo usermod --lock --shell /usr/sbin/nologin "$NAME"
sudo chmod 0700 "$HOME_DIR"
# Each run's folder is made in here: ytdlp writes, your group (only you) reads
# and deletes; nobody else gets in. The setgid bit gives what is made in it
# your group.
sudo install -d -o "$NAME" -g "$(id -gn)" -m 2770 "$OUT"
note "$NAME: no password, no login; home $HOME_DIR; downloads pass through $OUT."

say "The yt-dlp command"
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 "$DEBSWAY_DIR/bin/yt-dlp-session" "$SESSION"
sudo install -o root -g root -m 0755 "$DEBSWAY_DIR/bin/yt-dlp" "$CMD"

say "What your user may run as $NAME"
rule=$(mktemp)
printf '# Written by debsway extras/yt-dlp.sh. %s may run the yt-dlp session script,\n# and nothing else, as the user %s.\n%s ALL=(%s) NOPASSWD: %s\n' \
    "$(id -un)" "$NAME" "$(id -un)" "$NAME" "$SESSION" >"$rule"
if ! sudo visudo -cf "$rule" >/dev/null; then
    rm -f "$rule"
    die "The sudoers rule didn't pass visudo's check, so it wasn't installed."
fi
sudo install -o root -g root -m 0440 "$rule" "$SUDOERS"
rm -f "$rule"
note "Wrote $SUDOERS"
# A runaway run can't fill the machine with processes, or leave memory dumps
printf '# Written by debsway extras/yt-dlp.sh\n%s hard nproc 512\n%s hard core 0\n' "$NAME" "$NAME" |
    sudo tee "$LIMITS" >/dev/null

say "Keeping $NAME off your network"
sudo install -d -o root -g root -m 0755 "${FIREWALL%/*}"
sudo install -o root -g root -m 0644 "$DEBSWAY_DIR/data/yt-dlp-firewall.nft" "$FIREWALL"
# Loaded before the network comes up, at every boot
printf '%s\n' '# Written by debsway extras/yt-dlp.sh' '[Unit]' \
    'Description=Keep the ytdlp user off the local network (debsway)' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' \
    "ExecStart=/usr/sbin/nft -f $FIREWALL" \
    'ExecStop=/usr/sbin/nft delete table inet debsway_ytdlp' '' '[Install]' \
    'WantedBy=multi-user.target' | sudo tee "$UNIT" >/dev/null
sudo systemctl daemon-reload
# Restart, not just enable --now: a changed rule file is only loaded by a restart
sudo systemctl enable debsway-ytdlp-firewall.service >/dev/null &&
    sudo systemctl restart debsway-ytdlp-firewall.service ||
    warn "Couldn't load the firewall rule; check: systemctl status debsway-ytdlp-firewall"

note "Use it like yt-dlp:  yt-dlp URL   (yt-dlp -x URL: the sound only). Files land in ~/Downloads."
note "When a site stops working, update it: bash ~/debsway/extras/yt-dlp.sh"
note "Treat what it downloads as untrusted; mpv from the media extra plays it in a sandbox."
