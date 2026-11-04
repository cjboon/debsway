#!/bin/bash
# setup-vps.sh: sets up a fresh Debian 13 VPS to serve Wren Linux's website
# (or any static site), the careful way, and can be run again to repair or
# change it. Copy it to the VPS and run it there as root:
#     scp tools/setup-vps.sh root@SERVER:   then   ssh -t root@SERVER bash setup-vps.sh
# It asks what it needs, explaining each choice, or takes it from a file of
# VAR=value lines (--config FILE; the variables are below). Afterwards it is
# installed as  wren-vps  (sudo wren-vps --confirm, --status, ...).
#
#  - You, not root: a user of yours (VPS_ADMIN) who logs in with your SSH key
#    only; sudo asks for that user's password (for the provider's web console,
#    the way in when SSH can't be used). No passwords and no root over SSH.
#  - A firewall (nftables) that lets in only SSH and the web, SSH slowed down
#    against guessing.
#  - The web: Caddy, serving plain files from /srv/wren-site, with HTTPS
#    certificates fetched and renewed by itself when there is a domain
#    (VPS_DOMAIN), strict security headers (no scripts, frames or outside
#    resources), and no log of visitors. Caddy runs locked down by systemd.
#  - Tor onion services: the site at an onion address (VPS_ONION_SITE), and
#    SSH at a second one (VPS_ONION_SSH), which only a key of yours can even
#    find (client authorization, VPS_ONION_SSH_CLIENT). Once that works,
#    wren-vps --ssh-onion-only closes port 22 to the internet.
#  - Debian's security updates every day, with a reboot at night when one
#    needs it; kernel and network hardening (sysctl).
#  - Never locked out: the SSH and firewall changes undo themselves after
#    VPS_CONFIRM_MINUTES unless you confirm them from a second, new login
#    (wren-vps --confirm), and at the next boot if the server restarts before
#    that. Keep the first session open until then.
#  - A read-only git mirror at /git/ (pushed by tools/publish-site.sh).
#
# Variables (asked when not set; --yes takes the defaults, and needs the key):
#   VPS_ADMIN             your user's name (wren)
#   VPS_SSH_KEY           your SSH public key: the line itself, or a file holding it
#   VPS_DOMAIN            the site's domain, e.g. wrenlinux.org (none: no HTTPS
#                         yet, the site on plain http, for a test VM)
#   VPS_EMAIL             for the HTTPS certificate's notices (optional)
#   VPS_ONION_SITE        yes or no (yes)
#   VPS_ONION_SSH         yes or no (yes)
#   VPS_ONION_SSH_CLIENT  the public key from tools/vps-client.sh keygen (optional:
#                         without it, anyone who learns the onion address can reach SSH)
#   VPS_CONFIRM_MINUTES   how long a change waits for --confirm (10)
#   VPS_REBOOT_TIME       when to reboot after an update that needs it (04:00)
# Usage: bash setup-vps.sh [--config FILE] [--yes]
#        wren-vps --confirm | --ssh-onion-only | --ssh-public | --status
set -euo pipefail
umask 022

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# (a test points these at a folder and a log: nothing is run, only written down)
ROOT=${WREN_VPS_ROOT:-}
FAKE=${WREN_VPS_FAKE:-}
run() {
    if [ -n "$FAKE" ]; then echo "$*" >>"$FAKE"; return 0; fi
    "$@"
}
CONF=$ROOT/etc/wren-vps.conf
STATE=$ROOT/var/lib/wren-vps
BACKUP=$STATE/rollback
SSHD_DROP=$ROOT/etc/ssh/sshd_config.d/10-wren-vps.conf
NFT=$ROOT/etc/nftables.conf
TORRC=$ROOT/etc/tor/torrc
CADDYFILE=$ROOT/etc/caddy/Caddyfile
SITE=/srv/wren-site
GITDIR=/srv/wren-git
SELF=/usr/local/sbin/wren-vps
ROLLBACK=/usr/local/sbin/wren-vps-rollback
BOOT_UNIT=$ROOT/etc/systemd/system/wren-vps-undo-unconfirmed.service

