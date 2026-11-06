#!/bin/bash
# Checks bin/wren-menu (the menu behind "wren" in the bar): the window
# it opens, and the menu itself, driven through a real pseudo-terminal with
# arrow keys, Enter, Esc and mouse clicks. The programs it would run are
# pretend ones that only write down how they were called. Changes nothing.
# Run by test.sh, or:  bash tools/test-wren-menu.sh
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
command -v python3 >/dev/null || { echo "  ok    skipped: python3 isn't installed"; exit 0; }

mkdir -p "$T/fake" "$T/home/.local/bin" "$T/wren"
# shellcheck disable=SC2016  # written into the pretend programs, expanded when they run
{
    # foot: write down its arguments, one per line
    printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"%s/foot"\n' "$T" >"$T/fake/foot"
    # bash (what the menu runs the Wren Linux scripts with): write down the folder, the
    # arguments and whether it was asked to wait at the end
    printf '#!/bin/sh\necho "$PWD|$*|pause=$WREN_PAUSE" >>"%s/ran"\necho "printed by $*"\n' "$T" >"$T/fake/bash"
    printf '#!/bin/sh\ncat >/dev/null\n' >"$T/fake/less"
    # (keys --text prints the cheat sheet, as the real one does after filtering it)
    printf '#!/bin/sh\n[ "$1" = --text ] && exec cat "%s/home/.local/share/wren/keys.txt"\necho "keys" >>"%s/ran"\n' "$T" "$T" >"$T/home/.local/bin/keys"
}
chmod +x "$T/fake/"* "$T/home/.local/bin/keys"
# radios: what it lists comes from $T/radios-list; state per name in $T/radio-NAME
# shellcheck disable=SC2016  # written into the pretend program, expanded when it runs
cat >"$T/radios.sh" <<FAKE
#!/bin/bash
case \$1 in
    list) [ -f "$T/radios-list" ] && cat "$T/radios-list" ;;
    *) case \${2:-status} in
        status) cat "$T/radio-\$1" ;;
        toggle) echo "radios \$1 toggle" >>"$T/ran"; if [ "\$(cat "$T/radio-\$1")" = on ]; then echo off >"$T/radio-\$1"; else echo on >"$T/radio-\$1"; fi ;;
       esac ;;
esac
FAKE
: >"$T/wren/update.sh"
mkdir -p "$T/home/.local/share/wren"
for i in $(seq 100); do echo "line $i"; done >"$T/home/.local/share/wren/keys.txt"

# 1. The window: in grays, running the menu, and not fullscreen (the bar stays visible)
PATH="$T/fake:$PATH" HOME="$T/home" /bin/bash "$HERE/bin/wren-menu"
check "a click opens a window named wren-run" grep -qx -e --app-id=wren-run "$T/foot"
check "...quietly: only errors are logged (no warning about the missing icon protocol)" grep -qx -e --log-level=error "$T/foot"
check "...not fullscreen, so the bar stays visible" not grep -qx -e --fullscreen "$T/foot"
check "...with a black background" grep -qx 'colors.background=000000' "$T/foot"
check "...where one step of the mouse wheel moves one line of a list, not three" grep -qx 'scrollback.multiplier=1.0' "$T/foot"
check "...and the menu as its program" test "$(tail -1 "$T/foot")" = --tui
# every color is a gray: red = green = blue in each
check "every color it sets is a gray" python3 -I -c '
import re, sys
vals = re.findall(r"colors\.\w[\w-]*=([0-9a-f]{6})$", open(sys.argv[1]).read(), re.M)
assert len(vals) >= 18, len(vals)
assert all(v[0:2] == v[2:4] == v[4:6] for v in vals), vals
' "$T/foot"

# 2. The menu in a terminal. run_menu "KEYS"... : one scenario; prints what
# was drawn and exit status on the first line, then what ran
cat >"$T/drive.py" <<'PY'
import fcntl, os, pty, re, select, struct, sys, termios, time

def run(script, env, keys, rows=24, cols=80):
    """Start the menu in a pty, send each item of keys (a string, or a function
    of what has been drawn so far), return (drawn, exit status or None)."""
    pid, fd = pty.fork()
    if pid == 0:
        fcntl.ioctl(0, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        os.execvpe("/bin/bash", ["bash", script, "--tui"], env)
    drawn = b""
    ended = False
    READY = b"\x1b]9999;wren-ready\x07"
    def pump(until, limit=10):
        """Read what the menu draws until until() is true, the menu has ended,
        or limit seconds have passed (only a menu that hangs takes that long)."""
        nonlocal drawn, ended
        end = time.time() + limit
        while not ended and not until() and time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.05)
            if r:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    data = b""
                if not data:
                    ended = True
                    return
                drawn += data
    def quiet(wait):
        """Read until nothing more has come for wait seconds."""
        nonlocal drawn
        while not ended:
            before = len(drawn)
            pump(lambda: False, wait)
            if len(drawn) == before:
                return
    def ready_after(n):
        return lambda: drawn.count(READY) > n
    if keys and isinstance(keys[0], tuple) and keys[0][0] == "early":
        # the window is stretched just after the menu starts, before it has drawn anything
        time.sleep(0.08)
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", keys[0][1], keys[0][2], 0, 0))
        keys = keys[1:]
    # the menu says each time it waits for a key (WREN_MENU_TEST_READY):
    # every key is sent once the one before it has been handled
    pump(ready_after(0))
    for k in keys:
        n = drawn.count(READY)
        if isinstance(k, tuple):      # ("resize", rows, cols): the window is stretched
            before = len(drawn)
            fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", k[1], k[2], 0, 0))
            # it draws again while it waits for the same key: until that is done
            pump(lambda: len(drawn) > before, 3)
            quiet(0.3)
            continue
        text = k(drawn) if callable(k) else k
        os.write(fd, text.encode())
        pump(ready_after(n))
        # a click is a press and a release, each a key to the menu; a program it
        # started may wait for something else, so this is not waited for long
        if "M\x1b[<" in text:
            pump(ready_after(n + 1), 1)
    status = None
    # Only a menu that has closed its screen is exiting; one that said it waits
    # for a key stays open (status None), so there is nothing to wait for
    for _ in range(80 if ended else 0):   # (up to 8 s: a busy machine can be slow to exit)
        done, st = os.waitpid(pid, os.WNOHANG)
        if done:
            status = os.waitstatus_to_exitcode(st)
            break
        time.sleep(0.1)
    if status is None:
        os.kill(pid, 9)
        os.waitpid(pid, 0)
    return drawn.decode(errors="replace"), status

