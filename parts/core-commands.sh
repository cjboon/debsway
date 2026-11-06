#!/bin/bash
# The small commands the base desktop installs for itself: keys (the cheat
# sheet), wren-welcome (its first-login screen), timer, display-scale and
# sway-status (the bar). install-base.sh puts them in place while it sets sway
# up; this part does the same again so that wrenctl --update, which only reruns
# parts and extras, can bring them up to date when they change. It also
# installs ncal, whose cal draws the month in timer's screen, and links the
# documentation into ~/Documents/wren-docs.
# Usage: bash core-commands.sh [--remove]
# status: bin:timer
# files: data/keys.txt data/alarm.wav bin/keys bin/wren-welcome bin/timer bin/alarm-sounds bin/display-scale bin/sway-status
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

KEYS="$HOME/.local/share/wren/keys.txt"
COMMANDS=(keys wren-welcome timer alarm-sounds display-scale sway-status)
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
    for c in "${COMMANDS[@]}"; do remove_bin "$c"; done
    rm -f "$KEYS" "${KEYS%/*}/alarm.wav"
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
# The sound timer and alarm clock ring with: three short beeps (tools/make-alarm-sound.py)
install -m 0644 "$WREN_DIR/data/alarm.wav" "${KEYS%/*}/alarm.wav"
docs_links
