#!/bin/bash
# Checks the light and dark theme (bin/theme, data/themes, parts/theme.sh):
# the dark theme is debsway's look as it was; switching writes the bar's
# colors and the plain background (a snippet sway accepts), foot's [colors]
# (its other settings kept), mako's colors and the launcher's, and only in
# debsway's own files; switching back gives the same files; the lock screen
# gets the theme's color, black if the theme can't say; the debsway menu,
# nmtui, the power menu and the wallpaper list take their colors from it.
# In a temp home with pretend swaymsg, makoctl, notify-send, gsettings and pgrep:
# nothing reaches the running desktop. Run by test.sh, or:  bash tools/test-theme.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
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
unset SWAYSOCK WAYLAND_DISPLAY

mkdir -p "$T/fake"
for p in swaymsg makoctl notify-send wmenu gsettings; do
    printf '#!/bin/sh\necho "%s $*" >>"%s/calls"\n' "$p" "$T" >"$T/fake/$p"
done
# (mako "isn't running": the real one on this desktop is never reloaded)
printf '#!/bin/sh\nexit 1\n' >"$T/fake/pgrep"
chmod +x "$T/fake/"*
H=$T/home
setup() { # a home as debsway sets it up: its foot.ini, mako config, styled launcher
    rm -rf "$H"
    mkdir -p "$H/.local/bin" "$H/.local/share/debsway/themes" "$H/.config/foot" "$H/.config/mako" "$H/.config/sway/config.d"
    cp "$HERE/bin/theme" "$H/.local/bin/theme"
    cp "$HERE/data/themes/dark" "$HERE/data/themes/light" "$H/.local/share/debsway/themes/"
    cp "$HERE/data/foot.ini" "$H/.config/foot/foot.ini"
    printf '# Written by debsway parts/mako.sh\ndefault-timeout=5000\n' >"$H/.config/mako/config"
    cp /etc/sway/config "$H/.config/sway/config" 2>/dev/null || : >"$H/.config/sway/config"
    bash -c '. "$1/lib/sway.sh"; echo "$LAUNCHER_STYLED"' _ "$HERE" >>"$H/.config/sway/config"
    printf 'include %s/.config/sway/config.d/*.conf\n' "$H" >>"$H/.config/sway/config"
}
th() { : >"$T/calls"; env HOME="$H" XDG_CONFIG_HOME="$H/.config" PATH="$T/fake:$PATH" bash "$H/.local/bin/theme" "$@"; }
sh_in() { env HOME="$H" XDG_CONFIG_HOME="$H/.config" PATH="$T/fake:$PATH" sh -c "$1"; }

# ---- the palettes
setup
mkdir -p "$H/.config/debsway"
n=""
for t in dark light; do echo "$t" >"$H/.config/debsway/theme"; n+="$(th env | wc -l) "; done
check "both palettes are read whole: every color there, nothing that isn't one" test "$n" = "23 23 "
rm -f "$H/.config/debsway/theme"
dark() { th get "$1"; }
check "dark is debsway's look as it was: foot's colors as data/foot.ini" bash -c '
    f=$1; [ "$(sed -n "s/^foreground=\([0-9a-f]*\).*/\1/p" "$f")" = "$2" ] && [ "$(sed -n "s/^background=\([0-9a-f]*\).*/\1/p" "$f")" = "$3" ] &&
    [ "$(for i in 0 1 2 3 4 5 6 7; do sed -n "s/^regular$i=\([0-9a-f]*\).*/\1/p" "$f"; done | paste -sd" ")" = "$4" ] &&
    [ "$(for i in 0 1 2 3 4 5 6 7; do sed -n "s/^bright$i=\([0-9a-f]*\).*/\1/p" "$f"; done | paste -sd" ")" = "$5" ]' _ \
    "$HERE/data/foot.ini" "$(dark FOOT_FG)" "$(dark FOOT_BG)" "$(dark FOOT_REGULAR)" "$(dark FOOT_BRIGHT)"
check "...the bar see-through black with white text, as install-base.sh sets it" \
    bash -c '[ "$1" = 00000080 ] && [ "$2" = ffffff ] && grep -q "background #00000080" "$3"' _ "$(dark BAR_BG)" "$(dark BAR_TEXT)" "$HERE/install-base.sh"
check "...the lock screen black, the menus black and white" \
    bash -c '[ "$1" = 000000 ] && [ "$2" = 000000 ] && [ "$3" = ffffff ]' _ "$(dark LOCK)" "$(dark WMENU_BG)" "$(dark WMENU_TEXT)"
check "...and the debsway menu's grays as before" bash -c '[ "$1" = "000000 9a9a9a b8b8b8 c8c8c8 8a8a8a a8a8a8 bcbcbc d0d0d0" ] && [ "$2" = d0d0d0 ]' _ "$(dark MENU_REGULAR)" "$(dark MENU_FG)"
check "light: the warm background you chose, dark text" bash -c '[ "$1" = f2efe9 ] && [ "$2" = 2b2b2b ]' _ "$(th light >/dev/null; th get DESKTOP_BG)" "$(th get BAR_TEXT)"

