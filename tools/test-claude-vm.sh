#!/bin/bash
# Checks the claude-vm and claude-vm-session scripts (bin/) with a pretend
# sudo, so no user is made and nothing is run as anyone else. It does not boot
# a VM. Run by test.sh, or:
#   bash tools/test-claude-vm.sh
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}

mkdir -p "$T/fake"
# a pretend sudo: "-l" says whether the rule exists (when $T/rule is there), else it writes down
# the call (and fails if $T/sudo-fails is there); a pretend foot writes down how it was started
cat >"$T/fake/sudo" <<EOF
#!/bin/sh
case "\$*" in *" -l "*) [ -e "$T/rule" ] ;; *) echo "sudo \$*" >>"$T/calls"; [ ! -e "$T/sudo-fails" ] ;; esac
EOF
printf '#!/bin/sh\necho "foot $*" >>"%s/calls"\n' "$T" >"$T/fake/foot"
chmod +x "$T/fake/sudo" "$T/fake/foot"
# not in sway unless a check says so, even when the tests run in sway
unset WAYLAND_DISPLAY CLAUDE_VM_HOLD
export PATH="$T/fake:$PATH" HOME="$T/home"
run() { bash "$HERE/bin/claude-vm" "$@"; }

check "claude-vm says what to do when the sandbox isn't set up" \
    bash -c "! out=\$(bash '$HERE/bin/claude-vm' 2>&1) && [[ \$out == *claude-vm.sh* ]]"
touch "$T/rule"
check "claude-vm rejects an unknown command" \
    bash -c "! out=\$(bash '$HERE/bin/claude-vm' bogus 2>&1) && [[ \$out == *'unknown command'* ]]"
check "a rejected command starts nothing" test ! -e "$T/calls"

run
check "no argument runs the session's connect subcommand as claude-vm" \
    grep -qx "sudo -n -u claude-vm /usr/local/libexec/claude-vm-session connect" "$T/calls"
: >"$T/calls"
run status
check "a known command is passed through to the session" \
    grep -qx "sudo -n -u claude-vm /usr/local/libexec/claude-vm-session status" "$T/calls"

# From wmenu: no terminal on stdin or stdout, in sway
: >"$T/calls"
WAYLAND_DISPLAY=wayland-1 run </dev/null >/dev/null 2>&1
check "from a launcher, claude-vm opens a foot window and runs itself in it" \
    grep -qx "foot --title=Claude (VM) env CLAUDE_VM_HOLD=1 $HERE/bin/claude-vm connect" "$T/calls"
check "and doesn't start the session outside it" bash -c "! grep -q '^sudo' '$T/calls'"
: >"$T/calls"
WAYLAND_DISPLAY=wayland-1 run shell </dev/null >/dev/null 2>&1
check "claude-vm shell does the same" grep -q "^foot .*/claude-vm shell\$" "$T/calls"
: >"$T/calls"
WAYLAND_DISPLAY=wayland-1 run status </dev/null >/dev/null 2>&1
check "a command that only prints (status) opens no window" bash -c "! grep -q '^foot' '$T/calls'"
: >"$T/calls"
run </dev/null >/dev/null 2>&1
check "outside sway it opens no window" bash -c "! grep -q '^foot' '$T/calls'"
# Inside that window
: >"$T/calls"
out=$(CLAUDE_VM_HOLD=1 run </dev/null 2>&1)
check "in the window, claude-vm runs the session" \
    grep -qx "sudo -n -u claude-vm /usr/local/libexec/claude-vm-session connect" "$T/calls"
check "and the window closes when Claude Code ends" bash -c "! grep -q 'Press Enter' <<<'$out'"
touch "$T/sudo-fails"
out=$(CLAUDE_VM_HOLD=1 run </dev/null 2>&1)
check "it stays open after an error until Enter" grep -q 'Press Enter to close' <<<"$out"
check "and still reports the failure" bash -c "! CLAUDE_VM_HOLD=1 bash '$HERE/bin/claude-vm' </dev/null >/dev/null 2>&1"
rm "$T/sudo-fails"
check "claude-vm --help says so" bash -c "bash '$HERE/bin/claude-vm' --help | grep -q 'own foot window'"

