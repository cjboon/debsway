#!/bin/bash
# The small commands the base desktop installs for itself: keys (the cheat
# sheet), wren-welcome (its first-login screen), timer, display-scale,
# sway-status (the bar), wren-empty-workspace (Super + the key left of 1), and help and update, for Super+d to find. install-base.sh puts them in place while it sets sway
# up; this part does the same again so that wrenctl --update, which only reruns
# parts and extras, can bring them up to date when they change. It also
# installs ncal, whose cal draws the month in timer's screen, and links the
# documentation into ~/Documents/wren-docs.
# Usage: bash core-commands.sh [--remove]
# status: bin:timer
# files: data/keys.txt data/alarm.wav bin/keys bin/wren-welcome bin/timer lib/alarm-sounds.py bin/help bin/update bin/display-scale bin/sway-status bin/wren-empty-workspace
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

KEYS="$HOME/.local/share/wren/keys.txt"
COMMANDS=(keys wren-welcome timer display-scale sway-status help update wren-empty-workspace)
# The documentation, easy to find: links to the docs of the Wren Linux in use
DOCS="$HOME/Documents/wren-docs"

# docs_links: ~/Documents/wren-docs, a folder of links (README.md, the threat
# model, the guides) into the Wren Linux in use: the package's /usr/share/wren,
# or your own copy. A folder of that name that isn't Wren Linux's is left alone.
docs_links() {
    if [ -e "$DOCS" ] && [ ! -e "$DOCS/.wren-docs" ]; then
        note "$DOCS is yours (not made by Wren Linux), so it is left alone."
        return 0
    fi
    mkdir -p "$DOCS"
    : >"$DOCS/.wren-docs"
    ln -sfn "$WREN_DIR/README.md" "$DOCS/README.md"
    ln -sfn "$WREN_DIR/THREAT-MODEL.md" "$DOCS/THREAT-MODEL.md"
    ln -sfn "$WREN_DIR/docs" "$DOCS/guides"
    note "The documentation: $DOCS (README.md, THREAT-MODEL.md, guides/)"
}

if [ "${1:-}" = --remove ]; then
    warn "These are what the desktop's keys, bar and first-login screen run."
    remove_snippet empty-workspace
    for c in "${COMMANDS[@]}"; do remove_bin "$c"; done
    rm -f "$KEYS" "${KEYS%/*}/alarm.wav" "${KEYS%/*}/alarm-sounds.py"
    rm -rf "${KEYS%/*}/alarms"
    if [ -e "$DOCS/.wren-docs" ]; then
        rm -f "$DOCS/README.md" "$DOCS/THREAT-MODEL.md" "$DOCS/guides" "$DOCS/.wren-docs"
        rmdir "$DOCS" 2>/dev/null || true
    fi
    apt_purge ncal
    exit
fi

say "The base desktop's commands"
# cal and ncal: the month in the timer screen (click the time in the bar)
apt_install ncal
for c in "${COMMANDS[@]}"; do install_bin "$c"; done
mkdir -p "${KEYS%/*}"
install -m 0644 "$WREN_DIR/data/keys.txt" "$KEYS"
note "Cheat sheet: $KEYS"
# The bell (tools/make-alarm-sound.py): what rings if every other sound is gone
install -m 0644 "$WREN_DIR/data/alarm.wav" "${KEYS%/*}/alarm.wav"
# The other sounds timer can ring with (timer sound), the wren first: it is the default, so
# it is made now, ready for the first alarm
install -m 0644 "$WREN_DIR/lib/alarm-sounds.py" "${KEYS%/*}/alarm-sounds.py"
command -v python3 >/dev/null && python3 -I "${KEYS%/*}/alarm-sounds.py" make "${KEYS%/*}/alarms" ||
    warn "The alarm sounds weren't made, so alarms ring with the bell until you choose one: timer sound"
# Code 49 is the key left of 1, whatever a layout calls it: it lines up with the workspace numbers
put_snippet empty-workspace <<'EOF'
# The next empty workspace (Wren Linux parts/core-commands.sh)
bindcode $mod+49 exec ~/.local/bin/wren-empty-workspace
EOF
docs_links
