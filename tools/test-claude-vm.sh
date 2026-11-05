#!/bin/bash
# Checks the claude-vm and claude-vm-session scripts (bin/) with a pretend
# sudo, so no user is made and nothing is run as anyone else. It does not boot
# a VM. Run by test.sh, or:
#   bash tools/test-claude-vm.sh
# shellcheck disable=SC2016  # the inner shells and pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}

mkdir -p "$T/fake"
# a pretend sudo: "-l" says whether the rule for the user after -u exists ($T/rule-USER), else it writes down
# the call (and fails if $T/sudo-fails is there); a pretend foot writes down how it was started
cat >"$T/fake/sudo" <<EOF
#!/bin/sh
case "\$*" in *" -l "*) [ -e "$T/rule-\$3" ] ;; *) echo "sudo \$*" >>"$T/calls"; [ ! -e "$T/sudo-fails" ] ;; esac
EOF
printf '#!/bin/sh\necho "foot $*" >>"%s/calls"\n' "$T" >"$T/fake/foot"
chmod +x "$T/fake/sudo" "$T/fake/foot"
# not in sway unless a check says so, even when the tests run in sway
unset WAYLAND_DISPLAY CLAUDE_VM_HOLD
export PATH="$T/fake:$PATH" HOME="$T/home"
run() { bash "$HERE/bin/claude-vm" "$@"; }

check "claude-vm says what to do when the sandbox isn't set up" \
    bash -c "! out=\$(bash '$HERE/bin/claude-vm' 2>&1) && [[ \$out == *'wrenctl install claude-vm'* ]]"
touch "$T/rule-claude-vm"
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
port_se=$(sed -n 's/^port=\([0-9]*\).*/\1/p' "$HERE/bin/claude-vm-session" | head -1)
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
sed -e "s|/home/claude-vm|$S/home|g" -e "s|\"/home/\$me\"|\"$S/home\"|" \
    -e "s|/etc/wren/claude-vm-ports|$S/ports|" \
    -e "s|/usr/local/libexec/claude-vm-mockvps-kvm|$S/bin/mockvps|" \
    -e "s|/usr/local/libexec/wren-sandbox-net-check|$S/bin/sandbox-net-check|" \
    -e "s|/usr/local/libexec/claude-vm-net-check|$S/bin/net-check|" \
    -e "s|^export PATH=.*|export PATH=$S/bin:\$PATH|" \
    "$HERE/bin/claude-vm-session" >"$S/claude-vm-session"
# (a pretend firewall check: the rule is "gone" while $S/net-down is there; each
# watch it is asked for is written down)
printf '#!/bin/sh\n[ "$1" = --watch ] && { echo "watch $2" >>"%s/watched"; exit 0; }\n[ ! -e "%s/net-down" ]\n' "$S" "$S" >"$S/bin/sandbox-net-check"
chmod +x "$S/bin/sandbox-net-check"
# shellcheck disable=SC2016  # expanded by the pretend id, not here
printf '#!/bin/sh\n[ "$1" = -un ] && { cat "%s/me" 2>/dev/null || echo claude-vm; } || exec /usr/bin/id "$@"\n' "$S" >"$S/bin/id"
# (the home folder comes from the user database: here, always $S/home)
printf '#!/bin/sh\necho "$2:x:1:1::%s/home:/bin/bash"\n' "$S" >"$S/bin/getent"
chmod +x "$S/bin/getent"
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
session() { PATH="$S/bin:$PATH" WREN_NOABS=1 bash "$S/claude-vm-session" "$@"; }

# Its firewall, seen from the VM's user: checked before anything starts a VM (the
# install too, which has the internet), then watched: the session while it
# builds, and QEMU (its pid file) after
mkdir -p "$S/home/vm/run"
echo 4242 >"$S/home/vm/run/claude-vm.pid"
: >"$S/net-down"
: >"$S/calls"
out=$(session install 2>&1)
check "its firewall gone (flushed): the install doesn't run, and it says how to put it back" bash -c '
    ! grep -q -- "mockvps --yes" "$1" && grep -q "sudo systemctl restart wren-claude-vm-firewall" <<<"$2"' _ "$S/calls" "$out"
