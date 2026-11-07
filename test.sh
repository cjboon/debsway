#!/bin/bash
# test.sh: checks that Wren Linux still works. Its own scripts, and the
# outside things they depend on: Debian packages, download pages,
# signing keys, release signatures, and the Firefox and Debian features
# the hardening relies on. It installs and changes nothing; downloads
# are small (signatures and checksum lists) and go to a temporary folder.
# Run it now and then, and before you reinstall.
#
#   bash test.sh            everything (needs internet)
#   bash test.sh --offline  only what needs no internet
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
. "$WREN_DIR/lib/appimage.sh"
. "$WREN_DIR/lib/offline.sh"
. "$WREN_DIR/packages.sh"
# Keep going after a failure; every check reports for itself
set +e +o pipefail
# The tests run scripts with a pretend sudo; on a computer still set up as
# debsway (before the name), need_user would stop them (tools/test-location.sh
# checks that it does)
export WREN_ALLOW_OLD_INSTALL=1

OFFLINE=false
[ "${1:-}" = --offline ] && OFFLINE=true
# Room for the tests' temp folders (some write real disk images): with too little,
# they fail all over, for no fault of the scripts
free_mb=$(df -Pm "${TMPDIR:-/tmp}" 2>/dev/null | awk 'NR == 2 { print $4 }')
[ -z "$free_mb" ] || [ "$free_mb" -ge 500 ] ||
    die "Only $free_mb MB free in ${TMPDIR:-/tmp}; the tests need about 500. Free some, or run with TMPDIR=/var/tmp"
