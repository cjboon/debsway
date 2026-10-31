#!/bin/bash
# Checks extras/onion-site.sh's pieces without a VM: the onion-site command and
# its session (with a pretend sudo, id, mockvps-kvm and ssh), mockvps-kvm's
# no-network options (QEMU's command line, and that bad values are refused),
# Tor's settings, the firewall rule and the VM's provisioning script. No user is
# made and nothing outside a temp folder changes. Run by test.sh, or:
#   bash tools/test-onion-site.sh
# shellcheck disable=SC2016  # the inner bash expands its own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

# ---- the onion-site command, with a pretend sudo ----
mkdir -p "$T/fake" "$T/home"
# "-l" says whether the rule exists ($T/rule); else it writes down the call and
# keeps what came on standard input (an upload's tar stream)
cat >"$T/fake/sudo" <<EOF
#!/bin/sh
case "\$*" in *" -l "*) [ -e "$T/rule" ] ;; *) echo "sudo \$*" >>"$T/calls"; cat >"$T/stdin" ;; esac
EOF
chmod +x "$T/fake/sudo"
os() { PATH="$T/fake:$PATH" HOME="$T/home" XDG_STATE_HOME="$T/state" bash "$HERE/bin/onion-site" "$@"; }
out=$(os start 2>&1) && unset_ok=false || unset_ok=true
check "it says how to set it up when it isn't" bash -c '$1 && grep -q "extras/onion-site.sh" <<<"$2"' _ "$unset_ok" "$out"
touch "$T/rule"
check "an unknown command is refused" not os bogus
check "upload needs static or app" not os upload elsewhere "$T"
check "upload needs a folder that is there" not os upload static "$T/nothing"
check "nothing was started by those" test ! -e "$T/calls"
os start </dev/null
check "start runs the session's start, as onion-site" \
    grep -qx "sudo -n -u onion-site /usr/local/libexec/onion-site-session start" "$T/calls"
mkdir -p "$T/site/css"
echo hello >"$T/site/index.html"
echo body >"$T/site/css/a.css"
: >"$T/calls"
os upload static "$T/site"
check "upload hands the session a tar of the folder" \
    grep -qx "sudo -n -u onion-site /usr/local/libexec/onion-site-session upload static" "$T/calls"
check "...with the folder's files in it" bash -c 'tar -tf "$1" | grep -qx "./css/a.css"' _ "$T/stdin"
check "...owned by nobody of yours" bash -c '! tar -tvf "$1" | grep -v " root/root "' _ "$T/stdin"
check "address says so when there is none" not os address
mkdir -p "$T/state/debsway"
echo "abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrstuv.onion" >"$T/state/debsway/onion-site-address"
check "address prints the saved address" grep -q '\.onion$' <<<"$(os address)"

# ---- the session, as the onion-site user ----
# Its fixed paths are pointed into $T in a copy (the real script has no way to
# change them), with pretend id, mockvps-kvm and ssh that write down how they were
# run (mockvps also the environment that matters here)
S=$T/session
mkdir -p "$S/home/vm" "$S/home/.config/onion-site" "$S/bin"
sed -e "s|/home/onion-site|$S/home|g" \
    -e "s|/usr/local/libexec/onion-site-mockvps-kvm|$S/bin/mockvps|" \
    -e "s|^export PATH=.*|export PATH=$S/bin:\$PATH|" \
    "$HERE/bin/onion-site-session" >"$S/onion-site-session"
printf '#!/bin/sh\n[ "$1" = -un ] && echo onion-site || exec /usr/bin/id "$@"\n' >"$S/bin/id"
cat >"$S/bin/mockvps" <<EOF
#!/bin/sh
echo "mockvps \$* restrict=\${NET_RESTRICT:-} fwd=\${HOST_FORWARDS:-} socks=\${GUEST_SOCKS:-} prov=\${PROVISION_FILES:+yes}" >>"$S/calls"
case "\$1" in
    --status) [ -e "$S/running" ] && echo "VM 'onion-site' is Running" || echo "VM 'onion-site' is not running" ;;
    --start) [ -n "\${GUEST_SOCKS:-}" ] && [ -e "$S/update-fails" ] && exit 1 ;;
