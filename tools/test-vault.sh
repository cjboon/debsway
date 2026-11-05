#!/bin/bash
# Checks bin/vault (extras/vault.sh): open mounts the vault and starts a timer
# that closes it (an hour, --for TIME, or --no-timeout); the timer closes it
# when its time is up or the screen locks; close unmounts it, and if a program
# still has a file open in it, closes it anyway and ends gocryptfs, which holds
# the key. Runs with a pretend gocryptfs, fusermount3, mountpoint, systemd-run,
# systemctl, pgrep and pkill in a temp home, so nothing is mounted and nothing on
# this computer changes. Run by test.sh, or:  bash tools/test-vault.sh
# shellcheck disable=SC2016  # the pretend programs expand their own variables
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

mkdir -p "$T/bin" "$T/home"
# The vault is "open" while $T/mounted exists; "busy" while $T/busy does;
# the screen is "locked" while $T/locked does
cat >"$T/bin/gocryptfs" <<EOF
#!/bin/sh
echo "gocryptfs \$*" >>"$T/calls"
case "\$1" in -init) mkdir -p "\$4" && : >"\$4/gocryptfs.conf" ;; *) : >"$T/mounted" ;; esac
EOF
cat >"$T/bin/mountpoint" <<EOF
#!/bin/sh
[ -e "$T/mounted" ]
EOF
cat >"$T/bin/fusermount3" <<EOF
#!/bin/sh
echo "fusermount3 \$*" >>"$T/calls"
case "\$*" in *-z*) rm -f "$T/mounted" ;; *) [ ! -e "$T/busy" ] || exit 1; rm -f "$T/mounted" ;; esac
EOF
cat >"$T/bin/pgrep" <<EOF
#!/bin/sh
[ -e "$T/locked" ]
EOF
for p in systemd-run systemctl pkill notify-send; do
    printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\n' "$p" "$T" >"$T/bin/$p"
done
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH" HOME=$T/home XDG_STATE_HOME=$T/home/.local/state WREN_VAULT_POLL=0
V=$HERE/bin/vault
C=$T/home/.local/share/wren-vault
run() { : >"$T/calls"; bash "$V" "$@" >"$T/out" 2>&1; }

run open
check "no vault yet: open says how to make one" grep -q 'wrenctl install vault' "$T/out"
mkdir -p "$C" && : >"$C/gocryptfs.conf"

now=$(date +%s)
run open
check "open: gocryptfs mounts it in ~/Vault (and asks for the password)" grep -qx "gocryptfs -q $C $T/home/Vault" "$T/calls"
check "...~/Vault only yours" test "$(stat -c %a "$T/home/Vault")" = 700
until=$(sed -n 's/.* watch //p' "$T/calls")
check "...and starts the timer, as a user service, for an hour" bash -c '[ "$1" -ge $(($2 + 3590)) ] && [ "$1" -le $(($2 + 3610)) ]' _ "$until" "$now"
check "...which outlives the terminal (systemd-run --user)" grep -q '^systemd-run --user .*--unit=wren-vault-watch' "$T/calls"
check "status: open, and how long for" grep -q 'closes in 60 minutes' <<<"$(bash "$V" status)"
rm -f "$T/mounted"
run open --for 2h
until=$(sed -n 's/.* watch //p' "$T/calls")
check "--for 2h: two hours" bash -c '[ "$1" -ge $(($2 + 7190)) ] && [ "$1" -le $(($2 + 7210)) ]' _ "$until" "$now"
rm -f "$T/mounted"
run open --for 30m
until=$(sed -n 's/.* watch //p' "$T/calls")
check "--for 30m: half an hour" bash -c '[ "$1" -ge $(($2 + 1790)) ] && [ "$1" -le $(($2 + 1810)) ]' _ "$until" "$now"
rm -f "$T/mounted"
run open --no-timeout
check "--no-timeout: no time limit (the screen lock still closes it)" grep -q ' watch 0$' "$T/calls"
for bad in 0 2x 'h' '1;id'; do
    rm -f "$T/mounted"
    run open --for "$bad"
    check "--for '$bad' is refused, nothing opened" bash -c '! grep -q "^gocryptfs" "$1"' _ "$T/calls"
done

# The timer
: >"$T/mounted"
run watch $(($(date +%s) - 1))
check "the timer: time up, it closes" bash -c '[ ! -e "$1/mounted" ] && grep -qx "fusermount3 -u $1/home/Vault" "$1/calls"' _ "$T"
check "...says so" grep -q 'notify-send .*time was up' "$T/calls"
check "...and doesn't stop its own service (it ends by itself)" not grep -q '^systemctl' "$T/calls"
: >"$T/mounted"; : >"$T/locked"
run watch $(($(date +%s) + 3600))
check "the timer: the screen locks, it closes, though time is left" test ! -e "$T/mounted"
rm -f "$T/locked"

# Closing
: >"$T/mounted"
run close
check "close: unmounts it" bash -c '[ ! -e "$1/mounted" ] && grep -qx "vault: Closed." "$1/out"' _ "$T"
check "...and stops the timer" grep -qx 'systemctl --user stop wren-vault-watch.service' "$T/calls"
: >"$T/mounted"; : >"$T/busy"
run close
check "a file open in it: closed anyway (no new access)" grep -qx "fusermount3 -u -z $T/home/Vault" "$T/calls"
check "...and gocryptfs, holding the key, is ended" grep -q "^pkill -TERM .*gocryptfs" "$T/calls"
check "...saying so" grep -q 'still had a file open' "$T/out"
rm -f "$T/busy"
run close
check "close when it's closed: says so" grep -q 'It is closed' "$T/out"
check "status: closed" test "$(bash "$V" status)" = closed

# The extra: the hook the idle lock runs, and the vault made with gocryptfs -init
X=$HERE/extras/vault.sh
check "the extra puts a hook in on-lock.d that closes it" grep -q 'exec "\$HOME/.local/bin/vault" close quiet' "$X"
check "...makes the vault with gocryptfs -init, asking on the terminal" grep -q 'gocryptfs -init "\$CIPHER" </dev/tty' "$X"
check "...and --remove deletes no encrypted files" not grep -qE 'rm -rf? .*CIPHER' "$X"

[ "$fails" -eq 0 ]
