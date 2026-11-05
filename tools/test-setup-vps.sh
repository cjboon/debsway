#!/bin/bash
# Checks tools/setup-vps.sh with a pretend root folder: commands are only
# written down, never run, and its files land in a temp folder. SSH takes keys
# only and no root; the firewall lets in only SSH (slowed down) and the web;
# Caddy sends the strict headers and keeps no log; Tor's onion services, the
# SSH one for one client key only; the never-locked-out switch arms, refuses a
# confirmation from the session that made the change, takes one from a new
# login, and its rollback puts the old files back; port 22 closes only from a
# login that came through the onion. Changes nothing outside a temp folder.
# Run by test.sh, or:  bash tools/test-setup-vps.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
S=$HERE/tools/setup-vps.sh
T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl me@laptop'
CLIENT=ABCDEFGHIJKLMNOPQRSTUVWXYZ234567ABCDEFGHIJKLMNOPQRST
SITE_ONION=$(printf 's%.0s' {1..56}).onion
SSH_ONION=$(printf 'k%.0s' {1..56}).onion
fresh() { # a new pretend server: no user yet, Tor's onion names ready
    rm -rf "$T/root" "$T/calls"
    mkdir -p "$T/root/etc" "$T/root/var/lib/tor/wren-site" "$T/root/var/lib/tor/wren-ssh"
    echo 'root:x:0:0::/root:/bin/bash' >"$T/root/etc/passwd"
    echo "$SITE_ONION" >"$T/root/var/lib/tor/wren-site/hostname"
    echo "$SSH_ONION" >"$T/root/var/lib/tor/wren-ssh/hostname"
    : >"$T/calls"
}
vps() { # ARGS...: setup-vps.sh against the pretend server (VPS_* from the caller)
    env WREN_VPS_ROOT="$T/root" WREN_VPS_FAKE="$T/calls" bash "$S" "$@" 2>&1
}
R=$T/root

fresh
out=$(VPS_SSH_KEY=$KEY VPS_DOMAIN=example.org VPS_EMAIL=me@example.org VPS_ONION_SSH_CLIENT=$CLIENT vps --yes)
rc=$?
check "a first run with a domain, both onion services and a client key goes through${out:+: $(tail -1 <<<"$out")}" test "$rc" -eq 0
check "...its settings kept, for you alone (a rerun takes them)" bash -c '
    [ "$(stat -c %a "$1")" = 600 ] && grep -qx "VPS_ADMIN=wren" "$1" && grep -qx "VPS_DOMAIN=example.org" "$1" && grep -qx "VPS_SSH_PUBLIC=yes" "$1"' _ "$R/etc/wren-vps.conf"
check "your user, in the sudo group, logs in with your key alone" bash -c '
    grep -qx "useradd --create-home --shell /bin/bash --groups sudo wren" "$1" && [ "$(cat "$2/home/wren/.ssh/authorized_keys")" = "$3" ] &&
    [ "$(stat -c %a "$2/home/wren/.ssh/authorized_keys")" = 600 ] && [ "$(stat -c %a "$2/home/wren/.ssh")" = 700 ]' _ "$T/calls" "$R" "$KEY"
D=$R/etc/ssh/sshd_config.d/10-wren-vps.conf
check "sshd: no root, no passwords, keys only, only your user, no forwarding" bash -c '
    for l in "PermitRootLogin no" "PasswordAuthentication no" "KbdInteractiveAuthentication no" "AuthenticationMethods publickey" "AllowUsers wren" "AllowTcpForwarding no" "X11Forwarding no" "MaxAuthTries 3"; do grep -qx "$l" "$1" || { echo "$l"; exit 1; }; done' _ "$D"
check "...read first among sshd's files (10-), so a cloud image's 50-cloud-init.conf can't turn passwords back on" test -f "$D"
check "...and the script checks what sshd really does before it keeps it (sshd -T)" grep -q "sshd -T -C" "$S"
N=$R/etc/nftables.conf
check "firewall: nothing comes in by default, nothing is forwarded" bash -c '
    grep -q "type filter hook input priority 0; policy drop;" "$1" && grep -q "type filter hook forward priority 0; policy drop;" "$1"' _ "$N"