rm -f "$S/net-down" "$S/watched"
session install >/dev/null 2>&1
check "...with it: the session watched while it builds, and QEMU after" bash -c '
    grep -q "^watch [0-9]" "$1" && grep -qx "watch 4242" "$1"' _ "$S/watched"
rm -f "$S/home/vm/claude-vm.qcow2"

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
check "the guest installs its security updates by itself, Claude Code's too" bash -c '
    grep -q "unattended-upgrades" "$1" && grep -qF "APT::Periodic::Unattended-Upgrade \"1\";" "$1" && grep -qF "site=downloads.claude.ai" "$1"' _ "$HERE/data/claude-vm-provision.sh"
check "provisioning calls it on the guest's real file" \
    grep -q '^grub_no_wait /etc/default/grub' "$HERE/data/claude-vm-provision.sh"

# ---- Another account's VM: claude-vm-NAME, its own console port
: >"$S/calls"
echo claude-vm-work >"$S/me"
out=$(session status 2>&1)
check "an account without a console port (not set up by root) starts nothing, and says how" \
    bash -c '[[ $1 == *"wrenctl install claude-vm --account work"* ]] && [ ! -s "$2" ]' _ "$out" "$S/calls"
printf 'other 2251\nwork 2250\n' >"$S/ports"
touch "$S/vm-running"; echo disk >"$S/home/vm/claude-vm-work.qcow2"
session connect >/dev/null 2>&1
check "...with its port: it logs in to its own VM, on that port" grep -q "^ssh .*-p 2250 agent@127.0.0.1" "$S/calls"
check "...the VM named after its user" grep -q "HostKeyAlias=claude-vm-work" "$S/calls"
printf 'work 22\n' >"$S/ports"
: >"$S/calls"
check "...a port outside 2250-2299 is refused (2242 is claude-vm's, 2244 opencode-vm's)" bash -c '! session status' 
echo nobody >"$S/me"
check "the session refuses users that aren't claude-vm or claude-vm-NAME" bash -c '! session status'
rm -f "$S/me" "$S/home/vm/claude-vm-work.qcow2"

# claude-vm --account NAME
: >"$T/calls"
rm -f "$T/rule-claude-vm-work"
check "claude-vm --account: not set up yet, it says how, and starts nothing" bash -c "
    ! out=\$(bash '$HERE/bin/claude-vm' --account work status 2>&1) && [[ \$out == *'wrenctl install claude-vm --account work'* ]] && [ ! -s '$T/calls' ]"
touch "$T/rule-claude-vm-work"
bash "$HERE/bin/claude-vm" --account work status >/dev/null 2>&1
check "...set up: the session runs as claude-vm-work" grep -qx "sudo -n -u claude-vm-work /usr/local/libexec/claude-vm-session status" "$T/calls"
check "...a name that isn't one is refused" bash -c "! bash '$HERE/bin/claude-vm' --account ../x status 2>/dev/null"

# The firewall: each account user goes through the same rules, reaching only its own console port
printf '%s\n' 'claude-vm:x:900:900::/home/claude-vm:/bin/bash' 'claude-vm-work:x:901:901::/home/claude-vm-work:/bin/bash' \
    'claude-vm-home:x:902:902::/home/claude-vm-home:/bin/bash' 'claude-vm-Bad:x:903:903::/x:/bin/sh' >"$T/passwd"
printf 'work 2250\n' >"$T/ports"
fw=$(WREN_PASSWD=$T/passwd WREN_CLAUDE_VM_PORTS=$T/ports bash -c '. "$1/lib/claude-accounts.sh"; claude_vm_firewall_text "$1/data/claude-vm-firewall.nft"' _ "$HERE")
check "firewall: each account user through claude-vm's rules" bash -c '
    grep -qx "        meta skuid 901 jump claude_vm  # claude-vm-work" <<<"$1" && grep -qx "        meta skuid 902 jump claude_vm  # claude-vm-home" <<<"$1"' _ "$fw"
