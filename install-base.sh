#!/bin/bash
# The core desktop: sway and foot, a status bar, a key cheat sheet, and
# every part in parts/: automatic security updates, launcher, lock and idle,
# clipboard, notifications, firewall, kernel hardening, and (only where the hardware is)
# brightness keys, power profiles, NetworkManager and a random Wi-Fi MAC
# address. Everything else is in extras/: Firefox (with its hardening and the
# throwaway "incognito" Firefox), sound, screenshots, USB automount, emoji
# and more. A list right after you agree lets you pick some
# (nothing is checked for you), and they install after the base.
# It starts by explaining what it will do and asking whether to go on.
# Run as your normal user after you're online:
#   bash install-base.sh          explains, asks, installs
#   bash install-base.sh --yes    skips the explanation and the question
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

assume_yes=false
if [ "${1:-}" = --yes ]; then
    assume_yes=true
    shift
else
    bash "$DEBSWAY_DIR/prep/intro.sh" || exit 1
fi

. "$DEBSWAY_DIR/packages.sh"

need_user
# A root account with a password is another way to full control of the system
if [ "$(sudo passwd -S root 2>/dev/null | awk '{ print $2 }')" = P ]; then
    warn "The root account has a password. sudo already gives you root when you need it, so"
    warn "that password is one more way in. Lock it (sudo keeps working): sudo passwd -l root"
fi
. /etc/os-release
[ "${VERSION_CODENAME:-}" = "$DEBIAN_RELEASE" ] ||
    warn "Written for Debian 13 ($DEBIAN_RELEASE); this is ${PRETTY_NAME:-unknown}."

# The optional programs are chosen now, right after you agreed to the base
# install, and installed once the base is done. Nothing is checked for you.
picked=$(mktemp)
trap 'rm -f "$picked"' EXIT
bash "$DEBSWAY_DIR/install-extras.sh" --choose "$picked" || : >"$picked"

# Before anything is downloaded, so all of it can go through Tor
if ! $assume_yes; then
    say "Packages through Tor?"
    note "apt can download Debian's packages through Tor, over https, with obfs4 bridges"
    note "that you paste in: your network then can't see which packages you get, and it's"
    note "slower. You can also do it later: bash parts/apt-tor.sh"
    if ask "Download packages through Tor?" n; then
        bash "$DEBSWAY_DIR/parts/apt-tor.sh" ||
            warn "apt-tor didn't finish; packages will download the normal way."
    fi
fi

say "Installing packages"
apt_install "${PKGS[@]}"

say "sway config"
ensure_sway_config
check_sway_config || die "sway reports errors in $SWAY_CONFIG"
note "$SWAY_CONFIG (stock config + include for $SWAY_SNIPPETS)"

say "Key cheat sheet"
# Super+? shows data/keys.txt; it also opens once on the first login
KEYS="$HOME/.local/share/debsway/keys.txt"
mkdir -p "${KEYS%/*}"
install -m 0644 "$DEBSWAY_DIR/data/keys.txt" "$KEYS"
# Easy to find again: ~/KEYS.txt and the keys command. Both show only the lines
# for what is installed; keys rewrites ~/KEYS.txt each time it runs.
ln -sfn "$KEYS" "$HOME/KEYS.txt"
# (parts/core-commands.sh puts these in place again, so debsway --update can refresh them)
install_bin keys
install_bin debsway-welcome
install_bin timer
# Shift+slash is ? on a US keyboard; "question" follows the layout on others
put_snippet help <<'EOF'
# Key cheat sheet on Super+? (debsway install-base.sh)
bindsym $mod+Shift+slash exec foot --app-id=debsway-keys ~/.local/bin/keys
bindsym $mod+question exec foot --app-id=debsway-keys ~/.local/bin/keys
exec ~/.local/bin/debsway-welcome
EOF
note "Super+? shows it (also: type keys, or open ~/KEYS.txt). It opens by itself on your first login."

# Super+t, or a click on the time in the bar (bin/sway-status), opens the timer menu
put_snippet timer <<'EOF'
# Timers and alarms on Super+t (debsway install-base.sh)
bindsym $mod+t exec foot --app-id=debsway-timer ~/.local/bin/timer
EOF
# All the pop-up windows (key sheet, Wi-Fi, timer, the debsway menu) look and behave alike:
# floating, centered, over whatever you were doing. focus_follows_mouse is off because
# with it on, a pointer resting over another window (say a terminal running claude)
# takes the keyboard back from the pop-up, and Esc lands in that window instead.
put_snippet popups <<'EOF'
# Pop-up windows (debsway install-base.sh)
for_window [app_id="debsway-keys"] floating enable, resize set width 72 ppt height 85 ppt, move position center
for_window [app_id="debsway-run"] floating enable, resize set width 72 ppt height 85 ppt, move position center
for_window [app_id="debsway-nmtui"] floating enable, resize set width 60 ppt height 70 ppt, move position center
for_window [app_id="debsway-timer"] floating enable, resize set width 60 ppt height 60 ppt, move position center
focus_follows_mouse no
EOF
note "Pop-up windows are floating and centered; focus follows clicks, not the mouse pointer."
note "Super+t, or a click on the time in the bar: timers and alarms (or type: timer 10m tea)."

