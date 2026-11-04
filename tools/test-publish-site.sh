#!/bin/bash
# Checks tools/publish-site.sh with a pretend rsync and two local folders for
# the server: an unsigned commit isn't published at all; a signed one is
# copied (what the site no longer has deleted) and pushed to the mirror. Needs
# gpg. Changes nothing outside a temp folder. Run by test.sh, or:
#   bash tools/test-publish-site.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
command -v gpg >/dev/null || { echo "  ok    skipped: gpg isn't installed"; exit 0; }
T=$(mktemp -d)
# shellcheck disable=SC2317,SC2329  # runs from the EXIT trap
cleanup() { gpgconf --homedir "$T/gh" --kill all 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
export HOME=$T/home XDG_CONFIG_HOME='' XDG_CACHE_HOME=''
mkdir -p "$HOME"

# This checkout, as one commit, with a test key pinned
W=$T/w
mkdir -p "$W"
(cd "$HERE" && { git ls-files; git ls-files -o --exclude-standard -- site tools; } | sort -u | while read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done | tar -cf - -T -) | tar -C "$W" -xf -
mkdir -m 700 "$T/gh"
gpg --homedir "$T/gh" --batch --quiet --passphrase '' --quick-gen-key "publish test <p@t>" ed25519 sign 1y 2>/dev/null
F=$(gpg --homedir "$T/gh" --batch --with-colons --list-keys 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }')
gpg --homedir "$T/gh" --batch --armor --export "$F" >"$W/data/wren-signing-key.asc" 2>/dev/null
sed -i "s|^WREN_SIGNING_FPR=.*|WREN_SIGNING_FPR=$F|" "$W/pins.sh"
G=(git -C "$W" -c user.name=t -c user.email=t@t)
"${G[@]}" init -q -b main && "${G[@]}" add -A && "${G[@]}" -c commit.gpgsign=false commit -q -m unsigned

# The pretend server: a folder for the site (with a file the site doesn't
# have), a bare repository for the mirror; rsync copies and deletes like the real one
mkdir -p "$T/srv/site" && echo old >"$T/srv/site/gone.html"
git init -q --bare "$T/srv/mirror.git"
cat >"$T/rsync" <<EOF
#!/bin/bash
echo "rsync \$*" >>"$T/calls"
args=("\$@"); src=\${args[-2]} dest=\${args[-1]}
case " \$* " in *" --dry-run "*) exit 0 ;; esac
rm -rf "\$dest"* && cp -r "\$src". "\$dest" && rm -f "\$dest.wren-site"
EOF
chmod +x "$T/rsync"
pub() { env WREN_RSYNC="$T/rsync" WREN_PUBLISH_SITE="$T/srv/site/" WREN_PUBLISH_GIT="$T/srv/mirror.git" bash "$W/tools/publish-site.sh" "$@" 2>&1; }

out=$(pub --host wren-vps)
check "an unsigned commit: nothing is published" bash -c '
    grep -q "Nothing was published" <<<"$1" && [ -f "$2/srv/site/gone.html" ] && [ ! -e "$2/calls" ] && [ -z "$(git -C "$2/srv/mirror.git" for-each-ref)" ]' _ "$out" "$T"
GNUPGHOME=$T/gh "${G[@]}" -c gpg.program=gpg -c user.signingkey="$F" commit -q -S --allow-empty -m signed
C=$(git -C "$W" rev-parse HEAD)
out=$(pub --host wren-vps --dry-run)
check "--dry-run: rsync only shows what it would do; nothing is copied or pushed" bash -c '
    grep -q -- "--dry-run" "$1/calls" && [ -f "$1/srv/site/gone.html" ] && [ -z "$(git -C "$1/srv/mirror.git" for-each-ref)" ]' _ "$T"
: >"$T/calls"
out=$(pub --host wren-vps)
check "a signed commit: the site is copied, signed on every page${out:+: $(tail -1 <<<"$out")}" bash -c '
    grep -q "</code>, signed by the key on" "$1/srv/site/index.html" && [ -f "$1/srv/site/source/index.html" ]' _ "$T"
check "...what the site no longer has is gone from the server, and its build mark isn't copied" bash -c '[ ! -e "$1/srv/site/gone.html" ] && [ ! -e "$1/srv/site/.wren-site" ]' _ "$T"
check "...over ssh, without this computer's owners, files readable by the web server" grep -q -- "-rlt --delete --exclude=.wren-site --chmod=D755,F644 -e ssh" "$T/calls"
check "...and the mirror has exactly that commit as main" test "$(git -C "$T/srv/mirror.git" rev-parse refs/heads/main 2>/dev/null)" = "$C"
mkdir -p "$HOME/.config/wren/vps"
printf 'VPS_HOST=wren-vps\nVPS_SITE_ONION=%s.onion\n' "$(printf 'o%.0s' {1..56})" >"$HOME/.config/wren/vps/site.conf"
out=$(pub)
check "its settings file: the server, and the site's onion address on its pages" grep -q "Also at <code>$(printf 'o%.0s' {1..56}).onion</code>" "$T/srv/site/index.html"
printf 'VPS_HOST=wren-vps\nEVIL=1\n' >"$HOME/.config/wren/vps/site.conf"
check "...an unknown setting in it is refused" not pub
rm -f "$HOME/.config/wren/vps/site.conf"
check "no server named: refused" not pub
check "a server name that isn't one is refused" not pub --host 'x;rm -rf /'

[ "$fails" -eq 0 ]