check "claude-vm-session refuses anyone but the claude-vm user" \
    bash -c "! bash '$HERE/bin/claude-vm-session' connect 2>/dev/null"

# The firewall rule and the session agree on the guest SSH port: the loopback
# exception line ("ip daddr 127.0.0.1 tcp dport N accept") must use the port
# the session forwards to, or the host could not reach the guest's console.
port_fw=$(grep -oE 'daddr 127\.0\.0\.1 tcp dport [0-9]+' "$HERE/data/claude-vm-firewall.nft" | grep -oE '[0-9]+$' | head -1)
port_se=$(sed -n 's/^export SSH_HOST_PORT=//p' "$HERE/bin/claude-vm-session" | head -1)
check "the firewall's guest-SSH port matches the session's" test -n "$port_fw" -a "$port_fw" = "$port_se"

# mockvps and guest_ssh are shell functions; exec only runs programs, so
# "exec mockvps" fails with "not found"
check "the session never execs one of its own functions" \
    bash -c "! grep -qE 'exec (mockvps|guest_ssh)( |\$)' '$HERE/bin/claude-vm-session'"

# The session itself, as the claude-vm user. Its fixed paths are pointed into
# $T in a copy (the real script has no way to change them), with a pretend id,
# mockvps and ssh. $S/vm-running says whether the pretend VM is up.
S=$T/session
mkdir -p "$S/home/vm" "$S/home/.config/claude-vm" "$S/bin"
sed -e "s|/home/claude-vm|$S/home|g" \
    -e "s|/usr/local/libexec/claude-vm-mockvps-kvm|$S/bin/mockvps|" \
    -e "s|^export PATH=.*|export PATH=$S/bin:\$PATH|" \
    "$HERE/bin/claude-vm-session" >"$S/claude-vm-session"
# shellcheck disable=SC2016  # expanded by the pretend id, not here
printf '#!/bin/sh\n[ "$1" = -un ] && echo claude-vm || exec /usr/bin/id "$@"\n' >"$S/bin/id"
cat >"$S/bin/mockvps" <<MOCK
#!/bin/sh
echo "mockvps \$*" >>"$S/calls"
case "\$1" in
    --status) [ -e "$S/vm-running" ] && echo "VM 'claude-vm' is Running" || echo "VM 'claude-vm' is not running" ;;
esac
MOCK
printf '#!/bin/sh\necho "ssh $*" >>"%s/calls"\n' "$S" >"$S/bin/ssh"
chmod +x "$S/bin/id" "$S/bin/mockvps" "$S/bin/ssh"
touch "$S/home/.config/claude-vm/provision.sh"
session() { PATH="$S/bin:$PATH" DEBSWAY_NOABS=1 bash "$S/claude-vm-session" "$@"; }

: >"$S/calls"
session install >/dev/null 2>&1
check "install builds a VM when there is none" grep -qx -- "mockvps --yes" "$S/calls"
echo disk >"$S/home/vm/claude-vm.qcow2"
: >"$S/calls"
out=$(session install 2>&1)
check "install never replaces a VM that is already built" bash -c "! grep -q mockvps '$S/calls'"
check "install says to use rebuild for a fresh VM" grep -q 'claude-vm rebuild' <<<"$out"
check "a built VM's disk is still there after install" test -s "$S/home/vm/claude-vm.qcow2"
: >"$S/calls"
session rebuild >/dev/null 2>&1
check "rebuild still replaces it on purpose" grep -qx -- "mockvps --uninstall --yes" "$S/calls"

