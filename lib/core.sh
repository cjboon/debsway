# shellcheck shell=bash
# lib/core.sh: messages, prompts, and small checks. Sourced by lib.sh.

BIN="$HOME/.local/bin"

# Where saved downloads are kept (offline/: the Wi-Fi packages, Tor Browser,
# Whonix, Tails, the install image): in the Wren Linux folder when it has them
# already (a stick, your own copy) or you can write there; from the package's
# read-only copy in /usr/share/wren, in your own ~/.local/share/wren/offline
if [ -d "$WREN_DIR/offline" ] || [ -w "$WREN_DIR" ]; then
    OFFLINE_DIR=$WREN_DIR/offline
else
    OFFLINE_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/wren/offline
fi

# (WREN_SUDO: a test points this at a pretend sudo)
if [ "$(id -u)" -eq 0 ]; then SUDO=; else SUDO=${WREN_SUDO:-sudo}; fi

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
    if [ -n "${WREN_NONINTERACTIVE:-}" ]; then
        printf -v "$1" '%s' ''
        return
    fi
    if [ -n "${WREN_TEST_ANSWERS:-}" ]; then
        # For tools/test-bridges.sh: answers come from a file, one per line
        [ -e /proc/self/fd/8 ] || exec 8<"$WREN_TEST_ANSWERS"
        printf '%s\n' "$2" >&2
        IFS= read -r _line <&8 || _line=
    elif { : </dev/tty; } 2>/dev/null; then
        IFS= read -r -p "$2" _line </dev/tty || _line=
    fi
    printf -v "$1" '%s' "$_line"
}

# pause_if_asked: when a script was started from the Wren menu
# (WREN_PAUSE=1), its window closes the moment the script ends, so wait for
# Esc (or Enter) first. Called at the end of what the user may want to read, not when
# nothing was done. Does nothing in a terminal of your own.
pause_if_asked() {
    [ -n "${WREN_PAUSE:-}" ] && [ -z "${WREN_NONINTERACTIVE:-}" ] || return 0
    # (the Wren menu then knows the window already waited)
    [ -z "${WREN_PAUSED_FILE:-}" ] || : >"$WREN_PAUSED_FILE" 2>/dev/null || true
    { : </dev/tty; } 2>/dev/null || return 0
    local k more
    printf '\nPress Esc to close. ' >&2
    while IFS= read -rsn1 k </dev/tty; do
        case $k in
            '' | q | Q) break ;;
            $'\e')
                # a plain Esc closes; an arrow key (Esc plus more) does not
                if IFS= read -rsn1 -t "${WREN_ESC_WAIT:-0.1}" more </dev/tty; then
                    while IFS= read -rsn1 -t "${WREN_ESC_WAIT:-0.1}" more </dev/tty; do :; done
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
    # (indented as note's lines are, so a question sits with what it is about)
    tty_read reply "    $1 $hint "
    [[ ${reply:-$def} =~ ^[Yy] ]]
}