def click_on(label):
    """A mouse click on the row where `label` was last drawn (SGR report)."""
    def f(drawn):
        m = None
        for m in re.finditer(r"\x1b\[(\d+);(\d+)H(?:\x1b\[[0-9;]*m)* ?" + re.escape(label), drawn.decode(errors="replace")):
            pass
        assert m, "never drew " + label
        return "\x1b[<0;%d;%dM\x1b[<0;%d;%dm" % (int(m.group(2)) + 3, int(m.group(1)), int(m.group(2)) + 3, int(m.group(1)))
    return f

if __name__ == "__main__":
    script, home, path, folder, ranfile = sys.argv[1:6]
    scenario = sys.argv[6]
    env = {"PATH": path, "HOME": home, "TERM": "xterm-256color", "WREN_DIR": folder, "LANG": "C.UTF-8", "WREN_ESC_WAIT": "0.3", "WREN_MENU_TEST_READY": "1",
           # no browser or editor unless a scenario's test names some
           "WREN_MENU_BROWSERS": os.environ.get("WREN_MENU_BROWSERS", "/nonexistent"),
           "WREN_MENU_EDITORS": os.environ.get("WREN_MENU_EDITORS", "/nonexistent"),
           "WREN_MENU_APPS": os.environ.get("WREN_MENU_APPS", "/nonexistent"),
           "WREN_MENU_NMTUI": os.environ.get("WREN_MENU_NMTUI", "")}
    if scenario.startswith("sway-"):
        env["SWAYSOCK"] = "/nonexistent/sway.sock"
    SYSTEM, SETTINGS, APPS = click_on("System"), click_on("Settings"), click_on("Apps")
    NETWORK, POWER = click_on("Wi-Fi"), click_on("Power")
    scenarios = {
        "enter": ["k", "\r"],
        "all-lists": [APPS, "\x1b", SYSTEM, "\x1b", POWER, "\x1b", "\x1b"],
        "settings-list": [SETTINGS, "\x1b", "\x1b"],
        "top-only": ["\x1b"],
        "system-install": [APPS, click_on("Install apps")],
        "j-enter": [SYSTEM, "\r"],
        "j-remove": [APPS, click_on("Remove apps")],
        "up-wraps": ["\x1b[A", "\r"],
        "click-update": [SYSTEM, click_on("Update")],
        "click-outside": ["\x1b[<0;1;1M\x1b[<0;1;1m", "q"],
        # pasted text shaped like a mouse report: its row is a command
        "click-crafted": ["\x1b[<0;5;a[$(cd;touch pasted-ran)]M", "q"],
        "esc": ["\x1b"],
        "list-esc-esc": ["\r", "\x1b", "\x1b"],
        "list-esc-only": ["\r", "\x1b"],
        "list-back": [SYSTEM, click_on("Back"), "\x1b"],
        "help-esc": ["k", "\r", "\x1b"],
        "help-q": ["k", "\r", "q"],
        "help-space": ["k", "\r", " ", "\x1b"],
        "help-pgdn": ["k", "\r", "\x1b[6~", "\x1b"],
        "help-end": ["k", "\r", "\x1b[F", "\x1b"],
        "help-wheel": ["k", "\r", "\x1b[<65;5;5M", "\x1b[<65;5;5M", "\x1b[<65;5;5M", "\x1b[<65;5;5M", "\x1b[<65;5;5M", "\x1b[<65;5;5M", "\x1b[<65;5;5M", "\x1b[<65;5;5M", "\x1b"],
        "status-esc": [SYSTEM, click_on("Status"), "\x1b"],
        "resize": [("resize", 40, 120), "q"],
        "toggle-wifi": [NETWORK, click_on("Wi-Fi:"), "\x1b", SETTINGS, "\x1b", "\x1b"],
        "space-wifi": [NETWORK, " ", "\x1b", "\x1b"],
        "click-mic": [SETTINGS, click_on("Microphone"), "\x1b", "\x1b"],
        "net-choose": [NETWORK, click_on("Choose a network"), "\r", "\x1b", "\x1b"],
        "early-resize": [("early", 40, 120), "q"],
        "q": ["q"],
        "sway-terminal": [click_on("Terminal")],
        "sway-install-browser": [click_on("Web browser")],
        "sway-install-passwords": [click_on("Password manager")],
        "sway-tor": [APPS, click_on("Tor Browser")],
        "sway-whonix": [APPS, click_on("Whonix")],
        "sway-lock": [POWER, click_on("Lock")],
        "sway-logout": [POWER, click_on("Log out")],
        "power-suspend": [POWER, click_on("Suspend")],
        "power-reboot": [POWER, click_on("Reboot")],
        "power-shutdown": [POWER, click_on("Shut down")],
        "sway-power-list": [POWER, "\x1b", "\x1b"],
        "sway-space-terminal": [" ", "\x1b"],
        "sway-click-terminal": [click_on("Terminal")],
        "sway-browser": [click_on("Web browser")],
        "sway-editor": [APPS, click_on("Text editor")],
        "sway-files": [APPS, click_on("File manager")],
        "sway-all": [APPS, "\x1b", SETTINGS, "\x1b", SYSTEM, "\x1b", "\x1b"],
        "sway-passwords": [click_on("Password manager")],
        "sway-signal": [APPS, click_on("Signal")],
        "sway-simplex": [APPS, click_on("SimpleX")],
        "sway-claude": [APPS, click_on("Claude")],
        "sway-opencode": [APPS, click_on("opencode")],
        "vault-closed": [SETTINGS, click_on("Vault: closed"), "\r", "\x1b", "\x1b"],
        "vault-open": [SETTINGS, click_on("Vault: open"), "\x1b", "\x1b"],
        "backup": [SYSTEM, click_on("Back up now"), "\r", "\x1b", "\x1b"],
        "startup": [SYSTEM, click_on("Startup programs"), "\x1b", "\x1b"],
        "sway-switches-space": [SETTINGS, "k", "k", " ", "\r", "\x1b", SYSTEM, "\x1b", "\x1b"],
        "sway-securedns-click": [SETTINGS, click_on("Secure DNS"), "\r", "\x1b", "\x1b"],
        "sway-theme-click": [SETTINGS, click_on("Theme"), "\x1b", "\x1b"],
        "sway-signin": [NETWORK, click_on("Sign-in page")],
    }
    drawn, status = run(script, env, scenarios[scenario])
    if len(sys.argv) > 7:
        open(sys.argv[7], "w").write(re.sub(r"\x1b\[[0-9;?<]*[A-Za-z]|\x1b\][^\x07]*\x07", "\n", drawn))
    print("STATUS", status)
    print("DREW", "|".join(re.findall(r"(Help|Install apps|Update|Status)", drawn)[:4]))
    print("DREWALL", "|".join(re.findall(r"(Help|Terminal|Install apps|Update|Status)", drawn)[:5]))
    print("DREWAPPS", "|".join(re.findall(r"(Help|Terminal|Web browser|Text editor|Install apps)", drawn)[:5]))
    print("DREWMORE", "|".join(dict.fromkeys(re.findall(r"(File manager|Password manager|Signal|SimpleX|Claude|opencode|Back up now|Install apps|Vault: \w+)", drawn))))
    # where the title "wren" was drawn each time: row;column
    print("TITLES", " ".join("%s;%s" % m for m in re.findall(r"\x1b\[(\d+);(\d+)H\x1b\[1mWren Linux", drawn)))
