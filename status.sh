#!/bin/bash
# Shows what Wren Linux has set up on this machine.
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
. "$WREN_DIR/packages.sh"
. "$WREN_DIR/lib/secure-dns.sh"
. "$WREN_DIR/lib/apt-keys.sh"

show() {
    if is_installed "$1"; then printf '  [x] %s\n' "$1"; else printf '  [ ] %s\n' "$1"; fi
}

# Encrypted if any layer under the device is dm-crypt (LUKS)
on_crypt() { lsblk -s -no TYPE "$1" 2>/dev/null | grep -qx crypt; }

# Security at a glance: the few things that matter most, each checked here,
# with what to run when one isn't done. [x] yes, [~] partly, [ ] no. The
# details follow below. (WREN_ETC and WREN_FX_CLIENT: where /etc and
# the firefox command are, for tests.)
glance() { printf '  [%s] %s\n' "$1" "$2"; }
ETC=${WREN_ETC:-/etc}
FX=${WREN_FX_CLIENT:-/usr/local/bin/firefox}
echo "Security at a glance:"
root_src=$(findmnt -no SOURCE / 2>/dev/null | sed 's/\[.*//')
if [ -n "$root_src" ] && on_crypt "$root_src"; then
    glance x "Disk encrypted: without your passphrase nobody can read it"
else
    glance " " "Disk NOT encrypted: anyone with the computer can read your files (reinstall with encrypted LVM)"
fi
if ! command -v swaylock >/dev/null; then
    glance " " "No screen lock: bash parts/swaylock.sh"
elif [ -f "$SWAY_SNIPPETS/idle.conf" ]; then
    glance x "Screen locks by itself when you're away (Super+Escape locks it now)"
else
    glance "~" "Screen locks only when you lock it (Super+Escape): bash parts/swayidle.sh locks it when idle"
fi
# (ufw's service is a one-shot that stays "active" after ufw disable: its setting says)
if systemctl is-active --quiet ufw 2>/dev/null && grep -qsx 'ENABLED=yes' "$ETC/ufw/ufw.conf"; then
    glance x "Firewall on: nothing from outside can connect in"
else
    glance " " "Firewall off: bash parts/ufw.sh"
fi
# The sandboxes' own firewalls, really loaded: a "flush ruleset" (Debian's own
# nftables service does one) takes them away and leaves their services "active".
# Each sandbox then refuses to start (bin/sandbox-net-check); this says which.
# Only root can list them: with sudo already unlocked (sudo -n), never asking.
fw_tables=()
for u in "$ETC"/systemd/system/wren-*-firewall.service; do
    [ -f "$u" ] && systemctl is-enabled --quiet "${u##*/}" 2>/dev/null || continue
    while read -r f; do
        t=$(sed -n 's/^table inet \([a-z_]*\) {$/\1/p' "$f" 2>/dev/null | head -1)
        [ -n "$t" ] && fw_tables+=("$t:${u##*/}")
    done < <(sed -n 's|^ExecStart=/usr/sbin/nft -f ||p' "$u")
