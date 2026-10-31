#!/bin/bash
# Checks extras/yt-dlp.sh's pieces without sudo, a ytdlp user or yt-dlp itself:
# the yt-dlp command (bin/yt-dlp) with a pretend sudo and session, the session
# script (bin/yt-dlp-session) with a pretend yt-dlp, and what the extra
# installs and in which order. Changes nothing outside a temp folder. Run by
# test.sh, or:  bash tools/test-yt-dlp.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

# ---- the yt-dlp command: runs the session as ytdlp, copies the files out ----
mkdir -p "$T/fake" "$T/home" "$T/out"
echo "my secret" >"$T/home/secret"
# sudo -n -u ytdlp SESSION ARGS...: runs SESSION ARGS (as you, here)
printf '#!/bin/sh\necho "$*" >"%s/sudo-args"\nshift 3\nexec "$@"\n' "$T" >"$T/fake/sudo"
printf '#!/bin/sh\nexit 1\n' >"$T/fake/xdg-user-dir"
# the pretend session: what a run of yt-dlp leaves in its folder
cat >"$T/session" <<EOF
#!/bin/bash
id=\$1; shift
printf '%s\n' "\$id" >"$T/id"
printf '%s\n' "\$@" >"$T/args"
mkdir -m 2770 "$T/out/\$id" && cd "$T/out/\$id" || exit 9
echo video >video.mp4
mkdir sub && echo two >sub/b.webm
echo half >c.part
ln -s "$T/home/secret" link.mp4
exit \${RC:-0}
EOF
chmod +x "$T/fake/"* "$T/session"
yt() { env PATH="$T/fake:/usr/bin:/bin" HOME="$T/home" DEBSWAY_SUDO="$T/fake/sudo" \
    DEBSWAY_YTDLP_SESSION="$T/session" DEBSWAY_YTDLP_OUT="$T/out" bash "$HERE/bin/yt-dlp" "$@"; }

said=$(yt -x 'https://example.org/v?a=1&b=2' --opt "two words" 2>&1)
check "it runs the session as ytdlp, without asking for a password" grep -q "^-n -u ytdlp $T/session " "$T/sudo-args"
check "...with a new run id (24 hex digits) first" grep -qxE '[0-9a-f]{24}' "$T/id"
check "...and your options and URL as they were" \
    test "$(cat "$T/args")" = "$(printf '%s\n' -x 'https://example.org/v?a=1&b=2' --opt 'two words')"
check "the download is copied into ~/Downloads" test "$(cat "$T/home/Downloads/video.mp4")" = video
check "...with the folders yt-dlp made" test "$(cat "$T/home/Downloads/sub/b.webm")" = two
check "...as a file of yours, not a link" bash -c '[ -f "$1" ] && [ ! -L "$1" ] && [ "$(stat -c %U "$1")" = "$(id -un)" ]' _ "$T/home/Downloads/video.mp4"
check "an unfinished download (.part) isn't copied" test ! -e "$T/home/Downloads/c.part"
check "a link (to one of your files) isn't copied" bash -c '[ ! -e "$1" ] && [ ! -L "$1" ]' _ "$T/home/Downloads/link.mp4"
check "...and your file is untouched" test "$(cat "$T/home/secret")" = "my secret"
check "the run's folder is deleted afterwards" test -z "$(ls -A "$T/out")"
check "it says how many files and where" grep -q "yt-dlp: 2 file(s) in $T/home/Downloads" <<<"$said"
yt URL >/dev/null 2>&1
check "a file you already have isn't overwritten: the new one is \"video (2).mp4\"" \
    bash -c '[ "$(cat "$1/video.mp4")" = video ] && [ -f "$1/video (2).mp4" ] && [ -f "$1/sub/b (2).webm" ]' _ "$T/home/Downloads"
RC=3 yt URL >/dev/null 2>&1
check "yt-dlp's exit status is passed on" test $? = 3
check "copies are made with cp -P (a file swapped for a link meanwhile stays a link)" \
    grep -q 'cp -P --no-preserve=all -- "$f" "$target"' "$HERE/bin/yt-dlp"
