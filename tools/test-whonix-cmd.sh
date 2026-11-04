#!/bin/bash
# Checks the whonix command (bin/whonix) with a pretend virsh and virt-manager:
# that "whonix stop" leaves both VMs off even when they only open a shutdown
# dialog, switching off only those still running; that a start that fails says
# why; and what extras/whonix.sh does so it works right after installing.
# Nothing real is started. Run by test.sh, or:  bash tools/test-whonix-cmd.sh
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

mkdir -p "$T/bin" "$T/state"
# virsh: each VM's state is a file; "shutdown" turns it off only for a VM in
# $T/obeys (one that shuts down by itself); start fails for one in $T/broken
cat >"$T/bin/virsh" <<EOF
#!/bin/sh
shift 2   # -c qemu:///session
echo "virsh \$*" >>"$T/calls"
cmd=\$1; shift
[ "\$1" = --graceful ] && shift
case \$cmd in
    domstate) cat "$T/state/\$1" 2>/dev/null || echo "shut off" ;;
    start) if [ -e "$T/broken" ]; then echo "error: Failed to start domain '\$1'" >&2; exit 1; fi
        echo running >"$T/state/\$1" ;;
    shutdown) if grep -qx "\$1" "$T/obeys" 2>/dev/null; then echo "shut off" >"$T/state/\$1"; fi ;;
    destroy) echo "shut off" >"$T/state/\$1" ;;
esac
EOF
printf '#!/bin/sh\necho "virt-manager $*" >>"%s/calls"\n' "$T" >"$T/bin/virt-manager"
# (no notification may reach your desktop: stderr isn't a terminal here, so one is sent)
printf '#!/bin/sh\necho "notify-send $*" >>"%s/notified"\n' "$T" >"$T/bin/notify-send"
chmod +x "$T/bin/"*
w() { PATH="$T/bin:$PATH" WHONIX_STOP_WAIT=1 sh "$HERE/bin/whonix" "$@"; }
reset() { : >"$T/calls"; rm -f "$T/state/"* "$T/obeys" "$T/broken"; }

reset
w start
check "start starts the Gateway, then the Workstation, then shows it" \
    bash -c 'grep "^virsh start\|^virt-manager" "$1" | paste -sd";" | grep -qx "virsh start Whonix-Gateway;virsh start Whonix-Workstation;virt-manager -c qemu:///session --show-domain-console Whonix-Workstation"' _ "$T/calls"

reset
echo running >"$T/state/Whonix-Gateway"; echo running >"$T/state/Whonix-Workstation"
w stop 2>/dev/null
check "stop asks both to shut down first" \
    bash -c 'grep -qx "virsh shutdown Whonix-Workstation" "$1" && grep -qx "virsh shutdown Whonix-Gateway" "$1"' _ "$T/calls"
check "...and switches off those that only opened their shutdown dialog" \
    bash -c 'grep -qx "shut off" "$1/Whonix-Workstation" && grep -qx "shut off" "$1/Whonix-Gateway"' _ "$T/state"
check "...cleanly (destroy --graceful), the Workstation first" \
    bash -c 'grep "^virsh destroy" "$1" | paste -sd";" | grep -qx "virsh destroy --graceful Whonix-Workstation;virsh destroy --graceful Whonix-Gateway"' _ "$T/calls"

reset
echo running >"$T/state/Whonix-Gateway"; echo running >"$T/state/Whonix-Workstation"
printf '%s\n' Whonix-Workstation Whonix-Gateway >"$T/obeys"
w stop 2>/dev/null
check "VMs that shut down by themselves are not switched off" not grep -q '^virsh destroy' "$T/calls"

reset
touch "$T/broken"
out=$(w start 2>&1) && rc=0 || rc=$?
check "a start that fails says why, and stops" bash -c '[ "$1" -ne 0 ] && grep -q "couldn.t start Whonix-Gateway: error: Failed to start" <<<"$2"' _ "$rc" "$out"
check "...in a notification too, when there's no terminal to say it on" grep -q "couldn.t start Whonix-Gateway" "$T/notified"
check "...without opening an empty window" not grep -q '^virt-manager' "$T/calls"

# Right after installing, without logging out and in
X=$HERE/extras/whonix.sh
check "whonix.sh gives you /dev/kvm now if the new kvm group hasn't applied yet" \
    bash -c 'grep -q "setfacl -m \"u:\$(id -un):rw\" /dev/kvm" "$1"' _ "$X"
check "the first start of sway puts ~/.local/bin in its PATH (commands installed then are found)" \
    bash -c 'sed -n "/^if \[ \"\$first_run\" = 1 \]/,/^fi/p" "$1" | grep -q "PATH=\"\$HOME/.local/bin:\$PATH\""' _ "$HERE/install-base.sh"

[ "$fails" -eq 0 ]
