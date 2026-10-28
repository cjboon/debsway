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

[ "$fails" -eq 0 ]