PY
menu() { # SCENARIO [FOLDER]: runs it, leaves the output in $out and what ran in $T/ran
    : >"$T/ran"
    out=$(python3 -I "$T/drive.py" "$HERE/bin/wren-menu" "$T/home" "$T/fake:/usr/bin:/bin" "${2-$T/wren}" "$T/ran" "$1" "$T/screen" 2>&1)
}

# the mark the test waits for is printed only when a test asks for it
w=$(sed -n '/^waiting() {/p' "$HERE/bin/wren-menu")
# shellcheck disable=SC2016  # the inner shell expands its own variables
check "the menu marks each wait for a key only for the test" bash -c '
    [ -n "$1" ] && [ -z "$(env -u WREN_MENU_TEST_READY bash -c "$1; waiting")" ] &&
    [ -n "$(WREN_MENU_TEST_READY=1 bash -c "$1; waiting")" ]' _ "$w"

menu enter
check "outside sway there is no Terminal entry (it would open in this terminal anyway)" not grep -q '^DREWALL.*Terminal' <<<"$out"
# inside sway: a Terminal entry, opening foot through sway as Super+Enter does
printf '#!/bin/sh
echo "swaymsg $*" >>"%s/ran"
' "$T" >"$T/fake/swaymsg"
chmod +x "$T/fake/swaymsg"
menu sway-terminal
check "inside sway the first screen has Terminal, and Help last" grep -q 'DREWALL Terminal|Help' <<<"$out"
# shellcheck disable=SC2016  # the inner shell expands its own variables
check "...which opens foot through sway, and the menu closes" bash -c 'grep -qx "swaymsg exec foot" "$1" && grep -q "STATUS 0" <<<"$2"' _ "$T/ran" "$out"
: >"$T/ran"
menu sway-space-terminal
check "Space on an entry that isn't a switch opens nothing" not grep -q "swaymsg exec" "$T/ran"
menu sway-click-terminal
check "...also with a click" grep -qx 'swaymsg exec foot' "$T/ran"
check "no editor installed: no line for it" not grep -qE '^DREWAPPS.*Text editor' <<<"$out"
menu sway-install-browser
# shellcheck disable=SC2016  # the inner shell expands its own variables
check "no browser installed: Web browser stays on the first screen, and offers to install one" \
    bash -c 'grep -q "Web browser: install one" "$1" && grep -qxF "$2/wren|install-extras.sh|pause=1" "$3"' _ "$T/screen" "$T" "$T/ran"
menu sway-install-passwords
# shellcheck disable=SC2016  # the inner shell expands its own variables
check "...and so does Password manager" \
    bash -c 'grep -q "Password manager: install one" "$1" && grep -qxF "$2/wren|install-extras.sh|pause=1" "$3"' _ "$T/screen" "$T" "$T/ran"
# A web browser and a text editor: the default browser (mimeapps.list) is the one opened
mkdir -p "$T/apps" "$T/home/.config"
for a in firefox firefox-esr mousepad; do printf '#!/bin/sh\n' >"$T/apps/$a"; chmod +x "$T/apps/$a"; done
export WREN_MENU_BROWSERS="$T/apps/firefox-esr $T/apps/firefox" WREN_MENU_EDITORS="$T/apps/mousepad"
printf '[Default Applications]\nx-scheme-handler/https=wren-firefox.desktop\n' >"$T/home/.config/mimeapps.list"
menu sway-editor
check "inside sway: Web browser, then Terminal, on the first screen; in Apps, Install apps first, then Text editor" grep -q 'DREWAPPS Web browser|Terminal|Help|Install apps|Text editor' <<<"$out"
menu sway-browser
check "...Web browser opens the default browser (the sandboxed firefox, though listed second), through sway" grep -qx "swaymsg exec $T/apps/firefox" "$T/ran"
rm "$T/home/.config/mimeapps.list"
menu sway-browser
check "...with no default set, the first one installed" grep -qx "swaymsg exec $T/apps/firefox-esr" "$T/ran"
menu sway-editor
check "...Text editor opens Mousepad" grep -qx "swaymsg exec $T/apps/mousepad" "$T/ran"
export WREN_MENU_EDITORS=/nonexistent
menu sway-browser
# shellcheck disable=SC2016  # the inner shell expands its own variables
check "...no editor installed: only Web browser" bash -c 'grep -q "Web browser" <<<"$1" && ! grep -q "Text editor" <<<"$1"' _ "$(grep ^DREWAPPS <<<"$out")"
unset WREN_MENU_BROWSERS WREN_MENU_EDITORS
# File manager, Password manager, Claude, Back up now and the Vault switch,
# each only when installed
check "nothing else installed: none of them" not grep -qE '^DREWMORE.*(File manager|Claude|Back up|Vault)' <<<"$out"
for a in thunar keepassxc signal-desktop simplex claude opencode-vm torbrowser-launcher whonix; do printf '#!/bin/sh\n' >"$T/apps/$a"; chmod +x "$T/apps/$a"; done
printf '#!/bin/sh\necho "backup $*" >>"%s/ran"\n' "$T" >"$T/apps/backup"
# a pretend vault: open while $T/vault-open exists
# shellcheck disable=SC2016  # the inner shell expands its own variables
printf '#!/bin/sh\necho "vault $*" >>"%s/ran"\ncase "$1" in status) [ -e "%s/vault-open" ] && echo "open in x" || echo closed ;; open) : >"%s/vault-open" ;; close) rm -f "%s/vault-open" ;; esac\n' "$T" "$T" "$T" "$T" >"$T/apps/vault"
chmod +x "$T/apps/backup" "$T/apps/vault"
export WREN_MENU_APPS="$T/apps/torbrowser-launcher $T/apps/whonix $T/apps/thunar $T/apps/keepassxc $T/apps/signal-desktop $T/apps/simplex $T/apps/claude $T/apps/opencode-vm $T/apps/vault $T/apps/backup"
menu sway-all
check "all installed: Password manager first; Install apps, File manager, Signal, SimpleX, Claude, opencode in Apps; the Vault in Settings; Back up now in System" \
    grep -q '^DREWMORE Password manager|Install apps|File manager|Signal|SimpleX|Claude|opencode|Vault: closed|Back up now' <<<"$out"