check "...SSH slowed down against guessing, and the web (HTTPS too, HTTP/3 included)" bash -c '
    grep -q "tcp dport 22 ct state new limit rate 10/minute burst 5 packets accept" "$1" && grep -q "tcp dport { 80, 443 } accept" "$1" && grep -q "udp dport 443 accept" "$1"' _ "$N"
if command -v nft >/dev/null && unshare -rn true 2>/dev/null; then
    check "...Debian's nft takes it (checked in a network namespace of its own)" unshare -rn nft -c -f "$N"
fi
C=$R/etc/caddy/Caddyfile
check "Caddy: no admin port, the certificate's email, your domain, www sent there" bash -c '
    grep -q "^    admin off$" "$1" && grep -q "^    email me@example.org$" "$1" && grep -q "^example.org {$" "$1" && grep -q "redir https://example.org{uri} permanent" "$1"' _ "$C"
check "...the headers: no script, frame or outside resource; no referrer; HSTS; its onion address" bash -c '
    grep -qF "Content-Security-Policy \"default-src '"'"'none'"'"'; style-src '"'"'self'"'"'; img-src '"'"'self'"'"'; base-uri '"'"'none'"'"'; form-action '"'"'none'"'"'; frame-ancestors '"'"'none'"'"'\"" "$1" &&
    grep -q "Referrer-Policy no-referrer" "$1" && grep -q "Strict-Transport-Security" "$1" && grep -qF "Onion-Location \"http://$2{uri}\"" "$1"' _ "$C" "$SITE_ONION"
check "...the onion site on 127.0.0.1 only, and no log of visitors" bash -c '
    grep -q "^http://:8080 {$" "$1" && grep -q "bind 127.0.0.1" "$1" && ! grep -qE "^[[:space:]]*log([[:space:]]|$)" "$1"' _ "$C"
check "...for any name: Tor Browser asks for the .onion name, and Caddy gives an empty page to a name it does not know" bash -c '! grep -q "^http://127.0.0.1:8080" "$1"' _ "$C"
check "...the git mirror at /git/, the site from /srv/wren-site" bash -c 'grep -q "handle_path /git/\*" "$1" && grep -q "root \* /srv/wren-site" "$1"' _ "$C"
H=$R/etc/systemd/system/caddy.service.d/60-wren-vps.conf
check "...and Caddy itself locked down by systemd" bash -c '
    for l in ProtectSystem=strict NoNewPrivileges=yes ProtectHome=yes PrivateDevices=yes CapabilityBoundingSet=CAP_NET_BIND_SERVICE RestrictNamespaces=yes; do grep -qx "$l" "$1" || exit 1; done' _ "$H"
check "Tor: onion services only (no proxy for anyone), the site and SSH, on 127.0.0.1" bash -c '
    grep -qx "SocksPort 0" "$1" && grep -qx "HiddenServicePort 80 127.0.0.1:8080" "$1" && grep -qx "HiddenServicePort 22 127.0.0.1:22" "$1"' _ "$R/etc/tor/torrc"
A=$R/var/lib/tor/wren-ssh/authorized_clients/wren.auth
check "...SSH's onion address only for your client key" bash -c '[ "$(cat "$1")" = "descriptor:x25519:$2" ] && [ "$(stat -c %a "$1")" = 600 ]' _ "$A" "$CLIENT"
check "security updates every day, a reboot at 04:00 when one needs it, services restarted by themselves" bash -c '
    grep -q "Automatic-Reboot \"true\"" "$1/etc/apt/apt.conf.d/52wren-vps" && grep -q "Automatic-Reboot-Time \"04:00\"" "$1/etc/apt/apt.conf.d/52wren-vps" &&
    grep -q "restart} = '"'"'a'"'"'" "$1/etc/needrestart/conf.d/60-wren-vps.conf"' _ "$R"
check "kernel and network hardening (sysctl)" bash -c 'grep -qx "kernel.kptr_restrict = 2" "$1" && grep -qx "net.ipv4.conf.all.accept_redirects = 0" "$1"' _ "$R/etc/sysctl.d/60-wren-vps.conf"
check "it says where the site and both onion addresses are, and how to log in through the onion" bash -c '
    grep -q "https://example.org" <<<"$1" && grep -q "$2" <<<"$1" && grep -q "$3" <<<"$1" && grep -q "vps-client.sh ssh-config wren $3" <<<"$1"' _ "$out" "$SITE_ONION" "$SSH_ONION"
