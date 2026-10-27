#!/bin/bash
# Firefox hardening, for every profile:
#  - uBlock Origin (from Debian) in "medium mode": scripts and frames from
#    other sites are blocked everywhere. That's where most malicious ads
#    and drive-by attacks come from. Allow a site that breaks with:
#    ublock-allow example.com
#  - The JavaScript JIT is off. Most serious Firefox exploits target it.
#    JavaScript still works, a bit slower; heavy web apps may lag. A
#    profile can turn it back on (firefox-profiles/new-profile.sh asks).
#  - HTTPS-Only Mode: Firefox won't load unencrypted pages without asking,
#    so nobody on café or hotel Wi-Fi can tamper with them.
#  - A notice when Firefox was updated while it's running: the running
#    browser keeps the old, unfixed version until you restart it.
# These are defaults: change one in a profile at about:config.
# Usage: bash firefox-hardening.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

# Debian's Firefox reads default prefs from /etc/firefox-esr/*.js and
# policies from /etc/firefox-esr/policies/policies.json
ETC=/etc/firefox-esr
PREFS="$ETC/debsway-hardening.js"
ALLOW=/usr/local/bin/ublock-allow
CHECK="$HOME/.local/bin/firefox-restart-check"
UNITS="$HOME/.config/systemd/user"

if [ "${1:-}" = --remove ]; then
    systemctl --user disable --now firefox-restart-check.timer >/dev/null 2>&1 || true
    rm -f "$UNITS/firefox-restart-check.service" "$UNITS/firefox-restart-check.timer"
    if grep -qs 'written by debsway' "$CHECK"; then rm -f "$CHECK"; fi
    if [ -f "$ETC/policies/.debsway-written" ] && sha256sum --status -c "$ETC/policies/.debsway-written"; then
        sudo rm -f "$ETC/policies/policies.json" "$ETC/policies/.debsway-written"
        sudo rmdir "$ETC/policies" 2>/dev/null || true
    fi
    sudo rm -f "$PREFS" "$ETC/debsway-ublock-allow" "$ALLOW"
    note "Firefox is back to its own defaults after a restart. uBlock Origin stays installed."
    exit
fi

say "Firefox hardening"
apt_install firefox-esr webext-ublock-origin-firefox libnotify-bin

printf '%s\n' \
    '// Written by debsway parts/firefox-hardening.sh. Defaults for every' \
    '// profile; a profile can change them at about:config.' \
    '' \
    '// HTTPS-Only Mode: no unencrypted pages without asking first' \
    'pref("dom.security.https_only_mode", true);' \
    '' \
    '// JavaScript JIT off: slower JavaScript, much less to attack' \
    'pref("javascript.options.ion", false);' \
    'pref("javascript.options.baselinejit", false);' \
    'pref("javascript.options.native_regexp", false);' \
    'pref("javascript.options.asmjs", false);' | sudo tee "$PREFS" >/dev/null
note "HTTPS-Only Mode on, JavaScript JIT off ($PREFS)"

sudo install -m 0755 "$DEBSWAY_DIR/config/ublock-allow" "$ALLOW"
if sudo "$ALLOW" --refresh; then
    note "uBlock Origin blocks other sites' scripts and frames. When a site breaks:"
    note "  ublock-allow example.com   (then restart Firefox; ublock-allow --list shows them)"
else
    warn "uBlock Origin's medium mode isn't set; see above."
fi

say "Firefox update notice"
mkdir -p "$(dirname -- "$CHECK")" "$UNITS"
cat >"$CHECK" <<'EOF'
#!/bin/sh
# firefox-restart-check: written by debsway parts/firefox-hardening.sh.
# Says so when Firefox was updated while running. The running browser
# keeps the old, unfixed version until it's restarted.
notified=${XDG_RUNTIME_DIR:-/tmp}/firefox-restart-notified
for pid in $(pgrep -u "$(id -u)" -x firefox-esr); do
    exe=$(readlink "/proc/$pid/exe") || continue
    case $exe in *" (deleted)") ;; *) continue ;; esac
    grep -qx "$pid" "$notified" 2>/dev/null && continue
    notify-send -u critical "Firefox was updated" \
        "Restart Firefox (close it, open it again) to use the fixed version." &&
        echo "$pid" >>"$notified"
done
EOF
chmod +x "$CHECK"
cat >"$UNITS/firefox-restart-check.service" <<EOF
[Unit]
Description=Tell me when Firefox needs a restart after an update (debsway)

[Service]
Type=oneshot
ExecStart=$CHECK
EOF
cat >"$UNITS/firefox-restart-check.timer" <<'EOF'
[Unit]
Description=Check every 10 minutes whether Firefox needs a restart (debsway)

[Timer]
OnStartupSec=2min
OnUnitActiveSec=10min

[Install]
WantedBy=timers.target
EOF
if systemctl --user daemon-reload 2>/dev/null &&
    systemctl --user enable --now firefox-restart-check.timer >/dev/null 2>&1; then
    note "Checks every 10 minutes and shows a notification when Firefox needs a restart."
else
    warn "Couldn't start the check now; it starts with your next login."
    systemctl --user enable firefox-restart-check.timer >/dev/null 2>&1 || true
fi
note "Restart Firefox for all of this to take effect."
