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
    shutdown)
        # (a VM still starting isn't listening for its power button yet: the press is lost)
        if [ -s "$T/deaf" ]; then sed -i 1d "$T/deaf"; exit 0; fi
        if grep -qx "\$1" "$T/obeys" 2>/dev/null; then echo "shut off" >"$T/state/\$1"; fi ;;
    dumpxml)
        echo "<domain type='kvm'><name>\$2</name><serial type='pty'><target port='0'/></serial>"
        [ -e "$T/wren-net" ] && echo "<qemu:commandline><qemu:arg value='{&quot;id&quot;: &quot;wren-gw-net&quot;}'/></qemu:commandline>"
        echo "</domain>" ;;
    create)
        [ ! -e "$T/create-broken" ] || { echo "error: no such thing" >&2; exit 1; }
        name=\$(sed -n 's|.*<name>\(.*\)</name>.*|\1|p' "\$1")
        echo "virsh create \$name" >>"$T/calls"
        cp "\$1" "$T/created-\$name.xml"
        logf=\$(sed -n 's|.*<log file="\([^"]*\)".*|\1|p' "\$1")
        if [ -e "$T/says-\$name" ]; then cat "$T/says-\$name" >"\$logf"; else printf 'lots of apt\r\nWREN-RESULT: ok\r\n' >"\$logf"; fi
        if [ -e "$T/state-after-\$name" ]; then cat "$T/state-after-\$name" >"$T/state/\$name"; else echo "shut off" >"$T/state/\$name"; fi ;;
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
w() { env -u SWAYSOCK -u WAYLAND_DISPLAY -u DISPLAY HOME="$T/home" PATH="$T/bin:$PATH" WHONIX_STOP_WAIT=1 WHONIX_UPDATE_POLL=0.1 \
    WHONIX_TTY="${TTY_FILE:-$T/no-terminal}" sh "$HERE/bin/whonix" "$@"; }
reset() { : >"$T/calls"; rm -f "$T/state/"* "$T/obeys" "$T/broken" "$T/wren-net" "$T/passt-broken" "$T/create-broken" "$T"/says-* "$T"/state-after-* "$T"/created-*; }

reset
w start
/bin/sleep 0.3   # (virt-manager runs on its own, in the background)
check "start starts the Gateway, then the Workstation, then opens both" \
    bash -c 'grep "^virsh start\|^virt-manager" "$1" | paste -sd";" | grep -qx "virsh start Whonix-Gateway;virsh start Whonix-Workstation;virt-manager -c qemu:///session --show-domain-console Whonix-Gateway;virt-manager -c qemu:///session --show-domain-console Whonix-Workstation"' _ "$T/calls"

reset
echo running >"$T/state/Whonix-Gateway"; echo running >"$T/state/Whonix-Workstation"
out=$(w stop 2>&1) && rc=0 || rc=$?
check "stop asks both to shut down first" \
    bash -c 'grep -qx "virsh shutdown Whonix-Workstation" "$1" && grep -qx "virsh shutdown Whonix-Gateway" "$1"' _ "$T/calls"
check "...one that doesn't: never switched off unasked, it fails, and says what to do" bash -c '
    ! grep -q "^virsh destroy" "$1" && [ "$2" -ne 0 ] && grep -q "still running" <<<"$3" && grep -q "whonix stop --force" <<<"$3"' _ "$T/calls" "$rc" "$out"

reset
echo running >"$T/state/Whonix-Gateway"; echo running >"$T/state/Whonix-Workstation"
w stop --force 2>/dev/null
check "stop --force asks first too" grep -qx "virsh shutdown Whonix-Workstation" "$T/calls"
check "...and switches off those still running" \
    bash -c 'grep -qx "shut off" "$1/Whonix-Workstation" && grep -qx "shut off" "$1/Whonix-Gateway"' _ "$T/state"
check "...cleanly (destroy --graceful), the Workstation first" \
    bash -c 'grep "^virsh destroy" "$1" | paste -sd";" | grep -qx "virsh destroy --graceful Whonix-Workstation;virsh destroy --graceful Whonix-Gateway"' _ "$T/calls"

