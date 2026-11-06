#!/bin/bash
# Claude Code inside a disposable virtual machine. Instead of running the
# agent as another user on this computer, this runs it in its own throwaway
# Debian guest (QEMU/KVM), so a kernel bug that would escape a user-level
# sandbox only reaches a VM you can delete. It is self-contained: it needs
# nothing else installed. (It can also run side by side with the lighter
# extras/claude-code.sh, which it leaves untouched.)
#
# How it is put together:
#  - A locked user, claude-vm (no password, no login), runs the one
#    qemu-system-x86_64 process. The guest's disk is its own; there is no
#    shared folder with you on purpose. The agent's only way to hand work
#    back is to push to a git host you pull from with claude-pull (this
#    script installs that command too, so the VM stands on its own).
#  - QEMU's user-mode networking turns the guest's traffic into ordinary
#    host sockets owned by claude-vm, so a firewall rule on that user
#    (data/claude-vm-firewall.nft) governs the guest too: internet yes; your
#    router, printers and local services no. The one hole is loopback to the
#    guest's own SSH console (127.0.0.1:2242), which the host needs to log in.
#  - The guest is built unattended with the bundled mockvps-kvm (QEMU, no
#    libvirt), its installer kernel checked against Debian's signed lists,
#    then provisioned to install Claude Code from Anthropic's apt repository
#    (the same key fingerprint pinned in pins.sh). The guest gets its own git
#    identity and ssh key, never yours.
#  - Your user may run exactly one thing as claude-vm: the claude-vm-session
#    script (a rule in /etc/sudoers.d). The claude-vm command calls it.
# Needs KVM (VT-x/AMD-V and /dev/kvm). Without it, extras/claude-code.sh
# runs Claude Code as its own user instead: lighter, but it shares your
# kernel, so a kernel bug could get out (docs/extras.md compares the two).
# See THREAT-MODEL.md.
# Another account (a second Claude login, apart from the first): --account
# NAME makes the user claude-vm-NAME with a VM of its own (its own disk, keys
# and Claude login), its own console port (2250-2299, in
# /etc/wren/claude-vm-ports) that only it may reach, a firewall line and a
# sudo rule; claude-vm --account NAME runs it. --remove-account NAME takes it
# out again.
# How big the VM is (lib/vm-size.sh): the first time, it shows this computer's
# memory and free disk, suggests a size and asks (Enter takes the suggestion),
# and never lets the VM have so much that the computer runs short. --memory MB
# and --disk MB choose it, then or later (memory from the VM's next start, the
# disk from its next build, claude-vm rebuild).
# Usage: bash claude-vm.sh [--remove | --manual | --account NAME | --remove-account NAME]
#                          [--memory MB] [--disk MB]
# summary: Claude Code in a disposable VM (no shared folder)
# security: most
# files: bin/no-abstract-sockets lib/claude-accounts.sh bin/claude-vm-net-check bin/sandbox-net-check
# status: bin:claude-vm file:/usr/local/libexec/claude-vm-session
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$WREN_DIR/lib/claude-accounts.sh"
. "$WREN_DIR/lib/vm-size.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

# --memory MB and --disk MB, wherever they are; the rest stays in order
SIZE_MEM='' SIZE_DISK='' rest=()
while [ $# -gt 0 ]; do
    case $1 in
        --memory) [ $# -ge 2 ] || die "--memory needs a number of MB"; SIZE_MEM=$2; shift 2 ;;
        --disk) [ $# -ge 2 ] || die "--disk needs a number of MB"; SIZE_DISK=$2; shift 2 ;;
        *) rest+=("$1"); shift ;;
    esac
done
set -- "${rest[@]}"

AGENT=claude-vm
AGENT_HOME=/home/$AGENT
SESSION=/usr/local/libexec/claude-vm-session
MOCKVPS=/usr/local/libexec/claude-vm-mockvps-kvm
SUDOERS=/etc/sudoers.d/wren-claude-vm
FIREWALL=/etc/wren/claude-vm.nft
UNIT=/etc/systemd/system/wren-claude-vm-firewall.service
PROVISION_DST=$AGENT_HOME/.config/claude-vm/provision.sh
VM_USER=agent

# setup_vm_user: the locked user $AGENT, in the kvm group only
setup_vm_user() {
    say "The $AGENT user"
    if ! id "$AGENT" >/dev/null 2>&1; then
        sudo useradd --create-home --home-dir "$AGENT_HOME" --shell /bin/bash --user-group \
            --comment "Wren Linux Claude Code VM" "$AGENT"
    fi
    sudo usermod --lock "$AGENT"
    sudo chmod 700 "$AGENT_HOME"
    # It needs /dev/kvm; the kvm group is the only group it gets
    if ! id -nG "$AGENT" | grep -qw kvm; then
        sudo usermod -aG kvm "$AGENT"
    fi
    note "$AGENT: no password, no login, in the kvm group only."
}

