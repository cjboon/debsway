# shellcheck shell=bash
# lib/core.sh: messages, prompts, and small checks. Sourced by lib.sh.

BIN="$HOME/.local/bin"

# (DEBSWAY_SUDO: a test points this at a pretend sudo)
if [ "$(id -u)" -eq 0 ]; then SUDO=; else SUDO=${DEBSWAY_SUDO:-sudo}; fi

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# tty_read VAR "Prompt": reads a line from the terminal into VAR, or
# leaves it empty when there is no terminal. The prompt goes to stderr,
# so only the check for a terminal is silenced, never the prompt.
tty_read() {
    local _line=
    # An unattended run (install-base.sh installing its default apps) never
    # prompts: it leaves the answer empty, so ask() falls back to its default.
    if [ -n "${DEBSWAY_NONINTERACTIVE:-}" ]; then
        printf -v "$1" '%s' ''
        return
    fi
    if [ -n "${DEBSWAY_TEST_ANSWERS:-}" ]; then
        # For tools/test-bridges.sh: answers come from a file, one per line
        [ -e /proc/self/fd/8 ] || exec 8<"$DEBSWAY_TEST_ANSWERS"
        printf '%s\n' "$2" >&2
        IFS= read -r _line <&8 || _line=
    elif { : </dev/tty; } 2>/dev/null; then
        IFS= read -r -p "$2" _line </dev/tty || _line=
    fi
    printf -v "$1" '%s' "$_line"
}

# pause_if_asked: when a script was started from the debsway menu
# (DEBSWAY_PAUSE=1), its window closes the moment the script ends, so wait for
# Esc (or Enter) first. Called at the end of what the user may want to read, not when
# nothing was done. Does nothing in a terminal of your own.
pause_if_asked() {
    [ -n "${DEBSWAY_PAUSE:-}" ] && [ -z "${DEBSWAY_NONINTERACTIVE:-}" ] || return 0
    # (the debsway menu then knows the window already waited)
    [ -z "${DEBSWAY_PAUSED_FILE:-}" ] || : >"$DEBSWAY_PAUSED_FILE" 2>/dev/null || true
    { : </dev/tty; } 2>/dev/null || return 0
    local k more
    printf '\nPress Esc to close. ' >&2
    while IFS= read -rsn1 k </dev/tty; do
        case $k in
            '' | q | Q) break ;;
            $'\e')
                # a plain Esc closes; an arrow key (Esc plus more) does not
                if IFS= read -rsn1 -t "${DEBSWAY_ESC_WAIT:-0.1}" more </dev/tty; then
                    while IFS= read -rsn1 -t "${DEBSWAY_ESC_WAIT:-0.1}" more </dev/tty; do :; done
                else
                    break
                fi ;;
        esac
    done
    printf '\n' >&2
}

# ask "Question?" [y|n]: default answer is the second argument
ask() {
    local reply def=${2:-n} hint='[y/N]'
    [ "$def" = y ] && hint='[Y/n]'
    tty_read reply "$1 $hint "
    [[ ${reply:-$def} =~ ^[Yy] ]]
}

# auto_or_ask VARNAME "Question?" [y|n]: for prompts install-base.sh needs to
# answer for you when it installs its default apps unattended. If VARNAME is
# set to yes/no (1/y/yes or 0/n/no) that is the answer, with no prompt;
# otherwise it just asks (and an unattended run with VARNAME unset takes the
# default, because tty_read returns empty). A person running the script by
# hand is always asked.
auto_or_ask() {
    case ${!1:-} in
        1 | y | Y | yes | YES) return 0 ;;
        0 | n | N | no | NO) return 1 ;;
    esac
    shift
    ask "$@"
}