# a file that can't be copied: the run's folder (and what is in it) is kept
cat >"$T/session-unreadable" <<EOF
#!/bin/bash
id=\$1
mkdir "$T/out/\$id" && cd "$T/out/\$id" || exit 9
echo ok >fine.mp4
echo locked >locked.mp4 && chmod 000 locked.mp4
EOF
chmod +x "$T/session-unreadable"
said=$(env PATH="$T/fake:/usr/bin:/bin" HOME="$T/home" DEBSWAY_SUDO="$T/fake/sudo" DEBSWAY_YTDLP_SESSION="$T/session-unreadable" \
    DEBSWAY_YTDLP_OUT="$T/out" bash "$HERE/bin/yt-dlp" URL 2>&1)
check "a file it can't copy: the run's folder is kept, nothing downloaded is lost" \
    bash -c 'ls "$1"/*/locked.mp4' _ "$T/out"
check "...and it says so, and where" grep -q "1 file(s) could not be copied; they are still in $T/out/" <<<"$said"
check "...the others are still copied" test -f "$T/home/Downloads/fine.mp4"
chmod -R u+rwx "$T/out" && rm -rf "${T:?}/out/"*
printf '#!/bin/bash\nexit 1\n' >"$T/session-fails"
chmod +x "$T/session-fails"
said=$(env PATH="$T/fake:/usr/bin:/bin" HOME="$T/home" DEBSWAY_SUDO="$T/fake/sudo" DEBSWAY_YTDLP_SESSION="$T/session-fails" \
    DEBSWAY_YTDLP_OUT="$T/out" bash "$HERE/bin/yt-dlp" URL 2>&1)
check "when it fails with nothing downloaded, it says how to update yt-dlp" grep -q 'bash ~/debsway/extras/yt-dlp.sh' <<<"$said"

# ---- the session script, as ytdlp would run it (paths moved into the temp folder) ----
S=$T/yt-dlp-session
mkdir -p "$T/s/out" "$T/s/home" "$T/s/lib"
# as extras/yt-dlp.sh makes it: setgid, so what is made in it gets its group
chmod 2770 "$T/s/out"
sed -e "s|^YTDLP=.*|YTDLP=$T/s/lib/yt-dlp|" -e "s|^OUT=.*|OUT=$T/s/out|" -e "s|^HOME_DIR=.*|HOME_DIR=$T/s/home|" \
    "$HERE/bin/yt-dlp-session" >"$S"
cat >"$T/s/lib/yt-dlp" <<'EOF'
import os, sys
print("argv", sys.argv[1:])
print("cwd", os.getcwd())
print("home", os.environ.get("HOME"), "path", os.environ.get("PATH"))
print("isolated", sys.flags.isolated)
EOF
id=0123456789abcdef01234567
out=$(PYTHONPATH=/nonexistent bash "$S" "$id" --flag 'https://example.org/x' 2>&1)
check "the session runs yt-dlp with python3 -I (no Python settings from outside)" grep -qx 'isolated 1' <<<"$out"
check "...with config files ignored, no self-update, QuickJS for the JavaScript, then your options" \
    grep -qxF "argv ['--ignore-config', '--no-update', '--js-runtimes', 'quickjs', '--flag', 'https://example.org/x']" <<<"$out"
check "...in this run's own folder" grep -qxF "cwd $T/s/out/$id" <<<"$out"
check "...made rw for ytdlp and your group only, its group kept for what is made in it (2770)" \
    test "$(stat -c %a "$T/s/out/$id")" = 2770
# Linux drops the setgid bit when ytdlp (not in your group) sets a folder's mode,
# so the folder must get it from $OUT, never from mkdir -m or chmod: with them
# yt-dlp's files got ytdlp's group and couldn't be read (the first real run)
check "...by a plain mkdir: no mkdir -m or chmod, which would lose the setgid bit as ytdlp" \
    bash -c 'grep -qx "mkdir \"\$OUT/\$id\"" "$1" && ! grep -qE "^[^#]*(mkdir -m|chmod)" "$1"' _ "$HERE/bin/yt-dlp-session"
