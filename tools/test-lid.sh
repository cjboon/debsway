#!/bin/bash
# Checks extras/lid-awake.sh's pieces: logind's settings (data/lid-logind.conf)
# and bin/lid, with a pretend sway that has a laptop panel and an external
# screen, and a pretend swaylock. Changes nothing. Run by test.sh, or:
#   bash tools/test-lid.sh
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

CONF=$HERE/data/lid-logind.conf
for k in HandleLidSwitch HandleLidSwitchExternalPower HandleLidSwitchDocked; do
    check "logind: $k=ignore" grep -qx "$k=ignore" "$CONF"
done
check "logind: the settings are in its [Login] section" grep -qx '\[Login\]' "$CONF"
check "logind: nothing else is changed" test "$(grep -c '^[A-Za-z]' "$CONF")" = 3

# pretend sway (a laptop panel and an external screen) and swaylock
mkdir -p "$T/fake"
cat >"$T/fake/swaymsg" <<FAKE
#!/bin/sh
case "\$*" in
    *get_outputs*) printf '%s\n' "Output eDP-1 'Some Panel'" "  Current mode: 1920x1080" "Output HDMI-A-1 'Some Monitor'" ;;
    *) echo "swaymsg \$*" >>"$T/calls" ;;
esac
FAKE
printf '#!/bin/sh\necho "swaylock $*" >>"%s/calls"\n' "$T" >"$T/fake/swaylock"
printf '#!/bin/sh\nexit 1\n' >"$T/fake/pgrep"
chmod +x "$T/fake/"*
lid() { PATH="$T/fake:$PATH" sh "$HERE/bin/lid" "$@"; }

lid close
check "closing the lid locks the screen" grep -qx 'swaylock -f -c 000000' "$T/calls"
check "...before the panel goes off" test "$(head -1 "$T/calls")" = 'swaylock -f -c 000000'
check "...turns the laptop's own panel off" grep -qx 'swaymsg output eDP-1 power off' "$T/calls"
check "...but not the external screen" not grep -q 'HDMI-A-1' "$T/calls"
: >"$T/calls"
lid open
check "opening it turns the panel back on" grep -qx 'swaymsg output eDP-1 power on' "$T/calls"
check "...and doesn't lock" not grep -q swaylock "$T/calls"
# already locked: no second swaylock on top
printf '#!/bin/sh\nexit 0\n' >"$T/fake/pgrep"
: >"$T/calls"
lid close
check "closing it while locked doesn't start a second swaylock" not grep -q swaylock "$T/calls"
check "a wrong word is refused" not lid sideways

E=$HERE/extras/lid-awake.sh
check "sway runs bin/lid on the lid switch, also while locked" \
    grep -q 'bindswitch --reload --locked lid:on exec ~/.local/bin/lid close' "$E"
check "logind is told to read its settings again, not restarted (that could end the session)" \
    grep -q 'systemctl kill -s HUP systemd-logind' "$E"

[ "$fails" -eq 0 ]