check "...Apps ends with Remove apps, just before Back" grep -A1 -x ' *Remove apps *' "$T/screen" | grep -q 'Back'
menu sway-tor
check "Tor Browser opens through sway" grep -qx "swaymsg exec $T/apps/torbrowser-launcher" "$T/ran"
menu sway-whonix
check "Whonix opens through sway" grep -qx "swaymsg exec $T/apps/whonix" "$T/ran"
# Power
printf '#!/bin/sh\necho "systemctl $*" >>"%s/ran"\n' "$T" >"$T/fake/systemctl"
printf '#!/bin/sh\necho "wren-lock" >>"%s/ran"\n' "$T" >"$T/home/.local/bin/wren-lock"
chmod +x "$T/fake/systemctl" "$T/home/.local/bin/wren-lock"
menu sway-power-list
# shellcheck disable=SC2016  # the inner shell expands its own variables
check "Power lists Lock, Suspend, Log out, Reboot and Shut down" \
    bash -c 'for l in Lock Suspend "Log out" Reboot "Shut down"; do grep -q "$l" "$1" || exit 1; done' _ "$T/screen"
menu sway-lock
check "...Lock locks, through sway" grep -qx "swaymsg exec $T/home/.local/bin/wren-lock" "$T/ran"
menu sway-logout
check "...Log out leaves sway" grep -qx "swaymsg exit" "$T/ran"
menu power-suspend
check "...Suspend" grep -qx "systemctl suspend" "$T/ran"
menu power-reboot
check "...Reboot" grep -qx "systemctl reboot" "$T/ran"
menu power-shutdown
check "...Shut down" grep -qx "systemctl poweroff" "$T/ran"
menu sway-all
# shellcheck disable=SC2016  # the inner shell expands its own variables
check "each list says where you are, and how to go back" bash -c 'grep -q "Wren Linux > Apps" "$1" && grep -q "Esc goes back" "$1"' _ "$T/screen"
menu sway-files
check "File manager opens Thunar through sway" grep -qx "swaymsg exec $T/apps/thunar" "$T/ran"
menu sway-passwords
check "Password manager opens KeePassXC" grep -qx "swaymsg exec $T/apps/keepassxc" "$T/ran"
menu sway-signal
check "Signal opens Signal Desktop" grep -qx "swaymsg exec $T/apps/signal-desktop" "$T/ran"
menu sway-simplex
check "SimpleX opens SimpleX Chat" grep -qx "swaymsg exec $T/apps/simplex" "$T/ran"
menu sway-opencode
check "opencode opens opencode-vm (which opens its own window)" grep -qx "swaymsg exec $T/apps/opencode-vm" "$T/ran"
menu sway-claude
check "Claude: the claude command, in a window, in your home (it asks which, and goes where it must)" grep -qx "swaymsg exec foot --title=Claude -D $T/home $T/apps/claude" "$T/ran"
rm -f "$T/vault-open"
menu vault-closed
# shellcheck disable=SC2016  # the inner shell expands its own variables
check "Vault: closed, chosen: it opens (asking for its password in the window)" bash -c 'grep -qx "vault open" "$1" && [ -e "$2" ]' _ "$T/ran" "$T/vault-open"
check "...and the line then says open" grep -q 'Vault: open' "$T/screen"
menu vault-open
# shellcheck disable=SC2016  # the inner shell expands its own variables
check "Vault: open, chosen: it closes, and the menu stays" bash -c 'grep -qx "vault close" "$1" && [ ! -e "$2" ]' _ "$T/ran" "$T/vault-open"
menu backup
check "Back up now runs backup in the window" grep -qx 'backup ' "$T/ran"
# Startup programs, in System: the edit screen, in the window; then the menu again
printf '#!/bin/sh\necho "wren-autostart $*" >>"%s/ran"\n' "$T" >"$T/apps/wren-autostart"
chmod +x "$T/apps/wren-autostart"
WREN_MENU_APPS="$WREN_MENU_APPS $T/apps/wren-autostart"
menu startup
# shellcheck disable=SC2016  # the inner shell expands its own variables
check "Startup programs opens the edit screen, and comes back" bash -c 'grep -qx "wren-autostart edit" "$1" && grep -q "STATUS 0" <<<"$2"' _ "$T/ran" "$out"
# The theme and secure DNS switches: each only when installed
# shellcheck disable=SC2016  # the inner shell expands its own variables
printf '#!/bin/sh\necho "theme $*" >>"%s/ran"\n[ -n "$1" ] || echo "Theme: light"\n' "$T" >"$T/apps/theme"
# shellcheck disable=SC2016  # the inner shell expands its own variables
printf '#!/bin/sh\necho "secure-dns $*" >>"%s/ran"\n[ "$1" != status ] || echo off\n' "$T" >"$T/apps/secure-dns"
chmod +x "$T/apps/theme" "$T/apps/secure-dns"
WREN_MENU_APPS="$WREN_MENU_APPS $T/apps/theme $T/apps/secure-dns"
: >"$T/ran"
menu sway-switches-space
# shellcheck disable=SC2016  # the inner shell expands its own variables
check "inside sway the Theme and Secure DNS lines are listed, with their state" bash -c 'grep -q "Theme: Light" "$1" && grep -q "Secure DNS: off" "$1"' _ "$T/screen"
check "Space on Secure DNS switches it, in the window" grep -qx "secure-dns toggle" "$T/ran"
check "the first screen says how secure DNS is, without opening the list" grep -q "Settings: DNS off" "$T/screen"
: >"$T/ran"
menu sway-securedns-click
check "...a click on it too" grep -qx "secure-dns toggle" "$T/ran"
: >"$T/ran"
menu sway-theme-click
check "a click on Theme switches the theme" grep -qx "theme toggle" "$T/ran"
printf '#!/bin/sh\n' >"$T/apps/wifi-signin"
chmod +x "$T/apps/wifi-signin"
WREN_MENU_APPS="$WREN_MENU_APPS $T/apps/wifi-signin"
: >"$T/ran"
menu sway-signin
# shellcheck disable=SC2016  # the inner shell expands its own variables
check "Wi-Fi sign-in opens the sign-in window through sway, and the menu closes" bash -c '
    grep -qx "swaymsg exec $1" "$2" && grep -q "STATUS 0" <<<"$3"' _ "$T/apps/wifi-signin" "$T/ran" "$out"
# shellcheck disable=SC2016  # the inner shell expands its own variables
check "the menu looks for theme and secure-dns where they are installed" bash -c '
    grep "^APPS=" "$1" | grep -q "\$HOME/.local/bin/wren-autostart \$HOME/.local/bin/theme \$HOME/.local/bin/secure-dns /usr/local/bin/wifi-signin}"' _ "$HERE/bin/wren-menu"
