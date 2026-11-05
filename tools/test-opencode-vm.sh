#!/bin/bash
# Checks the opencode-vm and opencode-vm-session scripts (bin/) with a pretend
# sudo, so no user is made and nothing is run as anyone else. It does not boot
# a VM. Run by test.sh, or:
#   bash tools/test-opencode-vm.sh
# shellcheck disable=SC2016  # the inner shells and grep patterns expand their own variables
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
# a pretend sudo: "-l" says whether the rule exists (when $T/rule is there), else it writes down
# the call (and fails if $T/sudo-fails is there); a pretend foot writes down how it was started
cat >"$T/fake/sudo" <<EOF
#!/bin/sh
case "\$*" in *" -l "*) [ -e "$T/rule" ] ;; *) echo "sudo \$*" >>"$T/calls"; [ ! -e "$T/sudo-fails" ] ;; esac
EOF
printf '#!/bin/sh\necho "foot $*" >>"%s/calls"\n' "$T" >"$T/fake/foot"
chmod +x "$T/fake/sudo" "$T/fake/foot"
# not in sway unless a check says so, even when the tests run in sway
unset WAYLAND_DISPLAY OPENCODE_VM_HOLD
export PATH="$T/fake:$PATH" HOME="$T/home"
run() { bash "$HERE/bin/opencode-vm" "$@"; }

check "opencode-vm says what to do when the sandbox isn't set up" \
    bash -c "! out=\$(bash '$HERE/bin/opencode-vm' 2>&1) && [[ \$out == *'wrenctl install opencode-vm'* ]]"
touch "$T/rule"
check "opencode-vm rejects an unknown command" \
    bash -c "! out=\$(bash '$HERE/bin/opencode-vm' bogus 2>&1) && [[ \$out == *'unknown command'* ]]"
check "a rejected command starts nothing" test ! -e "$T/calls"

run
check "no argument runs the session's connect subcommand as opencode-vm" \
    grep -qx "sudo -n -u opencode-vm /usr/local/libexec/opencode-vm-session connect" "$T/calls"
: >"$T/calls"
run status
check "a known command is passed through to the session" \
    grep -qx "sudo -n -u opencode-vm /usr/local/libexec/opencode-vm-session status" "$T/calls"

# From wmenu: no controlling terminal (setsid, as sway's exec), in sway
launch() { setsid -w bash "$HERE/bin/opencode-vm" "$@"; }
: >"$T/calls"
WAYLAND_DISPLAY=wayland-1 launch </dev/null >/dev/null 2>&1
check "from a launcher, opencode-vm opens a foot window and runs itself in it" \
    grep -qx "foot --title=opencode (VM) env OPENCODE_VM_HOLD=1 $HERE/bin/opencode-vm connect" "$T/calls"
check "and doesn't start the session outside it" bash -c "! grep -q '^sudo' '$T/calls'"
: >"$T/calls"
WAYLAND_DISPLAY=wayland-1 launch shell </dev/null >/dev/null 2>&1
check "opencode-vm shell does the same" grep -q "^foot .*/opencode-vm shell\$" "$T/calls"
: >"$T/calls"
# sway started on tty1 hands that console to what it starts: stdin a terminal,
# but no controlling one
WAYLAND_DISPLAY=wayland-1 script -qec "setsid -w bash $HERE/bin/opencode-vm" /dev/null </dev/null >/dev/null 2>&1
check "...also when sway was started on tty1 (stdin that console, out of sight)" \
    grep -qx "foot --title=opencode (VM) env OPENCODE_VM_HOLD=1 $HERE/bin/opencode-vm connect" "$T/calls"
: >"$T/calls"
WAYLAND_DISPLAY=wayland-1 launch status </dev/null >/dev/null 2>&1
check "a command that only prints (status) opens no window" bash -c "! grep -q '^foot' '$T/calls'"
: >"$T/calls"
run </dev/null >/dev/null 2>&1
check "outside sway it opens no window" bash -c "! grep -q '^foot' '$T/calls'"
# Inside that window
: >"$T/calls"
out=$(OPENCODE_VM_HOLD=1 run </dev/null 2>&1)
check "in the window, opencode-vm runs the session" \
    grep -qx "sudo -n -u opencode-vm /usr/local/libexec/opencode-vm-session connect" "$T/calls"
