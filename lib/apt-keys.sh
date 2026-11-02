# shellcheck shell=bash
# lib/apt-keys.sh: the signing keys of the apt repositories debsway adds,
# kept fresh. Sourced after lib.sh, by update.sh and status.sh.
#
# A key is installed when its extra runs, and an extra only runs again when
# its own files change. A key that expires (Signal's, Mullvad's, or the Tor
# Project's, whose signing subkey expires 2027-11-01) or that the vendor
# renews would then sit there unchanged: apt stops taking that repository's
# updates, and unattended-upgrades does so quietly. So update.sh checks each
# installed key every time, and fetches a new one when it can no longer sign
# or will stop within APT_KEY_WARN_DAYS days; the new key goes in only if it
# is exactly the pinned one (key_ok) and signs for longer than the old.
# status.sh shows the same check.

# NAME|FILE|FINGERPRINT VARIABLE|URL VARIABLE (pins.sh); FILE is where the
# script that adds the repository puts its key (a test checks they agree)
APT_KEYS=(
    "Claude Code|/etc/apt/keyrings/claude-code.asc|ANTHROPIC_FPR|ANTHROPIC_KEY_URL"
    "Signal|/usr/share/keyrings/signal-desktop-keyring.asc|SIGNAL_FPR|SIGNAL_KEY_URL"
    "Mullvad|/usr/share/keyrings/mullvad-keyring.asc|MULLVAD_FPR|MULLVAD_KEY_URL"
    "the Tor Project (lyrebird)|/usr/share/keyrings/debsway-torproject.asc|TORPROJECT_FPR|TORPROJECT_KEY_URL"
)
APT_KEY_WARN_DAYS=60
# (a test reads the key files from under this folder; sudo still writes to the real path)
APT_KEYS_ROOT=${DEBSWAY_KEYS_ROOT:-}

# key_sign_until FILE: until when (seconds since 1970; 0 for never) a key in
# FILE that isn't expired or revoked can sign; fails if none can
key_sign_until() {
    gpg --show-keys --with-colons "$1" 2>/dev/null | awk -F: '
        /^(pub|sub):/ && $2 !~ /[erd]/ && $12 ~ /s/ {
            found = 1
            if ($7 == "") never = 1; else if ($7 + 0 > max) max = $7 + 0
        }
        END { if (!found) exit 1; print (never ? 0 : max) }'
}

# apt_key_state FILE FPR: "ok", "soon DAYS" (it stops signing in DAYS days),
# or "bad" (not the pinned key, or it can't sign any more)
apt_key_state() {
    local until days
    key_ok "$1" "$2" && until=$(key_sign_until "$1") || { echo bad; return; }
    [ "$until" != 0 ] || { echo ok; return; }
    days=$(((until - $(date +%s)) / 86400))
    if [ "$days" -lt "$APT_KEY_WARN_DAYS" ]; then echo "soon $days"; else echo ok; fi
}

# apt_keys_installed: the APT_KEYS lines whose key file is on this computer
apt_keys_installed() {
    local k file
    for k in "${APT_KEYS[@]}"; do
        IFS='|' read -r _ file _ _ <<<"$k"
        [ ! -e "$APT_KEYS_ROOT$file" ] || echo "$k"
    done
}

# apt_keys_status: one line per installed key, for status.sh
apt_keys_status() {
    local name file fv uv state
    while IFS='|' read -r name file fv uv; do
        state=$(apt_key_state "$APT_KEYS_ROOT$file" "${!fv}")
        case $state in
            ok) printf '  [x] %s\n' "$name" ;;
            soon*) printf '  [!] %s: stops signing in %s days. bash update.sh fetches the new key\n' "$name" "${state#soon }" ;;
            *) printf '  [ ] %s: EXPIRED or not the pinned key, so apt takes no updates from it. bash update.sh fetches the new key\n' "$name" ;;
        esac
    done < <(apt_keys_installed)
}

# apt_keys_refresh: a new key for each installed one that can't sign, or
# stops soon. Never stops update.sh; returns 1 if a key is still bad after.
apt_keys_refresh() {
    local name file fv uv state tmp old new rc=0
    while IFS='|' read -r name file fv uv; do
        state=$(apt_key_state "$APT_KEYS_ROOT$file" "${!fv}")
        [ "$state" != ok ] || continue
        note "The signing key for $name $([ "$state" = bad ] && echo "can't sign any more" || echo "stops signing in ${state#soon } days"): fetching it again"
        tmp=$(mktemp)
        if ! wget -qO "$tmp" "${!uv}"; then
            warn "Couldn't download it from ${!uv}; kept the old one."
        elif ! key_ok "$tmp" "${!fv}"; then
            warn "The key at ${!uv} isn't exactly the pinned key ${!fv} (or it has expired). Not trusting it; kept the old one."
        else
            new=$(key_sign_until "$tmp") old=$(key_sign_until "$APT_KEYS_ROOT$file" || echo -1)
            # 0 is never: longer than any date
            if [ "$new" = 0 ] || { [ "$old" != 0 ] && [ "$new" -gt "$old" ]; }; then
                sudo install -m 0644 "$tmp" "$file"
                note "Installed the renewed key for $name."
                state=$(apt_key_state "$APT_KEYS_ROOT$file" "${!fv}")
            else
                warn "$name hasn't renewed its key yet; update.sh will look again next time."
            fi
        fi
        rm -f "$tmp"
        [ "$state" != bad ] || {
            warn "apt can't check $name's updates until this key is renewed."
            rc=1
        }
    done < <(apt_keys_installed)
    return "$rc"
}