# What this computer has. A part that only makes sense with some hardware asks
# first (skip_unless), so a desktop does not get laptop software. DEBSWAY_SYS
# is where /sys is, for tests.
SYS=${DEBSWAY_SYS:-/sys}
has_backlight() { compgen -G "$SYS/class/backlight/*" >/dev/null; }
has_battery() { compgen -G "$SYS/class/power_supply/BAT*" >/dev/null; }
has_power_profiles() { has_battery || [ -e "$SYS/firmware/acpi/platform_profile" ]; }
has_wifi() { compgen -G "$SYS/class/net/*/wireless" >/dev/null || compgen -G "$SYS/class/ieee80211/*" >/dev/null; }
has_bluetooth() { compgen -G "$SYS/class/bluetooth/*" >/dev/null; }

# skip_unless CHECK "what is missing": when install-base.sh runs a part
# (DEBSWAY_FROM_BASE=1) and CHECK finds no such hardware, say so and stop with
# success. Run by hand, a part always installs: you have said what you want.
skip_unless() {
    [ -n "${DEBSWAY_FROM_BASE:-}" ] || return 0
    if "$1"; then return 0; fi
    note "Skipped: $2 Install it later with: bash $(basename -- "$(dirname -- "$0")")/$(basename -- "$0")"
    exit 0
}

# For scripts that only touch your home folder
not_root() {
    [ "$(id -u)" -ne 0 ] || die "Run this as your normal user, not root."
}

# Desktop scripts run as the normal user and use sudo for system changes
need_user() {
    [ "$(id -u)" -ne 0 ] ||
        die "Run this as your normal user, not root. It uses sudo when it needs to."
    command -v sudo >/dev/null ||
        die "sudo isn't installed. Log in as root and run: bash $DEBSWAY_DIR/prep/setup-sudo.sh $(id -un)"
    # Two different failures: a user who is not allowed to use sudo at all, and one
    # who is but typed the password wrong
    if ! $SUDO -v; then
        if id -nG | tr ' ' '\n' | grep -qxE 'sudo|wheel|admin'; then
            die "sudo didn't accept the password (after three tries). Run this again and type your own password."
        fi
        die "Your user can't use sudo. Log in as root and run: bash $DEBSWAY_DIR/prep/setup-sudo.sh $(id -un)"
    fi
}

# sudo_keepalive: asks for the sudo password once, now, and keeps the permission
# fresh in the background until the script ends, so a long run is not stopped
# part way by a second password question. Returns 1 if the password was not
# accepted (after sudo's own three tries); the caller should then stop.
sudo_keepalive() {
    [ -z "$SUDO" ] || $SUDO -v || return 1
    [ -n "$SUDO" ] || return 0
    (
        # ends by itself when the script that started it is gone
        while kill -0 "$$" 2>/dev/null; do
            $SUDO -n true 2>/dev/null || exit 0
            sleep 50
        done
    ) &
    SUDO_KEEPALIVE_PID=$!
    trap '[ -z "${SUDO_KEEPALIVE_PID:-}" ] || { pkill -P "$SUDO_KEEPALIVE_PID" 2>/dev/null; kill "$SUDO_KEEPALIVE_PID" 2>/dev/null; }' EXIT
}

is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

have_internet() { getent hosts deb.debian.org >/dev/null 2>&1; }

# install_bin NAME: puts bin/NAME into ~/.local/bin. A different file there
# that debsway didn't write is kept as NAME.bak.
install_bin() {
    local src="$DEBSWAY_DIR/bin/$1" dest="$BIN/$1"
    if [ -f "$dest" ] && ! cmp -s "$src" "$dest" && ! grep -qis 'written by debsway' "$dest"; then
        cp "$dest" "$dest.bak"
        note "Old $dest kept as $dest.bak"
    fi
    install -D -m 0755 "$src" "$dest"
    note "Installed $dest"
}

# The wrapper that keeps a sandbox user off X11's abstract socket (see
# bin/no-abstract-sockets). One copy, root's, shared by incognito, claude-code
# and claude-vm; the last one to be removed takes it away.
NO_ABSTRACT=/usr/local/libexec/debsway-no-abstract-sockets
install_no_abstract() {
    sudo install -d -o root -g root -m 0755 /usr/local/libexec
    sudo install -o root -g root -m 0755 "$DEBSWAY_DIR/bin/no-abstract-sockets" "$NO_ABSTRACT"
}
remove_no_abstract() {
    local s
    for s in incognito-session claude-session claude-vm-session firefox-session; do
        [ ! -e "/usr/local/libexec/$s" ] || return 0
    done
    sudo rm -f "$NO_ABSTRACT"
}

