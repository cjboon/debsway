#!/bin/bash
# temp-claude-host.sh -- throwaway check, runs on the HOST as your normal
# user, AFTER: bash extras/claude-vm.sh
# It confirms the claude-vm sandbox is set up the way it should be: the locked
# user, the firewall, the one sudo rule, the built VM, and that YOU cannot
# read the claude-vm user's files. It changes nothing, but uses sudo for a few
# read-only inspections (reading root-only config and the claude-vm home).
# If temp-claude-vm.sh sits next to it, it also runs the in-guest checks.
# Delete both when you're done.

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
AGENT=claude-vm
AHOME=/home/$AGENT
SESSION=/usr/local/libexec/claude-vm-session
PORT=2242
DISK=$AHOME/vm/$AGENT.qcow2
KEY=$AHOME/.ssh/${AGENT}_id

pass=0; fail=0
ok() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; pass=$((pass+1)); }
no() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=$((fail+1)); }

echo "== host checks (uses sudo for read-only inspection) =="

echo "-- the command and its sudo rule --"
command -v claude-vm >/dev/null && ok "claude-vm command installed" || no "claude-vm command missing"
sudo -n -u "$AGENT" -l "$SESSION" >/dev/null 2>&1 \
    && ok "you may run only claude-vm-session as $AGENT" || no "the sudoers rule is not in place"
sudo visudo -cf /etc/sudoers.d/debsway-claude-vm >/dev/null 2>&1 \
    && ok "the sudoers file is valid" || no "the sudoers file is missing or invalid"

echo "-- the $AGENT user --"
id "$AGENT" >/dev/null 2>&1 && ok "$AGENT exists" || no "$AGENT does not exist"
sudo passwd -S "$AGENT" 2>/dev/null | grep -q ' L ' && ok "$AGENT is locked (no login)" || no "$AGENT is not locked"
groups=$(id -nG "$AGENT" 2>/dev/null | tr ' ' '\n' | grep -vx "$AGENT" | paste -sd, -)
[ "$groups" = kvm ] && ok "$AGENT's only extra group is kvm" || no "$AGENT's groups are '$groups' (expected only kvm)"
[ "$(stat -c %a "$AHOME" 2>/dev/null)" = 700 ] && ok "$AHOME is mode 700" || no "$AHOME is not mode 700"

echo "-- you are walled out of the $AGENT user's files --"
if ls "$AHOME" >/dev/null 2>&1; then no "you can list $AHOME (you should not be able to)"; else ok "you cannot read into $AHOME"; fi

echo "-- the firewall keeps $AGENT (and the guest) off your network --"
systemctl is-active --quiet debsway-claude-vm-firewall \
    && ok "the firewall service is active" || no "the firewall service is not active"
fw=$(sudo nft list table inet debsway_claude_vm 2>/dev/null)
grep -q "skuid \"$AGENT\"\|skuid $AGENT" <<<"$fw" && ok "the rule matches the $AGENT user" || no "no skuid $AGENT rule found"
grep -q "127.0.0.1 tcp dport $PORT accept" <<<"$fw" && ok "loopback :$PORT (guest console) is the only hole" || no "the guest-console exception is missing"
grep -q '192.168.0.0/16.*reject\|reject' <<<"$fw" && ok "private ranges are rejected" || no "no reject rule for private ranges"

echo "-- the engine, wrapper, provisioning and the built VM --"
for f in "$SESSION" /usr/local/libexec/claude-vm-mockvps-kvm; do
    [ -x "$f" ] && ok "installed: $f" || no "missing or not executable: $f"
done
sudo test -s "$AHOME/.config/claude-vm/provision.sh" && ok "provisioning script present" || no "provisioning script missing"
if sudo test -s "$DISK"; then ok "the VM disk exists ($DISK)"; else no "no VM disk yet -- build it: claude-vm rebuild"; fi

echo "-- bringing the VM up --"
# `pubkey` starts the VM if needed and prints the guest's key (no interactive session)
if pub=$(claude-vm pubkey 2>/dev/null) && [ -n "$pub" ]; then
    ok "the VM is up and answered over ssh"
    echo "    guest ssh public key (add as a deploy key on your git host):"
    echo "      $pub"
else
    no "could not bring the VM up / reach it (see $AHOME/vm/${AGENT}-run.log via sudo)"
fi

echo
echo "== host: $pass passed, $fail failed =="

# If the in-guest script is here, run it inside the guest and show its output.
if [ -f "$HERE/temp-claude-vm.sh" ]; then
    echo
    echo "== running temp-claude-vm.sh inside the guest =="
    echo "   (sudo may ask for your password to run the ssh client as $AGENT)"
    # The user shell reads the (user-readable) script and feeds it to the
    # guest's bash over ssh; sudo only runs the ssh client as claude-vm. The
    # guest script's own output — including any FAIL — streams back here.
    printf '%s\n' "$(<"$HERE/temp-claude-vm.sh")" | sudo -u "$AGENT" -H ssh \
        -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
        -o HostKeyAlias="$AGENT" -o IdentitiesOnly=yes -i "$KEY" -p "$PORT" \
        "agent@127.0.0.1" 'bash -s'
    rc=$?
    # ssh returns 255 only when it could not connect; any other non-zero is the
    # guest script reporting its own failures, which you have just seen above.
    [ "$rc" -ne 255 ] || echo "  (could not reach the guest over ssh; run the checks by hand with: claude-vm shell)"
else
    echo "Put temp-claude-vm.sh next to this script to also run the in-guest checks,"
    echo "or run them yourself: claude-vm shell   then paste temp-claude-vm.sh."
fi
