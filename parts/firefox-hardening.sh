#!/bin/bash
# Firefox hardening, for every profile:
#  - uBlock Origin (from Debian) in "medium mode": scripts and frames from
#    other sites are blocked everywhere. That's where most malicious ads
#    and drive-by attacks come from. Allow a site that breaks with:
#    ublock-allow example.com
#  - The JavaScript JIT is off. Most serious Firefox exploits target it.
#    JavaScript still works, a bit slower; heavy web apps may lag. A
#    profile can turn it back on (extras/firefox-profiles/new-profile.sh asks).
#  - HTTPS-Only Mode: Firefox won't load unencrypted pages without asking,
#    so nobody on café or hotel Wi-Fi can tamper with them.
#  - A notice when Firefox was updated while it's running: the running
#    browser keeps the old, unfixed version until you restart it.
# These are defaults: change one in a profile at about:config.
# Usage: bash firefox-hardening.sh [--remove]
# status: file:/etc/firefox-esr/debsway-hardening.js
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

# Debian's Firefox reads default prefs from /etc/firefox-esr/*.js and
# policies from /etc/firefox-esr/policies/policies.json
ETC=/etc/firefox-esr
PREFS="$ETC/debsway-hardening.js"
ALLOW=/usr/local/bin/ublock-allow
UNITS="$HOME/.config/systemd/user"

if [ "${1:-}" = --remove ]; then
    systemctl --user disable --now firefox-restart-check.timer >/dev/null 2>&1 || true
    rm -f "$UNITS/firefox-restart-check.service" "$UNITS/firefox-restart-check.timer"
    remove_bin firefox-restart-check
    if [ -f "$ETC/policies/.debsway-written" ] && sha256sum --status -c "$ETC/policies/.debsway-written"; then
        sudo rm -f "$ETC/policies/policies.json" "$ETC/policies/.debsway-written"
        sudo rmdir "$ETC/policies" 2>/dev/null || true
    fi
    sudo rm -f "$PREFS" "$ETC/debsway-ublock-allow" "$ALLOW"
    # Firefox and uBlock Origin are part of the core (install-base.sh), so they stay
    apt_purge
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
    'pref("javascript.options.asmjs", false);' \
    '' \
    '// Open straight to the home page: no Mozilla welcome, first-run or' \
    '// whats-new tabs, and no "make Firefox your default browser" nag.' \
    'pref("browser.aboutwelcome.enabled", false);' \
    'pref("browser.startup.homepage_override.mstone", "ignore");' \
    'pref("browser.shell.checkDefaultBrowser", false);' \
    'pref("datareporting.policy.firstRunURL", "");' \
    '' \
    '// A blank Firefox Home / New Tab: no shortcuts, sponsored tiles,' \
    '// stories, highlights, weather or the centre search box (the address' \
    '// bar searches, with DuckDuckGo as the default from policies.json).' \
    'pref("browser.newtabpage.activity-stream.feeds.topsites", false);' \
    'pref("browser.newtabpage.activity-stream.showSponsoredTopSites", false);' \
    'pref("browser.newtabpage.activity-stream.feeds.section.topstories", false);' \
    'pref("browser.newtabpage.activity-stream.showSponsored", false);' \
    'pref("browser.newtabpage.activity-stream.feeds.section.highlights", false);' \
    'pref("browser.newtabpage.activity-stream.showWeather", false);' \
    'pref("browser.newtabpage.activity-stream.showSearch", false);' \
    '' \
    '// ...with the fox wallpaper you use (Firefox 128+ New Tab wallpapers).' \
    'pref("browser.newtabpage.activity-stream.newtabWallpapers.enabled", true);' \
    'pref("browser.newtabpage.activity-stream.newtabWallpapers.v2.enabled", true);' \
    'pref("browser.newtabpage.activity-stream.newtabWallpapers.wallpaper", "dark-fox-anniversary");' | sudo tee "$PREFS" >/dev/null
note "HTTPS-Only Mode on, JavaScript JIT off, blank foxy home page ($PREFS)"

sudo install -m 0755 "$DEBSWAY_DIR/bin/ublock-allow" "$ALLOW"
if sudo "$ALLOW" --refresh; then
    note "uBlock Origin blocks other sites' scripts and frames. When a site breaks:"
    note "  ublock-allow example.com   (then restart Firefox; ublock-allow --list shows them)"
else
    warn "uBlock Origin's medium mode isn't set; see above."
fi

say "Firefox update notice"
mkdir -p "$UNITS"
install_bin firefox-restart-check
cat >"$UNITS/firefox-restart-check.service" <<EOF
[Unit]
Description=Tell me when Firefox needs a restart after an update (debsway)

[Service]
Type=oneshot
ExecStart=$BIN/firefox-restart-check
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