[ -n "$FAKE" ] || [ "$(id -u)" -eq 0 ] || die "run it as root (sudo bash $0)."

# ---- questions: from the environment, the config file, or asked ----
interactive() { [ -z "${WREN_VPS_YES:-}" ] && { : </dev/tty; } 2>/dev/null; }
# ask_value VAR DEFAULT "Question" EXPLANATION...: keeps VAR when it is set
ask_value() {
    local var=$1 def=$2 q=$3 a
    shift 3
    if [ -n "${!var:-}" ]; then return 0; fi
    if interactive; then
        echo
        for line in "$@"; do note "$line"; done
        IFS= read -r -p "    $q${def:+ [$def]}: " a </dev/tty || a=
        printf -v "$var" '%s' "${a:-$def}"
    else
        printf -v "$var" '%s' "$def"
    fi
}
yes_no() { case ${!1:-} in yes | no) ;; y | Y) printf -v "$1" yes ;; n | N) printf -v "$1" no ;; *) die "$1 is yes or no, not \"${!1:-}\"." ;; esac; }

load_config() {
    local f=$1 k v
    [ -f "$f" ] || die "no config file $f."
    while IFS='=' read -r k v; do
        case $k in
            '' | \#*) continue ;;
            VPS_ADMIN | VPS_SSH_KEY | VPS_DOMAIN | VPS_EMAIL | VPS_ONION_SITE | VPS_ONION_SSH | VPS_ONION_SSH_CLIENT | VPS_CONFIRM_MINUTES | VPS_REBOOT_TIME | VPS_SSH_PUBLIC)
                # set in the environment: that wins
                if [ -z "${!k:-}" ]; then v=${v%\"}; v=${v#\"}; printf -v "$k" '%s' "$v"; fi ;;
            *) die "$f: unknown setting \"$k\"." ;;
        esac
    done <"$f"
}

