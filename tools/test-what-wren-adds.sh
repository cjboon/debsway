#!/bin/bash
# Checks docs/what-wren-adds.md against the scripts, so it can't drift: every script it names is
# there, each part that hardens something is in it, and the values it gives for Wren Linux are
# the ones Wren Linux sets. Its Debian column was measured on a plain Debian 13 and can't be
# checked here: docs/maintaining.md says to measure it again at each new Debian.
# Run by test.sh, or:  bash tools/test-what-wren-adds.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
D=$HERE/docs/what-wren-adds.md
missing=$(grep -oE '`(parts|extras|lib|bin|data)/[A-Za-z0-9_./-]+|`[a-z-]+\.sh`' "$D" | tr -d '`' | sort -u | while read -r f; do [ -e "$HERE/$f" ] || echo "$f"; done | paste -sd' ')
check "every script it names is there${missing:+: missing $missing}" test -z "$missing"
# (these make the desktop work; they change nothing about security or privacy)
NOT_SECURITY=' core-commands clock wmenu brightnessctl wl-clipboard mako foot-config autostart wallpaper theme power-profiles-daemon wren-menu command-hints console-tmux grub-colors network-manager sandbox-dns swaylock '
. "$HERE/packages.sh"
left=
for p in "${PARTS[@]}"; do
    case $NOT_SECURITY in *" $p "*) continue ;; esac
    grep -q "parts/$p\.sh" "$D" || left+=" $p"
done
check "each base part that hardens something has a row${left:+: not there:$left}" test -z "$left"
bad=
while IFS='|' read -r _ key _debian wren _; do
    key=$(tr -d ' `' <<<"$key") wren=$(tr -d ' ' <<<"$wren")
    [[ $key =~ ^(kernel|net|fs|dev)\. ]] || continue
    grep -qx "$key = $wren" "$HERE/data/sysctl-hardening.conf" || bad+=" $key=$wren"
done <"$D"
check "the kernel settings it gives are the ones Wren Linux sets${bad:+: not:$bad}" test -z "$bad"
bad=
for w in init_on_free=1 slab_nomerge page_alloc.shuffle=1 debugfs=off intel_iommu=on iommu.strict=1; do
    grep -qF "$w" "$HERE/parts/boot-hardening.sh" && grep -qF "\`$w\`" "$D" || bad+=" $w"
done
check "...and the boot settings${bad:+: not:$bad}" test -z "$bad"
for e in firefox-sandbox claude-vm tor-browser whonix backup vault keepassxc security-key startup-watch; do
    check "extra $e is in it, and still an extra" bash -c 'grep -q "\`$1\`" "$2" && [ -f "$3/extras/$1.sh" ] && ! grep -q "^# retired:" "$3/extras/$1.sh"' _ "$e" "$D" "$HERE"
done
check "it says where to read what isn't protected" grep -q 'THREAT-MODEL.md' "$D"
check "the README points to it" grep -q 'docs/what-wren-adds.md' "$HERE/README.md"
[ "$fails" -eq 0 ]