# write_firewall [no]: the rule file, with each account's lines, checked by nft
# before it replaces the old one, then loaded (no: only written)
write_firewall() {
    local rules
    rules=$(mktemp)
    claude_vm_firewall_text "$WREN_DIR/data/claude-vm-firewall.nft" >"$rules"
    if ! sudo nft -c -f "$rules" >/dev/null; then
        rm -f "$rules"
        die "nft didn't accept the new firewall rule, so the old one stays."
    fi
    sudo install -d -o root -g root -m 0755 "${FIREWALL%/*}"
    sudo install -o root -g root -m 0644 "$rules" "$FIREWALL"
    rm -f "$rules"
    [ "${1:-}" = no ] && return 0
    sudo systemctl restart wren-claude-vm-firewall.service ||
        warn "Couldn't load the firewall rule; check: systemctl status wren-claude-vm-firewall"
}

# install_provision: the provisioning script, with Anthropic's pinned key
# filled in, where only $AGENT can read it
install_provision() {
    local prov
    sudo install -d -o "$AGENT" -g "$AGENT" -m 0700 "$AGENT_HOME/.config" "$AGENT_HOME/.config/claude-vm"
    prov=$(mktemp)
    sed -e "s|@ANTHROPIC_FPR@|$ANTHROPIC_FPR|g" \
        -e "s|@ANTHROPIC_KEY_URL@|$ANTHROPIC_KEY_URL|g" \
        -e "s|@VM_USER@|$VM_USER|g" \
        "$WREN_DIR/data/claude-vm-provision.sh" >"$prov"
    sudo install -o "$AGENT" -g "$AGENT" -m 0600 "$prov" "$PROVISION_DST"
    rm -f "$prov"
}

# sudoers_rule FILE: your user may run the session script, and nothing else,
# as $AGENT. A broken sudoers file locks you out of sudo, so visudo checks it first
sudoers_rule() {
    local rule
    rule=$(mktemp)
    printf '# Written by Wren Linux extras/claude-vm.sh. %s may run the claude-vm-session script,\n# and nothing else, as the user %s.\n%s ALL=(%s) NOPASSWD: %s\n' \
        "$(id -un)" "$AGENT" "$(id -un)" "$AGENT" "$SESSION" >"$rule"
    if ! sudo visudo -cf "$rule" >/dev/null; then
        rm -f "$rule"
        die "The sudoers rule didn't pass visudo's check, so it wasn't installed."
    fi
    sudo install -o root -g root -m 0440 "$rule" "$1"
    rm -f "$rule"
    note "Wrote $1"
}

# build_vm: builds $AGENT's VM unless it has one (that is kept, with what is
# unpushed in it)
build_vm() {
    say "Building the VM"
    if sudo test -s "$AGENT_HOME/vm/$AGENT.qcow2"; then
        note "The VM is already built; kept as it is. For a fresh one: claude-vm${1:+ --account $1} rebuild"
    else
        note "This installs Debian and Claude Code inside the guest; it takes 5-15 minutes"
        note "and downloads a few hundred MB."
        if sudo -u "$AGENT" "$SESSION" install; then
            say "The VM is ready"
            note "Its ssh public key (add it on your git host so the agent can push):"
            sudo -u "$AGENT" "$SESSION" pubkey 2>/dev/null | sed 's/^/        /' || true
            if ask "Add it to GitHub now (wrenctl gh deploy-key)?" n; then
                bash "$WREN_DIR/gh-helper.sh" deploy-key ${1:+--account "$1"} ||
                    warn "The key wasn't added. To try again: wrenctl gh deploy-key${1:+ --account $1}"
            fi
        else
            warn "The build didn't finish. Try again with: claude-vm${1:+ --account $1} rebuild"
        fi
    fi
}

# set_port NAME PORT | set_port NAME: NAME's console port written (or taken
# out) in the file only root can write
set_port() {
    local tmp
    tmp=$(mktemp)
    { awk -v n="$1" '$1 != n' "$CLAUDE_VM_PORTS" 2>/dev/null || true; [ -z "${2:-}" ] || echo "$1 $2"; } >"$tmp"
    sudo install -d -o root -g root -m 0755 "${CLAUDE_VM_PORTS%/*}"
    sudo install -o root -g root -m 0644 "$tmp" "$CLAUDE_VM_PORTS"
    rm -f "$tmp"
}