check "...and at the next boot, if the server restarts before it is confirmed (the timer wouldn't survive that)" bash -c '
    f="$1/etc/systemd/system/wren-vps-undo-unconfirmed.service"
    grep -qx "ConditionPathExists=/var/lib/wren-vps/rollback" "$f" && grep -qx "ExecStart=/usr/local/sbin/wren-vps-rollback" "$f" &&
    grep -qx "WantedBy=multi-user.target" "$f" && grep -qx "systemctl enable wren-vps-undo-unconfirmed.service" "$2"' _ "$R" "$T/calls"
check "it installs itself as wren-vps, and the rollback" bash -c '[ -x "$1/usr/local/sbin/wren-vps" ] && [ -x "$1/usr/local/sbin/wren-vps-rollback" ]' _ "$R"

# The never-locked-out switch
check "the SSH and firewall change undoes itself in 10 minutes unless confirmed" grep -qx "systemd-run --quiet --unit=wren-vps-rollback --on-active=10min --timer-property=AccuracySec=5s /usr/local/sbin/wren-vps-rollback" "$T/calls"
check "...it says so, and how to confirm from a new login" bash -c 'grep -q "undo themselves in 10 minutes" <<<"$1" && grep -q "sudo wren-vps --confirm" <<<"$1"' _ "$out"
out=$(VPS_SSH_KEY=$KEY vps --yes)
check "...a second run while it waits is refused" bash -c 'grep -q "still waiting to be confirmed" <<<"$1"' _ "$out"
: >"$T/calls"
out=$(SSH_CONNECTION="198.51.100.7 50001 203.0.113.1 22" vps --confirm)
check "...confirmed from a new login: the timer stops, the old copies go" bash -c '
    grep -qx "systemctl stop wren-vps-rollback.timer" "$1" && [ ! -d "$2/var/lib/wren-vps/rollback" ]' _ "$T/calls" "$R"
# the session that armed it can't confirm it
fresh
SSH_CONNECTION="198.51.100.7 50000 203.0.113.1 22" VPS_SSH_KEY=$KEY VPS_ONION_SSH_CLIENT=$CLIENT vps --yes >/dev/null
out=$(SSH_CONNECTION="198.51.100.7 50000 203.0.113.1 22" vps --confirm)
check "...from the very session that made the change: refused (it proves nothing)" bash -c '
    grep -q "Confirm from a NEW login" <<<"$1" && [ -d "$2/var/lib/wren-vps/rollback" ]' _ "$out" "$R"
# the rollback itself, with its paths in the pretend root and pretend commands
mkdir -p "$T/fakebin"
for c in systemctl nft logger; do printf '#!/bin/sh\necho "%s $*" >>"%s"\n' "$c" "$T/rb-calls" >"$T/fakebin/$c"; chmod +x "$T/fakebin/$c"; done
sed -e "s|/var/lib/wren-vps|$R/var/lib/wren-vps|g" -e "s|/etc/|$R/etc/|g" "$R/usr/local/sbin/wren-vps-rollback" >"$T/rollback"
PATH="$T/fakebin:$PATH" sh "$T/rollback"
check "the rollback takes away what wasn't there before, and reloads SSH and the firewall" bash -c '
    [ ! -e "$1/etc/ssh/sshd_config.d/10-wren-vps.conf" ] && [ ! -e "$1/etc/nftables.conf" ] && [ ! -d "$1/var/lib/wren-vps/rollback" ] &&
    grep -qx "systemctl reload ssh" "$2" && grep -qx "nft flush ruleset" "$2"' _ "$R" "$T/rb-calls"