esac
exit 0
EOF
printf '#!/bin/sh\necho "ssh $*" >>"%s/calls"\ncat >"%s/ssh-stdin"\n' "$S" "$S" >"$S/bin/ssh"
chmod +x "$S/bin/id" "$S/bin/mockvps" "$S/bin/ssh"
touch "$S/home/.config/onion-site/provision.sh"
session() { PATH="$S/bin:$PATH" DEBSWAY_NOABS=1 bash "$S/onion-site-session" "$@"; }
starts() { grep '^mockvps --start' "$S/calls"; }

check "the session refuses anyone but the onion-site user" not bash "$HERE/bin/onion-site-session" start
: >"$S/calls"
session install >/dev/null 2>&1
check "install builds the VM (with the network the installer needs)" \
    grep -q '^mockvps --yes restrict= fwd= socks= prov=yes' "$S/calls"
check "...then starts it with no network, only the site's port forwarded" \
    test "$(starts | tail -1)" = "mockvps --start restrict=1 fwd=127.0.0.1:18080:80 socks= prov="
echo disk >"$S/home/vm/onion-site.qcow2"
: >"$S/calls"
out=$(session install 2>&1)
check "install never replaces a VM that is already built" not grep -q -- '--yes' "$S/calls"
check "...and says rebuild is for that" grep -q 'onion-site rebuild' <<<"$out"
: >"$S/calls"
session start >/dev/null 2>&1
check "start: no network, the site's port only" test "$(starts)" = "mockvps --start restrict=1 fwd=127.0.0.1:18080:80 socks= prov="
touch "$S/running"
: >"$S/calls"
session update >/dev/null 2>&1
check "update lends the VM Tor's SOCKS port, and runs the upgrade as root" \
    grep -q "restrict=1 fwd=127.0.0.1:18080:80 socks=10.0.2.100:9050 prov=yes" <<<"$(starts | head -1)"
check "...then starts it again without that" test "$(starts | tail -1)" = "mockvps --start restrict=1 fwd=127.0.0.1:18080:80 socks= prov="
touch "$S/update-fails"
: >"$S/calls"
check "a failed update says so" not session update
check "...and still leaves it running without the relay to Tor" test "$(starts | tail -1)" = "mockvps --start restrict=1 fwd=127.0.0.1:18080:80 socks= prov="
rm -f "$S/update-fails"
check "upload refuses anything but static or app" not session upload ../etc
: >"$S/calls"
echo stream | session upload app >/dev/null 2>&1
check "upload unpacks the stream into /srv/site/app in the VM" \
    bash -c 'grep -q "^ssh .*tar -x --no-same-owner" "$1" && grep -q "mv \"\$new\" /srv/site/app$" "$1"' _ "$S/calls"
check "...restarting the Python app if there is one" grep -q 'systemctl restart site-app.service' "$S/calls"
check "...with the stream passed through" grep -qx stream "$S/ssh-stdin"

# ---- mockvps-kvm's no-network options ----
M=$HERE/vendor/mockvps-kvm/mockvps-kvm.sh
nic() { # PHASE: the -nic value define_cmd builds, with this environment
    bash -c '. "$1"; init_defaults; VWANT_BIN=qemu DISK=d BOOT_DIR=b MONITOR_SOCK=m PIDFILE=p
        define_cmd "$2" log; for i in "${!QQA[@]}"; do [ "${QQA[i]}" != -nic ] || echo "${QQA[i + 1]}"; done' _ "$M" "$1"
}
out=$(NET_RESTRICT=1 HOST_FORWARDS=127.0.0.1:18080:80 GUEST_SOCKS=10.0.2.100:9050 nic run)
check "mockvps: NET_RESTRICT=1 gives QEMU restrict=on" grep -q ',restrict=on' <<<"$out"
check "mockvps: the site's port is forwarded from host loopback only" grep -q ',hostfwd=tcp:127.0.0.1:18080-:80' <<<"$out"
check "mockvps: GUEST_SOCKS relays one address to Tor's SOCKS port, per connection" \
    grep -q ',guestfwd=tcp:10.0.2.100:9050-cmd:socat - TCP:127.0.0.1:9050' <<<"$out"