# account NAME: sets AGENT, AGENT_HOME, PROVISION_DST and the sudoers file for it
account() {
    claude_account_valid "$1" || die "An account name is small letters and digits, a letter first, at most 15 (e.g. work)."
    AGENT=$CLAUDE_VM_PREFIX$1
    AGENT_HOME=/home/$AGENT
    PROVISION_DST=$AGENT_HOME/.config/claude-vm/provision.sh
    ACCOUNT_SUDOERS=/etc/sudoers.d/wren-claude-vm-$1
}

# remove_account NAME: its sudo rule and port, its VM powered off, and (if you
# say so) the user and its home, with the VM disk and what is unpushed in it
remove_account() {
    account "$1"
    sudo rm -f "$ACCOUNT_SUDOERS"
    sudo pkill -KILL -u "$AGENT" 2>/dev/null || true
    set_port "$1"
    vm_size_remove "$AGENT"
    if id "$AGENT" >/dev/null 2>&1; then
        if ask "Delete the user $AGENT and its home folder $AGENT_HOME (its VM disk, with anything not pushed, its ssh key and Claude login)?" n; then
            sudo userdel -r "$AGENT" 2>/dev/null || sudo userdel "$AGENT"
            note "Removed the user $AGENT and its VM."
        else
            note "Kept the user $AGENT and $AGENT_HOME (it can't be started: its sudo rule is gone)."
        fi
    fi
}

if [ "${1:-}" = --account ] || [ "${1:-}" = --remove-account ]; then
    [ -n "${2:-}" ] || die "Usage: bash claude-vm.sh $1 NAME"
    account "$2"
    if [ "$1" = --remove-account ]; then
        remove_account "$2"
        # (after the user and its port are gone, so the rule doesn't name them)
        if [ -f "$FIREWALL" ]; then write_firewall; fi
        note "The account $2 is gone."
        exit
    fi
    { [ -x "$SESSION" ] && id claude-vm >/dev/null 2>&1; } ||
        die "Set up the claude-vm sandbox first: bash $WREN_DIR/extras/claude-vm.sh"
    [ -e /dev/kvm ] || die "No /dev/kvm: turn on virtualization (VT-x / AMD-V) in the firmware settings."
    port=$(claude_vm_port "$2")
    if [ -z "$port" ]; then
        port=$(claude_vm_free_port) || die "No free console port left in 2250-2299."
    fi
    setup_vm_user
    say "Its console port and firewall line"
    set_port "$2" "$port"
    write_firewall
    note "$AGENT can reach the internet and its own guest's console (127.0.0.1:$port), nothing else."
    install_provision
    say "Its sudo rule"
    sudoers_rule "$ACCOUNT_SUDOERS"
    vm_size_choose "$AGENT" "$SIZE_MEM" "$SIZE_DISK"
    build_vm "$2"
    cat <<EOF

    claude-vm --account $2           Claude Code in this account's own VM
    claude-vm --account $2 shell     (and shell, status, stop, pubkey, rebuild)

    The first time, Claude shows a login link: log in with the other account.
    Its VM, disk, keys and login are apart from the first VM's; neither can
    reach the other's console.
EOF
    exit
fi

if [ "${1:-}" = --remove ]; then
    # the other accounts first, each with its own question
    mapfile -t accounts < <(claude_account_users "$CLAUDE_VM_PREFIX" | cut -d: -f1)
    for u in "${accounts[@]}"; do remove_account "${u#"$CLAUDE_VM_PREFIX"}"; done
    AGENT=claude-vm AGENT_HOME=/home/claude-vm
    sudo rm -f "$CLAUDE_VM_PORTS"
    vm_size_remove claude-vm
    remove_bin claude-vm
    remove_claude_chooser
    # claude-pull and claude-share are shared with extras/claude-code.sh; keep them if that
    # sandbox is still set up (its session wrapper is the tell)
    [ -e /usr/local/libexec/claude-session ] || { remove_bin claude-pull; remove_bin claude-share; }
    sudo systemctl disable --now wren-claude-vm-firewall.service >/dev/null 2>&1 || true
    sudo nft delete table inet wren_claude_vm 2>/dev/null || true
    sudo rm -f "$SUDOERS" "$SESSION" "$MOCKVPS" "$FIREWALL" "$UNIT"
    sudo rm -f /usr/local/libexec/claude-vm-net-check
    remove_no_abstract
    remove_net_check
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    sudo rmdir /usr/local/libexec /etc/wren 2>/dev/null || true
    if id "$AGENT" >/dev/null 2>&1; then
        if ask "Delete the user $AGENT and its home folder $AGENT_HOME (the VM disk, its ssh key and settings)?" n; then
            sudo pkill -KILL -u "$AGENT" 2>/dev/null || true
            sudo userdel -r "$AGENT" 2>/dev/null || sudo userdel "$AGENT"
            note "Removed the user $AGENT and its VM."
        else
            note "Kept the user $AGENT and $AGENT_HOME (the VM is still there)."
        fi
    fi
    # QEMU and friends go unless another script's marker still needs them
    apt_purge qemu-system-x86 qemu-utils socat nftables
    note "Removed the claude-vm sandbox. extras/claude-code.sh, if installed, is untouched."
    exit
