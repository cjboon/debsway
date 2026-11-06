#!/bin/bash
# Checks that the bar says when security updates stop arriving: bin/wren-update-result, and
# what bin/sway-status makes of it, with a pretend ip and stamp, and how the part sets it up.
# That apt-get update exits 0 with every server out of reach, and that the daily job then still
# marks success unless it's strict, was seen with Debian's real apt.systemd.daily, in a
# container. A real desktop's bar hasn't shown this. Run by test.sh, or:
#   bash tools/test-update-watch.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
mkdir "$T/bin"
printf '#!/bin/sh\ncase "$*" in *"route show default"*) [ ! -e "%s/online" ] || echo "default via 192.0.2.1" ;; esac\n' "$T" >"$T/bin/ip"
chmod +x "$T/bin/ip"
export WREN_UPDATE_STAMP=$T/stamp WREN_UPDATE_RUN=$T/run WREN_UPDATE_DROPIN=$T/dropin WREN_UPTIME=$T/uptime
: >"$T/dropin"
echo '90000.00 1.00' >"$T/uptime"
# run the helper with the pretend ip: its own PATH line comes out, in a copy
sed 's|^export PATH=.*|export PATH="$TEST_PATH"|' "$HERE/bin/wren-update-result" >"$T/result"
result() { TEST_PATH="$T/bin:/usr/bin:/bin" sh "$T/result"; cat "$T/run/state"; }
# (timeout: without --updates, this would be the bar itself, which never ends)
bar() { PATH="$T/bin:$PATH" timeout 10 sh "$HERE/bin/sway-status" --updates; }
hours_ago() { touch -d "$1 hours ago" "$T/stamp"; }

: >"$T/online"
hours_ago 2
check "fetched just now: ok" test "$(result)" = ok
check "...the bar says nothing" test -z "$(bar)"
hours_ago 30
check "a day and a bit ago (a run may just have been skipped): ok" test "$(result)" = ok
hours_ago 40
check "not fetched, and online: failed" test "$(result)" = failed
check "...the bar says so, at once" test "$(bar)" = "updates failed"
rm -f "$T/stamp"
check "never fetched, and online: failed" test "$(result)" = failed
hours_ago 40
rm -f "$T/online"
check "not fetched, and offline: offline, which is no failure" test "$(result)" = offline
check "...the bar says nothing" test -z "$(bar)"
echo failed >"$T/run/state"
check "...even if the last run failed: you're offline now" test -z "$(bar)"
: >"$T/online"; echo ok >"$T/run/state"
hours_ago 80
check "over 3 days old, online for long (say the timer never runs): the bar says so" test "$(bar)" = "updates old"
echo '3600.00 1.00' >"$T/uptime"
check "...not just after a start: it's about to fetch" test -z "$(bar)"
echo failed >"$T/run/state"
check "...a failed run says so even then" test "$(bar)" = "updates failed"
echo '90000.00 1.00' >"$T/uptime"; echo ok >"$T/run/state"
rm -f "$T/dropin"
check "automatic updates taken out: nothing" test -z "$(bar)"
: >"$T/dropin"
TEST_PATH="$T/bin:/usr/bin:/bin" sh "$T/result"
check "the state can be read by you" test "$(stat -c %a "$T/run/state")" = 644

S=$HERE/bin/sway-status
check "the bar shows it, and the startup watch's, in a colour you can't miss" bash -c '
    grep -qF "\$(alert updates \"\$updates_now\")\$(alert whonix \"\$(whonix_due)\")\$(alert startup \"\$startup_now\")" "$1" && grep -qF "\"color\":\"#ffd000\",\"urgent\":true" "$1"' _ "$S"
check "...in tmux's bar too" grep -qF '$(alert updates "$(updates)")$(alert whonix "$(whonix_due)")$(alert startup "$(startup)")' "$S"
check "a notification too, once, and a click says what to do" bash -c '
    grep -q "updates_was=\$updates_now" "$1" && grep -qF "\"name\":\"updates\"" "$1" && grep -q "sudo apt update" "$1"' _ "$S"
P=$HERE/parts/unattended-upgrades.sh
check "only the daily job is strict, through its own settings file" bash -c '
    grep -q "Environment=APT_CONFIG=\$STRICT" "$1" && grep -q "APT::Update::Error-Mode \"any\"" "$1" && [ "$(grep -c "Error-Mode" "$1")" = 1 ]' _ "$P"
check "...the result written when each run ends, whatever happened" grep -q 'ExecStopPost=-$HELPER' "$P"
check "--remove takes it all out" bash -c 'sed -n "/--remove/,/^fi/p" "$1" | grep -q "\$HELPER\" \"\$STRICT\" \"\$DROPIN\""' _ "$P"
check "Status says so too" grep -q "aren't arriving" "$HERE/status.sh"

[ "$fails" -eq 0 ]