reset
echo running >"$T/state/Whonix-Gateway"; echo running >"$T/state/Whonix-Workstation"
printf '%s\n' Whonix-Workstation Whonix-Gateway >"$T/obeys"
w stop 2>/dev/null; rc=$?
check "VMs that shut down by themselves are not switched off" not grep -q '^virsh destroy' "$T/calls"
check "...and that counts as done" test "$rc" = 0
out=$(w stop --now 2>&1) && rc=0 || rc=$?
check "stop with anything else: refused, nothing shut down" bash -c '
    [ "$1" -ne 0 ] && grep -q usage <<<"$2"' _ "$rc" "$out"

# The power button: a rule of acpid's in both images, which powers off with no
# desktop involved (tried on a real Whonix 18.2.4.2: both off in 5 s, disks clean)
P=$HERE/data/whonix-power-button
check "the rule: the power button powers off, past the desktop's dialog" bash -c '
    grep -qx "event=button\[ /\]power" "$1" && grep -qx "action=/usr/bin/systemctl poweroff --ignore-inhibitors" "$1" &&
    [ "$(grep -vc "^#" "$1")" = 2 ]' _ "$P"
check "...written into the Gateway" bash -c '
    sed -n "/^gateway_config()/,/^}/p" "$1" | grep -q "whonix-power-button\" /etc/acpi/events/wren-power-button"' _ "$HERE/extras/whonix.sh"
check "...and the Workstation" bash -c '
    grep "^ws_files=" "$1" | grep -q "whonix-power-button\" /etc/acpi/events/wren-power-button"' _ "$HERE/extras/whonix.sh"

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

# Nothing to stop: it says so, rather than nothing at all
reset
out=$(w stop 2>&1) && rc=0 || rc=$?
check "whonix stop with nothing running: it says there is nothing to stop" bash -c '[ "$1" = 0 ] && grep -q "aren.t running right now so there is nothing to stop" <<<"$2"' _ "$rc" "$out"
check "...and presses no button" not grep -q '^virsh shutdown' "$T/calls"
out=$(w stop --force 2>&1) && rc=0 || rc=$?
check "...with --force too" bash -c '[ "$1" = 0 ] && grep -q "nothing to stop" <<<"$2"' _ "$rc" "$out"
echo running >"$T/state/Whonix-Gateway"; echo Whonix-Gateway >"$T/obeys"
out=$(w stop 2>&1)
check "...but not when one was running" not grep -q 'nothing to stop' <<<"$out"

# A press in about the first 70 seconds after a start is lost (seen on a real Workstation)
reset; echo running >"$T/state/Whonix-Workstation"; echo Whonix-Workstation >"$T/obeys"; echo lost >"$T/deaf"
env -u SWAYSOCK -u WAYLAND_DISPLAY -u DISPLAY HOME="$T/home" PATH="$T/bin:$PATH" WHONIX_STOP_WAIT=7 WHONIX_TTY="$T/no-terminal" sh "$HERE/bin/whonix" stop >/dev/null 2>&1
check "whonix stop presses again: a press a VM still starting didn't hear isn't the last" test "$(cat "$T/state/Whonix-Workstation")" = "shut off"
rm -f "$T/deaf"

# ---- whonix update ----
ST=$T/home/.local/state/wren
STAMP=$ST/whonix-updated
mkdir -p "$ST"
old_stamp() { touch -d '10 days ago' "$STAMP"; }
is_old() { [ -n "$(find "$STAMP" -mmin +14000)" ]; }
is_new() { [ -z "$(find "$STAMP" -mmin +5)" ]; }
# (the pretend virsh writes create down twice: as called, and which VM)
creates() { grep '^virsh create\|^virsh start\|^virsh shutdown' "$T/calls" | grep -v '^virsh create /' | paste -sd';'; }

reset; rm -f "$STAMP"
out=$(w update 2>&1) && rc=0 || rc=$?
check "an install from before whonix update: refused, it says what to do, and nothing starts" bash -c '
    [ "$1" -ne 0 ] && grep -q "installed before whonix update" <<<"$2" && ! grep -qE "^virsh (create|start)" "$3"' _ "$rc" "$out" "$T/calls"

reset; old_stamp; echo running >"$T/state/Whonix-Gateway"
out=$(w update 2>&1) && rc=0 || rc=$?
check "Whonix running: refused (your work is in there), and nothing else starts" bash -c '
    [ "$1" -ne 0 ] && grep -q "whonix stop" <<<"$2" && ! grep -q "^virsh create" "$3"' _ "$rc" "$out" "$T/calls"
check "...the 7 days don't reset" is_old

reset; old_stamp; : >"$T/obeys"; echo Whonix-Gateway >"$T/obeys"
out=$(w update 2>&1) && rc=0 || rc=$?
check "the Gateway updates first, then runs for the Workstation to update, then shuts down" \
    test "$(creates)" = "virsh create Whonix-Gateway;virsh start Whonix-Gateway;virsh create Whonix-Workstation;virsh shutdown Whonix-Gateway"
check "...each started with the note, its serial port logged" bash -c '
    for v in Gateway Workstation; do
        grep -qF "<qemu:arg value=\"type=11,value=io.systemd.credential:wren.update=1\"/>" "$1/created-Whonix-$v.xml" &&
        grep -q "<log file=\"$2/Whonix-$v-update.log\" append=\"off\"/>" "$1/created-Whonix-$v.xml" || exit 1
    done' _ "$T" "$ST"
check "...which virsh can read (well formed)" bash -c '! command -v xmllint >/dev/null || xmllint --noout "$1"/created-Whonix-*.xml' _ "$T"
check "...from a copy: its saved settings aren't changed, so the next start is an ordinary one" not grep -qE '^virsh (define|edit)' "$T/calls"
check "...it worked: the 7 days start again" is_new
check "...it says so, and leaves no log or copy behind" bash -c '
    [ "$1" = 0 ] && grep -q "up to date" <<<"$2" && [ -z "$(ls "$3" | grep -E -- "-update\.(log|xml)")" ]' _ "$rc" "$out" "$ST"

reset; : >"$T/wren-net"; old_stamp; echo Whonix-Gateway >"$T/obeys"
w update >/dev/null 2>&1
check "the Gateway's own network: passt before each of its two starts" test "$(grep -c '^passt ' "$T/calls")" = 2
check "...its card kept in the copy, the note beside it" bash -c 'grep -q "wren-gw-net" "$1" && grep -q "wren.update=1" "$1" && [ "$(grep -c "<qemu:commandline>" "$1")" = 1 ]' _ "$T/created-Whonix-Gateway.xml"

reset; old_stamp; printf 'WREN-RESULT: failed: apt\r\n' >"$T/says-Whonix-Gateway"
out=$(w update 2>&1) && rc=0 || rc=$?
check "the Gateway's update fails: it stops there" test "$(creates)" = "virsh create Whonix-Gateway"
check "...says why, and the 7 days don't reset" bash -c '[ "$1" -ne 0 ] && grep -q "failed: apt" <<<"$2" && grep -q "reminder stays" <<<"$2"' _ "$rc" "$out"
check "...still due" is_old
check "...the log is kept, to look at" test -e "$ST/Whonix-Gateway-update.log"

reset; old_stamp; echo Whonix-Gateway >"$T/obeys"; printf 'WREN-RESULT: failed: Tor Browser\r\n' >"$T/says-Whonix-Workstation"
out=$(w update 2>&1) && rc=0 || rc=$?
check "the Workstation's fails: the Gateway is still shut down, and the 7 days don't reset" bash -c '
    [ "$1" -ne 0 ] && grep -q "^virsh shutdown Whonix-Gateway" "$2" && grep -q "failed: Tor Browser" <<<"$3"' _ "$rc" "$T/calls" "$out"
check "...still due" is_old

# What the VM says is only compared with one exact line, and it may be from a hacked VM
for lie in 'WREN-RESULT: okay' 'WREN-RESULT: ok and more' ' WREN-RESULT: ok' 'x WREN-RESULT: ok' 'wren-result: ok' 'nothing at all'; do
    reset; old_stamp; printf '%s\r\n' "$lie" >"$T/says-Whonix-Gateway"
    w update >/dev/null 2>&1
    check "it says \"$lie\": not counted" is_old
done
reset; old_stamp; printf 'WREN-RESULT: ok\nWREN-RESULT: failed: apt\n' >"$T/says-Whonix-Gateway"
w update >/dev/null 2>&1
check "...only its last word counts" is_old
reset; old_stamp; printf 'WREN-RESULT: failed: \033]0;owned\007\033[2J$(reboot)\r\n' >"$T/says-Whonix-Gateway"
out=$(w update 2>&1)
check "what a VM says can't steer your terminal: control characters and the like are taken out" bash -c '
    ! grep -q "$(printf "\033")" <<<"$1" && ! grep -qF "\$(reboot)" <<<"$1"' _ "$out"

reset; old_stamp; echo running >"$T/state-after-Whonix-Gateway"
out=$(WHONIX_UPDATE_LIMIT=1 w update 2>&1) && rc=0 || rc=$?
check "an update that never ends is switched off, and doesn't count" bash -c '
    [ "$1" -ne 0 ] && grep -q "^virsh destroy Whonix-Gateway" "$2" && grep -q "switched off" <<<"$3"' _ "$rc" "$T/calls" "$out"
check "...still due" is_old
reset; old_stamp; echo running >"$T/state-after-Whonix-Gateway"; printf 'more than the limit\n' >"$T/says-Whonix-Gateway"
out=$(WHONIX_UPDATE_LOG_MAX=4 w update 2>&1) && rc=0 || rc=$?
check "a VM that writes without end is switched off: it can't fill this disk" bash -c '[ "$1" -ne 0 ] && grep -q "^virsh destroy Whonix-Gateway" "$2"' _ "$rc" "$T/calls"
reset; old_stamp; echo paused >"$T/state-after-Whonix-Gateway"
out=$(w update 2>&1) && rc=0 || rc=$?
check "paused (a full disk here): it says so, and stops" bash -c '[ "$1" -ne 0 ] && grep -q "disk here is full" <<<"$2"' _ "$rc" "$out"
reset; old_stamp; : >"$T/create-broken"
out=$(w update 2>&1) && rc=0 || rc=$?
check "it can't start: it says why, and doesn't count" bash -c '[ "$1" -ne 0 ] && grep -q "no such thing" <<<"$2"' _ "$rc" "$out"
check "...still due" is_old

# While an update runs: another, starting Whonix, stopping it
reset; old_stamp
flock "$ST/whonix-update.lock" /bin/sleep 30 &
locker=$!
i=0; while [ "$i" -lt 50 ] && flock -n "$ST/whonix-update.lock" true; do /bin/sleep 0.1; i=$((i + 1)); done
out=$(w update 2>&1) && rc=0 || rc=$?
check "while one runs, a second update is refused" bash -c '[ "$1" -ne 0 ] && grep -q "running already" <<<"$2" && ! grep -q "^virsh create" "$3"' _ "$rc" "$out" "$T/calls"
echo running >"$T/state/Whonix-Gateway"
out=$(w stop 2>&1) && rc=0 || rc=$?
check "...whonix stop won't press the power button in the middle of apt" bash -c '[ "$1" -ne 0 ] && grep -q "is updating" <<<"$2" && ! grep -q "^virsh shutdown" "$3"' _ "$rc" "$out" "$T/calls"
reset
echo n >"$T/tty"
out=$(TTY_FILE=$T/tty w start 2>&1) && rc=0 || rc=$?
check "...starting Whonix: n cancels that, and only that" bash -c '[ "$1" = 0 ] && grep -q "update goes on" <<<"$2" && ! grep -qE "^virsh|^virt-manager" <<<"$(grep -v domstate "$3")"' _ "$rc" "$out" "$T/calls"
check "...the update still holds its lock" bash -c '! flock -n "$1" true' _ "$ST/whonix-update.lock"
out=$(w start 2>&1) && rc=0 || rc=$?
check "...with no terminal and no sway: it says so, and starts nothing" bash -c '[ "$1" -ne 0 ] && grep -q "is updating" <<<"$2" && ! grep -q "^virsh start" "$3"' _ "$rc" "$out" "$T/calls"
printf '#!/bin/sh\necho "foot $*" >>"%s/calls"\n' "$T" >"$T/bin/foot"
printf '#!/bin/sh\n' >"$T/bin/swaymsg"
chmod +x "$T/bin/foot" "$T/bin/swaymsg"
SWAYSOCK=x HOME="$T/home" PATH="$T/bin:$PATH" WHONIX_TTY="$T/no-terminal" sh "$HERE/bin/whonix" start
check "...from Super+d, in sway: a window to ask in" grep -q '^foot --title=Whonix .*bin/whonix start$' "$T/calls"
rm -f "$T/bin/foot" "$T/bin/swaymsg"
reset
: >"$T/tty"
(TTY_FILE=$T/tty w start >"$T/waited" 2>&1; echo "finished" >>"$T/waited") &
waiter=$!
/bin/sleep 0.5
check "...Enter: it waits, and hasn't started anything yet" not grep -q '^virsh start' "$T/calls"
pkill -P "$locker" 2>/dev/null; kill "$locker" 2>/dev/null
wait "$locker" 2>/dev/null
i=0; while [ "$i" -lt 100 ] && ! grep -q finished "$T/waited"; do /bin/sleep 0.1; i=$((i + 1)); done
check "...and opens it when the update is done" grep -q '^virsh start Whonix-Workstation' "$T/calls"
wait "$waiter" 2>/dev/null

# The question at whonix stop
both_on() { reset; echo running >"$T/state/Whonix-Gateway"; echo running >"$T/state/Whonix-Workstation"; printf '%s\n' Whonix-Workstation Whonix-Gateway >"$T/obeys"; }
both_on; old_stamp; echo >"$T/tty"; : >"$T/asked"
out=$(TTY_FILE=$T/tty w stop 2>&1)
check "over 7 days: whonix stop shuts down, and Enter means no update" bash -c '! grep -q "^virsh create" "$1" && grep -q "^virsh shutdown" "$1" && [ -z "$(find "$2" -mmin -5)" ]' _ "$T/calls" "$STAMP"
both_on; old_stamp; echo y >"$T/tty"
TTY_FILE=$T/tty w stop >/dev/null 2>&1; rc=$?
check "...y: it shuts down first, then updates" bash -c '
    a=$(grep -n "^virsh shutdown Whonix-Workstation" "$1" | head -1 | cut -d: -f1); b=$(grep -n "^virsh create Whonix-Gateway" "$1" | cut -d: -f1)
    [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] && [ "$2" = 0 ]' _ "$T/calls" "$rc"
check "...and that counts" is_new
both_on; old_stamp; echo y >"$T/tty"; rm -f "$T/obeys"
TTY_FILE=$T/tty w stop >/dev/null 2>&1; rc=$?
check "...y, but it won't shut down: no update on top of a running VM" bash -c '[ "$1" -ne 0 ] && ! grep -q "^virsh create" "$2"' _ "$rc" "$T/calls"
both_on; touch "$STAMP"; echo y >"$T/tty"
TTY_FILE=$T/tty w stop >/dev/null 2>&1
check "under 7 days: it doesn't ask" not grep -q '^virsh create' "$T/calls"
both_on; touch -d '6 days ago' "$STAMP"; echo y >"$T/tty"
TTY_FILE=$T/tty w stop >/dev/null 2>&1
check "...6 days: not yet" not grep -q '^virsh create' "$T/calls"
both_on; old_stamp
w stop >/dev/null 2>&1
check "no terminal to ask on: it just shuts down" bash -c 'grep -q "^virsh shutdown" "$1" && ! grep -q "^virsh create" "$1"' _ "$T/calls"
both_on; old_stamp; echo y >"$T/tty"
TTY_FILE=$T/tty w stop --force >/dev/null 2>&1
check "whonix stop --force: never asks" not grep -q '^virsh create' "$T/calls"
both_on; rm -f "$STAMP"; echo y >"$T/tty"
TTY_FILE=$T/tty w stop >/dev/null 2>&1
check "an install from before whonix update: never asks" not grep -q '^virsh create' "$T/calls"
reset; old_stamp; echo y >"$T/tty"
TTY_FILE=$T/tty w stop >/dev/null 2>&1
check "both off already: nothing to ask about" not grep -q '^virsh create' "$T/calls"

# The bar
mkdir -p "$T/bh/.local/bin" "$T/bh/.local/state/wren"
bar() { HOME="$T/bh" timeout 10 sh "$HERE/bin/sway-status" --whonix; }
check "the bar: no Whonix, nothing" test -z "$(bar)"
printf '#!/bin/sh\n' >"$T/bh/.local/bin/whonix"; chmod +x "$T/bh/.local/bin/whonix"
check "...Whonix from before whonix update: nothing (nothing inside it could answer)" test -z "$(bar)"
touch -d '6 days ago' "$T/bh/.local/state/wren/whonix-updated"
check "...updated 6 days ago: nothing" test -z "$(bar)"
touch -d '8 days ago' "$T/bh/.local/state/wren/whonix-updated"
check "...8 days ago: the reminder" test "$(bar)" = "whonix update"
S=$HERE/bin/sway-status
check "...in the colour you can't miss, in both bars" test "$(grep -cF '$(alert whonix "$(whonix_due)")' "$S")" = 2
check "...a click runs it, in a window that waits for you to read how it went" bash -c '
    sed -n "/\"name\":\"whonix\"/,/;;/p" "$1" | grep -q "whonix\" update; echo; printf \"Press Enter to close" ' _ "$S"
check "...on the text console's bar too" grep -q 'whonix:1) pop .*whonix update;' "$HERE/bin/console-click"

# Each window on an empty workspace: in a sway of its own (headless, nothing
# on your screen), with a virt-manager that opens a foot window with its title
if command -v sway >/dev/null && command -v foot >/dev/null && command -v python3 >/dev/null; then
    S=$(mktemp -d /tmp/wsw.XXXX)   # (short: sway's socket path has a length limit)
    mkdir "$S/bin"
    : >"$S/config"
    printf '#!/bin/sh\ncase $3 in domstate) echo running ;; esac\n' >"$S/bin/virsh"
    printf '#!/bin/sh\n(/bin/sleep 0.5; exec foot --title="$4 on QEMU/KVM User session" /bin/sleep 60) >/dev/null 2>&1 &\necho $! >>"%s/windows"\n' "$S" >"$S/bin/virt-manager"
    chmod +x "$S/bin/"*
    XDG_RUNTIME_DIR=$S WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 sway -c "$S/config" >/dev/null 2>&1 &
    swaypid=$!
    i=0
    while [ "$i" -lt 30 ] && ! ls "$S"/sway-ipc.* >/dev/null 2>&1; do /bin/sleep 0.2; i=$((i + 1)); done
    sock=$(ls "$S"/sway-ipc.* 2>/dev/null)
    disp=
    for f in "$S"/wayland-[0-9]*; do case $f in *.lock) ;; *) disp=${f##*/} ;; esac; done
    sm() { XDG_RUNTIME_DIR=$S SWAYSOCK=$sock swaymsg "$@"; }
    # where: "WORKSPACE:WINDOW ..." and the workspace you are on
    where() {
        sm -t get_tree | python3 -I -c '
import json, sys
out, here = [], None
def walk(n, ws=None):
    global here
    if n.get("type") == "workspace": ws = n["name"]
    if n.get("focused"): here = ws
    if n.get("pid"): out.append(ws + ":" + n["name"].split(" on ")[0])
    for c in n.get("nodes", []) + n.get("floating_nodes", []): walk(c, ws)
walk(json.load(sys.stdin))
print(" ".join(sorted(out)) + " | " + str(here))'
    }
    busy() { sm "workspace number $1" >/dev/null; XDG_RUNTIME_DIR=$S WAYLAND_DISPLAY=$disp foot --title="busy$1" /bin/sleep 60 >/dev/null 2>&1 &
        echo $! >>"$S/windows"; shown "busy$1"; }
    # shown TITLE...: wait (up to 10 s) until each of these windows is open
    shown() {
        local i=0 t
        while [ "$i" -lt 50 ]; do
            for t in "$@"; do grep -q "[0-9]:$t\b" <<<"$(where)" || break; done
            grep -q "[0-9]:$t\b" <<<"$(where)" && return 0
            /bin/sleep 0.2; i=$((i + 1))
        done
    }
    # (the windows these checks opened, by their numbers: nothing else is closed)
    clear_all() {
        # shellcheck disable=SC2046  # one number a line
        [ ! -s "$S/windows" ] || kill $(cat "$S/windows") 2>/dev/null
        : >"$S/windows"; /bin/sleep 0.4; sm "workspace number 1" >/dev/null
    }
    sw() { XDG_RUNTIME_DIR=$S SWAYSOCK=$sock WAYLAND_DISPLAY=$disp HOME=$T/home PATH="$S/bin:$PATH" sh "$HERE/bin/whonix" start; }
    if [ -n "$sock" ]; then
        sw
        check "in sway: the Gateway on the empty workspace you are on, the Workstation on the next, you with it" \
            test "$(where)" = "1:Whonix-Gateway 2:Whonix-Workstation | 2"
        clear_all; busy 2; busy 1; sw
        check "...yours and the next one busy: the next empty ones to the right" \
            test "$(where)" = "1:busy1 2:busy2 3:Whonix-Gateway 4:Whonix-Workstation | 4"
        clear_all; busy 10; busy 9; sw
        check "...nothing free to the right: to the left" \
            test "$(where)" = "10:busy10 7:Whonix-Workstation 8:Whonix-Gateway 9:busy9 | 7"
        clear_all
        mkdir -p "$T/home/.config/sway/config.d"
        : >"$T/home/.config/sway/config.d/one-workspace.conf"
        sw; shown Whonix-Gateway Whonix-Workstation
        check "...with one-workspace: both on the one screen" \
            test "$(where)" = "1:Whonix-Gateway 1:Whonix-Workstation | 1"
        rm -rf "$T/home/.config"
        clear_all
        # As the real one does on a desktop: it stays in front until its window closes,
        # and the first window can take longer than you'd think
        cat >"$S/bin/virt-manager" <<VM
#!/bin/sh
[ ! -e "$S/no-window" ] || exit 1
echo \$\$ >>"$S/windows"
[ "\$4" != Whonix-Gateway ] || /bin/sleep "\$(cat "$S/delay")"
exec foot --title="\$4 on QEMU/KVM User session" /bin/sleep 60
VM
        printf '#!/bin/sh\necho "$*" >>"%s/notified"\n' "$S" >"$S/bin/notify-send"
        chmod +x "$S/bin/virt-manager" "$S/bin/notify-send"
        # (timeout: whonix waiting on a window is the bug these look for)
        swt() { XDG_RUNTIME_DIR=$S SWAYSOCK=$sock WAYLAND_DISPLAY=$disp HOME=$T/home PATH="$S/bin:$PATH" timeout 30 sh "$HERE/bin/whonix" "$@"; }
        echo 0.5 >"$S/delay"
        began=$(date +%s); swt start; rc=$?; took=$(($(date +%s) - began))
        check "virt-manager stays in front: whonix still places both, you with the Workstation" \
            test "$(where)" = "1:Whonix-Gateway 2:Whonix-Workstation | 2"
        check "...and gives your terminal back, the windows left open" bash -c '[ "$1" = 0 ] && [ "$2" -lt 25 ]' _ "$rc" "$took"
        clear_all
        echo 12 >"$S/delay"
        swt start; rc=$?
        check "the Gateway's window takes 12 seconds: still moved, and the Workstation still opens" \
            bash -c '[ "$1" = 0 ] && [ "$2" = "1:Whonix-Gateway 2:Whonix-Workstation | 2" ]' _ "$rc" "$(where)"
        clear_all
        echo 0.5 >"$S/delay"
        swt gateway; rc=$?
        check "whonix gateway gives your terminal back too" bash -c '[ "$1" = 0 ] && [ "$2" = "1:Whonix-Gateway | 1" ]' _ "$rc" "$(where)"
        clear_all
        : >"$S/no-window"
        out=$(WHONIX_WINDOW_WAIT=1 swt start 2>&1); rc=$?
        check "no window ever appears: it fails, and says which and where to look" bash -c '
            [ "$1" -ne 0 ] && grep -q "couldn.t open the window of Whonix-Gateway" <<<"$2" && grep -q "Whonix-Gateway-console.log" <<<"$2"' _ "$rc" "$out"
        rm -f "$S/no-window"
        clear_all
    else
        check "a headless sway starts for the workspace checks" false
    fi
    kill "$swaypid" 2>/dev/null
    wait "$swaypid" 2>/dev/null
    rm -rf "$S"
fi

# Right after installing, without logging out and in
X=$HERE/extras/whonix.sh
check "whonix.sh gives you /dev/kvm now if the new kvm group hasn't applied yet" \
    bash -c 'grep -q "setfacl -m \"u:\$(id -un):rw\" /dev/kvm" "$1"' _ "$X"
check "the first start of sway puts ~/.local/bin in its PATH (commands installed then are found)" \
    bash -c 'sed -n "/^if \[ \"\$first_run\" = 1 \]/,/^fi/p" "$1" | grep -q "PATH=\"\$HOME/.local/bin:\$PATH\""' _ "$HERE/install-base.sh"

[ "$fails" -eq 0 ]