unset WREN_MENU_APPS
rm -f "$T/fake/swaymsg"
menu all-lists
# shellcheck disable=SC2016  # the inner shell expands its own variables
check "Apps holds Install apps; System holds Update and Status; Help is on the first screen" \
    bash -c 'grep -q "Install apps" "$1" && grep -q Update "$1" && grep -q Status "$1" && grep -q Help "$1"' _ "$T/screen"
# Choosing a network: nmtui, where there is one, else wifi.sh, in this window
printf '#!/bin/sh\necho nmtui >>"%s/ran"\n' "$T" >"$T/nmtui"
chmod +x "$T/nmtui"
: >"$T/wren/wifi.sh"
WREN_MENU_NMTUI=$T/nmtui
export WREN_MENU_NMTUI
menu net-choose
check "Wi-Fi > Choose a network runs nmtui in the window, and comes back" grep -qx nmtui "$T/ran"
unset WREN_MENU_NMTUI
menu net-choose
check "...without NetworkManager it runs wifi.sh" grep -qxF "$T/wren|wifi.sh|pause=" "$T/ran"
rm "$T/wren/wifi.sh"
menu enter
check "Enter on Help opens it in the pager, not less" grep -qx 'line 1' "$T/screen"
check "...which says how to close it" grep -q 'Esc closes' "$T/screen"

menu help-esc
check "Esc closes the Help page and the window" grep -q 'STATUS 0' <<<"$out"
menu help-q
check "q does too" grep -q 'STATUS 0' <<<"$out"
menu help-space
check "Space scrolls a page" grep -qx 'line 24' "$T/screen"
check "...and Esc then closes" grep -q 'STATUS 0' <<<"$out"
menu help-pgdn
check "Page Down scrolls a page" grep -qx 'line 24' "$T/screen"
menu help-end
check "End shows the last page" grep -qx 'line 100' "$T/screen"
menu help-wheel
check "the mouse wheel scrolls" grep -qx 'line 26' "$T/screen"
menu status-esc
check "Status is shown in the pager too" grep -qxF "$T/wren|status.sh|pause=" "$T/ran"
check "...and Esc closes it" grep -q 'STATUS 0' <<<"$out"

menu system-install
check "Install apps runs install-extras.sh in the Wren Linux folder" grep -qxF "$T/wren|install-extras.sh|pause=1" "$T/ran"

menu j-remove
check "Remove apps, after Install apps, runs install-extras.sh --remove in the Wren Linux folder" grep -qxF "$T/wren|install-extras.sh --remove|pause=1" "$T/ran"
menu j-enter
check "j moves down too (Update)" grep -qxF "$T/wren|update.sh|pause=1" "$T/ran"
check "what Update prints is also kept in a log" grep -qx 'printed by update.sh' "$T/home/.local/state/wren/menu-update.log"

menu up-wraps
check "Up from the first entry goes to the last (Help)" grep -qx 'line 1' "$T/screen"

menu click-update
check "a click on Update runs update.sh" grep -qxF "$T/wren|update.sh|pause=1" "$T/ran"

menu click-outside
check "a click outside the entries runs nothing" test ! -s "$T/ran"

rm -f "$T/home/pasted-ran"
menu click-crafted
# shellcheck disable=SC2016  # the inner shell expands them
check "a mouse report that isn't numbers (pasted text) runs nothing" bash -c '[ ! -e "$1/pasted-ran" ] && [ ! -s "$2" ]' _ "$T/home" "$T/ran"

menu esc
check "Esc closes the menu" grep -q 'STATUS 0' <<<"$out"
check "...and runs nothing" test ! -s "$T/ran"

menu q
check "q closes the menu" grep -q 'STATUS 0' <<<"$out"

menu list-esc-only
check "Esc in a list goes back, it doesn't close" grep -q 'STATUS None' <<<"$out"
menu list-esc-esc
check "...and Esc again closes" grep -q 'STATUS 0' <<<"$out"
menu list-back
check "the Back line goes back too (a mouse is enough)" grep -q 'STATUS 0' <<<"$out"

menu resize
check "the menu starts centered for the window's first size (24x80)" grep -q 'TITLES 9;19' <<<"$out"
check "and centers itself again, with no key pressed, when sway stretches the window" grep -q 'TITLES 9;19 17;39' <<<"$out"
check "...without leaving the menu" grep -q 'STATUS 0' <<<"$out"

menu early-resize
check "a window stretched before the first draw is drawn centered at once, with no jump" grep -qx 'TITLES 17;39' <<<"$(grep TITLES <<<"$out")"

# Wi-Fi, Bluetooth and the microphone: listed only when the computer has them
printf 'wifi on\nmic off\n' >"$T/radios-list"; echo on >"$T/radio-wifi"; echo off >"$T/radio-mic"
cp "$T/radios.sh" "$T/home/.local/bin/radios"; chmod +x "$T/home/.local/bin/radios"
menu toggle-wifi
check "Wi-Fi and the microphone are listed, with their state" grep -q 'Wi-Fi: on' "$T/screen" && grep -q 'Microphone: off' "$T/screen"
check "choosing Wi-Fi flips it" grep -qx 'radios wifi toggle' "$T/ran"
check "...the entry shows the new state" grep -q 'Wi-Fi: off' "$T/screen"
check "the first screen says how the microphone is, without opening the list" grep -q 'Settings: mic off' "$T/screen"
check "...and the menu stays open until Esc" grep -q 'STATUS 0' <<<"$out"
check "Bluetooth is not listed when the computer has none" not grep -q 'Bluetooth' "$T/screen"
: >"$T/ran"; echo on >"$T/radio-wifi"
menu space-wifi
# shellcheck disable=SC2016  # the inner shell expands its own variables
check "Space flips a switch too" bash -c 'grep -qx "radios wifi toggle" "$1" && grep -q "Wi-Fi: off" "$2"' _ "$T/ran" "$T/screen"
echo off >"$T/radio-mic"
menu click-mic
check "a click on Microphone flips it too" grep -qx 'radios mic toggle' "$T/ran"
printf 'bluetooth blocked\n' >"$T/radios-list"; echo blocked >"$T/radio-bluetooth"
menu settings-list
check "a Bluetooth held off by a hardware switch says so" grep -q 'Bluetooth: off (hardware switch)' "$T/screen"
: >"$T/radios-list"
menu top-only
# shellcheck disable=SC2016  # the inner shell expands its own variables
check "with nothing to switch there is no such list" bash -c '! grep -q Settings "$1"' _ "$T/screen"
check "...only the usual entries show" test "$(grep -c -E 'Wi-Fi|Bluetooth|Microphone' "$T/screen")" -eq 0
rm -f "$T/home/.local/bin/radios"

menu esc "$T/nowhere"
check "without the Wren Linux folder no Install apps or Update, only Help and Power" grep -q 'DREW Help$' <<<"$out"

