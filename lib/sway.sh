# shellcheck shell=bash
# lib/sway.sh: the sway config and the snippets parts add to it.
# Sourced by lib.sh.

SWAY_CONFIG="$HOME/.config/sway/config"
SWAY_SNIPPETS="$HOME/.config/sway/config.d"
SWAY_INCLUDE="include $SWAY_SNIPPETS/*.conf"
# The one definition of how debsway locks the screen
LOCK_CMD='swaylock -f -c 000000'

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
    if ! grep -qxF "$SWAY_INCLUDE" "$SWAY_CONFIG"; then
        printf '\n# debsway feature snippets\n%s\n' "$SWAY_INCLUDE" >>"$SWAY_CONFIG"
    fi
}

# sway -C exits 0 even on errors, so look for them in its output
check_sway_config() {
    local out
    out=$(sway -C -c "$SWAY_CONFIG" 2>&1 || true)
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