check "and the window closes when opencode ends" bash -c "! grep -q 'Press Enter' <<<'$out'"
touch "$T/sudo-fails"
out=$(OPENCODE_VM_HOLD=1 run </dev/null 2>&1)
check "it stays open after an error until Enter" grep -q 'Press Enter to close' <<<"$out"
check "and still reports the failure" bash -c "! OPENCODE_VM_HOLD=1 bash '$HERE/bin/opencode-vm' </dev/null >/dev/null 2>&1"
rm "$T/sudo-fails"
check "opencode-vm --help says so" bash -c "bash '$HERE/bin/opencode-vm' --help | grep -q 'own foot window'"

check "opencode-vm-session refuses anyone but the opencode-vm user" \
    bash -c "! bash '$HERE/bin/opencode-vm-session' connect 2>/dev/null"

# The firewall rule and the session agree on the guest SSH port: the loopback
# exception line ("ip daddr 127.0.0.1 tcp dport N accept") must use the port
# the session forwards to, or the host could not reach the guest's console.
port_fw=$(grep -oE 'daddr 127\.0\.0\.1 tcp dport [0-9]+' "$HERE/data/opencode-vm-firewall.nft" | grep -oE '[0-9]+$' | head -1)
port_se=$(sed -n 's/^export SSH_HOST_PORT=//p' "$HERE/bin/opencode-vm-session" | head -1)
check "the firewall's guest-SSH port matches the session's" test -n "$port_fw" -a "$port_fw" = "$port_se"

# mockvps and guest_ssh are shell functions; exec only runs programs, so
# "exec mockvps" fails with "not found"
check "the session never execs one of its own functions" \
    bash -c "! grep -qE 'exec (mockvps|guest_ssh)( |\$)' '$HERE/bin/opencode-vm-session'"

# The session itself, as the opencode-vm user. Its fixed paths are pointed into
# $T in a copy (the real script has no way to change them), with a pretend id,
# mockvps and ssh. $S/vm-running says whether the pretend VM is up.
S=$T/session
mkdir -p "$S/home/vm" "$S/home/.config/opencode-vm" "$S/bin"
sed -e "s|/home/opencode-vm|$S/home|g" \
    -e "s|/usr/local/libexec/opencode-vm-mockvps-kvm|$S/bin/mockvps|" \
    -e "s|/usr/local/libexec/wren-sandbox-net-check|$S/bin/sandbox-net-check|" \
    -e "s|^export PATH=.*|export PATH=$S/bin:\$PATH|" \
    "$HERE/bin/opencode-vm-session" >"$S/opencode-vm-session"
# (a pretend firewall check: the rule is "gone" while $S/net-down is there; each
# watch it is asked for is written down)
printf '#!/bin/sh\n[ "$1" = --watch ] && { echo "watch $2" >>"%s/watched"; exit 0; }\n[ ! -e "%s/net-down" ]\n' "$S" "$S" >"$S/bin/sandbox-net-check"
chmod +x "$S/bin/sandbox-net-check"
# shellcheck disable=SC2016  # expanded by the pretend id, not here
printf '#!/bin/sh\n[ "$1" = -un ] && echo opencode-vm || exec /usr/bin/id "$@"\n' >"$S/bin/id"
cat >"$S/bin/mockvps" <<MOCK
#!/bin/sh
echo "mockvps \$*" >>"$S/calls"
case "\$1" in
    --status) [ -e "$S/vm-running" ] && echo "VM 'opencode-vm' is Running" || echo "VM 'opencode-vm' is not running" ;;
esac
MOCK
printf '#!/bin/sh\necho "ssh $*" >>"%s/calls"\n' "$S" >"$S/bin/ssh"
chmod +x "$S/bin/id" "$S/bin/mockvps" "$S/bin/ssh"
touch "$S/home/.config/opencode-vm/provision.sh"
session() { PATH="$S/bin:$PATH" WREN_NOABS=1 bash "$S/opencode-vm-session" "$@"; }

# Its firewall, seen from the VM's user: checked before anything starts a VM (the
# install too, which has the internet), then watched: the session while it
# builds, and QEMU (its pid file) after
mkdir -p "$S/home/vm/run"
echo 4242 >"$S/home/vm/run/opencode-vm.pid"
: >"$S/net-down"
: >"$S/calls"
out=$(session install 2>&1)
check "its firewall gone (flushed): the install doesn't run, and it says how to put it back" bash -c '
    ! grep -q -- "mockvps --yes" "$1" && grep -q "sudo systemctl restart wren-opencode-vm-firewall" <<<"$2"' _ "$S/calls" "$out"