# ...and puts back what was
fresh
mkdir -p "$R/etc/ssh/sshd_config.d"; echo "# the old one" >"$R/etc/ssh/sshd_config.d/10-wren-vps.conf"; echo "# old rules" >"$R/etc/nftables.conf"
VPS_SSH_KEY=$KEY vps --yes >/dev/null
sed -e "s|/var/lib/wren-vps|$R/var/lib/wren-vps|g" -e "s|/etc/|$R/etc/|g" "$R/usr/local/sbin/wren-vps-rollback" >"$T/rollback"
: >"$T/rb-calls"; PATH="$T/fakebin:$PATH" sh "$T/rollback"
check "...and puts back what was there before" bash -c '
    [ "$(cat "$1/etc/ssh/sshd_config.d/10-wren-vps.conf")" = "# the old one" ] && [ "$(cat "$1/etc/nftables.conf")" = "# old rules" ] && grep -q "nft -f $1/etc/nftables.conf" "$2"' _ "$R" "$T/rb-calls"

# Closing port 22: only from a login through the onion
fresh
VPS_SSH_KEY=$KEY VPS_ONION_SSH_CLIENT=$CLIENT vps --yes >/dev/null
SSH_CONNECTION="198.51.100.7 1 203.0.113.1 22" vps --confirm >/dev/null
out=$(SSH_CONNECTION="198.51.100.7 2 203.0.113.1 22" vps --ssh-onion-only)
check "--ssh-onion-only from a login over the internet: refused, port 22 stays" bash -c '
    grep -q "through the SSH onion address" <<<"$1" && grep -q "tcp dport 22" "$2"' _ "$out" "$R/etc/nftables.conf"
out=$(SSH_CONNECTION="127.0.0.1 40000 127.0.0.1 22" vps --ssh-onion-only)
check "...from one through the onion: port 22 closed, the choice kept, and it waits for confirmation" bash -c '
    ! grep -q "tcp dport 22" "$2" && grep -qx "VPS_SSH_PUBLIC=no" "$3" && [ -d "$4/var/lib/wren-vps/rollback" ] && grep -q "undo themselves" <<<"$1"' _ "$out" "$R/etc/nftables.conf" "$R/etc/wren-vps.conf" "$R"
SSH_CONNECTION="127.0.0.1 40001 127.0.0.1 22" vps --confirm >/dev/null
out=$(SSH_CONNECTION="127.0.0.1 40002 127.0.0.1 22" vps --ssh-public)
check "--ssh-public opens it again" bash -c 'grep -q "tcp dport 22" "$1" && grep -qx "VPS_SSH_PUBLIC=yes" "$2"' _ "$R/etc/nftables.conf" "$R/etc/wren-vps.conf"

# In a terminal these ask nothing: what you chose is kept, also a domain left empty
# (its input stays open: at its end, a question would just take the empty answer)
if command -v script >/dev/null; then
    SSH_CONNECTION="127.0.0.1 40003 127.0.0.1 22" vps --confirm >/dev/null
    fresh
    VPS_SSH_KEY=$KEY VPS_ONION_SSH_CLIENT=$CLIENT vps --yes >/dev/null
    SSH_CONNECTION="198.51.100.7 1 203.0.113.1 22" vps --confirm >/dev/null
    SSH_CONNECTION="127.0.0.1 40004 127.0.0.1 22" WREN_VPS_ROOT="$T/root" WREN_VPS_FAKE="$T/calls" \
        timeout 10 script -qec "bash $S --ssh-onion-only" /dev/null < <(/bin/sleep 12) >"$T/pty" 2>&1
    rc=$?
    check "--ssh-onion-only in a terminal asks nothing again: it finishes, with your choices" bash -c '
        [ "$1" = 0 ] && ! grep -q "tcp dport 22" "$2"' _ "$rc" "$R/etc/nftables.conf"
fi

# No domain (a test VM), and no SSH onion
fresh
out=$(VPS_SSH_KEY=$KEY VPS_ONION_SSH=no vps --yes)
check "no domain: the site on plain http, port 80 alone, no HSTS" bash -c '
    grep -q "^:80 {$" "$1" && ! grep -q Strict-Transport "$1" && grep -q "tcp dport 80 accept" "$2" && ! grep -q 443 "$2"' _ "$R/etc/caddy/Caddyfile" "$R/etc/nftables.conf"
