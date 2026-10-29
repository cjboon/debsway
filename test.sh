#!/bin/bash
# test.sh: checks that debsway still works. Its own scripts, and the
# outside things they depend on: Debian packages, download pages,
# signing keys, release signatures, and the Firefox and Debian features
# the hardening relies on. It installs and changes nothing; downloads
# are small (signatures and checksum lists) and go to a temporary folder.
# Run it now and then, and before you reinstall.
#
#   bash test.sh            everything (needs internet)
#   bash test.sh --offline  only what needs no internet
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
. "$DEBSWAY_DIR/lib/appimage.sh"
. "$DEBSWAY_DIR/lib/offline.sh"
. "$DEBSWAY_DIR/packages.sh"
# Keep going after a failure; every check reports for itself
set +e +o pipefail

OFFLINE=false
[ "${1:-}" = --offline ] && OFFLINE=true
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
n_ok=0 n_warn=0 n_fail=0
ok() { printf '  \033[32mok\033[0m    %s\n' "$*"; n_ok=$((n_ok + 1)); }
meh() { printf '  \033[33mWARN\033[0m  %s\n' "$*"; n_warn=$((n_warn + 1)); }
bad() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; n_fail=$((n_fail + 1)); }
section() { printf '\n\033[1m%s\033[0m\n' "$*"; }
online() { ! $OFFLINE; }

cd "$DEBSWAY_DIR" || exit 1
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
for f in bin/claude-vm bin/claude-vm-session data/claude-vm-firewall.nft data/claude-vm-provision.sh vendor/mockvps-kvm/mockvps-kvm.sh; do
    [ -f "$f" ] || bad "extras/claude-vm.sh needs $f"
done
for f in bin/onion-site bin/onion-site-session lib/onion-site.sh data/onion-site-firewall.nft data/onion-site-provision.sh; do
    [ -f "$f" ] || bad "extras/onion-site.sh needs $f"
done
for f in lib/secure-dns.sh data/secure-dns-firewall.nft; do
    [ -f "$f" ] || bad "extras/secure-dns.sh needs $f"
done
for f in bin/incognito bin/incognito-session bin/wayland-restrict data/incognito-user.js data/incognito-firewall.nft; do
    [ -f "$f" ] || bad "parts/incognito.sh needs $f"
done
# The hardening parts read these
for f in data/sysctl-hardening.conf data/module-blacklist.conf data/foot.ini data/mousepad.settings data/snowflake-bridges.txt; do
    [ -f "$f" ] || bad "a part needs $f"
done
# bin/powermenu, bin/debsway-idle and bin/lid can't source lib/sway.sh, so their lock command is a copy
for f in bin/powermenu bin/debsway-idle bin/lid; do
    grep -qF "$LOCK_CMD" "$f" || bad "$f's lock command differs from LOCK_CMD in lib/sway.sh"
done
# Every sysctl key in the hardening file exists on this kernel
while read -r key _; do
    [ -e "/proc/sys/${key//.//}" ] || meh "sysctl $key doesn't exist on this kernel (data/sysctl-hardening.conf)"
done < <(grep -E '^[a-z]' data/sysctl-hardening.conf)
# Every helper a script installs from bin/ has to be there
mapfile -t wanted < <(grep -rhoE 'install_bin [a-z-]+' --include='*.sh' . | awk '{ print $2 }' | sort -u)
for name in "${wanted[@]}"; do
    [ -f "bin/$name" ] || bad "install_bin $name: there is no bin/$name"
done