check "...reaching its own console port only (claude-vm keeps 2242 to itself)" bash -c '
    grep -qx "        meta skuid 901 ip daddr 127.0.0.1 tcp dport 2250 accept  # claude-vm-work" <<<"$1" &&
    grep -qx "        meta skuid \"claude-vm\" ip daddr 127.0.0.1 tcp dport 2242 accept" <<<"$1" &&
    [ "$(grep -c "127.0.0.1 tcp dport [0-9]* accept" <<<"$1")" = 2 ]' _ "$fw"
check "...answering from its own console port only (QEMU's replies to the login)" bash -c '
    grep -qx "        meta skuid 901 ip saddr 127.0.0.1 tcp sport 2250 accept  # claude-vm-work" <<<"$1" &&
    grep -qx "        meta skuid \"claude-vm\" ip saddr 127.0.0.1 tcp sport 2242 accept" <<<"$1" &&
    [ "$(grep -c "127.0.0.1 tcp sport [0-9]* accept" <<<"$1")" = 2 ] && ! grep -q "^[^#]*established" <<<"$1"' _ "$fw"
check "...none for a user that only looks like one" bash -c '! grep -q "skuid 903" <<<"$1"' _ "$fw"
: >"$T/empty.nft"
if unshare -rn /usr/sbin/nft -c -f "$T/empty.nft" >/dev/null 2>&1; then
    sed "s/\"claude-vm\"/\"$(id -un)\"/g" <<<"$fw" >"$T/fw.nft"
    check "...which nft accepts" unshare -rn /usr/sbin/nft -c -f "$T/fw.nft"
fi
check "a free port: the lowest of 2250-2299 no account has" bash -c '
    printf "a 2250\nb 2251\n" >"$1"; [ "$(WREN_CLAUDE_VM_PORTS=$1 bash -c ". \"$2/lib/claude-accounts.sh\"; claude_vm_free_port")" -ge 2252 ]' _ "$T/ports2" "$HERE"

# The install script: an account needs claude-vm set up; its port is written
# (by root) before its firewall line; removing one takes the port out and
# writes the firewall again afterwards; each rule is checked first
c=$HERE/extras/claude-vm.sh
check "install: an account needs the claude-vm sandbox set up first" grep -q 'die "Set up the claude-vm sandbox first' "$c"
check "...its port is written before the firewall, which nft checks before it replaces the old one" bash -c '
    a=$(sed -n "/^if \[ \"\${1:-}\" = --account \]/,/^fi$/p" "$1"); [[ $a == *"set_port \"\$2\" \"\$port\""*write_firewall* ]] &&
    w=$(sed -n "/^write_firewall() {/,/^}/p" "$1") && [[ $w == *"nft -c -f"*"install -o root"* ]]' _ "$c"
check "...removing an account: user and port first, then the firewall" bash -c '
    a=$(sed -n "/^if \[ \"\${1:-}\" = --account \]/,/^fi$/p" "$1"); [[ $a == *remove_account*write_firewall* ]] &&
    sed -n "/^remove_account() {/,/^}/p" "$1" | grep -qx "    set_port \"\$1\""' _ "$c"
check "...each account has its own sudo rule, checked by visudo" bash -c '
    grep -q "ACCOUNT_SUDOERS=/etc/sudoers.d/wren-claude-vm-\$1" "$1" && sed -n "/^sudoers_rule() {/,/^}/p" "$1" | grep -q "visudo -cf"' _ "$c"