# remove_bin NAME: removes ~/.local/bin/NAME if debsway wrote it
remove_bin() {
    if grep -qis 'written by debsway' "$BIN/$1"; then rm -f "$BIN/$1"; fi
}

# script_found SCRIPT: what is set up of the part or extra SCRIPT, one per
# line, from its "# status:" line: a list of apt:PACKAGE, opt:APP (unpacked
# into ~/.local/opt), bin:COMMAND (in ~/.local/bin) and file:PATH. Nothing
# is printed if it isn't set up; one thing is enough.
script_found() {
    local tok what
    for tok in $(sed -n 's/^# status: //p' "$1" | head -1); do
        what=${tok#*:}
        case $tok in
            apt:*) if is_installed "$what"; then echo "$what"; fi ;;
            opt:*) if [ -f "$HOME/.local/opt/$what/.debsway-version" ]; then
                echo "$what $(cat "$HOME/.local/opt/$what/.debsway-version")"; fi ;;
            bin:*) if [ -e "$BIN/$what" ] || [ -L "$BIN/$what" ]; then echo "$what"; fi ;;
            file:*) what=${what/#\~/$HOME}
                if [ -e "$what" ]; then echo "${what##*/}"; fi ;;
        esac
    done
}

# profile_autostart sway|console: what a login on a text console starts (sway on
# tty1, or tmux on any tty), kept in ~/.config/debsway/login and acted on by one
# block in ~/.profile. The block loops: when the program ends it checks the file
# again, so switching the mode (extras/console-only.sh) can end sway or tmux and
# start the other without logging out. If the file is unchanged, ending the
# program logs out, as before. DEBSWAY_LOGIN_LOOP=1 marks a session started by
# the block (an older block, which exec'd sway, doesn't set it).
profile_autostart() {
    local profile="$HOME/.profile" mode="$HOME/.config/debsway/login"
    touch "$profile"
    sed -i -e '/^# >>> debsway autostart >>>$/,/^# <<< debsway autostart <<<$/d' \
        -e '/^# >>> debsway console >>>$/,/^# <<< debsway console <<<$/d' "$profile"
    mkdir -p "${mode%/*}"
    echo "$1" >"$mode"
    cat >>"$profile" <<'BLOCK'

# >>> debsway autostart >>>
# What a text console login starts: ~/.config/debsway/login says sway (tty1) or
# console (tmux, any tty). When it ends and that file has changed, the other starts.
case "$(tty 2>/dev/null)" in
    /dev/tty[0-9]*)
        if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${TMUX:-}" ]; then
            export DEBSWAY_LOGIN_LOOP=1
            while :; do
                m=$(cat "$HOME/.config/debsway/login" 2>/dev/null); m=${m:-sway}
                if [ "$m" = console ]; then
                    # bigger text on the console; ~/.config/debsway/console-font names another
                    setfont "$(cat "$HOME/.config/debsway/console-font" 2>/dev/null || echo Uni3-DejaVu30x16)" 2>/dev/null
                    tmux new-session -A -s main
                elif [ "$(tty)" = /dev/tty1 ]; then
                    env XDG_CURRENT_DESKTOP=sway sway
                else
                    break
                fi
                n=$(cat "$HOME/.config/debsway/login" 2>/dev/null)
                [ "${n:-sway}" != "$m" ] || exit
            done
        fi ;;
esac
# <<< debsway autostart <<<
BLOCK
}

# login_mode: sway or console, as profile_autostart last set it
login_mode() {
    local m
    m=$(cat "$HOME/.config/debsway/login" 2>/dev/null)
    echo "${m:-sway}"
}
