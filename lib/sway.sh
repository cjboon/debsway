# shellcheck shell=bash
# lib/sway.sh: the sway config and the snippets parts add to it.
# Sourced by lib.sh.

SWAY_CONFIG="$HOME/.config/sway/config"
SWAY_SNIPPETS="$HOME/.config/sway/config.d"
SWAY_INCLUDE="include $SWAY_SNIPPETS/*.conf"
# The one definition of how debsway locks the screen
LOCK_CMD='swaylock -f -c 000000'

# The launcher on Super+d (parts/wmenu.sh) is wmenu-run. wmenu has no height
# setting: its height follows its font. So the launcher gets a font a little
# larger than the bar's, to cover the bar completely instead of leaving a strip of
# it showing, and opaque colors in the bar's own black and white (the bar is
# see-through, so a see-through launcher would show it underneath). If a strip
# of the bar still shows, make the 12 bigger; if the launcher is too tall,
# smaller (the line is in ~/.config/sway/config, or here and run parts/wmenu.sh).
# shellcheck disable=SC2016  # $menu is sway's variable, not the shell's
LAUNCHER_STOCK='set $menu wmenu-run'
# shellcheck disable=SC2016
LAUNCHER_STYLED='set $menu wmenu-run -f '"'monospace 12'"' -N 000000 -n ffffff -M 000000 -m ffffff -S ffffff -s 000000'

# replace_line FILE OLD NEW: the line OLD in FILE becomes NEW; nothing else changes
replace_line() {
    local tmp
    tmp=$(mktemp)
    awk -v old="$2" -v new="$3" '$0 == old { print new; next } { print }' "$1" >"$tmp"
    cat "$tmp" >"$1"
    rm -f "$tmp"
}

# style_launcher FILE: the stock launcher line becomes debsway's. A line you
# changed yourself is left alone (the return status says whether it was ours).
style_launcher() {
    if grep -qxF "$LAUNCHER_STYLED" "$1"; then return 0; fi
    grep -qxF "$LAUNCHER_STOCK" "$1" || return 1
    replace_line "$1" "$LAUNCHER_STOCK" "$LAUNCHER_STYLED"
}

# unstyle_launcher FILE: back to the stock line
unstyle_launcher() { replace_line "$1" "$LAUNCHER_STYLED" "$LAUNCHER_STOCK"; }

# Some apps only speak X11. sway runs them through XWayland, but only
# finds XWayland when sway starts, so a fresh install needs a re-login.
need_xwayland() {
    local had=false
    is_installed xwayland && had=true
    # Always, even if it's there: this script's marker must hold it, or
    # removing another app that uses XWayland would take it away
    apt_install xwayland
    $had || warn "Installed XWayland. Log out and back in once so sway can use it."
}

# The user's sway config is the stock /etc/sway/config plus one include
# line, so each parts/ script can add or remove its own snippet file.
ensure_sway_config() {
    [ -f /etc/sway/config ] || die "sway isn't installed. Run install-base.sh first."
    mkdir -p "$SWAY_SNIPPETS"
    [ -f "$SWAY_CONFIG" ] || cp /etc/sway/config "$SWAY_CONFIG"
    # The snippets rebind these keys; sway shows its "errors in your config
    # file" bar for a key bound twice, so the stock bindings go
    sed -i -E '/^[[:space:]]*bindsym( --locked)? (XF86(Audio(Mute|LowerVolume|RaiseVolume|MicMute)|MonBrightness(Down|Up))|Print) exec (pactl|brightnessctl|grim)/d' "$SWAY_CONFIG"
    if ! grep -qxF "$SWAY_INCLUDE" "$SWAY_CONFIG"; then
        printf '\n# debsway feature snippets\n%s\n' "$SWAY_INCLUDE" >>"$SWAY_CONFIG"
    fi
}

# sway -C exits 0 even on errors, so look for them in its output
check_sway_config() {
    local out
    # Headless backend: validating needs no seat, so this also works over ssh
    out=$(WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 sway -C -c "$SWAY_CONFIG" 2>&1 || true)
    if grep -q '\[ERROR\]' <<<"$out"; then
        grep '\[ERROR\]' <<<"$out" >&2
        return 1
    fi
}

reload_sway() {
    if [ -n "${SWAYSOCK:-}" ] && swaymsg reload >/dev/null 2>&1; then
        note "Reloaded sway."
    else
        note "Takes effect the next time sway starts."
    fi
}

# put_snippet NAME < content: writes config.d/NAME.conf and checks it. If
# sway rejects it, the snippet that was there before is put back.
put_snippet() {
    local f="$SWAY_SNIPPETS/$1.conf" old=
    ensure_sway_config
    if [ -f "$f" ]; then
        old=$(mktemp)
        cp "$f" "$old"
    fi
    cat >"$f"
    if ! check_sway_config; then
        if [ -n "$old" ]; then
            mv "$old" "$f"
            die "sway rejected the new $f, so the old one was put back."
        fi
        rm -f "$f"
        die "sway rejected $f, so it was removed."
    fi
    if [ -n "$old" ]; then rm -f "$old"; fi
    note "Wrote $f"
    reload_sway
}

remove_snippet() {
    local f="$SWAY_SNIPPETS/$1.conf"
    if [ -f "$f" ]; then
        rm -f "$f"
        note "Removed $f"
        reload_sway
    fi
}