rm -f "$S/net-down" "$S/watched"
session install >/dev/null 2>&1
check "...with it: the session watched while it builds, and QEMU after" bash -c '
    grep -q "^watch [0-9]" "$1" && grep -qx "watch 4242" "$1"' _ "$S/watched"
rm -f "$S/home/vm/opencode-vm.qcow2"

: >"$S/calls"
session install >/dev/null 2>&1
check "install builds a VM when there is none" grep -qx -- "mockvps --yes" "$S/calls"
echo disk >"$S/home/vm/opencode-vm.qcow2"
: >"$S/calls"
out=$(session install 2>&1)
check "install never replaces a VM that is already built" bash -c "! grep -q mockvps '$S/calls'"
check "install says to use rebuild for a fresh VM" grep -q 'opencode-vm rebuild' <<<"$out"
check "a built VM's disk is still there after install" test -s "$S/home/vm/opencode-vm.qcow2"
: >"$S/calls"
session rebuild >/dev/null 2>&1
check "rebuild still replaces it on purpose" grep -qx -- "mockvps --uninstall --yes" "$S/calls"

# Starting a stopped VM takes a minute; the window must say so, not sit blank
cat >>"$S/bin/mockvps" <<MOCK
[ "\$1" = --start ] && printf '\n==> Waiting for SSH on 127.0.0.1:2244\n\nVM is ready.\n'
[ "\$1" = --start ] && [ -e "$S/start-fails" ] && { echo 'ERROR: SSH never came up' >&2; exit 1; }
exit 0
MOCK
: >"$S/calls"
out=$(session connect 2>&1)
check "connect starts a stopped VM" grep -qx -- "mockvps --start" "$S/calls"
check "it says the VM is starting and how long that takes" grep -q 'Starting the VM.*a minute' <<<"$out"
check "it shows mockvps's steps while it waits" grep -qx '  Waiting for SSH on 127.0.0.1:2244' <<<"$out"
check "but not mockvps's closing summary" bash -c "! grep -q 'VM is ready' <<<'$out'"
check "then it logs in and starts opencode" grep -q "^ssh .*cd ~/projects && exec opencode" "$S/calls"
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

# The guest's provisioning turns off GRUB's 5 s menu wait, on a copy of
# Debian's /etc/default/grub (and on one with no GRUB_TIMEOUT line at all)
printf '%s\n' 'GRUB_DEFAULT=0' 'GRUB_TIMEOUT=5' 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' >"$T/grub"
printf '%s\n' 'GRUB_DEFAULT=0' >"$T/grub-bare"
# shellcheck disable=SC2016  # run by the inner bash
grub_run() { bash -c '
    eval "$(sed -n "/^grub_no_wait() {/,/^}/p" "$1")"
    f=$2; update-grub() { echo updated >>"$f.log"; }
    grub_no_wait "$f"' _ "$HERE/data/opencode-vm-provision.sh" "$1"; }
grub_run "$T/grub"
grub_run "$T/grub-bare"
check "provisioning sets GRUB_TIMEOUT=0 in the guest" \
    test "$(grep '^GRUB_TIMEOUT' "$T/grub")" = GRUB_TIMEOUT=0
check "and leaves GRUB's other settings alone" grep -qx 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' "$T/grub"
check "it adds the line when there is none" grep -qx GRUB_TIMEOUT=0 "$T/grub-bare"
check "then it runs update-grub" grep -qx updated "$T/grub.log"
check "provisioning calls it on the guest's real file" \
    grep -q '^grub_no_wait /etc/default/grub' "$HERE/data/opencode-vm-provision.sh"


# ---- the guest's install of opencode: only an immutable release, only a file
# with GitHub's SHA-256, only the one program in it. The provisioning script
# runs here with a pretend GitHub (wget), apt-get, runuser and getent, and
# installs into $T/root instead of /usr/local.
P=$T/prov
mkdir -p "$P/bin" "$P/srv" "$P/root" "$P/agent"
sed -e "s|@OPENCODE_REPO@|owner/opencode|g; s|@VM_USER@|agent|g; s|/usr/local/|$P/root/usr/local/|g; s|/etc/apt/|$P/root/etc/apt/|g" \
    "$HERE/data/opencode-vm-provision.sh" >"$P/provision.sh"
for c in apt-get chown update-grub; do printf '#!/bin/sh\nexit 0\n' >"$P/bin/$c"; done
# wget -qO FILE URL: the release list, or the file it names
cat >"$P/bin/wget" <<EOF
#!/bin/sh
case "\$3" in
    https://api.github.com/repos/owner/opencode/releases/latest) cp "$P/srv/release.json" "\$2" ;;
    *) cp "$P/srv/asset" "\$2" ;;