# ---- switching
setup
cp "$H/.config/foot/foot.ini" "$T/foot.orig"
th apply
for f in "$H/.config/foot/foot.ini" "$H/.config/mako/config" "$H/.config/sway/config" "$H/.config/sway/config.d/theme.conf"; do cp "$f" "$T/dark.${f##*/}"; done
th light
check "theme light: it is set, and sway reloads" bash -c '[ "$(cat "$1")" = light ] && grep -qx "Theme: light" <<<"$2"' _ "$H/.config/debsway/theme" "$(th)"
check "...the bar warm and see-through, its text dark; the plain background warm" \
    bash -c 'grep -qx "    background #f2efe9b3" "$1" && grep -qx "    statusline #2b2b2b" "$1" && grep -qx "output \* bg #f2efe9 solid_color" "$1"' _ "$H/.config/sway/config.d/theme.conf"
check "...foot's colors light, its font and other settings kept" bash -c '
    grep -qx "background=f2efe9" "$1" && grep -qx "foreground=2b2b2b" "$1" && [ "$(grep -c "^regular" "$1")" = 8 ] &&
    grep -q "^font=" "$1" && grep -qx "\[search-bindings\]" "$1" && [ "$(grep -c "^\[colors\]" "$1")" = 1 ]' _ "$H/.config/foot/foot.ini"
check "...foot still reads it" bash -c 'command -v foot >/dev/null || exit 0; foot -C -c "$1"' _ "$H/.config/foot/foot.ini"
check "...notifications light" bash -c 'grep -qx "background-color=#f2efe9f0" "$1" && grep -qx "text-color=#2b2b2b" "$1" && grep -qx "default-timeout=5000" "$1"' _ "$H/.config/mako/config"
check "...the launcher (Super+d) light" grep -q "^set \$menu wmenu-run -f 'monospace 12' -N f2efe9 -n 2b2b2b " "$H/.config/sway/config"
check "...sway accepts it all" bash -c 'command -v sway >/dev/null || exit 0
    ! env -u WAYLAND_DISPLAY WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 sway -C -c "$1" 2>&1 | grep -q "\[ERROR\]"' _ "$H/.config/sway/config"
th light >/dev/null
check "...GTK apps prefer light: settings.ini for GTK 3 and 4, and libadwaita's color-scheme" bash -c '
    grep -qx "gtk-application-prefer-dark-theme=false" "$1/gtk-3.0/settings.ini" && grep -qx "gtk-application-prefer-dark-theme=false" "$1/gtk-4.0/settings.ini" &&
    grep -qx "gsettings set org.gnome.desktop.interface color-scheme prefer-light" "$2"' _ "$H/.config" "$T/calls"
printf '[Settings]\ngtk-font-name=Mine 11\n' >"$H/.config/gtk-3.0/settings.ini"
th light
check "...a settings.ini line of your own stays" bash -c 'grep -qx "gtk-font-name=Mine 11" "$1" && [ "$(grep -c prefer-dark "$1")" = 1 ]' _ "$H/.config/gtk-3.0/settings.ini"
th dark
check "theme dark again: foot.ini, mako's config, the launcher and the snippet as before (nothing left half light)" bash -c '
    cmp -s "$1/dark.foot.ini" "$2/.config/foot/foot.ini" && cmp -s "$1/dark.theme.conf" "$2/.config/sway/config.d/theme.conf" &&
    grep -qx "background-color=#285577ff" "$2/.config/mako/config" && grep -q "^set \$menu wmenu-run -f .monospace 12. -N 000000 -n ffffff" "$2/.config/sway/config"' _ "$T" "$H"
th toggle >/dev/null
check "theme toggle: the other one" grep -qx light "$H/.config/debsway/theme"
th dark >/dev/null

# ---- only debsway's own files
setup
printf '[colors]\nbackground=123456\n' >"$H/.config/foot/foot.ini"
printf 'background-color=#123456\n' >"$H/.config/mako/config"
th light
check "a foot.ini or mako config you wrote yourself is left alone" \
    bash -c 'grep -qx "background=123456" "$1" && [ "$(cat "$2")" = "background-color=#123456" ]' _ "$H/.config/foot/foot.ini" "$H/.config/mako/config"

# ---- the lock screen, and what can't be read
setup
LOCK=$(bash -c '. "$1/lib/sway.sh"; echo "$LOCK_CMD"' _ "$HERE")
check "the lock screen: the theme's color (dark: black)" test "$(sh_in "echo $LOCK")" = "swaylock -f -c 000000"
th light >/dev/null
check "...light: the warm one" test "$(sh_in "echo $LOCK")" = "swaylock -f -c f2efe9"
echo 'LOCK=$(touch pwned)' >>"$H/.local/share/debsway/themes/light"
check "a palette with a line that isn't a color isn't read at all" not th get LOCK
check "...and the lock screen is black then, never without a color" test "$(sh_in "echo $LOCK")" = "swaylock -f -c 000000"
check "...nothing in it ran" test ! -e "$H/pwned" -a ! -e pwned
rm -rf "$H/.local/bin/theme"
check "no theme command at all: black too" test "$(sh_in "echo $LOCK")" = "swaylock -f -c 000000"
setup
check "theme get: only a name of capitals" bash -c '! "$@" get "LOCK;id" && ! "$@" get ""' _ env HOME="$H" XDG_CONFIG_HOME="$H/.config" bash "$H/.local/bin/theme"