out=$(NET_RESTRICT=1 HOST_FORWARDS=127.0.0.1:18080:80 nic install)
check "mockvps: the install phase isn't changed by them" test "$out" = "user,model=virtio-net-pci"
check "mockvps: without them nothing changes" test "$(nic run)" = "user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2232-:22"
for bad in "NET_RESTRICT=yes" "HOST_FORWARDS=0.0.0.0:18080:80" "HOST_FORWARDS=127.0.0.1:80:80" \
    "HOST_FORWARDS=127.0.0.1:18080:80,hostfwd=tcp::2222-:22" "GUEST_SOCKS=10.0.2.100:9050-cmd:sh" \
    "GUEST_SOCKS=192.168.1.1:9050"; do
    check "mockvps refuses $bad" bash -c 'env HOME="$1" MOCKVPS_FORCE=1 WORKDIR="$1/vm" "$2" bash "$3" --status 2>&1 | grep -q ERROR' _ "$T" "$bad" "$M"
done

# ---- Tor, the firewall, the VM's setup ----
# shellcheck disable=SC1091
. "$HERE/lib.sh"
. "$HERE/lib/onion-site.sh"
set +e +o pipefail
torrc=$(onion_site_torrc yes)
check "Tor: port 80 of the onion address leads to the VM's forwarded port" \
    grep -qx "HiddenServicePort 80 127.0.0.1:18080" <<<"$torrc"
check "Tor: a v3 onion service, with its defences against floods" \
    bash -c 'grep -qx "HiddenServiceVersion 3" <<<"$1" && grep -qx "HiddenServiceEnableIntroDoSDefense 1" <<<"$1" && grep -qx "HiddenServicePoWDefensesEnabled 1" <<<"$1"' _ "$torrc"
check "Tor: without proof of work where tor lacks it" not grep -q PoW <<<"$(onion_site_torrc no)"
check "Tor: the onion site is on the list of the tor service's users" grep -qw .debsway-onion-site <<<"$TOR_SERVICE_MARKS"
check "the ports agree: Tor, the session and the firewall (18080, 2243)" \
    bash -c 'grep -q "^WEB=127.0.0.1:$2:80$" "$1/bin/onion-site-session" && grep -q "^export SSH_HOST_PORT=$3$" "$1/bin/onion-site-session" &&
        grep -q "tcp dport { $3, 9050 } accept" "$1/data/onion-site-firewall.nft"' _ "$HERE" "$ONION_SITE_WEB_PORT" "$ONION_SITE_SSH_PORT"
FW=$HERE/data/onion-site-firewall.nft
check "firewall: only the onion-site user is touched" grep -q 'meta skuid "onion-site" jump onion_site' "$FW"
check "firewall: on this computer only the VM's console and Tor's SOCKS port" \
    bash -c 'grep -c "accept" "$1" | grep -qx 5 && grep -q "oifname \"lo\" reject" "$1"' _ "$FW"
if command -v nft >/dev/null && unshare -rn true 2>/dev/null; then
    sed 's/skuid "onion-site"/skuid "root"/' "$FW" >"$T/fw.nft"
    check "nft accepts the firewall rule" unshare -rn nft -c -f "$T/fw.nft"
fi
P=$HERE/data/onion-site-provision.sh
for app in any python; do
    sed -e "s|@APP@|$app|g" -e "s|@VM_USER@|site|g" "$P" >"$T/prov-$app.sh"
    check "provision ($app) is a valid script" bash -n "$T/prov-$app.sh"
done
check "VM: time zone UTC" grep -q 'zoneinfo/UTC /etc/localtime' "$P"
check "VM: nginx shows no version and keeps no access log" \
    bash -c 'grep -q "server_tokens off;" "$1" && grep -q "access_log off;" "$1"' _ "$P"
check "VM: everything but static files goes to the app on 127.0.0.1:8000" grep -q 'proxy_pass http://127.0.0.1:8000;' "$P"
check "VM: the Python app is gunicorn on 127.0.0.1:8000, locked down" \
    bash -c 'grep -q "gunicorn --bind 127.0.0.1:8000" "$1" && grep -q "ProtectSystem=strict" "$1" && grep -q "NoNewPrivileges=yes" "$1"' _ "$P"
check "VM: later, apt goes only through the host's Tor" grep -q 'Acquire::https::Proxy "socks5h://10.0.2.100:9050";' "$P"

[ "$fails" -eq 0 ]