esac
EOF
printf '#!/bin/sh\nshift 3\nHOME=%s exec "$@"\n' "$P/agent" >"$P/bin/runuser"
printf '#!/bin/sh\necho "agent:x:1000:1000::%s:/bin/bash"\n' "$P/agent" >"$P/bin/getent"
# install, without -o/-g (only root may give files to root)
cat >"$P/bin/install" <<'EOF'
#!/bin/bash
a=()
while [ $# -gt 0 ]; do case $1 in -o | -g) shift 2 ;; *) a+=("$1"); shift ;; esac; done
exec /usr/bin/install "${a[@]}"
EOF
chmod +x "$P/bin/"*
A=opencode-linux-x64-baseline.tar.gz
# release TAG IMMUTABLE URL DIGEST: the release list the pretend GitHub gives
release() {
    python3 -I -c 'import json, sys; t, i, u, d, n = sys.argv[1:]; print(json.dumps({"tag_name": t, "immutable": i == "true", "assets": [{"name": n, "browser_download_url": u, "digest": d}]}))' \
        "$1" "$2" "$3" "$4" "$A" >"$P/srv/release.json"
}
# asset FILE...: the tarball, holding these files
asset() { rm -rf "$P/a" && mkdir -p "$P/a" && for f; do printf 'program %s\n' "$f" >"$P/a/$f"; done && tar -czf "$P/srv/asset" -C "$P/a" "$@"; }
prov() { rm -rf "$P/root" "$P/agent"; mkdir -p "$P/root/usr/local/bin" "$P/root/usr/local/share" "$P/root/etc/apt/apt.conf.d" "$P/agent"; PATH="$P/bin:$PATH" bash "$P/provision.sh" >"$P/out" 2>&1; }
url=https://github.com/owner/opencode/releases/download/v1.2.3/$A
asset opencode; sum=sha256:$(sha256sum "$P/srv/asset" | cut -d' ' -f1)
release v1.2.3 true "$url" "$sum"
prov
check "provisioning: an immutable release with GitHub's SHA-256 is installed" grep -qx 'program opencode' "$P/root/usr/local/bin/opencode"
check "...the guest's security updates install themselves" grep -qx 'APT::Periodic::Unattended-Upgrade "1";' "$P/root/etc/apt/apt.conf.d/20auto-upgrades"
check "...and its version kept" grep -qx v1.2.3 "$P/root/usr/local/share/opencode-version"
check "...the agent told how its work gets out (AGENTS.md, where opencode reads it)" grep -q 'push to the git host' "$P/agent/.config/opencode/AGENTS.md"
check "...and given its own ssh key" test -s "$P/agent/.ssh/id_ed25519.pub"
release v1.2.3 false "$url" "$sum"
prov
check "a release GitHub doesn't mark immutable is refused" bash -c '! [ -e "$1" ] && grep -q "immutable" "$2"' _ "$P/root/usr/local/bin/opencode" "$P/out"
release v1.2.3 true "$url" "sha256:$(printf '%064d' 0)"
prov
check "a file without GitHub's SHA-256 is refused" bash -c '! [ -e "$1" ] && grep -q "SHA-256" "$2"' _ "$P/root/usr/local/bin/opencode" "$P/out"
release 'v1.2.3;id' true "$url" "$sum"
prov
check "a tag that isn't a version is refused" test ! -e "$P/root/usr/local/bin/opencode"
release v1.2.3 true "https://example.org/$A" "$sum"
prov
check "a file from anywhere but the release on GitHub is refused" test ! -e "$P/root/usr/local/bin/opencode"
asset opencode extra; sum2=sha256:$(sha256sum "$P/srv/asset" | cut -d' ' -f1)
release v1.2.3 true "$url" "$sum2"
prov
check "an archive with more than the one program is refused" test ! -e "$P/root/usr/local/bin/opencode"

# ---- the extra
X=$HERE/extras/opencode-vm.sh
check "the extra fills in the repository pinned in pins.sh" grep -q 's|@OPENCODE_REPO@|$OPENCODE_REPO|g' "$X"
check "...installs no claude-pull (the git steps are printed instead)" bash -c '! grep -q claude-pull "$1" && grep -q "git diff main...origin/BRANCH" "$1"' _ "$X"
check "the shared no-abstract-sockets wrapper stays while opencode-vm needs it" grep -q 'opencode-vm-session' "$HERE/lib/core.sh"
[ "$fails" -eq 0 ]
