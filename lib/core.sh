# shellcheck shell=bash
# lib/core.sh: messages, prompts, and small checks. Sourced by lib.sh.

BIN="$HOME/.local/bin"

if [ "$(id -u)" -eq 0 ]; then SUDO=; else SUDO=sudo; fi

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
    sudo -v ||
        die "Your user can't use sudo. Log in as root and run: bash $DEBSWAY_DIR/prep/setup-sudo.sh $(id -un)"
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
    for s in incognito-session claude-session claude-vm-session; do
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