# 3. The prompt at the end of the install and update screens: Esc, Enter or q
cat >"$T/pause.py" <<'PY'
import os, pty, select, sys, time
def run(keys, pause=True):
    pid, fd = pty.fork()
    if pid == 0:
        env = dict(os.environ, TERM="xterm", WREN_ESC_WAIT="0.3")
        if pause: env["WREN_PAUSE"] = "1"
        else: env.pop("WREN_PAUSE", None)
        os.execvpe("/bin/bash", ["bash", "-c", ". " + sys.argv[1] + "; pause_if_asked; echo AFTER-IT"], env)
    out = b""
    def pump(w, stop=b"AFTER-IT"):
        """Read for up to w seconds; done early once stop has been printed."""
        nonlocal out
        end = time.time() + w
        while time.time() < end and stop not in out:
            r, _, _ = select.select([fd], [], [], 0.05)
            if r:
                try: d = os.read(fd, 4096)
                except OSError: return
                if not d: return
                out += d
    # until it asks (or, with nothing to wait for, has gone on)
    pump(5, b"Press Esc to close" if pause else b"AFTER-IT")
    waiting = b"AFTER-IT" not in out
    for k in keys:
        os.write(fd, k.encode()); pump(1.5)   # (only a key that must not close it waits this long)
    os.kill(pid, 9); os.waitpid(pid, 0)
    return waiting, b"AFTER-IT" in out, b"Press Esc to close" in out
for name, keys, pause in [("none", [], False), ("x-then-esc", ["x", "\x1b"], True), ("enter", ["\r"], True),
                          ("q", ["q"], True), ("arrow", ["\x1b[A"], True), ("nothing", [], True)]:
    waiting, closed, prompted = run(keys, pause)
    print(name, "waiting=%s closed=%s prompted=%s" % (waiting, closed, prompted))
PY
pausetest=$(python3 -I "$T/pause.py" "$HERE/lib/core.sh" 2>&1)
check "with no menu, nothing waits" grep -qx 'none waiting=False closed=True prompted=False' <<<"$pausetest"
check "the prompt asks for Esc" grep -q 'prompted=True' <<<"$pausetest"
check "a stray key does not close it, Esc does" grep -qx 'x-then-esc waiting=True closed=True prompted=True' <<<"$pausetest"
check "Enter closes it" grep -qx 'enter waiting=True closed=True prompted=True' <<<"$pausetest"
check "q closes it" grep -qx 'q waiting=True closed=True prompted=True' <<<"$pausetest"
check "an arrow key does not close it" grep -qx 'arrow waiting=True closed=False prompted=True' <<<"$pausetest"
check "without a key it keeps waiting" grep -qx 'nothing waiting=True closed=False prompted=True' <<<"$pausetest"

# 4. The screens it opens
check "the install screen waits for Enter only when asked to" grep -q 'pause_if_asked' "$HERE/install-extras.sh"
check "choosing nothing in the checklist leaves before that wait" python3 -I -c '
import re, sys
s = open(sys.argv[1]).read()
none = s.index("No extras chosen")
wait = s.index("pause_if_asked")
assert none < wait and "exit 0" in s[none:wait], "the no-choice exit must come first"
' "$HERE/install-extras.sh"
# shellcheck disable=SC2016  # the inner shells expand their own variables
check "nmtui has its color block (the install list draws itself now, lib/checklist.sh)" \
    bash -c '[ -n "$(sed -n "/^# newt (whiptail/,/^export NEWT_COLORS$/p" "$1")" ]' _ "$HERE/bin/nmtui"

# the nmtui wrapper: runs the real program with Wren Linux's colors, unless you set your own
# shellcheck disable=SC2016  # written into the pretend program, expanded when it runs
printf '#!/bin/sh\necho "colors=$NEWT_COLORS"\necho "colorterm=${COLORTERM:-}"\necho "args=$*"\n' >"$T/fake/nmtui"
chmod +x "$T/fake/nmtui"
nm=$(env -u NEWT_COLORS -u COLORTERM TERM=foot WREN_NMTUI="$T/fake/nmtui" bash "$HERE/bin/nmtui" connect X)
check "the nmtui wrapper sets Wren Linux's colors: in foot, exact white on foot's own (see-through) black" grep -q 'colors=root=#ffffff,default ' <<<"$nm"
check "...telling newt the terminal has 24-bit color, or it ignores them (and draws blue and red)" grep -qx 'colorterm=truecolor' <<<"$nm"
check "...and passes its arguments on" grep -qx 'args=connect X' <<<"$nm"
nm=$(env -u NEWT_COLORS -u COLORTERM TERM=linux WREN_NMTUI="$T/fake/nmtui" bash "$HERE/bin/nmtui")
# shellcheck disable=SC2016
check "at the console (no 24-bit color): color names" bash -c 'grep -q "colors=root=white,black" <<<"$1" && grep -qx "colorterm=" <<<"$1"' _ "$nm"
# shellcheck disable=SC2016
check "every one of newt's color sets is given (one left out stays red)" bash -c '
for c in root border window shadow title button actbutton compactbutton checkbox actcheckbox entry disentry label listbox actlistbox sellistbox actsellistbox textbox acttextbox helpline roottext emptyscale fullscale; do
    grep -qE "(^| )$c=" <<<"${1#colors=}" || exit 1
done' _ "$(grep '^colors=' <<<"$nm")"

# the real whiptail (newt, as nmtui is), with nmtui's colors: only black and
# white come out, the chosen line reversed (white behind it)
if command -v whiptail >/dev/null; then
    cat >"$T/wt.py" <<'PY'
import os, pty, select, sys, time, fcntl, termios, struct, re
def run(term):
    pid, fd = pty.fork()
    if pid == 0:
        env = dict(os.environ, TERM=term); env.pop("COLORTERM", None); env.pop("NEWT_COLORS", None)
        os.execvpe("bash", ["bash", "-c", 'eval "$(sed -n "/^# newt (whiptail/,/^export NEWT_COLORS$/p" "$1")"; exec whiptail --checklist pick 15 60 4 a one OFF b two OFF', "_", sys.argv[1]], env)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
    out = b""; end = time.time() + 1.0
    while time.time() < end:
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: d = os.read(fd, 65536)
            except OSError: break
            if not d: break
            out += d
    os.kill(pid, 9); os.waitpid(pid, 0)
    return set(re.findall(rb"\x1b\[([0-9;]*)m", out))
bw = {b"", b"1", b"30", b"37", b"39", b"40", b"47", b"49", b"38;2;0;0;0", b"38;2;255;255;255", b"48;2;0;0;0", b"48;2;255;255;255"}
for term, white_bg in (("foot", b"48;2;255;255;255"), ("linux", b"47")):
    c = run(term)
    print(term, "bw" if c and c <= bw else sorted(c - bw), "reversed" if white_bg in c else "flat")
    # in foot, black behind the text is foot's own background (49), which its
    # alpha makes see-through; an explicit black (48;2;0;0;0, 40) is solid
    if term == "foot":
        print("foot", "solid-black" if (b"48;2;0;0;0" in c or b"40" in c) else "see-through")