# ---- sudo in the VM, and what keeps it there
P=$HERE/data/claude-vm-provision.sh
check "the guest's user has sudo without a password, in a rule checked by visudo" bash -c 'grep -q "ALL=(ALL:ALL) NOPASSWD: ALL" "$1" && grep -q "visudo -cf /etc/sudoers.d/90-wren-agent" "$1"' _ "$P"
check "no such rule on this computer: only your one command as claude-vm" bash -c '! grep -q "ALL=(ALL:ALL)" "$1"' _ "$HERE/extras/claude-vm.sh"
check "QEMU runs under its syscall filter" bash -c 'grep -q "export QEMU_SANDBOX=on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny" "$1" && grep -q -- "-sandbox \"\$QEMU_SANDBOX\"" "$2"' _ "$HERE/bin/claude-vm-session" "$HERE/vendor/mockvps-kvm/mockvps-kvm.sh"
if command -v qemu-system-x86_64 >/dev/null; then
    q=$(sed -n 's/^export QEMU_SANDBOX=//p' "$HERE/bin/claude-vm-session")
    timeout 2 qemu-system-x86_64 -sandbox "$q" -machine none -nodefaults -display none -S >/dev/null 2>&1
    check "...QEMU here takes those settings" test "$?" = 124
fi
NS_PATH=/usr/sbin:/sbin:/usr/bin:/bin
if PATH=$NS_PATH command -v nft >/dev/null && unshare -rn true 2>/dev/null; then
    TN=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
    sed 's/meta skuid "claude-vm"/meta skuid 0/' "$HERE/data/claude-vm-firewall.nft" >"$TN/fw.nft"
    nc() { PATH=$NS_PATH unshare -rn bash -c 'ip link set lo up; [ "$1" = none ] || nft -f "$1" || exit 8; bash "$2"' _ "$1" "$HERE/bin/claude-vm-net-check"; echo $?; }
    check "the net check, the firewall there: go" test "$(nc "$TN/fw.nft")" = 0
    check "...no firewall: stop" test "$(nc none)" = 1
    rm -rf "$TN"
fi
check "the session stops if the net check says no, before the VM starts" bash -c '
    a=$(grep -n "\"\$NETCHECK\"; then" "$1" | cut -d: -f1); b=$(grep -n "mockvps --start" "$1" | cut -d: -f1); [ -n "$a" ] && [ "$a" -lt "$b" ]' _ "$HERE/bin/claude-vm-session"
check "both ssh commands forward nothing and ignore config files" bash -c '[ "$(grep -c "ssh \"\${SSH_SAFE\[@\]}\"" "$1")" = 2 ] && grep -q "ForwardAgent=no" "$1" && grep -q "ClearAllForwardings=yes" "$1" && grep -q -- "-F /dev/null" "$1"' _ "$HERE/bin/claude-vm-session"
check "pubkey checks what the guest says before showing it" grep -q "ssh-ed25519" "$HERE/bin/claude-vm-session"
check "a clean snapshot after install and rebuild" test "$(grep -c '^        clean_snapshot$' "$HERE/bin/claude-vm-session")" = 2
check "reset asks first, and no answer changes nothing" bash -c 'grep -q "Nothing was changed" "$1" && grep -q "\[y/N\]" "$1"' _ "$HERE/bin/claude-vm"
# A commit message with a terminal escape in it, through the real claude-pull
GP=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
# (set -e, and every git told which copy it works in: a step that fails stops
# here, never committing or pushing in the folder the test was started from)
( set -e
  export HOME=$GP GIT_CONFIG_NOSYSTEM=1
  git config --global user.name t; git config --global user.email t@e; git config --global init.defaultBranch main; git config --global commit.gpgsign false
  git init -q --bare "$GP/s.git"; git clone -q "$GP/s.git" "$GP/a" 2>/dev/null
  git -C "$GP/a" commit -q --allow-empty -m first; git -C "$GP/a" push -q origin main
  git clone -q "$GP/s.git" "$GP/b" 2>/dev/null
  git -C "$GP/a" commit -q --allow-empty -m "$(printf 'evil\033]52;c;x\007done')"; git -C "$GP/a" push -q origin main
  cd "$GP/b"; bash "$HERE/bin/claude-pull" </dev/null >"$GP/out" 2>&1 )
check "claude-pull shows the commit" grep -q 'evil' "$GP/out"
check "...without the terminal escape in its message" bash -c '! LC_ALL=C grep -q "$(printf "\033")" "$1"' _ "$GP/out"
rm -rf "$GP"

[ "$fails" -eq 0 ]
