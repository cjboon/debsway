#!/bin/bash
# Checks the whonix command (bin/whonix) with a pretend virsh and virt-manager:
# that "whonix stop" leaves both VMs off even when they only open a shutdown
# dialog, switching off only those still running; that a start that fails says
# why; and what extras/whonix.sh does so it works right after installing.
# Nothing real is started. Run by test.sh, or:  bash tools/test-whonix-cmd.sh
# shellcheck disable=SC2016  # the inner bash expands its own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
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
    dumpxml) [ -e "$T/wren-net" ] && echo "<qemu:arg value='{&quot;id&quot;: &quot;wren-gw-net&quot;}'/>" ;;
    destroy) echo "shut off" >"$T/state/\$1" ;;
esac
EOF
printf '#!/bin/sh\necho "virt-manager $*" >>"%s/calls"\n' "$T" >"$T/bin/virt-manager"
# passt: writes down how it was started (and fails for $T/passt-broken)
printf '#!/bin/sh\n[ -e "%s/passt-broken" ] && exit 1\necho "passt $*" >>"%s/calls"\n' "$T" "$T" >"$T/bin/passt"
# (no notification may reach your desktop: stderr isn't a terminal here, so one is sent)
printf '#!/bin/sh\necho "notify-send $*" >>"%s/notified"\n' "$T" >"$T/bin/notify-send"
chmod +x "$T/bin/"*
mkdir -p "$T/home"
w() { HOME=$T/home PATH="$T/bin:$PATH" WHONIX_STOP_WAIT=1 sh "$HERE/bin/whonix" "$@"; }
reset() { : >"$T/calls"; rm -f "$T/state/"* "$T/obeys" "$T/broken" "$T/wren-net" "$T/passt-broken"; }

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

# The Gateway's own network: passt, locked down, started before the Gateway
reset
w start
check "a Gateway from before (libvirt's own card): no passt of Wren Linux's" not grep -q '^passt' "$T/calls"
reset
: >"$T/wren-net"
w start
p=$(grep '^passt ' "$T/calls")
check "a Gateway with Wren Linux's card: passt first, then the Gateway" bash -c '
    grep "^passt\|^virsh start" "$1" | cut -d" " -f1-3 | paste -sd";" | grep -q "^passt [^;]*;virsh start Whonix-Gateway"' _ "$T/calls"
for o in --one-off --ipv4-only "--address 10.0.2.15" "--netmask 24" "--gateway 10.0.2.2" --no-map-gw "--dns-forward 10.0.2.3" --no-dhcp; do
    check "...passt $o" grep -q -- " $o" <<<"$p"
done
check "...its socket where the Gateway's card connects (extras/whonix.sh), in a folder only you can open" bash -c '
    sock=$(sed -n "s|^GW_NET_SOCK=\"\$HOME/\(.*\)\"$|\1|p" "$3")
    [ -n "$sock" ] && grep -q -- "--socket $2/$sock " <<<"$1" && [ "$(stat -c %a "$2/${sock%/*}")" = 700 ]' _ "$p" "$T/home" "$HERE/extras/whonix.sh"
check "...where passt's AppArmor profile lets it (owner @{HOME}/**)" bash -c '
    grep -q "^GW_NET_SOCK=\"\$HOME/" "$1"' _ "$HERE/extras/whonix.sh"
reset
: >"$T/wren-net"; : >"$T/passt-broken"
out=$(w start 2>&1) && rc=0 || rc=$?
check "passt won't start: the Gateway isn't started either, and it says so" bash -c '
    [ "$1" -ne 0 ] && grep -q "network (passt)" <<<"$2" && ! grep -q "^virsh start" "$3"' _ "$rc" "$out" "$T/calls"
reset
: >"$T/wren-net"; echo running >"$T/state/Whonix-Gateway"
w gateway
check "the Gateway running already: its passt isn't started again" not grep -q '^passt' "$T/calls"

# webtunnel's program in the Gateway: said when the one here (apt's) is newer
printf '#!/bin/sh\ncat "%s/lyrebird-here"\n' "$T" >"$T/bin/dpkg-query"
chmod +x "$T/bin/dpkg-query"
mkdir -p "$T/home/.local/state/wren"
lyr() { echo "$1" >"$T/lyrebird-here"; rm -f "$T/notified"; reset; w gateway 2>&1; }
echo 0.6.1-1 >"$T/home/.local/state/wren/whonix-lyrebird-version"
check "the Gateway's lyrebird as new as the one here: nothing said" test -z "$(lyr 0.6.1-1)"
out=$(lyr 0.6.2-1)
check "...a newer one here: it says so, and how to copy it in" bash -c '
    grep -q "lyrebird 0.6.2-1 is out; the Gateway has 0.6.1-1" <<<"$1" && grep -q "wrenctl install whonix --bridges" <<<"$1"' _ "$out"
check "...in a notification too, with no terminal" grep -q "lyrebird 0.6.2-1 is out" "$T/notified"
check "...and the Gateway still starts" grep -q '^virsh start Whonix-Gateway' "$T/calls"
rm -f "$T/home/.local/state/wren/whonix-lyrebird-version"
check "no webtunnel in the Gateway: nothing said" test -z "$(lyr 0.6.2-1)"

# Right after installing, without logging out and in
X=$HERE/extras/whonix.sh
check "whonix.sh gives you /dev/kvm now if the new kvm group hasn't applied yet" \
    bash -c 'grep -q "setfacl -m \"u:\$(id -un):rw\" /dev/kvm" "$1"' _ "$X"
check "the first start of sway puts ~/.local/bin in its PATH (commands installed then are found)" \
    bash -c 'sed -n "/^if \[ \"\$first_run\" = 1 \]/,/^fi/p" "$1" | grep -q "PATH=\"\$HOME/.local/bin:\$PATH\""' _ "$HERE/install-base.sh"

[ "$fails" -eq 0 ]