questions() {
    ask_value VPS_ADMIN wren "Your user's name on the server" \
        "You log in as a user of your own, never as root: root can't log in over SSH at all." \
        "sudo asks for this user's password; keep it in your password manager."
    [[ $VPS_ADMIN =~ ^[a-z][a-z0-9-]{0,30}$ ]] && [ "$VPS_ADMIN" != root ] ||
        die "\"$VPS_ADMIN\" can't be the user's name: small letters, digits and dashes, a letter first."

    ask_value VPS_SSH_KEY "" "Your SSH public key (the line from ~/.ssh/KEY.pub, or a file holding it)" \
        "Logging in takes this key and nothing else: no password can be guessed, because none is accepted." \
        "Make one on your own computer: ssh-keygen -t ed25519 -f ~/.ssh/wren-vps  (then paste ~/.ssh/wren-vps.pub)"
    if [ -f "$VPS_SSH_KEY" ]; then VPS_SSH_KEY=$(head -n1 "$VPS_SSH_KEY"); fi
    [[ $VPS_SSH_KEY =~ ^(ssh-ed25519|sk-ssh-ed25519@openssh\.com|ecdsa-sha2-nistp(256|384|521)|ssh-rsa)\ [A-Za-z0-9+/]+={0,2}(\ [[:print:]]*)?$ ]] ||
        die "That isn't an SSH public key (it starts with ssh-ed25519 ...). Nothing was changed."

    ask_value VPS_DOMAIN "" "The site's domain, e.g. wrenlinux.org (Enter: none yet)" \
        "With a domain, the site gets HTTPS: Caddy fetches the certificate itself and renews it." \
        "Point the domain's A (and AAAA) record at this server first. Without one, the site is" \
        "served on plain http: fine for a test VM, not for the public."
    VPS_DOMAIN=${VPS_DOMAIN,,}
    [ -z "$VPS_DOMAIN" ] || [[ $VPS_DOMAIN =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]] ||
        die "\"$VPS_DOMAIN\" isn't a domain name."
    if [ -n "$VPS_DOMAIN" ]; then
        ask_value VPS_EMAIL "" "An email for the certificate's notices (Enter: none)" \
            "Let's Encrypt writes here only if a certificate is about to run out. It isn't shown on the site."
        [ -z "${VPS_EMAIL:-}" ] || [[ $VPS_EMAIL =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || die "\"$VPS_EMAIL\" isn't an email address."
    fi

    ask_value VPS_ONION_SITE yes "The site at an onion address too? (yes/no)" \
        "Tor Browser visitors then reach it without leaving Tor: nobody on the way, not even" \
        "an exit relay, sees what they read. It hides the reader, not this server: the" \
        "server's address is public anyway, because the site is on the normal web too."
    yes_no VPS_ONION_SITE
    ask_value VPS_ONION_SSH yes "SSH at an onion address of its own? (yes/no)" \
        "You then log in through Tor. Once that works, port 22 can close to the whole" \
        "internet: nobody can scan for it or guess at it, and the server's logs never see" \
        "your home address. The provider's web console stays your way in if Tor is down."
    yes_no VPS_ONION_SSH
    if [ "$VPS_ONION_SSH" = yes ]; then
        ask_value VPS_ONION_SSH_CLIENT "" "Your onion client key (from: bash tools/vps-client.sh keygen; Enter: none)" \
            "With it, the SSH onion address is useless to anyone without your key file: they can't" \
            "even tell it exists. Without it, anyone who learns the address reaches SSH (which" \
            "still takes your SSH key). Strongly recommended."
        [ -z "$VPS_ONION_SSH_CLIENT" ] || [[ $VPS_ONION_SSH_CLIENT =~ ^[A-Z2-7]{52}$ ]] ||
            die "That isn't an onion client key (52 capital letters and digits 2-7)."
    fi
    VPS_CONFIRM_MINUTES=${VPS_CONFIRM_MINUTES:-10}
    [[ $VPS_CONFIRM_MINUTES =~ ^[1-9][0-9]?$ ]] || die "VPS_CONFIRM_MINUTES is 1 to 99."
    VPS_REBOOT_TIME=${VPS_REBOOT_TIME:-04:00}
    [[ $VPS_REBOOT_TIME =~ ^([01][0-9]|2[0-3]):[0-5][0-9]$ ]] || die "VPS_REBOOT_TIME is HH:MM."
    # Port 22 on the internet: open until --ssh-onion-only closes it
    VPS_SSH_PUBLIC=${VPS_SSH_PUBLIC:-yes}
    yes_no VPS_SSH_PUBLIC
    [ "$VPS_ONION_SSH" = yes ] || VPS_SSH_PUBLIC=yes
}

save_config() {
    mkdir -p "${CONF%/*}"
    (umask 077 && printf '# Written by setup-vps.sh (Wren Linux); run it again after a change\nVPS_ADMIN=%s\nVPS_SSH_KEY=%s\nVPS_DOMAIN=%s\nVPS_EMAIL=%s\nVPS_ONION_SITE=%s\nVPS_ONION_SSH=%s\nVPS_ONION_SSH_CLIENT=%s\nVPS_CONFIRM_MINUTES=%s\nVPS_REBOOT_TIME=%s\nVPS_SSH_PUBLIC=%s\n' \
        "$VPS_ADMIN" "$VPS_SSH_KEY" "$VPS_DOMAIN" "${VPS_EMAIL:-}" "$VPS_ONION_SITE" "$VPS_ONION_SSH" "${VPS_ONION_SSH_CLIENT:-}" \
        "$VPS_CONFIRM_MINUTES" "$VPS_REBOOT_TIME" "$VPS_SSH_PUBLIC" >"$CONF")
}

# ---- the files it writes ----
write_file() { # PATH MODE: stdin into PATH, made whole first (never half written)
    mkdir -p "$(dirname "$1")"
    cat >"$1.wren-new"
    chmod "$2" "$1.wren-new"
    mv "$1.wren-new" "$1"
}

sshd_conf() {
    cat <<EOF
# Written by Wren Linux setup-vps.sh. Read before the other files here, so
# what it says wins (sshd takes the first value it finds).
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
AllowUsers $VPS_ADMIN
X11Forwarding no
AllowAgentForwarding no
AllowTcpForwarding no
PermitTunnel no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
EOF
}

nft_conf() {
    local web=''
    [ -z "$VPS_DOMAIN" ] || web='tcp dport { 80, 443 } accept
        udp dport 443 accept'
    [ -n "$VPS_DOMAIN" ] || web='tcp dport 80 accept'
    cat <<EOF
#!/usr/sbin/nft -f
# Written by Wren Linux setup-vps.sh: nothing comes in but what is listed.
flush ruleset

table inet wren_vps {
    chain input {
        type filter hook input priority 0; policy drop;
        iif "lo" accept
        ct state established,related accept
        ct state invalid drop
        # what IPv6 needs to work at all, and ping (limited)
        meta l4proto ipv6-icmp accept
        icmp type { echo-request, destination-unreachable, time-exceeded, parameter-problem } limit rate 10/second accept
$(if [ "$VPS_SSH_PUBLIC" = yes ]; then printf '        # SSH, new connections slowed down against guessing\n        tcp dport 22 ct state new limit rate 10/minute burst 5 packets accept\n'; else printf '        # SSH only through its onion address (port 22 closed: wren-vps --ssh-public opens it)\n'; fi)
        # the web
        $web
    }
    chain forward {
        type filter hook forward priority 0; policy drop;
    }
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF
}

caddy_conf() {
    local onion=$1
    cat <<EOF
# Written by Wren Linux setup-vps.sh. No log of visitors is kept (no "log").
{
    admin off
$( [ -z "${VPS_EMAIL:-}" ] || printf '    email %s\n' "$VPS_EMAIL")
}

(wren_headers) {
    header {
        Content-Security-Policy "default-src 'none'; style-src 'self'; img-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
        X-Content-Type-Options nosniff
        X-Frame-Options DENY
        Referrer-Policy no-referrer
        Cross-Origin-Opener-Policy same-origin
        Permissions-Policy "camera=(), microphone=(), geolocation=(), interest-cohort=()"
        -Server
    }
}
(wren_files) {
    import wren_headers
    handle_path /git/* {
        root * $GITDIR
        file_server
    }
    handle {
        root * $SITE
        file_server
    }
}

EOF
    if [ -n "$VPS_DOMAIN" ]; then
        cat <<EOF
$VPS_DOMAIN {
    import wren_files
    header Strict-Transport-Security "max-age=31536000"
$( [ -z "$onion" ] || printf '    header Onion-Location "http://%s{uri}"\n' "$onion")
}
www.$VPS_DOMAIN {
    redir https://$VPS_DOMAIN{uri} permanent
}
EOF
    else
        cat <<'EOF'
# No domain yet: plain http, for a test VM
:80 {
    import wren_files
}
EOF
    fi
    if [ "$VPS_ONION_SITE" = yes ]; then
        cat <<'EOF'
# The onion site: Tor brings visitors here (Tor's own encryption, so http)
http://127.0.0.1:8080 {
    bind 127.0.0.1
    import wren_files
}
EOF
    fi
}

caddy_hardening() {
    cat <<'EOF'
# Written by Wren Linux setup-vps.sh: Caddy may read the site, bind the web
# ports and keep its certificates, and nothing more.
[Service]
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=/var/lib/caddy
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
RestrictSUIDSGID=yes
RestrictNamespaces=yes
RestrictRealtime=yes
LockPersonality=yes
SystemCallArchitectures=native
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
EOF
}

tor_block() {
    echo '# >>> Wren Linux setup-vps.sh >>>'
    echo '# Onion services only: this tor is no relay and no proxy for anyone'
    echo 'SocksPort 0'
    if [ "$VPS_ONION_SITE" = yes ]; then
        echo 'HiddenServiceDir /var/lib/tor/wren-site/'
        echo 'HiddenServicePort 80 127.0.0.1:8080'
    fi
    if [ "$VPS_ONION_SSH" = yes ]; then
        echo 'HiddenServiceDir /var/lib/tor/wren-ssh/'
        echo 'HiddenServicePort 22 127.0.0.1:22'
    fi
    echo '# <<< Wren Linux setup-vps.sh <<<'
}

sysctl_conf() {
    cat <<'EOF'
# Written by Wren Linux setup-vps.sh
kernel.kptr_restrict = 2
kernel.dmesg_restrict = 1
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2
kernel.yama.ptrace_scope = 1
fs.protected_symlinks = 1
fs.protected_hardlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
EOF
}

upgrades_conf() {
    cat <<EOF
// Written by Wren Linux setup-vps.sh: Debian's security updates every day,
// and a reboot at $VPS_REBOOT_TIME when one needs it
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "$VPS_REBOOT_TIME";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
}

rollback_script() {
    cat <<EOF
#!/bin/sh
# Written by Wren Linux setup-vps.sh: puts the SSH and firewall settings back
# as they were, when a change wasn't confirmed in time (wren-vps --confirm).
B=/var/lib/wren-vps/rollback
[ -d "\$B" ] || exit 0
for f in sshd nft; do
    case \$f in sshd) dest=/etc/ssh/sshd_config.d/10-wren-vps.conf ;; nft) dest=/etc/nftables.conf ;; esac
    if [ -f "\$B/\$f.absent" ]; then rm -f "\$dest"; elif [ -f "\$B/\$f" ]; then cp -p "\$B/\$f" "\$dest"; fi
done
systemctl reload ssh || systemctl restart ssh
if [ -f /etc/nftables.conf ]; then nft -f /etc/nftables.conf; else nft flush ruleset; fi
rm -rf "\$B"
logger -t wren-vps "SSH and firewall changes rolled back: they weren't confirmed in time"
EOF
}

# The timer that undoes a change doesn't survive a restart: someone locked out
# who restarts the server from the provider's console would keep the change.
# This undoes it at the next boot instead, while it is still unconfirmed.
boot_unit() {
    cat <<EOF
# Written by Wren Linux setup-vps.sh: an SSH or firewall change that wasn't
# confirmed (wren-vps --confirm) before a restart is undone at the next boot.
[Unit]
Description=Wren Linux: undo an SSH or firewall change that wasn't confirmed
ConditionPathExists=/var/lib/wren-vps/rollback
After=ssh.service nftables.service

[Service]
Type=oneshot
ExecStart=$ROLLBACK

[Install]
WantedBy=multi-user.target
EOF
}

# ---- the never-locked-out switch ----
armed() { [ -d "$BACKUP" ]; }
# session: where this login came from ("CLIENT PORT SERVER PORT"), or console.
# sudo clears SSH_CONNECTION, so it is looked up in the processes above this
# one, up to the SSH session that started them (root may read their settings).
session() {
    if [ -n "${SSH_CONNECTION:-}" ]; then echo "$SSH_CONNECTION"; return; fi
    local pid=$$ found
    while [ "${pid:-1}" -gt 1 ]; do
        found=$(tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | sed -n 's/^SSH_CONNECTION=//p' | head -n1)
        if [ -n "$found" ]; then echo "$found"; return; fi
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    done
    echo console
}
# arm: keeps the SSH and firewall files as they are now, and undoes the change
# in VPS_CONFIRM_MINUTES unless it is confirmed
arm() {
    armed && die "A change is still waiting to be confirmed: wren-vps --confirm (from a new login), or wait for it to undo itself."
    mkdir -p "$BACKUP"
    if [ -f "$SSHD_DROP" ]; then cp -p "$SSHD_DROP" "$BACKUP/sshd"; else : >"$BACKUP/sshd.absent"; fi
    if [ -f "$NFT" ]; then cp -p "$NFT" "$BACKUP/nft"; else : >"$BACKUP/nft.absent"; fi
    session >"$BACKUP/session"
    run systemd-run --quiet --unit=wren-vps-rollback --on-active="${VPS_CONFIRM_MINUTES}min" --timer-property=AccuracySec=5s "$ROLLBACK"
}
apply_ssh_firewall() {
    sshd_conf | write_file "$SSHD_DROP" 0644
    nft_conf | write_file "$NFT" 0755
    if [ -z "$FAKE" ]; then
        sshd -t || { "$ROLLBACK"; die "sshd refused the new settings; they were put back."; }
        # what sshd will really do, other files of the image included
        local eff
        eff=$(sshd -T -C user="$VPS_ADMIN",host=x,addr=203.0.113.1 2>/dev/null) || eff=
        grep -qx 'passwordauthentication no' <<<"$eff" && grep -qx 'permitrootlogin no' <<<"$eff" ||
            { "$ROLLBACK"; die "Another sshd setting still lets passwords or root in; nothing was changed. Look at: sshd -T"; }
        nft -c -f "$NFT" || { "$ROLLBACK"; die "nft refused the firewall; it was put back."; }
    fi
    run systemctl reload ssh
    run systemctl enable --now nftables
    run nft -f /etc/nftables.conf
}
confirm_hint() {
    note "These undo themselves in $VPS_CONFIRM_MINUTES minutes unless you confirm. Keep this session open, and"
    note "from a second, NEW terminal log in again ($1), then run:"
    note "  sudo wren-vps --confirm"
    note "If that login fails, do nothing: the old settings come back by themselves."
}

confirm() {
    armed || { note "Nothing is waiting to be confirmed."; exit 0; }
    local made_in now
    made_in=$(cat "$BACKUP/session" 2>/dev/null || true)
    now=$(session)
    if [ "$now" = console ]; then
        warn "Confirming from the console: that doesn't show SSH still lets you in. Try a new SSH login before you log out."
    elif [ "$made_in" = "$now" ]; then
        die "This is the session that made the change. Confirm from a NEW login: that proves you can still get in."
    fi
    run systemctl stop wren-vps-rollback.timer
    rm -rf "$BACKUP"
    say "Confirmed: the new SSH and firewall settings stay."
}

# ---- what it does ----
user_exists() { if [ -n "$FAKE" ]; then grep -q "^$1:" "$ROOT/etc/passwd" 2>/dev/null; else id "$1" >/dev/null 2>&1; fi; }
onion_of() { # NAME: the onion address tor made for it (it takes a moment)
    local f=$ROOT/var/lib/tor/$1/hostname i
    for i in $(seq 1 60); do
        if [ -s "$f" ]; then
            local h
            h=$(head -n1 "$f")
            [[ $h =~ ^[a-z2-7]{56}\.onion$ ]] && { echo "$h"; return 0; }
        fi
        [ -n "$FAKE" ] || sleep 1
    done
    return 1
}

setup() {
    say "Wren Linux VPS setup"
    if [ -z "$FAKE" ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        [ "${VERSION_CODENAME:-}" = trixie ] || warn "This is made for Debian 13 (trixie); this is ${PRETTY_NAME:-unknown}."
    fi
    armed && die "A change is still waiting to be confirmed: wren-vps --confirm (from a new login), or wait ${VPS_CONFIRM_MINUTES:-10} minutes."
    if [ -f "$CONF" ]; then load_config "$CONF"; note "Using what you chose before ($CONF); edit it and run this again to change it."; fi
    questions
    save_config

    say "Packages"
    run apt-get update -q
    run env DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends \
        nftables tor caddy unattended-upgrades needrestart sudo openssh-server rsync git ca-certificates

    say "Your user, $VPS_ADMIN"
    if ! user_exists "$VPS_ADMIN"; then
        run useradd --create-home --shell /bin/bash --groups sudo "$VPS_ADMIN"
    else
        run usermod -aG sudo "$VPS_ADMIN"
    fi
    local home=$ROOT/home/$VPS_ADMIN
    mkdir -p "$home/.ssh"
    printf '%s\n' "$VPS_SSH_KEY" | write_file "$home/.ssh/authorized_keys" 0600
    chmod 0700 "$home/.ssh"
    run chown -R "$VPS_ADMIN:$VPS_ADMIN" "/home/$VPS_ADMIN/.ssh"
    if [ -z "$FAKE" ] && passwd -S "$VPS_ADMIN" 2>/dev/null | awk '{ exit ($2 == "P") }'; then
        note "sudo, and the provider's web console, need a password for $VPS_ADMIN. SSH never takes it."
        if interactive; then
            passwd "$VPS_ADMIN" </dev/tty || warn "No password was set: set one with  passwd $VPS_ADMIN  before you log out."
        else
            warn "Set one before you log out:  passwd $VPS_ADMIN"
        fi
    fi

    say "Security updates, and hardening"
    upgrades_conf | write_file "$ROOT/etc/apt/apt.conf.d/52wren-vps" 0644
    sysctl_conf | write_file "$ROOT/etc/sysctl.d/60-wren-vps.conf" 0644
    run sysctl --system --quiet
    # restart services after an update by itself (no one is there to answer)
    # shellcheck disable=SC2016  # needrestart's own Perl variable
    printf '# Written by Wren Linux setup-vps.sh\n$nrconf{restart} = '"'"'a'"'"';\n' | write_file "$ROOT/etc/needrestart/conf.d/60-wren-vps.conf" 0644
    run systemctl enable --now unattended-upgrades

    say "Tor onion services"
    local onion_site='' onion_ssh=''
    if [ "$VPS_ONION_SITE" = yes ] || [ "$VPS_ONION_SSH" = yes ]; then
        local block
        block=$(tor_block)
        [ -f "$TORRC" ] || : | write_file "$TORRC" 0644
        { sed '/^# >>> Wren Linux setup-vps.sh >>>$/,/^# <<< Wren Linux setup-vps.sh <<<$/d' "$TORRC"; printf '%s\n' "$block"; } | write_file "$TORRC" 0644
        if [ "$VPS_ONION_SSH" = yes ]; then
            local auth=$ROOT/var/lib/tor/wren-ssh/authorized_clients
            mkdir -p "$auth"
            rm -f "$auth"/*.auth
            if [ -n "${VPS_ONION_SSH_CLIENT:-}" ]; then
                printf 'descriptor:x25519:%s\n' "$VPS_ONION_SSH_CLIENT" | write_file "$auth/$VPS_ADMIN.auth" 0600
            else
                warn "The SSH onion address works without a client key: anyone who learns it reaches SSH (your SSH key is still needed)."
            fi
            run chown -R debian-tor:debian-tor /var/lib/tor/wren-ssh
            run chmod 0700 /var/lib/tor/wren-ssh /var/lib/tor/wren-ssh/authorized_clients
        fi
        run systemctl enable tor
        run systemctl restart tor
        if [ "$VPS_ONION_SITE" = yes ]; then onion_site=$(onion_of wren-site) || warn "Tor hasn't made the site's onion address yet; run this again in a minute."; fi
        if [ "$VPS_ONION_SSH" = yes ]; then onion_ssh=$(onion_of wren-ssh) || warn "Tor hasn't made the SSH onion address yet; run this again in a minute."; fi
    else
        [ ! -f "$TORRC" ] || sed '/^# >>> Wren Linux setup-vps.sh >>>$/,/^# <<< Wren Linux setup-vps.sh <<<$/d' "$TORRC" | write_file "$TORRC" 0644
    fi

    say "The web server (Caddy)"
    mkdir -p "$ROOT$SITE" "$ROOT$GITDIR"
    if [ ! -e "$ROOT$SITE/index.html" ]; then
        printf '<!doctype html>\n<meta charset="utf-8">\n<title>Soon</title>\n<p>Soon.</p>\n' | write_file "$ROOT$SITE/index.html" 0644
    fi
    run chown "$VPS_ADMIN:$VPS_ADMIN" "$SITE" "$GITDIR"
    if [ ! -d "$ROOT$GITDIR/wren-linux.git" ]; then
        run sudo -u "$VPS_ADMIN" git init -q --bare "$GITDIR/wren-linux.git"
        # what a plain web server needs to serve it, kept up to date at every push
        run sudo -u "$VPS_ADMIN" cp "$GITDIR/wren-linux.git/hooks/post-update.sample" "$GITDIR/wren-linux.git/hooks/post-update"
    fi
    caddy_conf "$onion_site" | write_file "$CADDYFILE" 0644
    caddy_hardening | write_file "$ROOT/etc/systemd/system/caddy.service.d/60-wren-vps.conf" 0644
    if [ -z "$FAKE" ]; then caddy validate --adapter caddyfile --config "$CADDYFILE" >/dev/null || die "Caddy refused its settings ($CADDYFILE)."; fi
    run systemctl daemon-reload
    run systemctl enable caddy
    run systemctl restart caddy

    say "SSH and the firewall"
    rollback_script | write_file "$ROOT$ROLLBACK" 0755
    boot_unit | write_file "$BOOT_UNIT" 0644
    run systemctl daemon-reload
    run systemctl enable wren-vps-undo-unconfirmed.service
    # this script, as the wren-vps command
    if [ -f "$0" ]; then install -D -m 0755 "$0" "$ROOT$SELF"; fi
    arm
    apply_ssh_firewall
    note "SSH: your key only, as $VPS_ADMIN; no root, no passwords. Firewall: SSH$([ "$VPS_SSH_PUBLIC" = yes ] || echo ' (onion only)') and the web."
    confirm_hint "ssh $VPS_ADMIN@THIS-SERVER"

    say "Done"
    [ -z "$VPS_DOMAIN" ] || note "Site: https://$VPS_DOMAIN  (its DNS: A/AAAA to this server; add a CAA record for letsencrypt.org, and DNSSEC at your registrar)"
    [ -n "$VPS_DOMAIN" ] || note "Site: http://THIS-SERVER  (no domain yet: plain http)"
    [ -z "$onion_site" ] || note "Onion site: http://$onion_site"
    if [ -n "$onion_ssh" ]; then
        note "Onion SSH: $onion_ssh"
        note "  On your computer: bash tools/vps-client.sh ssh-config $VPS_ADMIN $onion_ssh"
        note "  Once logging in through it works: sudo wren-vps --ssh-onion-only (closes port 22 to the internet)"
    fi
    note "Publish the site: bash tools/publish-site.sh (on your computer)"
}

ssh_public() { # yes | no: port 22 open to the internet or not
    [ -f "$CONF" ] || die "Run the setup first (bash setup-vps.sh)."
    load_config "$CONF"
    questions
    if [ "$1" = no ]; then
        [ "$VPS_ONION_SSH" = yes ] || die "SSH has no onion address here (VPS_ONION_SSH=no): closing port 22 would lock you out."
        # only from a login that came through the onion: proof that it works
        case $(session) in
            "127.0.0.1 "* | "::1 "*) ;;
            *) die "Run this from a login through the SSH onion address (it comes from 127.0.0.1), so you know that way works." ;;
        esac
    fi
    VPS_SSH_PUBLIC=$1
    save_config
    arm
    apply_ssh_firewall
    if [ "$1" = no ]; then
        say "Port 22 is closed to the internet; SSH only through its onion address."
        confirm_hint "through the onion address"
    else
        say "Port 22 is open to the internet again (keys only, slowed down)."
        confirm_hint "ssh $VPS_ADMIN@THIS-SERVER"
    fi
}

status() {
    [ -f "$CONF" ] && load_config "$CONF" || die "Not set up yet: bash setup-vps.sh"
    echo "User: $VPS_ADMIN   Domain: ${VPS_DOMAIN:-none}   Port 22 on the internet: $VPS_SSH_PUBLIC"
    [ ! -s "$ROOT/var/lib/tor/wren-site/hostname" ] || echo "Onion site: $(head -n1 "$ROOT/var/lib/tor/wren-site/hostname")"
    [ ! -s "$ROOT/var/lib/tor/wren-ssh/hostname" ] || echo "Onion SSH: $(head -n1 "$ROOT/var/lib/tor/wren-ssh/hostname")"
    if armed; then echo "A change is waiting to be confirmed (wren-vps --confirm, from a new login)."; fi
}

case ${1:-} in
    --config) [ -n "${2:-}" ] || die "--config needs a file."; load_config "$2"; shift 2; [ "${1:-}" != --yes ] || WREN_VPS_YES=1; setup ;;
    --yes) WREN_VPS_YES=1; [ "${2:-}" != --config ] || load_config "${3:?--config needs a file}"; setup ;;
    "") setup ;;
    --confirm) confirm ;;
    --ssh-onion-only) ssh_public no ;;
    --ssh-public) ssh_public yes ;;
    --status) status ;;
    -h | --help) sed -n '2,/^set -euo/{ /^set -euo/d; s/^# \{0,1\}//; p }' "$0" ;;
    *) die "unknown option \"$1\" (--help)." ;;
esac