TMP=$(mktemp -d) || die "Couldn't make a temp folder in ${TMPDIR:-/tmp}."
trap 'rm -rf "$TMP"' EXIT
n_ok=0 n_warn=0 n_fail=0
ok() { printf '  \033[32mok\033[0m    %s\n' "$*"; n_ok=$((n_ok + 1)); }
meh() { printf '  \033[33mWARN\033[0m  %s\n' "$*"; n_warn=$((n_warn + 1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; n_fail=$((n_fail + 1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$*"; }
online() { ! $OFFLINE; }
# The tests of each piece (tools/test-NAME.sh) are in a git copy, not the package's
# (wrenctl install wren-dev gets one); without them, the checks below still run
dev_test() { # NAME SECTION LABEL
    [ -f "tools/test-$1.sh" ] || return 0
    section "$2"
    if out=$(bash "tools/test-$1.sh" 2>&1); then
        ok "$(grep -c '^  ok' <<<"$out") $3"
    else
        bad "$3: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
    fi
}

cd "$WREN_DIR" || exit 1
mapfile -t SCRIPTS < <(find . -path ./.git -prune -o -path ./ignore -prune -o -path ./offline -prune -o \
    \( -name '*.sh' -o -path './bin/*' \) -type f -print | sort)

# --------------------------------------------------------------------
section "Scripts"
bad_syntax=0
for f in "${SCRIPTS[@]}"; do
    bash -n "$f" 2>"$TMP/err" || { bad "syntax error in $f: $(head -1 "$TMP/err")"; bad_syntax=1; }
done
[ $bad_syntax -eq 1 ] || ok "${#SCRIPTS[@]} scripts parse"
if command -v shellcheck >/dev/null; then
    if shellcheck "${SCRIPTS[@]}" >"$TMP/sc" 2>&1; then
        ok "shellcheck finds nothing"
    else
        bad "shellcheck: $(grep -c '^In ' "$TMP/sc") problem(s); run: shellcheck ${SCRIPTS[*]}"
    fi
else
    meh "shellcheck isn't installed (sudo apt install shellcheck), skipped"
fi
for f in parts/*.sh extras/*.sh; do
    grep -q -- '--remove' "$f" || meh "$f has no --remove"
    grep -q '^# status: ' "$f" || meh "$f has no '# status:' line (status.sh can't show it)"
done
# "Written by Wren Linux parts/X.sh" (a header, a marker in a file it writes) names
# a script that is there
while IFS=: read -r f m; do
    s=$(sed -E 's/.*[Ww]ritten by Wren Linux //' <<<"$m")
    [ -f "$s" ] || bad "$f says it was written by $s, which doesn't exist"
done < <(grep -rHiE 'written by Wren Linux (parts|extras)/[a-z-]+\.sh' bin data extras parts lib | grep -v OLD_UMARK |
    sed -E 's/^([^:]*):.*([Ww]ritten by Wren Linux (parts|extras)\/[a-z-]+\.sh).*/\1:\2/')
# Every extra has its article in docs/extras/, which explains it from the ground up
for f in extras/*.sh extras/firefox-profiles/new-profile.sh; do
    case $f in extras/firefox-profiles/*) name=firefox-profiles ;; *) name=$(basename "$f" .sh) ;; esac
    [ -s "docs/extras/$name.md" ] || bad "$f has no article: docs/extras/$name.md"
    grep -qF "]($name.md)" docs/extras/README.md 2>/dev/null ||
        bad "docs/extras/README.md doesn't link to $name.md"
done
# install-extras.sh lists the extras with these one-line summaries
for f in extras/*.sh; do
    line=$(sed -n 's/^# summary: //p' "$f" | head -1)
    if [ -z "$line" ]; then
        meh "$f has no '# summary:' line (install-extras.sh can't describe it)"
    elif [ ${#line} -gt 52 ]; then
        meh "$f: the summary is ${#line} characters; over 52 is cut off in the list"
    fi
done
# extras/claude-code.sh and parts/incognito.sh install these as root
for f in bin/claude bin/claude-session bin/claude-unsandboxed bin/git data/claude-firewall.nft data/claude-agent-CLAUDE.md; do
    [ -f "$f" ] || bad "extras/claude-code.sh needs $f"
done
# extras/claude-vm.sh installs these (plus the bundled vendor/mockvps-kvm)
for f in bin/claude-vm bin/claude-vm-session bin/claude-vm-net-check data/claude-vm-firewall.nft data/claude-vm-provision.sh vendor/mockvps-kvm/mockvps-kvm.sh; do
    [ -f "$f" ] || bad "extras/claude-vm.sh needs $f"
done
# Whonix: --remove asks about the disks before it removes the VMs, and an install
# asks before it puts fresh disks over kept ones
w=$(sed -n '/--remove ]; then/,/^fi/p' extras/whonix.sh)
[ "$(grep -n 'ask "Also delete the Whonix disks' <<<"$w" | cut -d: -f1)" -lt "$(grep -n 'undefine' <<<"$w" | cut -d: -f1)" ] ||
    bad "extras/whonix.sh --remove removes the VMs before asking about their disks"
# shellcheck disable=SC2016  # the pattern is the script's own text, $ included
[ "$(grep -n 'Replace them with fresh ones' extras/whonix.sh | cut -d: -f1)" -lt "$(grep -n 'mv "$work/gw.qcow2" "$IMAGES/$GW.qcow2"' extras/whonix.sh | cut -d: -f1)" ] ||
    bad "extras/whonix.sh can put fresh disks over kept ones without asking"
for f in bin/onion-site bin/onion-site-session lib/onion-site.sh data/onion-site-firewall.nft data/onion-site-provision.sh; do
    [ -f "$f" ] || bad "extras/onion-site.sh needs $f"
done
for f in lib/install-iso.sh data/install-iso-preseed.cfg data/install-iso-disk.sh data/install-iso-late.sh data/install-iso-first-login.sh; do
    [ -f "$f" ] || bad "prep/make-install-iso.sh needs $f"
done
for f in bin/wren-camera data/webcam-off.rules; do
    [ -f "$f" ] || bad "extras/webcam.sh needs $f"
done
for f in lib/get-iso.sh lib/tails.sh lib/usb-stick.sh bin/get-iso; do
    [ -f "$f" ] || bad "extras/get-iso.sh needs $f"
done
for f in lib/tails.sh lib/usb-stick.sh bin/tails-usb; do
    [ -f "$f" ] || bad "extras/tails-usb.sh needs $f"
done
for f in lib/secure-dns.sh data/secure-dns-firewall.nft; do
    [ -f "$f" ] || bad "parts/secure-dns.sh needs $f"
done
for f in bin/incognito bin/incognito-session bin/wayland-restrict bin/wifi-signin data/incognito-user.js data/incognito-firewall.nft data/wifi-signin-firewall.nft; do
    [ -f "$f" ] || bad "parts/incognito.sh needs $f"
done
# The hardening parts read these
for f in data/sysctl-hardening.conf data/module-blacklist.conf data/foot.ini data/mousepad.settings data/snowflake-bridges.txt; do
    [ -f "$f" ] || bad "a part needs $f"
done
# bin/powermenu, bin/wren-idle and bin/lid can't source lib/sway.sh, so their lock command is a copy
for f in bin/powermenu bin/wren-idle bin/lid bin/wren-lock; do
    grep -qF "$LOCK_CMD" "$f" || bad "$f's lock command differs from LOCK_CMD in lib/sway.sh"
done
# The pop-up windows (key sheet, Wi-Fi, timer, the Wren menu) are all as
# see-through as the bar: every foot that opens one has the same alpha
for line in $(grep -rhoE 'foot [^"]*--app-id=wren-(keys|nmtui|timer)' bin install-base.sh | tr ' ' '#'); do
    [[ $line == *colors.alpha=0.85* ]] || bad "a pop-up window isn't see-through like the others: ${line//#/ }"
done
grep -q 'colors.alpha=0.85' bin/wren-menu || bad "the Wren menu's window isn't see-through like the others"
# Every sysctl key in the hardening file exists on this kernel
while read -r key _; do
    [ -e "/proc/sys/${key//.//}" ] || meh "sysctl $key doesn't exist on this kernel (data/sysctl-hardening.conf)"
done < <(grep -E '^[a-z]' data/sysctl-hardening.conf)
# Every helper a script installs from bin/ has to be there
mapfile -t wanted < <(grep -rhoE 'install_bin [a-z0-9-]+' --include='*.sh' . | awk '{ print $2 }' | sort -u)
for name in "${wanted[@]}"; do
    [ -f "bin/$name" ] || bad "install_bin $name: there is no bin/$name"
done

# --------------------------------------------------------------------
dev_test apt-markers "Package markers (apt_install / apt_purge), simulated" "marker checks"

# --------------------------------------------------------------------
dev_test bridges "Bridge chooser (Tor Browser, Whonix, OnionShare, apt over Tor), scripted" "bridge checks"

# --------------------------------------------------------------------
dev_test timer "Timers, alarms and the clock format (bin/timer), with pretend systemd" "timer checks"

# --------------------------------------------------------------------
dev_test home-private "Your home folder, closed to other users" "private home checks"
dev_test command-hints "Hints for commands that are not installed" "command hint checks"
dev_test wifi-signin "The Wi-Fi sign-in window and Firefox's own DNS" "Wi-Fi sign-in and Firefox DNS checks"
dev_test grub-colors "GRUB's colours" "GRUB colour checks"
dev_test claude "The claude command and the sandboxed Claude Code, with a pretend sudo" "claude checks"

# --------------------------------------------------------------------
dev_test claude-vm "The claude-vm command (Claude Code in a VM), with a pretend sudo" "claude-vm checks"

# --------------------------------------------------------------------
dev_test distro-vm "Distributions in VMs (extras/distro-vm.sh): the firewall in a network namespace, the downloads' signatures" "distro-vm checks"

# --------------------------------------------------------------------
dev_test git-guard "The git guard for ~/projects (bin/git), with real git" "git guard checks"

# --------------------------------------------------------------------
dev_test no-abstract "Sandbox users and X11's abstract socket (bin/no-abstract-sockets), with Landlock" "no-abstract-sockets checks"

# --------------------------------------------------------------------
dev_test signatures "Signature checks (lib/appimage.sh), with throwaway keys" "signature checks"

# --------------------------------------------------------------------
dev_test onion-site "Your onion site (extras/onion-site.sh): command, session, offline VM settings, Tor" "onion site checks"

# --------------------------------------------------------------------
dev_test yt-dlp "yt-dlp as its own user (extras/yt-dlp.sh): the command, the session, what it installs" "yt-dlp checks"

# --------------------------------------------------------------------
dev_test display-scale "Screen sharpness (bin/display-scale): EDID sizes, the notice, VM screens" "display-scale checks"

# --------------------------------------------------------------------
dev_test install-iso "The install ISO (prep/make-install-iso.sh): answers, boot menus, disk choice" "install ISO checks"

# --------------------------------------------------------------------
dev_test webcam "The webcam switch (bin/wren-camera, extras/webcam.sh), on a pretend /sys" "webcam checks"

# --------------------------------------------------------------------
dev_test firefox-catalog "Ready-made Firefox profiles (data/firefox-profiles.list): usable, their uBlock exceptions" "ready-made profile checks"
dev_test vm-size "How big claude-vm's VM may be (lib/vm-size.sh): suggestions, limits, root's file" "VM size checks"
dev_test wallet-tor "Tor offered to the wallets (lib/wallet-tor.sh): Feather, Sparrow, Electrum" "wallet Tor checks"
dev_test get-iso "Other systems' images (lib/get-iso.sh): newest release, signatures, a pretend internet" "get-iso checks"
dev_test tails-usb "Tails on a USB stick (lib/tails.sh): release file, which disks, writing" "Tails stick checks"

# --------------------------------------------------------------------
dev_test backup "What backups leave out (extras/backup.sh), in a pretend home" "backup checks"

# --------------------------------------------------------------------
dev_test onionshare-tor "OnionShare through webtunnel (bin/onionshare-tor, extras/onionshare.sh), with a pretend tor" "OnionShare private tor checks"
dev_test tor-service "Who keeps the system tor service on (lib/tor.sh), on a pretend /etc" "tor service checks"

# --------------------------------------------------------------------
dev_test dhcp-no-name "This computer's name stays off the networks it joins (lib/net.sh, wifi.sh)" "DHCP name checks"
dev_test update-watch "Saying when security updates stop arriving (bin/wren-update-result, the bar)" "update watch checks"
dev_test what-wren-adds "What Wren Linux adds to Debian (docs/what-wren-adds.md), against the scripts" "what it adds checks"
dev_test claude-share "Giving Claude files to look at (bin/claude-share), with a real git server" "claude-share checks"
dev_test tether "A phone over USB (bin/tether, parts/tether.sh), on a pretend /sys" "tether checks"
dev_test clock "The clock: NTP and the time zone (parts/clock.sh), with a pretend timedatectl" "clock checks"

# --------------------------------------------------------------------
# --------------------------------------------------------------------
dev_test live-extras "The live image's extras (parts/no-live-extras.sh), with pretend apt" "live extras checks"

# --------------------------------------------------------------------
dev_test mousepad "Mousepad's look (extras/mousepad.sh), with a pretend gsettings" "Mousepad checks"

# --------------------------------------------------------------------
dev_test manual "The extras' pages and --manual (docs/extras/, print_manual), with a pretend sudo" "manual install checks"

# --------------------------------------------------------------------
dev_test regular-extras "Claude Code as you (extras/claude-regular.sh), next to the sandboxed one" "regular extras checks"

# --------------------------------------------------------------------
dev_test autologin "Autologin on tty1 (extras/autologin.sh), with a pretend sudo" "autologin checks"

# --------------------------------------------------------------------
dev_test vault "The vault (bin/vault, extras/vault.sh), with a pretend gocryptfs" "vault checks"

# --------------------------------------------------------------------
dev_test signal "Signal (extras/signal.sh): the pinned key, no setuid sandbox helper" "Signal checks"

# --------------------------------------------------------------------
dev_test opencode-vm "opencode in a VM (extras/opencode-vm.sh): the command, the session, the guest's install" "opencode-vm checks"

# --------------------------------------------------------------------
dev_test apt-keys "Signing keys of added apt repositories: checked and renewed" "apt key checks"

# --------------------------------------------------------------------
dev_test webtunnel "webtunnel for the system tor: the Tor Project's repository, lyrebird only" "webtunnel checks"

# --------------------------------------------------------------------
dev_test console-font "console-font in a terminal window (foot's text size)" "console-font checks"

# --------------------------------------------------------------------
dev_test usb "The usb command, with pretend lsblk, udisksctl and sudo" "usb checks"
dev_test encrypt-usb "Encrypting a USB stick (encrypt-usb.sh), with a pretend sudo" "encrypt-usb checks"

# --------------------------------------------------------------------
dev_test wallpaper "Your wallpaper (bin/wallpaper) and Debian's collections (extras/wallpapers.sh)" "wallpaper checks"

# --------------------------------------------------------------------
dev_test theme "Light or dark (bin/theme, data/themes), in a temp home with pretend swaymsg and makoctl" "theme checks"

# --------------------------------------------------------------------
dev_test vim "vim with colors (extras/vim.sh, data/vimrc), in a temp home" "vim checks"

# --------------------------------------------------------------------
dev_test w3m "w3m keeps cookies only while it is open (bin/w3m), with a pretend w3m" "w3m checks"

# --------------------------------------------------------------------
dev_test status "status.sh's screen lock line, with and without swaylock" "status checks"

# --------------------------------------------------------------------
dev_test whonix-cmd "The whonix command (bin/whonix), with a pretend virsh" "whonix command checks"
dev_test whonix-update "whonix update, inside the VMs (data/whonix-update*), with pretend apt and update-torbrowser" "whonix update checks"
dev_test whonix-feather "Whonix's Workstation: files written into a real disk image, and Feather's download checked" "whonix workstation checks"

# --------------------------------------------------------------------
dev_test wifi-scan "wifi.sh's network scan never hangs, with a pretend iw" "Wi-Fi scan checks"

# --------------------------------------------------------------------
dev_test sshd-check "The sshd settings check (lib/net.sh), with sample sshd -T output" "sshd settings checks"

# --------------------------------------------------------------------
dev_test offline-fresh "Old package lists are refused (lib/offline.sh), with a pretend clock" "offline freshness checks"

# --------------------------------------------------------------------
dev_test media-sandbox "The media sandbox (bin/media-sandbox), with a pretend bubblewrap" "media sandbox checks"

# --------------------------------------------------------------------
section "Status lines: one extra's marker must not be another script's package"
# install-extras.sh puts a * next to an extra when any item on its "# status:"
# line is found, so a package that incognito, claude-vm or another script also
# installs would leave the * on after --remove. git.sh is known: the program
# itself is its only marker.
shared=0
for f in extras/*.sh; do
    case ${f##*/} in git.sh) continue ;; esac
    for pkg in $(sed -n 's/^# status: //p' "$f" | head -1 | tr ' ' '\n' | sed -n 's/^apt://p'); do
        others=$(grep -lE "apt_install .*([ \"]|^)$pkg( |\"|$|\\\\)" extras/*.sh parts/*.sh install-base.sh 2>/dev/null | grep -vxF "$f" | paste -sd' ' || true)
        if [ -n "$others" ]; then
            bad "$f lists apt:$pkg on its status line, which $others also installs"
            shared=1
        fi
    done
done
[ "$shared" = 0 ] && ok "no extra's status line lists a package another script installs"
# The same for files and commands: one a base part sets up is there on every
# computer, so update.sh would take the extra for set up and run it again
# (console-only once named the base's tmux config, and left sway when run)
partmarks=$(sed -n 's/^# status: //p' parts/*.sh | tr ' ' '\n' | grep -E '^(file|bin):' | sort -u)
shared=0
for f in extras/*.sh; do
    for tok in $(sed -n 's/^# status: //p' "$f" | head -1 | tr ' ' '\n' | grep -E '^(file|bin):'); do
        if grep -qxF "$tok" <<<"$partmarks"; then
            bad "$f lists $tok on its status line, which a base part sets up too"
            shared=1
        fi
    done
done
[ "$shared" = 0 ] && ok "no extra's status line names a file or command a base part sets up"

# --------------------------------------------------------------------
dev_test update "update.sh: which scripts to rerun, with a pretend server" "update checks"

# --------------------------------------------------------------------
dev_test git-push "Publishing, signed (tools/git-push.sh), with a pretend server and a throwaway key" "git-push checks"
dev_test release "Publishing and installing here in one command (tools/release.sh)" "release checks"
dev_test tag-release "Releases: a signed tag, and the install image (tools/tag-release.sh, tools/publish-image.sh), with a throwaway key" "release tag and image checks"
dev_test wren-dev "A git copy to work on (extras/wren-dev.sh), from a pretend server" "wren-dev checks"
dev_test build-deb "The Wren Linux package (tools/build-deb.sh), unpacked in a temp folder" "package checks"

# --------------------------------------------------------------------
dev_test apt-repo "The signed apt repository (tools/make-apt-repo.sh), with apt as you" "repository checks"

# --------------------------------------------------------------------
dev_test wren-repo "Wren Linux's repository on a computer (parts/wren-repo.sh), with a pretend sudo" "repository part checks"

# --------------------------------------------------------------------
dev_test location "Wren Linux from wherever it is (not only ~/wren)" "location checks"

# --------------------------------------------------------------------
dev_test update-package "update.sh in the Wren Linux package's copy (no git), with a pretend upgrade" "package update checks"

# --------------------------------------------------------------------
dev_test signing-key "The signing key (extras/signing-key.sh, wren-key), with a pretend sudo" "signing key checks"

# --------------------------------------------------------------------
dev_test git-helper "git-helper.sh: a copy from a stick, connected to what was published" "git-helper checks"
dev_test gh-helper "gh-helper.sh: a token you make, and the rules on main, with a pretend gh" "gh-helper checks"
dev_test site "The website (site/, tools/build-site.sh): plain HTML, no script, built from a signed commit" "website checks"
dev_test setup-vps "The VPS setup (tools/setup-vps.sh), with a pretend root folder" "VPS setup checks"
dev_test vps-client "Your side of the VPS (tools/vps-client.sh): keys, Tor client file, ssh entry" "VPS client checks"
dev_test publish-site "Publishing the site (tools/publish-site.sh): only a signed commit" "publish checks"
dev_test try-vps "Trying the VPS setup in a VM (tools/try-vps.sh), without starting one" "try-vps checks"
dev_test security-key "Hardware security keys (extras/security-key.sh), with pretend sudo and PAM" "security key checks"
dev_test wallet-sandbox "Sandboxed wallets (extras/wallet-sandbox.sh): the firewall in a network namespace, the clipboard, the session" "wallet sandbox checks"
dev_test hardware-wallet "Hardware wallets (extras/hardware-wallet.sh): the udev rule, for the user at the keyboard only" "hardware wallet checks"
dev_test sudo-timeout "sudo remembers your password for 60 seconds (parts/sudo-timeout.sh)" "sudo timeout checks"
dev_test sandbox-dns "The sandboxes' DNS only to this computer's resolver (parts/sandbox-dns.sh), with a pretend nft" "sandbox DNS checks"

# --------------------------------------------------------------------
dev_test sandbox-net "Every sandbox off your network, or not running (bin/sandbox-net-check): the rules in a network namespace, the sessions, status.sh" "sandbox firewall checks"
dev_test startup-watch "The startup watch (bin/wren-watch, extras/startup-watch.sh) in a pretend home" "startup watch checks"
dev_test wren-lock "Every lock runs the on-lock programs (bin/wren-lock), with a pretend swaylock" "wren-lock checks"
dev_test keepassxc "KeePassXC (extras/keepassxc.sh): locked at every lock, on workspace 2 at login" "KeePassXC checks"
dev_test foot-config "The terminal's look (parts/foot-config.sh)" "foot config checks"
dev_test autostart "What opens at login (bin/wren-autostart)" "autostart checks"

# --------------------------------------------------------------------
dev_test update-signed "update.sh: only what Wren Linux's own key signed, with throwaway keys" "signed update checks"
if [ -n "${WREN_SIGNING_FPR:-}" ]; then
    if key_ok data/wren-signing-key.asc "$WREN_SIGNING_FPR"; then
        ok "data/wren-signing-key.asc is exactly the pinned key, and can sign"
        grep -qF "$WREN_SIGNING_FPR" SECURITY.md || bad "SECURITY.md doesn't name the pinned key, $WREN_SIGNING_FPR"
    else
        bad "data/wren-signing-key.asc isn't exactly the key WREN_SIGNING_FPR in pins.sh, or it has expired"
    fi
fi

# --------------------------------------------------------------------
dev_test wren-menu "The Wren menu in the bar (bin/wren-menu), with a pretend wmenu and foot" "Wren menu checks"

# --------------------------------------------------------------------
dev_test launcher "The Super+d launcher line (lib/sway.sh), on pretend sway configs" "launcher checks"

# --------------------------------------------------------------------
dev_test wren-cmd "The Wren Linux command and its man page (bin/wrenctl, data/wrenctl.1)" "Wren Linux command checks"

# --------------------------------------------------------------------
dev_test zram "Compressed memory (extras/zram.sh): its settings and page" "zram checks"
dev_test dim "The fade before the screen locks (bin/dim-warning), with a pretend brightnessctl" "dim checks"

# --------------------------------------------------------------------
dev_test hardware "Hardware-only parts (lib/core.sh), on a pretend /sys" "hardware checks"

# --------------------------------------------------------------------
dev_test extras-flow "Choosing extras first and installing them after the base" "extras flow checks"

# --------------------------------------------------------------------
dev_test mpv-notice "mpv's one-time note when there is no sound" "mpv notice checks"

# --------------------------------------------------------------------
dev_test dim "Fading the windows without the focus (bin/wren-dim), in a real sway" "window fading checks"
dev_test battery-bar "The low battery warning in the bar (bin/sway-status), with a pretend battery" "low battery checks"
dev_test keys "The key cheat sheet shows only what is installed (bin/keys)" "cheat sheet checks"
dev_test empty-workspace "The next empty workspace (bin/wren-empty-workspace), in a real sway" "empty workspace checks"

# --------------------------------------------------------------------
dev_test wifi-remove "wifi.sh --remove (lib/net.sh), on a pretend /etc" "wifi remove checks"

# --------------------------------------------------------------------
dev_test radios "Wi-Fi, Bluetooth and microphone switches (bin/radios), with pretend rfkill and wpctl" "radio switch checks"
dev_test pipewire-audio "The sound extra mutes the microphone and says so only when it worked (extras/pipewire-audio.sh), with a pretend wpctl" "sound extra checks"

# --------------------------------------------------------------------
dev_test console "Console-only: the autostart swap, the tmux bar and its clicks" "console-only checks"

# --------------------------------------------------------------------
dev_test bluetooth-conf "Bluetooth's start-off setting and the new extras" "bluetooth setup checks"

# --------------------------------------------------------------------
dev_test firefox-sandbox "The sandboxed Firefox (bin/firefox), with pretend sudo and setfacl" "sandboxed Firefox checks"
dev_test sandbox-sockets "The sandboxed browsers and your runtime folder (your audio server is in it)" "runtime folder checks"

# --------------------------------------------------------------------
dev_test firefox-policy "Firefox's policies.json (bin/ublock-allow): uBlock, DNS-over-HTTPS off" "Firefox policy checks"

# --------------------------------------------------------------------
dev_test secure-dns "Encrypted DNS (parts/secure-dns.sh): resolvers, Unbound's settings, the firewall rule, the switch" "secure DNS checks"

# --------------------------------------------------------------------
dev_test lid "The lid that doesn't suspend (extras/lid-awake.sh, bin/lid), with a pretend sway" "lid checks"

# --------------------------------------------------------------------
dev_test profile-users "Firefox profiles with a user of their own (new-profile.sh), with pretend sudo" "profile user checks"

# --------------------------------------------------------------------
section "Pinned keys and versions (pins.sh): checked by hand within a year?"
now=$(date +%s)
# Each "# checked: DATE" line belongs to the next VARIABLE= line
while read -r day what; do
    age=$(((now - $(date -d "$day" +%s)) / 86400))
    if [ "$age" -gt 365 ]; then
        meh "$what last checked $day ($age days ago): check it again by hand"
    else
        ok "$what checked $day"
    fi
done < <(awk '/^# checked: / { day = $3 } /^[A-Z][A-Z0-9_]*=/ && day { sub(/=.*/, ""); print day, $0; day = "" }' pins.sh)

# --------------------------------------------------------------------
section "Debian and Firefox features Wren Linux relies on"
. /etc/os-release
[ "${VERSION_CODENAME:-}" = "$DEBIAN_RELEASE" ] && ok "this is Debian $DEBIAN_RELEASE" ||
    meh "this is ${PRETTY_NAME:-unknown}, Wren Linux is written for $DEBIAN_RELEASE"
if is_installed firefox-esr; then
    [ "$(readlink /usr/share/firefox-esr/browser/defaults/syspref)" = /etc/firefox-esr ] &&
        ok "Firefox reads default prefs from /etc/firefox-esr (firefox-hardening)" ||
        bad "Debian's Firefox no longer links browser/defaults/syspref to /etc/firefox-esr"
fi
UBO="/usr/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/uBlock0@raymondhill.net"
if [ -f "$UBO/managed_storage.json" ]; then
    grep -q '"adminSettings"' "$UBO/managed_storage.json" &&
        ok "uBlock Origin still takes adminSettings (medium mode policy)" ||
        bad "uBlock Origin no longer has adminSettings; ublock-allow needs updating"
fi
if [ -f /etc/apparmor.d/torbrowser.Tor.tor ]; then
    grep -qs 'Wren Linux' /etc/apparmor.d/local/torbrowser.Tor.tor &&
        ok "Tor Browser's AppArmor profile has the DNS fix" ||
        meh "Tor Browser's AppArmor profile lacks the DNS fix: wrenctl install tor-browser"
fi
if [ -f "$SWAY_CONFIG" ] && command -v sway >/dev/null; then
    check_sway_config 2>"$TMP/sway" && ok "your sway config has no errors" ||
        bad "your sway config has errors: $(head -1 "$TMP/sway")"
fi

online || { section "Skipping the online checks (--offline)"; }

# --------------------------------------------------------------------
if online; then
    section "Debian packages"
    # Every package name in the scripts' apt_install lines and package lists
    mapfile -t names < <(
        {
            printf '%s\n' "${PKGS[@]}"
            cat parts/*.sh extras/*.sh extras/firefox-profiles/*.sh wifi.sh | awk '
                /(PKGS|LIBS|pkgs)\+?=\(/ { grab = 1 }
                /apt_install / && !/apt_install "/ { sub(/.*apt_install /, ""); sub(/[;|#].*/, ""); print; next }
                grab { line = $0; sub(/.*=\(/, "", line); if (sub(/\).*/, "", line)) grab = 0; print line }' |
                tr -s ' ()' '\n'
        } | grep -E '^[a-z0-9][a-z0-9.+-]+$' | sort -u
    )
    # Not from Debian: checked further down
    elsewhere=" claude-code mullvad-vpn mullvad-browser sparrowwallet "
    missing=()
    for p in "${names[@]}"; do
        [[ $elsewhere == *" $p "* ]] && continue
        cand=$(apt-cache policy "$p" 2>/dev/null | awk '/Candidate:/ { print $2 }')
        if [ -z "$cand" ] || [ "$cand" = "(none)" ]; then missing+=("$p"); fi
    done
    for p in "${missing[@]}"; do
        if [ "$p" = torbrowser-launcher ] &&
            wget -q --spider "https://packages.debian.org/$DEBIAN_RELEASE/$p"; then
            meh "$p is in Debian's contrib section, which this machine's apt doesn't use"
        else
            bad "Debian package $p not found (renamed or removed?)"
        fi
    done
    [ ${#missing[@]} -gt 0 ] || ok "all ${#names[@]} packages exist"

    # ----------------------------------------------------------------
    section "Signing keys: still published, still the pinned key, not expiring"
    check_key() { # NAME FPR URL
        local f="$TMP/key-$1" fpr exp sig
        if ! wget -qO "$f" "$3"; then bad "$1: key not downloadable from $3"; return; fi
        fpr=$(gpg --show-keys --with-colons "$f" 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }')
        if [ "$fpr" != "$2" ]; then bad "$1: key at $3 is $fpr, pinned $2"; return; fi
        exp=$(gpg --show-keys --with-colons "$f" 2>/dev/null | awk -F: '/^pub/ { print $7; exit }')
        # A signing-capable key or subkey that's neither expired nor revoked
        sig=$(gpg --show-keys --with-colons "$f" 2>/dev/null |
            awk -F: '($1 == "pub" || $1 == "sub") && $12 ~ /s/ && $2 !~ /[er]/ && ($7 == "" || $7 > '"$now"') { n++ } END { print n + 0 }')
        if [ -n "$exp" ] && [ "$exp" -lt $((now + 90 * 86400)) ]; then
            meh "$1: key expires $(date -d "@$exp" +%F); its owner usually extends it, re-check then"
        elif [ "$sig" -eq 0 ]; then
            bad "$1: key has no valid signing key left"
        else
            ok "$1: $fpr"
        fi
    }
    # GitHub's host keys (pins.sh): do they still match what GitHub says?
    hosts=$(wget -qO- --timeout=20 https://api.github.com/meta |
        python3 -I -c 'import json,sys; [print("github.com " + k) for k in json.load(sys.stdin)["ssh_keys"]]' | sort)
    if [ -z "$hosts" ]; then meh "GitHub's host keys: couldn't ask GitHub"
    elif [ "$hosts" = "$(sort <<<"$GITHUB_HOST_KEYS")" ]; then ok "GitHub's host keys: as pinned"
    else bad "GitHub's host keys have changed: check them, and update GITHUB_HOST_KEYS in pins.sh"; fi
    check_key "Claude Code" "$ANTHROPIC_FPR" "$ANTHROPIC_KEY_URL"
    check_key "Tor Browser" "$TB_FPR" "$TB_KEY_URL"
    check_key "Whonix" "$WHONIX_FPR" "$WHONIX_KEY_URL"
    check_key "Feather" "$FEATHER_FPR" "$FEATHER_KEY_URL"
    check_key "SimpleX" "$SIMPLEX_FPR" "$SIMPLEX_KEY_URL"
    check_key "Sparrow" "$SPARROW_FPR" "$SPARROW_KEY_URL"
    check_key "Mullvad" "$MULLVAD_FPR" "$MULLVAD_KEY_URL"
    check_key "Signal" "$SIGNAL_FPR" "$SIGNAL_KEY_URL"
    check_key "Tails" "$TAILS_FPR" "$TAILS_KEY_URL"
    check_key "Debian CD" "$DEBIAN_CD_FPR" "$DEBIAN_CD_KEY_URL"
    check_key "Kali" "$KALI_FPR" "$KALI_KEY_URL"
    check_key "Arch Linux" "$ARCH_ISO_FPR" "$ARCH_ISO_KEY_URL"
    check_key "Parrot" "$PARROT_FPR" "$PARROT_KEY_URL"
    check_key "Qubes 4.3" "$QUBES_FPR" "$QUBES_KEY_URL"
    check_key "yt-dlp" "$YTDLP_FPR" "$YTDLP_KEY_URL"
    # ----------------------------------------------------------------
    section "Newest releases: found, and signed by the pinned key"
    exists() { wget -q --spider "$1"; }

    v=$(wget -qO- https://aus1.torproject.org/torbrowser/update_3/release/download-linux-x86_64.json |
        sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    if [[ $v =~ ^[0-9.]+$ ]]; then
        u="https://dist.torproject.org/torbrowser/$v/tor-browser-linux-x86_64-$v.tar.xz"
        exists "$u" && exists "$u.asc" && ok "Tor Browser $v (prep/fetch-tor-browser.sh)" ||
            bad "Tor Browser $v: download or signature missing at $u"
        [ "${v%%.*}" = "$TB_SAFEST_VERSION" ] ||
            meh "Tor Browser is now $v; re-check data/tor-browser-safest.js against its SecurityLevel.sys.mjs, then TB_SAFEST_VERSION in pins.sh"
    else
        bad "Tor Browser: can't read the newest version (download-linux-x86_64.json changed?)"
    fi

    v=$(wget -qO- https://www.whonix.org/wiki/KVM |
        grep -o "download/libvirt/[0-9.]*/Whonix-LXQt-[0-9.]*\.Intel_AMD64" |
        sed 's|.*/Whonix-[^-]*-\(.*\)\.Intel_AMD64|\1|' | sort -uV | tail -1)
    if [[ $v =~ ^[0-9.]+$ ]]; then
        u="https://www.whonix.org/download/libvirt/$v/Whonix-LXQt-$v.Intel_AMD64.qcow2.libvirt.xz"
        exists "$u" && wget -qO "$TMP/w.asc" "$u.asc" && ok "Whonix $v (extras/whonix.sh)" ||
            bad "Whonix $v: download or signature missing at $u"
        [ "${v%%.*}" = "$WHONIX_TESTED_VERSION" ] ||
            meh "Whonix is now $v; re-check the image edits in extras/whonix.sh, then WHONIX_TESTED_VERSION"
    else
        bad "Whonix: can't read the newest version from whonix.org/wiki/KVM"
    fi

    v=$(latest_github_tag feather-wallet/feather)
    F=https://featherwallet.org/files/releases
    if [ -n "$v" ] && wget -qO "$TMP/fh" "$F/hashes-$v.txt" &&
        verify_clearsigned "$FEATHER_FPR" "$FEATHER_KEY_URL" "$TMP/fh" "$TMP/fs" 2>/dev/null &&
        grep -q "feather-$v.AppImage" "$TMP/fs" && exists "$F/linux-appimage/feather-$v.AppImage"; then
        ok "Feather $v: signed hash list and AppImage"
    else
        bad "Feather ${v:-?}: release, hash list or signature not as expected"
    fi

    v=$(latest_github_tag simplex-chat/simplex-chat)
    G=https://github.com/simplex-chat/simplex-chat/releases/download/$v
    if [ -n "$v" ] && wget -qO "$TMP/ss" "$G/_sha256sums" && wget -qO "$TMP/ss.asc" "$G/_sha256sums.asc" &&
        verify_detached "$SIMPLEX_FPR" "$SIMPLEX_KEY_URL" "$TMP/ss.asc" "$TMP/ss" 2>/dev/null &&
        grep -q "$v/simplex-desktop-x86_64.AppImage" "$TMP/ss"; then
        ok "SimpleX $v: signed hash list"
    else
        bad "SimpleX ${v:-?}: release, hash list or signature not as expected"
    fi

    v=$(latest_github_tag sparrowwallet/sparrow)
    G=https://github.com/sparrowwallet/sparrow/releases/download/$v
    if [ -n "$v" ] && wget -qO "$TMP/sm" "$G/sparrow-$v-manifest.txt" &&
        wget -qO "$TMP/sm.asc" "$G/sparrow-$v-manifest.txt.asc" &&
        verify_detached "$SPARROW_FPR" "$SPARROW_KEY_URL" "$TMP/sm.asc" "$TMP/sm" 2>/dev/null &&
        grep -q "sparrowwallet_$v-1_amd64.deb" "$TMP/sm"; then
        ok "Sparrow $v: signed manifest lists the .deb"
    else
        bad "Sparrow ${v:-?}: release, manifest or signature not as expected"
    fi

    # Apps installed earlier that have a newer release by now: NAME REPO SCRIPT
    while read -r app repo script; do
        have=$(installed_version "$app")
        [ -n "$have" ] || continue
        v=$(latest_github_tag "$repo")
        if [ -n "$v" ] && [ "$v" != "$have" ]; then
            meh "$app $have is installed, $v is out: bash extras/$script"
        fi
    done <<'LIST'
feather feather-wallet/feather feather-wallet.sh
simplex simplex-chat/simplex-chat simplex-chat.sh
LIST
    # Sparrow comes as a .deb straight from its makers, not from an apt
    # repository, so nothing updates it by itself either
    if is_installed sparrowwallet; then
        have=$(dpkg-query -W -f='${Version}' sparrowwallet 2>/dev/null)
        have=${have%-*}
        v=$(latest_github_tag sparrowwallet/sparrow)
        if [ -n "$v" ] && [ "$v" != "$have" ]; then
            meh "sparrow $have is installed, $v is out: wrenctl install sparrow-wallet"
        fi
    fi
    # Apps from other apt repositories only update by themselves if allowed
    while read -r pkg conf; do
        is_installed "$pkg" || continue
        [ -f "/etc/apt/apt.conf.d/52wren-$conf" ] ||
            meh "$pkg gets no automatic updates; run its script in extras/ again"
    done <<'LIST'
mullvad-vpn mullvad
mullvad-browser mullvad
claude-code claude-code
LIST

    check_repo() { # NAME FPR KEYURL BASE PACKAGES...
        local name=$1 fpr=$2 key=$3 base=$4 p
        shift 4
        if ! wget -qO "$TMP/ir" "$base/InRelease" ||
            ! verify_clearsigned "$fpr" "$key" "$TMP/ir" "$TMP/ir.txt" 2>/dev/null; then
            bad "$name apt repository: InRelease missing or not signed by the pinned key"
            return
        fi
        wget -qO "$TMP/pk" "$base/main/binary-amd64/Packages" ||
            { bad "$name apt repository: no package list"; return; }
        for p in "$@"; do
            grep -qx "Package: $p" "$TMP/pk" || { bad "$name apt repository has no $p"; return; }
        done
        ok "$name apt repository: signed, has $*"
    }
    # Tails: the release file still reads as tails-usb expects, and its image's
    # signature is there (the image itself is too big to fetch here)
    . lib/tails.sh
    if wget -qO "$TMP/tails.json" "$TAILS_LATEST_URL" && line=$(tails_latest "$TMP/tails.json"); then
        read -r v _ <<<"$line"
        exists "$TAILS_SIG_BASE/tails-amd64-$v.img.sig" && ok "Tails $v: release file and signature (extras/tails-usb.sh)" ||
            bad "Tails $v: no signature at $TAILS_SIG_BASE/tails-amd64-$v.img.sig"
    else
        bad "Tails: the release file at $TAILS_LATEST_URL isn't as tails-usb expects"
    fi

    # The resolvers parts/secure-dns.sh offers: each IPv4 address answers on port
    # 853 with a certificate for its pinned name (IPv6 is often not reachable)
    . lib/secure-dns.sh
    if command -v openssl >/dev/null; then
        for name in "${DNS_PROVIDERS[@]}"; do
            pin=$(dns_pin "$name") tls=${pin%% *} bad_addr=
            for a in ${pin#* }; do
                [[ $a == *:* ]] && continue
                echo | timeout 15 openssl s_client -connect "$a:853" -servername "$tls" \
                    -verify_hostname "$tls" -verify_return_error -brief 2>&1 | grep -q '^Verification: OK' ||
                    bad_addr+=" $a"
            done
            if [ -z "$bad_addr" ]; then ok "DNS over TLS: $tls answers with its certificate"
            else bad "DNS over TLS: $tls not reachable or wrong certificate at$bad_addr (pins.sh DOT_*)"; fi
        done
    else
        meh "openssl isn't installed, so the DNS-over-TLS resolvers weren't checked"
    fi

    check_repo "Mullvad" "$MULLVAD_FPR" "$MULLVAD_KEY_URL" \
        https://repository.mullvad.net/deb/stable/dists/stable mullvad-vpn mullvad-browser
    check_repo "Claude Code" "$ANTHROPIC_FPR" "$ANTHROPIC_KEY_URL" \
        https://downloads.claude.ai/claude-code/apt/stable/dists/stable claude-code
fi

# --------------------------------------------------------------------
section "Saved offline copies"
any=false
for f in "$OFFLINE_DIR"/torbrowser/tor-browser-linux-*.tar.xz; do
    [ -f "$f" ] || continue
    any=true
    verify_detached "$TB_FPR" "$OFFLINE_DIR"/torbrowser/tor-browser-developers.asc "$f.asc" "$f" 2>/dev/null &&
        ok "$f verifies" || bad "$f doesn't verify: run prep/fetch-tor-browser.sh again"
done
for f in "$OFFLINE_DIR"/whonix/Whonix-*.libvirt.xz; do
    [ -f "$f" ] || continue
    any=true
    verify_detached "$WHONIX_FPR" "$OFFLINE_DIR"/whonix/derivative.asc "$f.asc" "$f" 2>/dev/null &&
        ok "$f verifies" || bad "$f doesn't verify: run extras/whonix.sh --fetch again"
done
if [ -f "$OFFLINE_DIR"/debs/Packages ]; then
    any=true
    if [ -d "$OFFLINE_DIR"/debs/verify ] && verify_offline_lists "$OFFLINE_DIR"/debs/verify "$TMP/sums" 2>"$TMP/err" &&
        check_offline_debs "$OFFLINE_DIR"/debs "$TMP/sums" 2>>"$TMP/err"; then
        ok "offline/debs: $(grep -c '^Package:' "$OFFLINE_DIR"/debs/Packages) packages for wifi.sh, all in Debian's signed lists"
    else
        bad "offline/debs doesn't check out ($(head -1 "$TMP/err")): run prep/fetch-offline-debs.sh again"
    fi
fi
$any || ok "none saved (that's fine)"

# --------------------------------------------------------------------
printf '\n%d ok, %d warnings, %d failures\n' "$n_ok" "$n_warn" "$n_fail"
[ "$n_fail" -eq 0 ]