# --------------------------------------------------------------------
section "Package markers (apt_install / apt_purge), simulated"
if out=$(bash tools/test-apt-markers.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") marker checks"
else
    bad "package marker checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "Bridge chooser (Tor Browser, Whonix, OnionShare, apt over Tor), scripted"
if out=$(bash tools/test-bridges.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") bridge checks"
else
    bad "bridge checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "Timers, alarms and the clock format (bin/timer), with pretend systemd"
if out=$(bash tools/test-timer.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") timer checks"
else
    bad "timer checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "The claude command (sandboxed Claude Code), with a pretend sudo"
if out=$(bash tools/test-claude.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") claude checks"
else
    bad "claude checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "The claude-vm command (Claude Code in a VM), with a pretend sudo"
if out=$(bash tools/test-claude-vm.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") claude-vm checks"
else
    bad "claude-vm checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "The git guard for ~/projects (bin/git), with real git"
if out=$(bash tools/test-git-guard.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") git guard checks"
else
    bad "git guard checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "Sandbox users and X11's abstract socket (bin/no-abstract-sockets), with Landlock"
if out=$(bash tools/test-no-abstract.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") no-abstract-sockets checks"
else
    bad "no-abstract-sockets checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "Signature checks (lib/appimage.sh), with throwaway keys"
if out=$(bash tools/test-signatures.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") signature checks"
else
    bad "signature checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "Your onion site (extras/onion-site.sh): command, session, offline VM settings, Tor"
if out=$(bash tools/test-onion-site.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") onion site checks"
else
    bad "onion site checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "Who keeps the system tor service on (lib/tor.sh), on a pretend /etc"
if out=$(bash tools/test-tor-service.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") tor service checks"
else
    bad "tor service checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "The sshd settings check (lib/net.sh), with sample sshd -T output"
if out=$(bash tools/test-sshd-check.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") sshd settings checks"
else
    bad "sshd settings checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "Old package lists are refused (lib/offline.sh), with a pretend clock"
if out=$(bash tools/test-offline-fresh.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") offline freshness checks"
else
    bad "offline freshness checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "The media sandbox (bin/media-sandbox), with a pretend bubblewrap"
if out=$(bash tools/test-media-sandbox.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") media sandbox checks"
else
    bad "media sandbox checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "Status lines: one extra's marker must not be another script's package"
# install-extras.sh puts a * next to an extra when any item on its "# status:"
# line is found, so a package that incognito, claude-vm or another script also
# installs would leave the * on after --remove. firefox.sh and git.sh are known:
# the program itself is their only marker.
shared=0
for f in extras/*.sh; do
    case ${f##*/} in firefox.sh | git.sh) continue ;; esac
    for pkg in $(sed -n 's/^# status: //p' "$f" | head -1 | tr ' ' '\n' | sed -n 's/^apt://p'); do
        others=$(grep -lE "apt_install .*([ \"]|^)$pkg( |\"|$|\\\\)" extras/*.sh parts/*.sh install-base.sh 2>/dev/null | grep -vxF "$f" | paste -sd' ' || true)
        if [ -n "$others" ]; then
            bad "$f lists apt:$pkg on its status line, which $others also installs"
            shared=1
        fi
    done
done
[ "$shared" = 0 ] && ok "no extra's status line lists a package another script installs"

# --------------------------------------------------------------------
section "update.sh: which scripts to rerun, with a pretend server"
if out=$(bash tools/test-update.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") update checks"
else
    bad "update checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "The debsway menu in the bar (bin/debsway-menu), with a pretend wmenu and foot"
if out=$(bash tools/test-debsway-menu.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") debsway menu checks"
else
    bad "debsway menu checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "The Super+d launcher line (lib/sway.sh), on pretend sway configs"
if out=$(bash tools/test-launcher.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") launcher checks"
else
    bad "launcher checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "The debsway command and its man page (bin/debsway, data/debsway.1)"
if out=$(bash tools/test-debsway-cmd.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") debsway command checks"
else
    bad "debsway command checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "The fade before the screen locks (bin/dim-warning), with a pretend brightnessctl"
if out=$(bash tools/test-dim.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") dim checks"
else
    bad "dim checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "Hardware-only parts (lib/core.sh), on a pretend /sys"
if out=$(bash tools/test-hardware.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") hardware checks"
else
    bad "hardware checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "Choosing extras first and installing them after the base"
if out=$(bash tools/test-extras-flow.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") extras flow checks"
else
    bad "extras flow checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "mpv's one-time note when there is no sound"
if out=$(bash tools/test-mpv-notice.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") mpv notice checks"
else
    bad "mpv notice checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "The key cheat sheet shows only what is installed (bin/keys)"
if out=$(bash tools/test-keys.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") cheat sheet checks"
else
    bad "cheat sheet checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "wifi.sh --remove (lib/net.sh), on a pretend /etc"
if out=$(bash tools/test-wifi-remove.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") wifi remove checks"
else
    bad "wifi remove checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "Wi-Fi, Bluetooth and microphone switches (bin/radios), with pretend rfkill and wpctl"
if out=$(bash tools/test-radios.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") radio switch checks"
else
    bad "radio switch checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "Bluetooth's start-off setting and the new extras"
if out=$(bash tools/test-bluetooth-conf.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") bluetooth setup checks"
else
    bad "bluetooth setup checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "The sandboxed Firefox (bin/firefox), with pretend sudo and setfacl"
if out=$(bash tools/test-firefox-sandbox.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") sandboxed Firefox checks"
else
    bad "sandboxed Firefox checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "Firefox's policies.json (bin/ublock-allow): uBlock, DNS-over-HTTPS off"
if out=$(bash tools/test-firefox-policy.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") Firefox policy checks"
else
    bad "Firefox policy checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "Encrypted DNS (extras/secure-dns.sh): resolvers, Unbound's settings, the firewall rule"
if out=$(bash tools/test-secure-dns.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") secure DNS checks"
else
    bad "secure DNS checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "The lid that doesn't suspend (extras/lid-awake.sh, bin/lid), with a pretend sway"
if out=$(bash tools/test-lid.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") lid checks"
else
    bad "lid checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

# --------------------------------------------------------------------
section "Firefox profiles with a user of their own (new-profile.sh), with pretend sudo"
if out=$(bash tools/test-profile-users.sh 2>&1); then
    ok "$(grep -c '^  ok' <<<"$out") profile user checks"
else
    bad "profile user checks: $(grep '  FAIL' <<<"$out" | head -3 | tr -s ' ' | paste -sd';')"
fi

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
section "Debian and Firefox features debsway relies on"
. /etc/os-release
[ "${VERSION_CODENAME:-}" = "$DEBIAN_RELEASE" ] && ok "this is Debian $DEBIAN_RELEASE" ||
    meh "this is ${PRETTY_NAME:-unknown}, debsway is written for $DEBIAN_RELEASE"
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
    grep -qs 'debsway' /etc/apparmor.d/local/torbrowser.Tor.tor &&
        ok "Tor Browser's AppArmor profile has the DNS fix" ||
        meh "Tor Browser's AppArmor profile lacks the DNS fix: bash extras/tor-browser.sh"
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
    check_key "Claude Code" "$ANTHROPIC_FPR" "$ANTHROPIC_KEY_URL"
    check_key "Tor Browser" "$TB_FPR" "$TB_KEY_URL"
    check_key "Whonix" "$WHONIX_FPR" "$WHONIX_KEY_URL"
    check_key "Feather" "$FEATHER_FPR" "$FEATHER_KEY_URL"
    check_key "SimpleX" "$SIMPLEX_FPR" "$SIMPLEX_KEY_URL"
    check_key "Sparrow" "$SPARROW_FPR" "$SPARROW_KEY_URL"
    check_key "Mullvad" "$MULLVAD_FPR" "$MULLVAD_KEY_URL"

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
    # Apps from other apt repositories only update by themselves if allowed
    while read -r pkg conf; do
        is_installed "$pkg" || continue
        [ -f "/etc/apt/apt.conf.d/52debsway-$conf" ] ||
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
    # The resolvers extras/secure-dns.sh offers: each IPv4 address answers on port
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
for f in offline/torbrowser/tor-browser-linux-*.tar.xz; do
    [ -f "$f" ] || continue
    any=true
    verify_detached "$TB_FPR" offline/torbrowser/tor-browser-developers.asc "$f.asc" "$f" 2>/dev/null &&
        ok "$f verifies" || bad "$f doesn't verify: run prep/fetch-tor-browser.sh again"
done
for f in offline/whonix/Whonix-*.libvirt.xz; do
    [ -f "$f" ] || continue
    any=true
    verify_detached "$WHONIX_FPR" offline/whonix/derivative.asc "$f.asc" "$f" 2>/dev/null &&
        ok "$f verifies" || bad "$f doesn't verify: run extras/whonix.sh --fetch again"
done
if [ -f offline/debs/Packages ]; then
    any=true
    if [ -d offline/debs/verify ] && verify_offline_lists offline/debs/verify "$TMP/sums" 2>"$TMP/err" &&
        check_offline_debs offline/debs "$TMP/sums" 2>>"$TMP/err"; then
        ok "offline/debs: $(grep -c '^Package:' offline/debs/Packages) packages for wifi.sh, all in Debian's signed lists"
    else
        bad "offline/debs doesn't check out ($(head -1 "$TMP/err")): run prep/fetch-offline-debs.sh again"
    fi
fi
$any || ok "none saved (that's fine)"

# --------------------------------------------------------------------
printf '\n%d ok, %d warnings, %d failures\n' "$n_ok" "$n_warn" "$n_fail"
[ "$n_fail" -eq 0 ]