PY
    wt=$(python3 -I "$T/wt.py" "$HERE/bin/nmtui" 2>&1)
    check "the real whiptail in foot: only black and white, the chosen line reversed" grep -qx 'foot bw reversed' <<<"$wt"
    check "...and at the console" grep -qx 'linux bw reversed' <<<"$wt"
    check "...in foot no black is drawn solid: the background is foot's own, see-through like the bar's windows" grep -qx 'foot see-through' <<<"$wt"
fi

# the introduction (prep/intro.sh, start.sh's first screen) says what to press
if command -v less >/dev/null; then
    cat >"$T/intro.py" <<'PY'
import os, pty, select, sys, time, fcntl, termios, struct, re
pid, fd = pty.fork()
if pid == 0:
    os.execvpe("bash", ["bash", sys.argv[1]], dict(os.environ, TERM="xterm", WREN_ASSUME_YES="1"))
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 20, 80, 0, 0))
out = b""
def pump(want, w=10):
    """Read until want has been drawn (True), or w seconds have passed (False)."""
    global out
    end = time.time() + w
    while time.time() < end:
        if want in re.sub(rb"\x1b\[[0-9;?]*[A-Za-z]|\x1b[=>]|\r|\x07", b"", out).decode(errors="replace"):
            return True
        r, _, _ = select.select([fd], [], [], 0.05)
        if r:
            try: d = os.read(fd, 65536)
            except OSError: break
            if not d: break
            out += d
    return False
print("first", pump("Space for more, b to go back, q to go on"))
for _ in range(12):
    os.write(fd, b" "); time.sleep(0.1)
print("end", pump("The end. Press q to go on to the question"))
os.write(fd, b"q")
for _ in range(50):
    done, st = os.waitpid(pid, os.WNOHANG)
    if done: break
    time.sleep(0.1)
if not done:
    os.kill(pid, 9); os.waitpid(pid, 0)
print("q", bool(done) and os.waitstatus_to_exitcode(st) == 0)
PY
    intro=$(python3 -I "$T/intro.py" "$HERE/prep/intro.sh" 2>&1)
    check "the introduction says what to press while you read (Space, b, q)" grep -qx 'first True' <<<"$intro"
    check "...and on its last page that q goes on" grep -qx 'end True' <<<"$intro"
    check "...and q does go on" grep -qx 'q True' <<<"$intro"
    # what it promises is what the base does ("nothing that isn't listed here")
    text=$(WREN_ASSUME_YES=1 bash "$HERE/prep/intro.sh" </dev/null 2>/dev/null)
    # shellcheck disable=SC2016  # the inner shell expands its own variables
    check "the introduction lists encrypted DNS, the private home, what it removes, tmux and the clock" bash -c '
        for w in Unbound "umask 077" avahi tmux NTP; do grep -q "$w" <<<"$1" || { echo "$w"; exit 1; }; done' _ "$text"
    # shellcheck disable=SC2016  # the inner shell expands its own variables
    check "...and doesn't list what are extras now (sound, screenshots, emoji) as the base" bash -c '! sed "/Before any of that/,\$d" <<<"$1" | grep -qiE "\bsound\b|screenshots|emoji"' _ "$text"
    # shellcheck disable=SC2016  # the inner shell expands its own variables
    check "...and asks for the extras first, not at the end" bash -c '! grep -q "At the end, offer" <<<"$1" && ! grep -q "if you$" <<<"$1"' _ "$text"
fi
nm=$(NEWT_COLORS='root=red,blue' WREN_NMTUI="$T/fake/nmtui" bash "$HERE/bin/nmtui")
check "colors you set yourself win" grep -qx 'colors=root=red,blue' <<<"$nm"
# shellcheck disable=SC2016  # a literal $HOME in the bar's script
check "the Wi-Fi name in the bar opens the wrapper" grep -q 'exec "\$HOME/.local/bin/nmtui"' "$HERE/bin/sway-status"

# a click on the bar opens a window, a second click closes it (open_or_close in
# bin/sway-status), with a pretend swaymsg: "kill" succeeds only if one is open
mkdir -p "$T/oc/bin" "$T/oc/xdg"
printf '#!/bin/sh\necho "$*" >>"%s/oc/sway"\ncase "$*" in *kill*) [ -e "%s/oc/open" ] ;; *) exit 0 ;; esac\n' "$T" "$T" >"$T/oc/bin/swaymsg"
chmod +x "$T/oc/bin/swaymsg"
oc() { # APP-ID: runs open_or_close as the bar would; what happened is in $T/oc/sway and $T/oc/ran
    : >"$T/oc/sway"; rm -f "$T/oc/ran"
    PATH="$T/oc/bin:$PATH" XDG_RUNTIME_DIR="$T/oc/xdg" sh -c 'eval "$(sed -n "/^menu_busy() {/,/^}/p; /^open_or_close() {/,/^}/p" "$1")"; open_or_close "$2" touch "$3"; wait' \
        _ "$HERE/bin/sway-status" "$1" "$T/oc/ran"
    # (the window is started on its own, so give it a moment)
    for _ in 1 2 3 4 5 6 7 8 9 10; do [ ! -e "$T/oc/ran" ] || break; /bin/sleep 0.1; done
}
rm -f "$T/oc/open"; oc wren-timer
check "bar: a click with nothing open opens the window" test -e "$T/oc/ran"
touch "$T/oc/open"; oc wren-timer
# shellcheck disable=SC2016  # expanded by the inner shell or Python, on purpose
check "...a click while it is open closes it, and opens nothing" \
    bash -c 'grep -qx -- "-q \[app_id=\"wren-timer\"\] kill" "$1/sway" && [ ! -e "$1/ran" ]' _ "$T/oc"
echo $$ >"$T/oc/xdg/wren-menu-busy"; oc wren-run
# shellcheck disable=SC2016  # expanded by the inner shell or Python, on purpose
check "...but the Wren menu running Update (busy) is only brought to the front, never closed" \
    bash -c 'grep -qx -- "-q \[app_id=\"wren-run\"\] focus" "$1/sway" && ! grep -q kill "$1/sway" && [ ! -e "$1/ran" ]' _ "$T/oc"