# Starting a stopped VM takes a minute; the window must say so, not sit blank
cat >>"$S/bin/mockvps" <<MOCK
[ "\$1" = --start ] && printf '\n==> Waiting for SSH on 127.0.0.1:2242\n\nVM is ready.\n'
[ "\$1" = --start ] && [ -e "$S/start-fails" ] && { echo 'ERROR: SSH never came up' >&2; exit 1; }
exit 0
MOCK
: >"$S/calls"
out=$(session connect 2>&1)
check "connect starts a stopped VM" grep -qx -- "mockvps --start" "$S/calls"
check "it says the VM is starting and how long that takes" grep -q 'Starting the VM.*a minute' <<<"$out"
check "it shows mockvps's steps while it waits" grep -qx '  Waiting for SSH on 127.0.0.1:2242' <<<"$out"
check "but not mockvps's closing summary" bash -c "! grep -q 'VM is ready' <<<'$out'"
check "then it logs in and starts Claude Code" grep -q "^ssh .*cd ~/projects && exec claude" "$S/calls"
touch "$S/start-fails"
: >"$S/calls"
out=$(session connect 2>&1)
check "a failed start shows mockvps's error" grep -q 'ERROR: SSH never came up' <<<"$out"
check "and doesn't try to log in" bash -c "! grep -q '^ssh' '$S/calls'"
rm "$S/start-fails"
touch "$S/vm-running"
: >"$S/calls"
out=$(session connect 2>&1)
check "a running VM is not started again, nor announced" bash -c "! grep -q -- --start '$S/calls' && [ -z '$out' ]"

# mockvps-kvm's wait for the guest's SSH, on its own: the guest answers on
# the 3rd check and takes the key on the 2nd try. Polling every 10 s cost up
# to 10 s of a start that is about a minute; every 2 s it's at most 2.
# shellcheck disable=SC2016  # run by the inner bash
waited=$(bash -c '
    eval "$(sed -n "/^wait_for_ssh_key_login() {/,/^}/p" "$1")"
    log() { :; }; die() { echo died; exit 1; }
    n=0; ssh_banner_ready() { n=$((n + 1)); [ "$n" -ge 3 ]; }
    k=0; probe_key_login() { k=$((k + 1)); [ "$k" -ge 2 ]; }
    t=0; sleep() { t=$((t + $1)); }
    wait_for_ssh_key_login && echo "$t"' _ "$HERE/vendor/mockvps-kvm/mockvps-kvm.sh")
check "mockvps notices the guest's SSH within 2 s of it coming up (waited ${waited:-?} s)" \
    test "${waited:-99}" -le 6
# shellcheck disable=SC2016  # run by the inner bash
gaveup=$(bash -c '
    eval "$(sed -n "/^wait_for_ssh_key_login() {/,/^}/p" "$1")"
    log() { :; }; die() { echo died; exit 1; }
    ssh_banner_ready() { false; }
    sleep() { SECONDS=$((SECONDS + $1)); }
    wait_for_ssh_key_login' _ "$HERE/vendor/mockvps-kvm/mockvps-kvm.sh")
check "and still gives up when the guest never answers" test "$gaveup" = died

# The guest's provisioning turns off GRUB's 5 s menu wait, on a copy of
# Debian's /etc/default/grub (and on one with no GRUB_TIMEOUT line at all)
printf '%s\n' 'GRUB_DEFAULT=0' 'GRUB_TIMEOUT=5' 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' >"$T/grub"
printf '%s\n' 'GRUB_DEFAULT=0' >"$T/grub-bare"
# shellcheck disable=SC2016  # run by the inner bash
grub_run() { bash -c '
    eval "$(sed -n "/^grub_no_wait() {/,/^}/p" "$1")"
    f=$2; update-grub() { echo updated >>"$f.log"; }
    grub_no_wait "$f"' _ "$HERE/data/claude-vm-provision.sh" "$1"; }
grub_run "$T/grub"
grub_run "$T/grub-bare"
check "provisioning sets GRUB_TIMEOUT=0 in the guest" \
    test "$(grep '^GRUB_TIMEOUT' "$T/grub")" = GRUB_TIMEOUT=0
check "and leaves GRUB's other settings alone" grep -qx 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' "$T/grub"
check "it adds the line when there is none" grep -qx GRUB_TIMEOUT=0 "$T/grub-bare"
check "then it runs update-grub" grep -qx updated "$T/grub.log"
check "provisioning calls it on the guest's real file" \
    grep -q '^grub_no_wait /etc/default/grub' "$HERE/data/claude-vm-provision.sh"

[ "$fails" -eq 0 ]
