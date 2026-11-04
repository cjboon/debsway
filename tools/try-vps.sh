#!/bin/bash
# try-vps.sh: tries tools/setup-vps.sh in a VM on this computer, the way a
# fresh VPS would get it, before any real server meets it. The VM is the
# bundled vendor/mockvps-kvm: a Debian 13 install of its own, reachable only
# from this computer (SSH on a loopback port, the site at
# http://127.0.0.1:8080 through an SSH tunnel). Needs KVM and the
# mockvps-kvm extra (wrenctl install mockvps-kvm, once), and downloads
# Debian's installer the first time (5-15 minutes).
#  - The VM's user, vps, becomes setup-vps.sh's user (its SSH key is the one
#    mockvps-kvm made), with no domain (plain http), both onion services, and
#    an onion client key made here (tools/vps-client.sh keygen try-vps).
#  - It then confirms from a second login, as you would.
#  - --publish puts the site from this copy's newest commit on it (signed or
#    not: it's a test), --status shows its onion addresses, --ssh logs in.
# The sandboxed Firefox can't reach 127.0.0.1 (its firewall): look at the site
# with Tor Browser at its onion address (the onion site is tried for real),
# or curl http://127.0.0.1:8080.
# Usage: bash tools/try-vps.sh [--publish | --status | --ssh | --stop | --start | --uninstall | --print-provision]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
not_root

VM=wren-vps-test
PORT=2240
WORK=${XDG_DATA_HOME:-$HOME/.local/share}/wren/try-vps
MOCK=$WREN_DIR/vendor/mockvps-kvm/mockvps-kvm.sh
KEY=$HOME/.ssh/${VM}_id
mock() { bash "$MOCK" --name "$VM" --port "$PORT" --workdir "$WORK" "$@"; }
vm_ssh() { ssh -o IdentitiesOnly=yes -o HostKeyAlias="$VM" -o StrictHostKeyChecking=accept-new -i "$KEY" -p "$PORT" vps@127.0.0.1 "$@"; }

# provision CLIENT-KEY: what runs as root in the VM: setup-vps.sh, as it is
# in this copy, with the test's choices
provision() {
    local client=$1
    printf '#!/bin/bash\n# Made by Wren Linux tools/try-vps.sh\nset -e\n'
    printf "cat >/root/setup-vps.sh <<'WREN_TRY_VPS_SETUP'\n"
    cat "$WREN_DIR/tools/setup-vps.sh"
    printf 'WREN_TRY_VPS_SETUP\n'
    # shellcheck disable=SC2016  # expanded in the VM, not here
    printf 'VPS_SSH_KEY=$(head -n1 /home/vps/.ssh/authorized_keys) VPS_ADMIN=vps VPS_DOMAIN= VPS_ONION_SITE=yes VPS_ONION_SSH=yes VPS_ONION_SSH_CLIENT=%s VPS_CONFIRM_MINUTES=30 bash /root/setup-vps.sh --yes\n' "$client"
}
grep -qx 'WREN_TRY_VPS_SETUP' "$WREN_DIR/tools/setup-vps.sh" && die "setup-vps.sh holds the line that ends its copy here; rename it in try-vps.sh."

client_key() {
    bash "$WREN_DIR/tools/vps-client.sh" keygen-show try-vps 2>/dev/null ||
        bash "$WREN_DIR/tools/vps-client.sh" keygen try-vps | tail -n1
}

case ${1:-} in
    --print-provision) provision "${2:-$(client_key)}"; exit ;;
    --stop) mock --stop; exit ;;
    --start) mock --start; exit ;;
    --uninstall) mock --uninstall; exit ;;
    --ssh) shift; vm_ssh "$@"; exit ;;
    --status)
        printf '#!/bin/bash\nwren-vps --status\n' >"$WORK/status.sh"
        mock --provision-only --provision "$WORK/status.sh"
        exit ;;
    --publish)
        out=${XDG_CACHE_HOME:-$HOME/.cache}/wren/try-vps-site
        bash "$WREN_DIR/tools/build-site.sh" --out "$out" || die "The site couldn't be built."
        # tar over the VM's SSH: no rsync needed for a test
        tar -C "$out" --exclude=.wren-site -cf - . | vm_ssh 'tar -C /srv/wren-site --no-same-owner -xf - && find /srv/wren-site -type d -exec chmod 755 {} + && find /srv/wren-site -type f -exec chmod 644 {} +' ||
            die "Couldn't copy the site to the VM (is it running? bash tools/try-vps.sh --start)."
        note "The site is on the VM: curl http://127.0.0.1:8080/ (or its onion address in Tor Browser: --status)."
        exit ;;
    "") ;;
    *) die "Usage: bash tools/try-vps.sh [--publish | --status | --ssh | --stop | --start | --uninstall | --print-provision]" ;;
esac

[ -e /dev/kvm ] || die "No /dev/kvm: KVM is off in the BIOS, or this is a VM itself (docs/bios.md)."
# mockvps-kvm needs its extra first (QEMU, and its command): it refuses to run without
[ -e "$HOME/.local/bin/mockvps-kvm" ] || die "First set up the VM tool, once: wrenctl install mockvps-kvm   (then run this again)"
mkdir -p "$WORK"
chmod 700 "$WORK"
say "The onion client key for the test (kept in ~/.config/wren/vps/try-vps.key)"
client=$(client_key)
provision "$client" >"$WORK/provision.sh"
printf '#!/bin/bash\nset -e\nwren-vps --confirm\nwren-vps --status\n' >"$WORK/confirm.sh"
say "A test VPS: $VM (SSH on 127.0.0.1:$PORT only)"
if mock --status >/dev/null 2>&1; then
    note "It is there already: running setup-vps.sh on it again."
    mock --provision-only --provision "$WORK/provision.sh"
else
    mock --yes --provision "$WORK/provision.sh"
fi
say "Confirming from a second login, as you would"
mock --provision-only --provision "$WORK/confirm.sh"
say "Done"
note "Log in:        bash tools/try-vps.sh --ssh"
note "The site:      bash tools/try-vps.sh --publish, then curl http://127.0.0.1:8080/"
note "Onion SSH:     bash tools/vps-client.sh tor-auth ONION try-vps, then ssh-config vps ONION"
note "Remove it all: bash tools/try-vps.sh --uninstall"
