#!/bin/bash
# build-site.sh: makes Wren Linux's website, a folder of plain files, from one
# commit: its pages (site/), and a browsable copy of every file in it, with the
# commit log and a download of the whole commit. No JavaScript, no cookies,
# nothing loaded from elsewhere: it works in Tor Browser's Safest mode. The
# signing key's fingerprint and the git address come from pins.sh.
#  - --require-signed (what tools/publish-site.sh uses): only a commit signed
#    by the key pins.sh pins, checked as update.sh checks one, so the site
#    shows exactly what that key vouched for.
#  - --onion ADDRESS: the site's onion address, shown on every page and on
#    Verify (setup-vps.sh prints it).
#  - --pages DIR: the pages from DIR instead of the commit's site/ (to try
#    changes before they are committed; never with --require-signed).
#  - --preview: the pages as they are in this copy (site/, committed or not),
#    into ~/Downloads/wren-site-preview (unless --out says otherwise), opened in
#    the sandboxed Firefox: it may read ~/Downloads, so nothing listens on a
#    port and no firewall opens. (The server's headers aren't there: look at
#    those on the test VM, tools/try-vps.sh.)
# Usage: bash tools/build-site.sh --out DIR [--commit REV] [--onion ADDRESS] [--require-signed] [--pages DIR]
#        bash tools/build-site.sh --preview [--out DIR]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$WREN_DIR/lib/appimage.sh"
. "$WREN_DIR/lib/update.sh"
not_root

g() { git -C "$WREN_DIR" "$@"; }
usage() { die "Usage: bash tools/build-site.sh --out DIR [--commit REV] [--onion ADDRESS] [--require-signed] [--pages DIR]"; }

out='' rev=HEAD onion='' signed=false pages='' preview=false
while [ $# -gt 0 ]; do
    case $1 in
        --out) out=${2:-}; shift 2 || usage ;;
        --commit) rev=${2:-}; shift 2 || usage ;;
        --onion) onion=${2:-}; shift 2 || usage ;;
        --pages) pages=${2:-}; shift 2 || usage ;;
        --require-signed) signed=true; shift ;;
        --preview) preview=true; shift ;;
        *) usage ;;
    esac
done
if $preview; then
    $signed && die "--preview shows what isn't committed yet, so not with --require-signed."
    [ -n "$pages" ] || pages=$WREN_DIR/site
    [ -n "$out" ] || out=$HOME/Downloads/wren-site-preview
fi
[ -n "$out" ] || usage
# It replaces OUT: only a folder it made before (its mark inside), or none
if [ -e "$out" ] && [ ! -f "$out/.wren-site" ]; then
    die "$out exists and isn't a site this made (no .wren-site in it); give a new folder."
fi
[ -z "$onion" ] || [[ $onion =~ ^[a-z2-7]{56}\.onion$ ]] || die "\"$onion\" isn't an onion address (56 letters and digits, then .onion)."
if $signed && [ -n "$pages" ]; then die "--pages takes pages that aren't committed, so not with --require-signed."; fi
need_tools git:git python3:python3

commit=$(g rev-parse --verify --quiet "$rev^{commit}") || die "\"$rev\" isn't a commit here."
if $signed; then
    [ -n "${WREN_SIGNING_FPR:-}" ] || die "pins.sh pins no signing key, so nothing can be checked."
    update_signed "$commit" || die "Commit $commit isn't signed by Wren Linux's key ($WREN_SIGNING_FPR); the site wasn't built."
fi
# What the site says comes from the commit too: its pins.sh, not this copy's
fpr=$(g show "$commit:pins.sh" | sed -n 's/^WREN_SIGNING_FPR=//p' | head -n1)
url=$(g show "$commit:pins.sh" | sed -n 's/^WREN_GIT_URL=//p' | head -n1)
[[ $fpr =~ ^[0-9A-F]{40}$ ]] || die "The commit's pins.sh pins no signing key."

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir "$T/src"
g archive --format=tar "$commit" | tar -C "$T/src" -xf -
[ -n "$pages" ] || pages=$T/src/site
[ -f "$pages/layout.html" ] || die "$pages has no layout.html: is it the site's folder?"
g log -n 60 --format='%H%x09%ad%x09%s' --date=short "$commit" >"$T/log"

rm -rf "$out.new"
mkdir -p "$out.new"
SITE_FPR=$fpr SITE_GIT_URL=$url SITE_COMMIT=$commit SITE_ONION=$onion SITE_SIGNED=$($signed && echo yes) \
    python3 -I "$WREN_DIR/tools/site.py" "$pages" "$T/src" "$T/log" "$out.new" || die "The site couldn't be made."
# The whole commit as one download, the same bytes each time it is made
g archive --format=tar --prefix=wren-linux/ "$commit" | gzip -9n >"$out.new/wren-linux.tar.gz"
(cd "$out.new" && sha256sum wren-linux.tar.gz >wren-linux.tar.gz.sha256)
echo "$commit" >"$out.new/.wren-site"
# Every file readable by the web server, nothing executable
find "$out.new" -type d -exec chmod 0755 {} + && find "$out.new" -type f -exec chmod 0644 {} +
rm -rf "$out"
mv "$out.new" "$out"
note "The site, from commit ${commit:0:12}, is in $out ($(du -sh "$out" | cut -f1))."
if $preview; then
    # (a test gives its own pretend firefox)
    fx=${WREN_FIREFOX:-/usr/local/bin/firefox}
    if [ -x "$fx" ]; then
        note "Opening it in the sandboxed Firefox."
        "$fx" "file://$out/index.html" >/dev/null 2>&1 &
    else
        note "Open it in a browser: file://$out/index.html"
    fi
fi