fi

[ -e /dev/kvm ] || die "No /dev/kvm: turn on virtualization (VT-x / AMD-V) in the firmware settings."

say "Installing what the VM sandbox needs"
# qemu + qemu-utils: the hypervisor. socat: clean power-off. nftables: the
# rule that keeps the guest off your network. openssh-client: logging into the
# guest. cpio/gzip/wget: the unattended installer. gpgv + keyring: verify
# Debian's signature on the installer. The agent itself is installed INSIDE
# the guest, from Anthropic's signed repo, by the provisioning step.
apt_install qemu-system-x86 qemu-utils socat nftables openssh-client \
    cpio gzip wget gpgv debian-archive-keyring

setup_vm_user

say "Keeping $AGENT (and so the guest) off your network"
# (with each other account's lines)
write_firewall no
printf '%s\n' '# Written by Wren Linux extras/claude-vm.sh' '[Unit]' \
    'Description=Keep the claude-vm user (and its guest) off the local network (Wren Linux)' \
    'Before=network-pre.target' 'Wants=network-pre.target' '' '[Service]' \
    'Type=oneshot' 'RemainAfterExit=yes' \
    "ExecStart=/usr/sbin/nft -f $FIREWALL" \
    'ExecStop=/usr/sbin/nft delete table inet wren_claude_vm' '' '[Install]' \
    'WantedBy=multi-user.target' | sudo tee "$UNIT" >/dev/null
sudo systemctl daemon-reload
# Restart, not just enable --now: the unit stays "active" after it first ran,
# so a rule file changed by an update would otherwise not be loaded
sudo systemctl enable wren-claude-vm-firewall.service >/dev/null &&
    sudo systemctl restart wren-claude-vm-firewall.service ||
    warn "Couldn't load the firewall rule; check: systemctl status wren-claude-vm-firewall"
note "$AGENT can reach the internet and the guest's console, nothing else."

say "The VM engine and the claude-vm command"
sudo install -d -o root -g root -m 0755 /usr/local/libexec
# The bundled mockvps-kvm, where claude-vm (which has no access to your home)
# can run it. It looks at its own location, so the wren-only reminder in it
# stays quiet here.
sudo install -o root -g root -m 0755 "$WREN_DIR/vendor/mockvps-kvm/mockvps-kvm.sh" "$MOCKVPS"
sudo install -o root -g root -m 0755 "$WREN_DIR/bin/claude-vm-net-check" /usr/local/libexec/claude-vm-net-check
sudo install -o root -g root -m 0755 "$WREN_DIR/bin/claude-vm-session" "$SESSION"
install_no_abstract
install_net_check

install_provision
sudoers_rule "$SUDOERS"
install_bin claude-vm
install_bin claude
# How you bring the agent's pushed work into your own copy, after reviewing
# it. Shared with extras/claude-code.sh, which installs the same command.
install_bin claude-pull
install_bin claude-share

vm_size_choose "$AGENT" "$SIZE_MEM" "$SIZE_DISK"
build_vm

cat <<EOF

    claude                 Claude Code, asking which if you have set up more than one
    claude-vm              Claude Code inside the disposable VM (boots it; powers it off when you exit)
    claude-vm shell        a plain shell in the VM
    claude-vm status       is the VM running?
    claude-vm stop         power the VM off
    claude-vm pubkey       the VM's ssh public key (add it on your git host)
    claude-vm rebuild      throw the VM away and build a fresh one

    The agent works in ~/projects INSIDE the VM. There is no shared folder:
    it hands work back only by pushing to a git host, which you bring into
    your own copy with claude-pull (installed above; it shows what's new and
    asks before merging). The VM reaches the internet but nothing on your
    machine or local network.
EOF