done
if [ ${#fw_tables[@]} -gt 0 ]; then
    if loaded=$(sudo -n nft list tables 2>/dev/null); then
        gone=()
        for e in "${fw_tables[@]}"; do
            grep -qx "table inet ${e%%:*}" <<<"$loaded" || gone+=("${e#*:}")
        done
        if [ ${#gone[@]} -eq 0 ]; then
            glance x "The sandboxes' firewalls are loaded (${#fw_tables[@]})"
        else
            glance " " "Sandbox firewall NOT loaded, so that sandbox won't start: sudo systemctl restart $(printf '%s\n' "${gone[@]}" | sort -u | paste -sd' ')"
        fi
    else
        glance "~" "The sandboxes' firewalls weren't checked (that needs sudo): sudo -v; bash status.sh"
    fi
    if systemctl is-enabled --quiet nftables.service 2>/dev/null; then
        glance "~" "Debian's nftables service is on: its \"flush ruleset\" can take the sandboxes' firewalls away (sudo systemctl disable nftables)"
    fi
fi
if is_installed unattended-upgrades && grep -qs 'Unattended-Upgrade "1"' "$ETC/apt/apt.conf.d/20auto-upgrades"; then
    glance x "Security updates install by themselves"
else
    glance " " "Security updates don't install by themselves: bash parts/unattended-upgrades.sh"
fi
if [ -x "$FX" ] && [ "$(sed -n 's|^x-scheme-handler/https=||p' "$HOME/.config/mimeapps.list" 2>/dev/null | head -1)" = wren-firefox.desktop ]; then
    glance x "Web links open in the sandboxed Firefox"
elif [ -x "$FX" ]; then
    glance "~" "The sandboxed Firefox is there, but links open in another browser: bash extras/firefox-sandbox.sh"
else
    glance " " "No sandboxed browser: bash extras/firefox-sandbox.sh"
fi
if secure_dns_on; then
    glance x "DNS encrypted, for every program"
elif [ -x "$FX" ]; then
    # (Wren Linux's Firefox encrypts its own while secure DNS is off: bin/firefox-session)
    if secure_dns_installed; then
        glance "~" "Secure DNS switched off: Firefox encrypts its own, other programs don't (Wren menu: Secure DNS)"
    else
        glance "~" "DNS encrypted for Firefox only: bash parts/secure-dns.sh, for every program"
    fi
else
    glance " " "DNS not encrypted: your network sees which sites you look up (bash parts/secure-dns.sh)"
fi
echo

echo "Disk encryption:"
plain=()
for m in / /home; do
    src=$(findmnt -no SOURCE "$m" 2>/dev/null | sed 's/\[.*//') || continue
    [ -n "$src" ] || continue
    [ "$m" = / ] || [ "$src" != "$(findmnt -no SOURCE / | sed 's/\[.*//')" ] || continue
    if on_crypt "$src"; then printf '  [x] %s\n' "$m"; else printf '  [ ] %s (%s)\n' "$m" "$src"; plain+=("$m"); fi
done
while read -r name type; do
    case $name in /dev/zram*) continue ;; esac
    dev=$name
    [ "$type" = file ] && dev=$(findmnt -no SOURCE -T "$name" | sed 's/\[.*//')
    if on_crypt "$dev"; then printf '  [x] swap %s\n' "$name"; else printf '  [ ] swap %s\n' "$name"; plain+=("swap"); fi
done < <(swapon --show=NAME,TYPE --noheadings 2>/dev/null)
if [ ${#plain[@]} -gt 0 ]; then
    warn "Not encrypted: ${plain[*]}. Anyone with the laptop can read your files,"
    warn "wallets and passwords. Reinstall with encrypted LVM (see README, Installing Debian)."
fi

echo "Base packages:"
for p in "${PKGS[@]}"; do show "$p"; done

# status_of SCRIPT: "[x] name (what)" from the script's "# status:" line
status_of() {
    local name have=()
    name=$(basename -- "$1" .sh)
    mapfile -t have < <(script_found "$1")
    if [ ${#have[@]} -eq 1 ] && [ "${have[0]}" = "$name" ]; then
        printf '  [x] %s\n' "$name"
    elif [ ${#have[@]} -gt 0 ]; then
        printf '  [x] %s (%s)\n' "$name" "$(IFS=,; echo "${have[*]}" | sed 's/,/, /g')"
    else
        printf '  [ ] %s\n' "$name"
    fi
}

echo "Parts (parts/):"
for part in "${PARTS[@]}"; do status_of "$WREN_DIR/parts/$part.sh"; done

echo "Extras (optional, extras/):"
for f in "$WREN_DIR"/extras/*.sh; do status_of "$f"; done
for f in "$OFFLINE_DIR"/torbrowser/tor-browser-linux-*.tar.xz "$OFFLINE_DIR"/whonix/Whonix-*.libvirt.xz; do
    [ -f "$f" ] && printf '      saved: %s\n' "${f#"$WREN_DIR"/}"
done

echo "Packages Wren Linux installed (one marker per script; apt purge wren-NAME removes it):"
# (dpkg-query fails when no package matches, as on a fresh install)
markers=$({ dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 'wren-*' 2>/dev/null || true; } | awk '$1 == "ii" { print $2 }')
if [ -n "$markers" ]; then
    for m in $markers; do
        printf '  %s: %s\n' "${m#wren-}" "$(marker_depends "$m" | paste -sd' ')"
    done
else
    echo "  (none recorded yet)"
fi

echo "Firefox (extras/firefox-sandbox.sh):"
if [ -x /usr/local/bin/incognito ]; then
    echo "  [x] incognito command (throwaway Firefox as the locked-down user)"
else
    echo "  [ ] incognito command (throwaway Firefox as the locked-down user)"
fi
if [ -f /etc/firefox-esr/wren-hardening.js ]; then
    echo "  [x] HTTPS-Only Mode, JavaScript JIT off"
else
    echo "  [ ] HTTPS-Only Mode, JavaScript JIT off"
fi
FX_ETC=${WREN_FIREFOX_ETC:-/etc/firefox-esr}
if [ -f "${WREN_FIREFOX_DIST:-/usr/share/firefox-esr/distribution}/.wren-written" ]; then
    # (no file: medium, as Wren Linux was before the choice)
    mode=$(cat "$FX_ETC/wren-ublock-mode" 2>/dev/null || true)
    if [ "$mode" = standard ]; then
        echo "  [x] uBlock Origin standard mode (ublock-allow --mode medium also blocks other sites' scripts)"
    else
        n=$(grep -cv '^#' "$FX_ETC/wren-ublock-allow" 2>/dev/null || true)
        echo "  [x] uBlock Origin medium mode (${n:-0} sites allowed: ublock-allow --list)"
    fi
else
    echo "  [ ] uBlock Origin"
fi
if systemctl --user is-enabled --quiet firefox-restart-check.timer 2>/dev/null; then
    echo "  [x] notice when Firefox needs a restart after an update"
else
    echo "  [ ] notice when Firefox needs a restart after an update"
fi

echo "Firefox profile commands (extras/firefox-profiles/new-profile.sh):"
found=false
for c in "$HOME"/.local/bin/firefox-*; do
    if grep -qsE 'Wren Linux (extras/)?firefox-profiles/' "$c"; then
        printf '  %s\n' "${c##*/}"
        found=true
    fi
done
$found || echo "  (none)"

echo "Screen lock:"
# Without swaylock nothing locks, whatever the idle settings say
if ! command -v swaylock >/dev/null; then
    echo "  NONE: swaylock isn't installed, so the screen never locks (put it back: bash parts/swaylock.sh)"
elif [ -x "$HOME/.local/bin/wren-idle" ] && [ -f "$SWAY_SNIPPETS/idle.conf" ]; then
    echo "  screen off after $("$HOME/.local/bin/wren-idle" --minutes) minutes idle, locked a minute later (change it: timer lock MINUTES)"
elif [ -f "$SWAY_SNIPPETS/idle.conf" ]; then
    echo "  after 5 minutes idle (to change it with timer lock: bash parts/swayidle.sh again)"
else
    echo "  only when you lock it (bash parts/swayidle.sh locks it after 30 minutes idle)"
fi

echo "Theme:"
if [ -x "$HOME/.local/bin/theme" ]; then
    "$HOME/.local/bin/theme" | sed 's/^Theme: /  /; s/$/ (switch: theme light, theme dark, or the Wren menu)/'
else
    echo "  dark (bash parts/theme.sh: theme light or dark)"
fi

echo "Wallpaper:"
if [ -x "$HOME/.local/bin/wallpaper" ]; then
    "$HOME/.local/bin/wallpaper" status | sed 's/^Wallpaper: //; s/^/  /'
else
    echo "  sway's own setting (bash parts/wallpaper.sh: your picture from ~/Pictures/wren/desktop)"
fi

echo "sway snippets in $SWAY_SNIPPETS:"
shopt -s nullglob
snippets=("$SWAY_SNIPPETS"/*.conf)
if [ ${#snippets[@]} -gt 0 ]; then printf '  %s\n' "${snippets[@]##*/}"; else echo "  (none)"; fi

echo "Network:"
for ifc in $(wifi_ifaces); do
    how="not set up"
    if systemctl is-active --quiet NetworkManager &&
        nmcli -t -f DEVICE,STATE device 2>/dev/null | grep -q "^$ifc:connected"; then
        how="NetworkManager"
    elif [ -f "/etc/network/interfaces.d/wren-wifi-$ifc" ]; then
        how="ifupdown + wpa_supplicant (wifi.sh)"
    elif systemctl is-enabled --quiet "wpa_supplicant@$ifc.service" 2>/dev/null; then
        how="wpa_supplicant@$ifc + systemd-networkd (wifi.sh)"
    elif grep -qs "iface $ifc" /etc/network/interfaces; then
        how="ifupdown (Debian installer)"
    fi
    printf '  %s: %s\n' "$ifc" "$how"
done
if [ -e /etc/tor/.wren-apt-tor ]; then
    echo "  apt downloads through Tor (parts/apt-tor.sh)"
else
    echo "  apt downloads directly"
fi
echo "  $(dns_status)"
if [ -n "$(apt_keys_installed)" ]; then
    echo "Signing keys of added apt repositories:"
    apt_keys_status
fi
if [ -f /etc/NetworkManager/conf.d/90-wren-random-mac.conf ]; then
    echo "  random Wi-Fi MAC address: on"
else
    echo "  random Wi-Fi MAC address: off"
fi
if have_internet; then echo "  online"; else echo "  offline"; fi