echo 999999999 >"$T/oc/xdg/wren-menu-busy"; oc wren-run
check "...a busy mark left by a menu that is gone doesn't stop the closing" grep -q kill "$T/oc/sway"
echo 'x; reboot' >"$T/oc/xdg/wren-menu-busy"; oc wren-run
check "...nor does a mark that isn't a number" grep -q kill "$T/oc/sway"
rm -f "$T/oc/xdg/wren-menu-busy" "$T/oc/open"
oc wren-timer
# shellcheck disable=SC2016  # expanded by the inner shell, on purpose
check "one bar window at a time: opening the timer closes the menu, the Wi-Fi screen and the cheat sheet" \
    bash -c 'for w in wren-run wren-nmtui wren-keys; do grep -qx -- "-q \[app_id=\"$w\"\] kill" "$1/sway" || exit 1; done; [ -e "$1/ran" ]' _ "$T/oc"
echo $$ >"$T/oc/xdg/wren-menu-busy"; oc wren-timer
# shellcheck disable=SC2016  # expanded by the inner shell, on purpose
check "...but not a Wren menu that is running Update" bash -c '! grep -q "wren-run" "$1/sway" && [ -e "$1/ran" ]' _ "$T/oc"
rm -f "$T/oc/xdg/wren-menu-busy"
# Super+m: sway-status --menu, as a click on "wren" in the bar
mkdir -p "$T/oc/home/.local/bin"
printf '#!/bin/sh\ntouch "%s/oc/menu-ran"\n' "$T" >"$T/oc/home/.local/bin/wren-menu"
chmod +x "$T/oc/home/.local/bin/wren-menu"
echo 4242 >"$T/oc/xdg/sway-status.pid"
rm -f "$T/oc/open" "$T/oc/menu-ran"; : >"$T/oc/sway"
timeout 5 env PATH="$T/oc/bin:$PATH" HOME="$T/oc/home" XDG_RUNTIME_DIR="$T/oc/xdg" sh "$HERE/bin/sway-status" --menu </dev/null >/dev/null 2>&1
for _ in 1 2 3 4 5 6 7 8 9 10; do [ ! -e "$T/oc/menu-ran" ] || break; /bin/sleep 0.1; done
check "Super+m (sway-status --menu) opens the Wren menu" test -e "$T/oc/menu-ran"
check "...and leaves the running bar's PID file alone" test "$(cat "$T/oc/xdg/sway-status.pid")" = 4242
touch "$T/oc/open"; rm -f "$T/oc/menu-ran"; : >"$T/oc/sway"
timeout 5 env PATH="$T/oc/bin:$PATH" HOME="$T/oc/home" XDG_RUNTIME_DIR="$T/oc/xdg" sh "$HERE/bin/sway-status" --menu </dev/null >/dev/null 2>&1
/bin/sleep 0.3
# shellcheck disable=SC2016  # expanded by the inner shell, on purpose
check "...pressed again while it's open: closes it, opens nothing" \
    bash -c 'grep -qx -- "-q \[app_id=\"wren-run\"\] kill" "$1/sway" && [ ! -e "$1/menu-ran" ]' _ "$T/oc"
rm -f "$T/oc/open" "$T/oc/xdg/sway-status.pid"
# shellcheck disable=SC2016  # $mod is sway's, not the shell's
check "sway binds Super+m to it, in the part's snippet (update.sh re-runs a part, never install-base.sh)" bash -c '
    grep -qx "bindsym \$mod+m exec ~/.local/bin/sway-status --menu" "$1/parts/wren-menu.sh" && grep -qx "put_snippet wren-menu <<.EOF." "$1/parts/wren-menu.sh" &&
    ! grep -q "sway-status --menu" "$1/install-base.sh"' _ "$HERE"
check "the cheat sheet lists Super+m" grep -q 'Super+m .*Wren menu' "$HERE/data/keys.txt"
# sway restarts swaybar on every reload, and swaybar stops the status script's
# whole process group: a window started in it would be killed mid-way
rm -f "$T/oc/open" "$T/oc/sid"
PATH="$T/oc/bin:$PATH" XDG_RUNTIME_DIR="$T/oc/xdg" sh -c 'eval "$(sed -n "/^menu_busy() {/,/^}/p; /^open_or_close() {/,/^}/p" "$1")"; open_or_close wren-timer sh -c "echo \$\$ \$(ps -o sid= -p \$\$) >\"\$1\"" _ "$2"; wait' \
    _ "$HERE/bin/sway-status" "$T/oc/sid"
for _ in 1 2 3 4 5 6 7 8 9 10; do [ ! -s "$T/oc/sid" ] || break; /bin/sleep 0.1; done
# shellcheck disable=SC2016  # expanded by the inner shell, on purpose
check "a window from the bar has a session of its own (a sway reload, which restarts the bar, doesn't close it)" \
    bash -c 'read -r pid sid <"$1" && [ "$pid" = "$sid" ]' _ "$T/oc/sid"
# shellcheck disable=SC2016  # expanded by the inner shell or Python, on purpose
check "the time, the Wi-Fi name and Wren Linux in the bar each open or close their window" bash -c '
    grep -qF "open_or_close wren-timer foot -o colors.alpha=0.85 --app-id=wren-timer" "$1" &&
    grep -qF "open_or_close wren-nmtui foot -o colors.alpha=0.85 --app-id=wren-nmtui" "$1" &&
    grep -qF "open_or_close wren-run \"\$HOME/.local/bin/wren-menu\"" "$1"' _ "$HERE/bin/sway-status"
# shellcheck disable=SC2016  # expanded by the inner shell or Python, on purpose
check "the menu marks itself busy before Update or Install apps, and unmarks after" \
    python3 -I -c 'import sys; s = open(sys.argv[1]).read(); a = s.index("echo $$ >\"$busy\""); assert a < s.index("bash update.sh") and a < s.index("bash install-extras.sh") < s.index("rm -f \"$WREN_PAUSED_FILE\" \"$busy\"")' "$HERE/bin/wren-menu"

# the bar
check "the bar shows Wren Linux" grep -q '"full_text":"wren"' "$HERE/bin/sway-status"
check "the bar has no separate Help any more" not grep -q '"name":"help"' "$HERE/bin/sway-status"
check "a click on Wren Linux starts the menu" grep -q 'wren-menu' "$HERE/bin/sway-status"

# shellcheck disable=SC2016  # the inner bash, and the menu's own text
# A script that waits at its end marks it, so the menu doesn't ask a second time;
# one that stops on an error before that leaves no mark, and the menu waits
check "pause_if_asked marks that the window waited" bash -c '. "$1/lib.sh"; WREN_PAUSE=1 WREN_PAUSED_FILE="$2/paused" pause_if_asked </dev/null >/dev/null 2>&1; [ -e "$2/paused" ]' _ "$HERE" "$T"
# shellcheck disable=SC2016  # the menu's own text, $ included
check "the menu waits after an error only without that mark" grep -q '"$rc" -ne 0 \] && \[ ! -e "$WREN_PAUSED_FILE" \]' "$HERE/bin/wren-menu"

[ "$fails" -eq 0 ]