say "Look"
put_snippet appearance <<'EOF'
# No window borders (debsway install-base.sh)
default_border none
default_floating_border none
hide_edge_borders both
EOF
note "Windows have no borders."

say "Sharp screens"
# display-scale sets a screen's scale; its watcher says so, once per screen,
# when a sharp one is still at scale 1 (also when one is plugged in later)
install_bin display-scale
put_snippet display-watch <<'EOF'
# Notice sharp screens whose text is small (debsway display-scale)
exec ~/.local/bin/display-scale watch
EOF
note "Text too small on a sharp screen? display-scale makes it bigger (sway tells you once)."

say "sway status bar"
# bin/sway-status shows debsway (clickable: parts/debsway-menu.sh) | wifi | volume | brightness | battery | date
install_bin sway-status
# Edit the stock bar in place; a second bar block would add a second bar
if grep -q 'status_command while date' "$SWAY_CONFIG"; then
    sed -i 's|^\([[:space:]]*\)status_command while date.*|\1status_command ~/.local/bin/sway-status|' "$SWAY_CONFIG"
    note "Bar now runs sway-status."
fi
# See-through black instead of the stock grey
if grep -q '^[[:space:]]*background #323232$' "$SWAY_CONFIG"; then
    sed -i 's|^\([[:space:]]*\)background #323232$|\1background #00000080|' "$SWAY_CONFIG"
    note "Bar background is see-through black."
fi
check_sway_config || die "sway reports errors in $SWAY_CONFIG"
reload_sway

say "Start sway on tty1 login"
PROFILE="$HOME/.profile"
first_run=0
if grep -q '>>> debsway \(autostart\|console\)' "$PROFILE" 2>/dev/null; then
    note "Already set up in $PROFILE"
else
    first_run=1
    profile_autostart sway
    note "Added to $PROFILE. Other ttys (Ctrl+Alt+F2) still give a plain shell."
fi
# On a plain text console (Ctrl+Alt+F2, or tty1 without autostart) say where the keys are
if ! grep -q '>>> debsway hint' "$PROFILE" 2>/dev/null; then
    cat >>"$PROFILE" <<'EOF'

# >>> debsway hint >>>
case "$(tty 2>/dev/null)" in
    /dev/tty[0-9]*) [ -n "${WAYLAND_DISPLAY:-}" ] || echo "debsway: type keys for the key cheat sheet" ;;
esac
# <<< debsway hint <<<
EOF
fi

# Last, because the network-manager part can drop the connection briefly
failed=()
for part in "${PARTS[@]}"; do
    say "Part: $part"
    DEBSWAY_FROM_BASE=1 bash "$DEBSWAY_DIR/parts/$part.sh" || failed+=("$part")
done

if [ ${#failed[@]} -gt 0 ]; then
    warn "These parts failed: ${failed[*]}. Re-run one with: bash parts/NAME.sh"
fi

# The extras picked at the start (nothing was checked for you). They go in
# after the base: they need sway's config and the parts to be in place.
# git still asks for your commit name and email (just typing, fine on the
# console) but not for the GitHub login, which needs a browser that isn't
# running yet: log in later with  gh auth login
if [ -s "$picked" ]; then
    DEBSWAY_SETUP_GH=1 DEBSWAY_GH_LOGIN=0 bash "$DEBSWAY_DIR/install-extras.sh" --install "$picked" ||
        warn "Some extras didn't install; the message above says which."
else
    note "No extras chosen. Pick some any time with: debsway --apps"
fi

say "Done"
cat <<'EOF'
    Super+? lists every key; it also opens by itself the first time.
    debsway --status shows what's installed;
    debsway --apps picks more extras any time (sound, a browser, screenshots,
    USB automount... are there if you didn't pick them now).
    Reboot once: the boot hardening applies after it
    (check with: cat /proc/cmdline).
EOF

# First run, on a text console with no desktop yet: start sway now instead of
# making you log out and in. (The boot hardening still waits for a reboot.)
if [ "$first_run" = 1 ] && [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DEBSWAY_NO_SWAY:-}" ] &&
    [ -t 0 ] && case "$(tty 2>/dev/null)" in /dev/tty[0-9]*) true ;; *) false ;; esac; then
    note "Starting in 5 seconds (Ctrl+C to stay in the text console)..."
    sleep 5
    # the console-only extra may have been picked: then it is tmux that starts
    if [ "$(login_mode)" = console ]; then exec tmux new-session -A -s main; fi
    exec env XDG_CURRENT_DESKTOP=sway sway
fi