check "...no SSH onion: none in Tor's settings, and port 22 can't be closed" bash -c '
    ! grep -q "wren-ssh" "$1/etc/tor/torrc" && SSH_CONNECTION="1.2.3.4 5 6.7.8.9 22" WREN_VPS_ROOT="$1" WREN_VPS_FAKE="$2" bash "$3" --confirm >/dev/null 2>&1 &&
    ! SSH_CONNECTION="127.0.0.1 5 127.0.0.1 22" WREN_VPS_ROOT="$1" WREN_VPS_FAKE="$2" bash "$3" --ssh-onion-only >/dev/null 2>&1' _ "$R" "$T/calls" "$S"
check "...a client-less SSH onion is warned about" bash -c '
    rm -rf "$1/var/lib/wren-vps/rollback"; out=$(VPS_SSH_KEY="$4" VPS_ONION_SSH=yes WREN_VPS_ROOT="$1" WREN_VPS_FAKE="$2" bash "$3" --yes 2>&1); grep -q "works without a client key" <<<"$out"' _ "$R" "$T/calls" "$S" "$KEY"
check "...and a rerun replaces Wren Linux's block in torrc, never adds a second" test "$(grep -c '^# >>> Wren Linux setup-vps.sh >>>$' "$R/etc/tor/torrc")" = 1

# What it refuses, before it changes anything
for bad in "VPS_SSH_KEY=not-a-key" "VPS_ADMIN=root" "VPS_ADMIN=Bad_Name" "VPS_DOMAIN=not_a_domain" "VPS_ONION_SSH_CLIENT=short" "VPS_CONFIRM_MINUTES=0" "VPS_REBOOT_TIME=25:00" "VPS_ONION_SITE=maybe"; do
    fresh
    out=$(env VPS_SSH_KEY="$KEY" "$bad" WREN_VPS_ROOT="$R" WREN_VPS_FAKE="$T/calls" bash "$S" --yes 2>&1)
    check "$bad is refused, and nothing is installed" bash -c '[ ! -s "$1" ] && [ ! -e "$2/etc/ssh/sshd_config.d/10-wren-vps.conf" ]' _ "$T/calls" "$R"
done
fresh
check "no SSH key at all: refused (nothing to log in with)" not env WREN_VPS_ROOT="$R" WREN_VPS_FAKE="$T/calls" bash "$S" --yes
printf 'VPS_ADMIN=wren\nVPS_EVIL=1\n' >"$T/bad.conf"
check "a config file with an unknown setting: refused" not env WREN_VPS_ROOT="$R" WREN_VPS_FAKE="$T/calls" bash "$S" --config "$T/bad.conf" --yes
printf 'VPS_ADMIN=deploy\nVPS_SSH_KEY=%s\nVPS_ONION_SSH=no\n' "$KEY" >"$T/good.conf"
fresh
env WREN_VPS_ROOT="$R" WREN_VPS_FAKE="$T/calls" bash "$S" --config "$T/good.conf" --yes >/dev/null 2>&1
check "--config FILE: its settings are used (another user's name)" grep -qx "AllowUsers deploy" "$R/etc/ssh/sshd_config.d/10-wren-vps.conf"
# sudo clears SSH_CONNECTION: the login's origin is found above it instead
cat >"$T/session.sh" <<'EOF'
eval "$(sed -n '/^session() {/,/^}/p' "$1")"
unset SSH_CONNECTION
session
EOF
out=$(SSH_CONNECTION="127.0.0.1 40000 127.0.0.1 22" bash -c 'env -u SSH_CONNECTION bash "$1" "$2"; true' _ "$T/session.sh" "$S")
check "under sudo (SSH_CONNECTION cleared), the login's origin is found in the processes above" test "$out" = "127.0.0.1 40000 127.0.0.1 22"
out=$(env -u SSH_CONNECTION setsid bash "$T/session.sh" "$S" </dev/null)
check "...and with no SSH login above at all, it is the console" test "$out" = console
check "every question explains what it is for" bash -c '[ "$(grep -c "ask_value VPS_" "$1")" -ge 6 ] && grep -q "nobody can scan for it" "$1" && grep -q "no password can be guessed" "$1"' _ "$S"

[ "$fails" -eq 0 ]