# ---- the commands that take their colors from it
setup
th light >/dev/null
menu=$(env HOME="$H" XDG_CONFIG_HOME="$H/.config" bash -c 'eval "$(sed -n "/^gray_options() {/,/^}/p" "$1")"; gray_options' _ "$HERE/bin/debsway-menu" | paste -sd' ')
check "the debsway menu's window: light, dark text" bash -c 'grep -q "colors.background=f2efe9" <<<"$1" && grep -q "colors.foreground=2b2b2b" <<<"$1" && grep -q "colors.regular0=f2efe9" <<<"$1"' _ "$menu"
printf '#!/bin/sh\necho "colors=$NEWT_COLORS"\n' >"$T/fake/nmtui-real"
chmod +x "$T/fake/nmtui-real"
nm=$(env -u NEWT_COLORS -u COLORTERM HOME="$H" XDG_CONFIG_HOME="$H/.config" TERM=foot DEBSWAY_NMTUI="$T/fake/nmtui-real" bash "$HERE/bin/nmtui")
check "nmtui: dark text on foot's own background" grep -q "colors=root=#2b2b2b,default " <<<"$nm"
env HOME="$H" XDG_CONFIG_HOME="$H/.config" PATH="$T/fake:$PATH" sh "$HERE/bin/powermenu" </dev/null >/dev/null 2>&1
check "the power menu: light" grep -q "^wmenu -p Power: -f monospace 12 -N f2efe9 -n 2b2b2b" "$T/calls"
th dark >/dev/null
menu=$(env HOME="$H" XDG_CONFIG_HOME="$H/.config" bash -c 'eval "$(sed -n "/^gray_options() {/,/^}/p" "$1")"; gray_options' _ "$HERE/bin/debsway-menu" | paste -sd' ')
check "...and dark again: the menu as it was" bash -c 'grep -q "colors.background=000000" <<<"$1" && grep -q "colors.foreground=d0d0d0" <<<"$1"' _ "$menu"
rm -f "$H/.local/bin/theme"
menu=$(env HOME="$H" XDG_CONFIG_HOME="$H/.config" bash -c 'eval "$(sed -n "/^gray_options() {/,/^}/p" "$1")"; gray_options' _ "$HERE/bin/debsway-menu" | paste -sd' ')
check "...and with no theme command: the dark colors" grep -q "colors.background=000000" <<<"$menu"

# ---- incognito: the theme as one checked word, Firefox's look to match
line=$(grep -F 'unexpected theme' "$HERE/bin/incognito-session")
check "incognito's session refuses a theme other than light or dark" not bash -c 'die() { exit 1; }; theme="dark;id"; eval "$1"' _ "$line"
check "...and takes light" bash -c 'die() { exit 1; }; theme=light; eval "$1"' _ "$line"
mkdir -p "$T/ip"
( base=$T/ip theme=light; mkdir -p "$base/profile"; : >"$base/profile/user.js"
  eval "$(sed -n '/^# Downloads go to memory too/,/^} >>"\$base\/profile\/user.js"/p' "$HERE/bin/incognito-session")" ) 2>/dev/null
check "...light: Firefox's light look" grep -q 'firefox-compact-light@mozilla.org' "$T/ip/profile/user.js"
check "incognito hands over the theme, dark when none was chosen" python3 -I -c '
import sys; s = open(sys.argv[1]).read()
assert "case $theme in light | dark) ;; *) theme=dark ;; esac" in s
assert "\"$audio_arg\" \"$theme\" \"$@\"" in s' "$HERE/bin/incognito"

# ---- the part, and the menu's line
check "the part is in the base, after foot's and mako's" bash -c '. "$1/packages.sh"; p=" ${PARTS[*]} "; [[ $p == *" mako foot-config wallpaper theme "* ]]' _ "$HERE"
check "--remove goes back to dark first" python3 -I -c 'import sys; s = open(sys.argv[1]).read(); r = s.index("= --remove ]"); assert s.index("theme\" dark", r) < s.index("remove_bin theme", r)' "$HERE/parts/theme.sh"
check "foot's part keeps the theme's colors when it writes foot.ini again" grep -q '"$BIN/theme" apply' "$HERE/parts/foot-config.sh"
check "the debsway menu has a Theme line, inside sway" bash -c 'grep -q "ids+=(theme)" "$1" && grep -q "\"\$THEME_CMD\" toggle" "$1"' _ "$HERE/bin/debsway-menu"

[ "$fails" -eq 0 ]