# choose VAR "Question" DEFAULT OPTION...: one of the OPTIONs into VAR, typed
# in full or by its first letter; Enter (or no terminal to ask on) gives
# DEFAULT. Anything else asks again. The OPTIONs start with different letters.
choose() {
    local _var=$1 _q=$2 _def=$3 _reply _o _hint=""
    shift 3
    for _o; do _hint+="${_hint:+ / }$_o"; done
    while :; do
        tty_read _reply "    $_q $_hint (Enter: $_def) "
        _reply=${_reply,,}
        if [ -z "$_reply" ]; then
            printf -v "$_var" '%s' "$_def"
            return
        fi
        for _o; do
            if [ "$_reply" = "$_o" ] || [ "$_reply" = "${_o:0:1}" ]; then
                printf -v "$_var" '%s' "$_o"
                return
            fi
        done
        note "Type one of: $_hint"
    done
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
# first (skip_unless), so a desktop does not get laptop software. WREN_SYS
# is where /sys is, for tests.
SYS=${WREN_SYS:-/sys}
has_backlight() { compgen -G "$SYS/class/backlight/*" >/dev/null; }
has_battery() { compgen -G "$SYS/class/power_supply/BAT*" >/dev/null; }
has_power_profiles() { has_battery || [ -e "$SYS/firmware/acpi/platform_profile" ]; }
has_wifi() { compgen -G "$SYS/class/net/*/wireless" >/dev/null || compgen -G "$SYS/class/ieee80211/*" >/dev/null; }
has_bluetooth() { compgen -G "$SYS/class/bluetooth/*" >/dev/null; }

# skip_unless CHECK "what is missing": when install-base.sh runs a part
# (WREN_FROM_BASE=1) and CHECK finds no such hardware, say so and stop with
# success. Run by hand, a part always installs: you have said what you want.
skip_unless() {
    [ -n "${WREN_FROM_BASE:-}" ] || return 0
    if "$1"; then return 0; fi
    note "Skipped: $2 Install it later with: bash $(basename -- "$(dirname -- "$0")")/$(basename -- "$0")"
    exit 0
}

# For scripts that only touch your home folder
not_root() {
    [ "$(id -u)" -ne 0 ] || die "Run this as your normal user, not root."
}

# old_install: this computer was set up before Wren Linux had its name
# (debsway): its settings, firewall rules and sudo rules are under the old
# names, and the scripts of today would set up second copies next to them
old_install() { [ -d "$HOME/.config/debsway" ] || [ -d "$HOME/.local/share/debsway" ]; }

# Desktop scripts run as the normal user and use sudo for system changes
need_user() {
    [ "$(id -u)" -ne 0 ] ||
        die "Run this as your normal user, not root. It uses sudo when it needs to."
    if old_install && [ -z "${WREN_ALLOW_OLD_INSTALL:-}" ]; then
        warn "This computer was set up as debsway, before it was called Wren Linux: its settings,"
        warn "firewall rules and sudo rules are under the old names, and this would set up second"
        warn "copies next to them. Reinstall instead: back up your home, make an install stick with"
        die "bash $WREN_DIR/prep/make-install-iso.sh, and install from it. (WREN_ALLOW_OLD_INSTALL=1 runs it anyway.)"
    fi
    command -v sudo >/dev/null ||
        die "sudo isn't installed. Log in as root and run: bash $WREN_DIR/prep/setup-sudo.sh $(id -un)"
    # Two different failures: a user who is not allowed to use sudo at all, and one
    # who is but typed the password wrong. A typo shouldn't end a first install:
    # it asks whether to try again (yes unless you say no), where there is someone
    # to ask, a few rounds at most; nothing has been changed yet either way
    local round=1
    until $SUDO -v; do
        id -nG | tr ' ' '\n' | grep -qxE 'sudo|wheel|admin' ||
            die "Your user can't use sudo. Log in as root and run: bash $WREN_DIR/prep/setup-sudo.sh $(id -un)"
        warn "sudo didn't accept the password (three tries). Your own password, the one you log in with."
        if [ -n "${WREN_NONINTERACTIVE:-}" ] || [ "$round" -ge 5 ] ||
            { [ -z "${WREN_TEST_ANSWERS:-}" ] && ! { : </dev/tty; } 2>/dev/null; } ||
            ! ask "Try again?" y; then
            die "Stopped before changing anything. Run this again and type your own password."
        fi
        round=$((round + 1))
    done
}

# sudo_keepalive: asks for the sudo password once, now, and keeps the permission
# fresh in the background until the script ends, so a long run is not stopped
# part way by a second password question. Returns 1 if the password was not
# accepted (after sudo's own three tries); the caller should then stop.
sudo_keepalive() {
    [ -z "$SUDO" ] || $SUDO -v || return 1
    [ -n "$SUDO" ] || return 0
    # (its own messages go nowhere: when the script ends, the exit trap below stops
    # its sleep, and the shell would say "Terminated" about that, after all is done)
    (
        # ends by itself when the script that started it is gone
        while kill -0 "$$" 2>/dev/null; do
            $SUDO -n true 2>/dev/null || exit 0
            sleep 50
        done
    ) 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!
    trap '[ -z "${SUDO_KEEPALIVE_PID:-}" ] || { pkill -P "$SUDO_KEEPALIVE_PID" 2>/dev/null; kill "$SUDO_KEEPALIVE_PID" 2>/dev/null; }' EXIT
}

# print_manual [PAGE]: what --manual prints. The "## MANUAL INSTALL" section of
# docs/extras/PAGE.md (by default the running extra's name), without its code fences, with
# each @VAR@ filled in from a variable of the same name (pins.sh, or the
# script's own; an array gives its items). Changes nothing and needs no sudo.
print_manual() {
    local doc line out name m
    doc="$WREN_DIR/docs/extras/${1:-$(basename -- "$0" .sh)}.md"
    grep -qx '## MANUAL INSTALL' "$doc" 2>/dev/null ||
        die "There are no manual steps in $doc."
    while IFS= read -r line; do
        out=
        while [[ $line =~ @([A-Z][A-Z0-9_]*)@ ]]; do
            m=${BASH_REMATCH[0]} name=${BASH_REMATCH[1]}
            out+=${line%%"$m"*}
            if declare -p "$name" >/dev/null 2>&1; then
                declare -n ref=$name
                out+="${ref[*]}"
                unset -n ref
            else
                out+=$m
            fi
            line=${line#*"$m"}
        done
        printf '%s\n' "$out$line"
    done < <(awk '$0 == "## MANUAL INSTALL" { on = 1; next } on && /^## / { exit } on && !/^```/' "$doc")
}

is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'
}

have_internet() { getent hosts deb.debian.org >/dev/null 2>&1; }

# install_bin NAME: puts bin/NAME into ~/.local/bin. A different file there
# that Wren Linux didn't write is kept as NAME.bak.
install_bin() {
    local src="$WREN_DIR/bin/$1" dest="$BIN/$1"
    if [ -f "$dest" ] && ! cmp -s "$src" "$dest" && ! grep -qis 'written by Wren Linux' "$dest"; then
        cp "$dest" "$dest.bak"
        note "Old $dest kept as $dest.bak"
    fi
    install -D -m 0755 "$src" "$dest"
    note "Installed $dest"
}

# printable: standard input without control characters (an escape sequence that
# steers the terminal, a carriage return that writes over a line, a backspace...),
# tabs and line breaks kept, and without the 8-bit ones in their UTF-8 form
# (U+0080-U+009F: some terminals obey those too). For text from outside, before
# it reaches the terminal: a commit message from the server, a Wi-Fi network's name.
printable() { LC_ALL=C sed 's/\xc2[\x80-\x9f]//g' | LC_ALL=C tr -d '\000-\010\013-\037\177'; }

# The wrapper that keeps a sandbox user off X11's abstract socket (see
# bin/no-abstract-sockets). One copy, root's, shared by the sandboxes; the last
# one to be removed takes it away.
NO_ABSTRACT=/usr/local/libexec/wren-no-abstract-sockets
install_no_abstract() {
    sudo install -d -o root -g root -m 0755 /usr/local/libexec
    sudo install -o root -g root -m 0755 "$WREN_DIR/bin/no-abstract-sockets" "$NO_ABSTRACT"
}
remove_no_abstract() {
    local s
    for s in wallet-session incognito-session claude-session claude-vm-session opencode-vm-session firefox-session onion-site-session yt-dlp-session distro-vm-session; do
        [ ! -e "/usr/local/libexec/$s" ] || return 0
    done
    # (a media viewer given a web address; this one is yours, in ~/.local/bin)
    [ ! -e "$BIN/media-sandbox" ] || return 0
    sudo rm -f "$NO_ABSTRACT"
}

# The check that a sandbox's firewall really holds (see bin/sandbox-net-check).
# One copy, root's, shared by the sandboxes; the last one to be removed takes it away.
NET_CHECK=/usr/local/libexec/wren-sandbox-net-check
install_net_check() {
    sudo install -d -o root -g root -m 0755 /usr/local/libexec
    sudo install -o root -g root -m 0755 "$WREN_DIR/bin/sandbox-net-check" "$NET_CHECK"
}
remove_net_check() {
    local s
    for s in incognito-session claude-session claude-vm-session opencode-vm-session firefox-session onion-site-session yt-dlp-session; do
        [ ! -e "/usr/local/libexec/$s" ] || return 0
    done
    sudo rm -f "$NET_CHECK"
}

# remove_wayland_restrict: takes wayland-restrict away once nothing uses it (call
# it after the script's own command is gone)
remove_wayland_restrict() {
    local c
    for c in /usr/local/bin/wallet /usr/local/bin/firefox /usr/local/bin/incognito "$BIN/media-sandbox"; do
        [ ! -e "$c" ] || return 0
    done
    remove_bin wayland-restrict
}

# remove_bin NAME: removes ~/.local/bin/NAME if Wren Linux wrote it
remove_bin() {
    if grep -qis 'written by Wren Linux' "$BIN/$1"; then rm -f "$BIN/$1"; fi
}

# script_found SCRIPT: what is set up of the part or extra SCRIPT, one per
# line, from its "# status:" line: a list of apt:PACKAGE, opt:APP (unpacked
# into ~/.local/opt), bin:COMMAND (in ~/.local/bin), file:PATH and gone:PACKAGE
# (for a script that removes it: done once it isn't installed). Nothing
# is printed if it isn't set up; one thing is enough.
script_found() {
    local tok what
    for tok in $(sed -n 's/^# status: //p' "$1" | head -1); do
        what=${tok#*:}
        case $tok in
            apt:*) if is_installed "$what"; then echo "$what"; fi ;;
            gone:*) if ! is_installed "$what"; then echo "no $what"; fi ;;
            opt:*) if [ -f "$HOME/.local/opt/$what/.wren-version" ]; then
                echo "$what $(cat "$HOME/.local/opt/$what/.wren-version")"; fi ;;
            bin:*) if [ -e "$BIN/$what" ] || [ -L "$BIN/$what" ]; then echo "$what"; fi ;;
            file:*) what=${what/#\~/$HOME}
                if [ -e "$what" ]; then echo "${what##*/}"; fi ;;
        esac
    done
}