check "...with ytdlp's home and a plain PATH" grep -qxF "home $T/s/home path /usr/bin:/bin" <<<"$out"
check "a run id that is there already is refused (no writing into another run)" not bash "$S" "$id" URL
for bad in '' x '../aaaaaaaaaaaaaaaaaaaaaaa' 0123456789ABCDEF01234567 0123456789abcdef0123456; do
    check "the run id '$bad' is refused" not bash "$S" "$bad" URL
done

# ---- what the extra installs ----
X=$HERE/extras/yt-dlp.sh
order() { # TEXT-BEFORE TEXT-AFTER: in the extra, the first comes before the second
    python3 -I -c 'import sys; s = open(sys.argv[1]).read(); a, b = s.index(sys.argv[2]), s.index(sys.argv[3]); assert a < b' "$X" "$1" "$2"
}
check "yt-dlp is downloaded from the release found (a fixed tag, not \"latest\" twice)" \
    grep -qF 'base=https://github.com/$REPO/releases/download/$tag' "$X"
check "its checksums must be signed by the pinned key before anything is installed" \
    order 'verify_detached "$YTDLP_FPR" "$YTDLP_KEY_URL" "$tmp/SHA2-256SUMS.sig" "$tmp/SHA2-256SUMS"' 'sudo install -o root -g root -m 0755 "$tmp/yt-dlp"'
check "...and the file must have the checksum the signed list gives" \
    order 'sha256sum -c --quiet' 'sudo install -o root -g root -m 0755 "$tmp/yt-dlp"'
check "yt-dlp is installed as root's file (ytdlp can't change it)" grep -qF 'sudo install -o root -g root -m 0755 "$tmp/yt-dlp" "$LIBDIR/yt-dlp"' "$X"
check "the key is fetched from keys.openpgp.org, not from the GitHub it signs for" \
    bash -c '. "$1/pins.sh"; [ "$YTDLP_FPR" = AC0CBBE6848D6A873464AF4E57CF65933B5A7581 ] && [[ $YTDLP_KEY_URL == https://keys.openpgp.org/* ]]' _ "$HERE"
check "ytdlp is a system user with no password and no login" \
    bash -c 'grep -qF -- "useradd --system --user-group" "$1" && grep -qF "usermod --lock --shell /usr/sbin/nologin" "$1"' _ "$X"
check "the sudoers rule allows the session script only, and is checked with visudo first" \
    bash -c 'grep -qF "ALL=(%s) NOPASSWD: %s" "$1" && grep -qF "sudo visudo -cf \"\$rule\"" "$1"' _ "$X"
check "the firewall keeps ytdlp off the network with the sandboxed Firefox's rules" bash -c '
    a=$(sed -n "/chain firefox {/,\$p" "$1/data/firefox-firewall.nft" | sed "s/chain firefox/chain X/")
    b=$(sed -n "/chain ytdlp {/,\$p" "$1/data/yt-dlp-firewall.nft" | sed "s/chain ytdlp/chain X/")
    [ -n "$a" ] && [ "$a" = "$b" ] && grep -qF "meta skuid \"ytdlp\" jump ytdlp" "$1/data/yt-dlp-firewall.nft"' _ "$HERE"
remove=$(sed -n '/^if \[ "${1:-}" = --remove \]/,/^fi$/p' "$X")
for thing in '"$SUDOERS"' '"$CMD"' '"$SESSION"' '"$FIREWALL"' '"$LIBDIR"' '"$OUT"' 'userdel "$NAME"' 'nft delete table inet debsway_ytdlp' 'apt_purge'; do
    check "--remove takes out $thing" grep -qF -- "$thing" <<<"$remove"
done

[ "$fails" -eq 0 ]
