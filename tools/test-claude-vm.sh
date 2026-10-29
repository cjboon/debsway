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
# a pretend sudo: "-l" says whether the rule exists (when $T/rule is there), else it writes down the call
cat >"$T/fake/sudo" <<EOF
#!/bin/sh
case "\$*" in *" -l "*) [ -e "$T/rule" ] ;; *) echo "sudo \$*" >>"$T/calls" ;; esac
EOF
chmod +x "$T/fake/sudo"
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

[ "$fails" -eq 0 ]