# profile_autostart sway|console: what a login on a text console starts (sway on
# tty1, or tmux on any tty), kept in ~/.config/wren/login and acted on by one
# block in ~/.profile. The block loops: when the program ends it checks the file
# again, so switching the mode (extras/console-only.sh) can end sway or tmux and
# start the other without logging out. If the file is unchanged, ending the
# program logs out, as before. WREN_LOGIN_LOOP=1 marks a session started by
# the block (an older block, which exec'd sway, doesn't set it).
profile_autostart() {
    local profile="$HOME/.profile" mode="$HOME/.config/wren/login"
    touch "$profile"
    sed -i -e '/^# >>> Wren Linux autostart >>>$/,/^# <<< Wren Linux autostart <<<$/d' \
        -e '/^# >>> Wren Linux console >>>$/,/^# <<< Wren Linux console <<<$/d' "$profile"
    mkdir -p "${mode%/*}"
    echo "$1" >"$mode"
    cat >>"$profile" <<'BLOCK'

# >>> Wren Linux autostart >>>
# What a text console login starts: ~/.config/wren/login says sway (tty1) or
# console (tmux, any tty). When it ends and that file has changed, the other starts;
# otherwise tmux's end logs out, and sway's leaves you at the shell, if it ended by
# itself: if not, it asks your password first.
case "$(tty 2>/dev/null)" in
    /dev/tty[0-9]*)
        if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${TMUX:-}" ]; then
            export WREN_LOGIN_LOOP=1
            while :; do
                m=$(cat "$HOME/.config/wren/login" 2>/dev/null); m=${m:-sway}
                if [ "$m" = console ]; then
                    # bigger text on the console; ~/.config/wren/console-font names another
                    setfont "$(cat "$HOME/.config/wren/console-font" 2>/dev/null || echo Uni3-Terminus28x14)" 2>/dev/null
                    rm -f "$HOME/.config/wren/console-redraw"
                    tmux new-session -A -s main
                    # console-font leaves this to say: detached on purpose, come back with the new font
                    [ ! -e "$HOME/.config/wren/console-redraw" ] || continue
                elif [ "$(tty)" = /dev/tty1 ]; then
                    # A sway that didn't end by itself (a crash, out of memory, killed) may
                    # have been locked, so nothing starts again without your password, even
                    # with autologin. In this boot only: restarting needs what it always did.
                    r=$HOME/.local/state/wren/sway-running
                    b=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)
                    if [ -n "$b" ] && [ "$(cat "$r" 2>/dev/null)" = "$b" ]; then
                        trap '' INT QUIT TSTP
                        printf '\nsway stopped unexpectedly, perhaps while locked, and its windows are gone.\nYour password starts it again.\n'
                        until su -c true "$(id -un)"; do sleep 1; done
                        trap - INT QUIT TSTP
                        rm -f "$r"
                        # it can't start at all: you need the shell, to see why
                        if [ -n "${q:-}" ]; then
                            printf '\nsway keeps failing. Start it again: sway   Log out: exit\n'
                            break
                        fi
                    fi
                    mkdir -p "${r%/*}"
                    printf '%s\n' "$b" >"$r"
                    s=$(date +%s)
                    rc=0
                    env XDG_CURRENT_DESKTOP=sway sway || rc=$?
                    if [ "$rc" != 0 ]; then
                        q=
                        [ "$(($(date +%s) - s))" -ge 10 ] || q=1
                        continue
                    fi
                    rm -f "$r"
                else
                    break
                fi
                n=$(cat "$HOME/.config/wren/login" 2>/dev/null)
                if [ "${n:-sway}" = "$m" ]; then
                    # Leaving tmux (its last window) logs out. Leaving sway leaves
                    # you here, at the shell: with autologin, logging out would
                    # only log you in again and start sway
                    [ "$m" = sway ] || exit
                    printf '\nsway has ended. Start it again: sway   Log out: exit\n'
                    break
                fi
            done
        fi ;;
esac
# <<< Wren Linux autostart <<<
BLOCK
}

# login_mode: sway or console, as profile_autostart last set it
login_mode() {
    local m
    m=$(cat "$HOME/.config/wren/login" 2>/dev/null)
    echo "${m:-sway}"
}
