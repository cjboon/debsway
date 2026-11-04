#!/bin/bash
# Checks the website (site/, tools/build-site.sh, tools/site.py): built from a
# commit, it holds no script, no inline style or event handler, nothing loaded
# from elsewhere, and no link that leads nowhere, so it works in Tor Browser's
# Safest mode and under the strict Content-Security-Policy setup-vps.sh sends;
# both themes are there; the fingerprint and git address are pins.sh's; the
# source browser escapes every file (this one holds <script>alert(1)</script>
# in this comment, and the site must still hold no script); and with
# --require-signed only a commit the pinned key signed is built. Changes
# nothing outside a temp folder. Run by test.sh, or:  bash tools/test-site.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
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
. "$HERE/pins.sh"

# A copy of this checkout, with what isn't committed yet, as one commit
W=$T/w
mkdir -p "$W"
(cd "$HERE" && { git ls-files; git ls-files -o --exclude-standard -- site tools; } | sort -u | while read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done | tar -cf - -T -) | tar -C "$W" -xf -
G=(git -C "$W" -c user.name=t -c user.email=t@t -c commit.gpgsign=false)
"${G[@]}" init -q -b main && "${G[@]}" add -A && "${G[@]}" commit -q -m "as it is now"

O=$T/out
out=$(bash "$W/tools/build-site.sh" --out "$O" 2>&1)
check "it builds, from the commit${out:+: $(tail -1 <<<"$out")}" test -f "$O/index.html"
check "...its pages, the source browser, the log and the download" bash -c '
    for f in index.html install.html verify.html style.css source/index.html source/log.html source/README.md.html source/docs/bios.md.html wren-linux.tar.gz wren-linux.tar.gz.sha256; do [ -f "$1/$f" ] || { echo "$f"; exit 1; }; done' _ "$O"

# The whole site, every tag and link: plain HTML only
cat >"$T/lint.py" <<'PY'
import html.parser, os, re, sys
root = sys.argv[1]
ALLOWED = {"html", "head", "meta", "title", "link", "body", "header", "nav", "main", "footer", "a", "h1", "h2",
           "p", "ul", "ol", "li", "strong", "code", "pre", "div", "table", "tr", "td", "hr"}
VOID = {"meta", "link", "hr"}
bad = []
class P(html.parser.HTMLParser):
    def __init__(self, path):
        super().__init__(convert_charrefs=True)
        self.path, self.stack = path, []
    def handle_starttag(self, tag, attrs):
        where = os.path.relpath(self.path, root)
        if tag not in ALLOWED:
            bad.append("%s: <%s>" % (where, tag))
        for k, v in attrs:
            v = v or ""
            if k.startswith("on") or k == "style":
                bad.append("%s: %s= on <%s>" % (where, k, tag))
            if re.match(r"\s*(javascript|data|vbscript):", v, re.I):
                bad.append("%s: %s=%s" % (where, k, v))
        a = dict(attrs)
        if tag == "link" and (a.get("rel") != "stylesheet" or re.match(r"[a-z]+:", a.get("href", ""))):
            bad.append("%s: a <link> to %s" % (where, a.get("href")))
        if tag == "a":
            h = a.get("href", "")
            if not re.match(r"(https?:)?//", h) and not h.startswith("#"):
                target = os.path.normpath(os.path.join(os.path.dirname(self.path), h.split("#")[0]))
                if not os.path.exists(target):
                    bad.append("%s: a link to %s, which isn't there" % (where, h))
        if tag not in VOID:
            self.stack.append(tag)
    def handle_endtag(self, tag):
        if not self.stack or self.stack.pop() != tag:
            bad.append("%s: </%s> doesn't close what is open" % (os.path.relpath(self.path, root), tag))
for top, _, files in os.walk(root):
    for f in files:
        if f.endswith(".html"):
            p = P(os.path.join(top, f))
            p.feed(open(os.path.join(top, f), encoding="utf-8").read())
            if p.stack:
                bad.append("%s: <%s> left open" % (os.path.relpath(p.path, root), p.stack[-1]))
print("\n".join(bad[:5]))
sys.exit(1 if bad else 0)
PY
lint=$(python3 -I "$T/lint.py" "$O")
check "every page: only plain tags, no script, inline style or event handler, every tag closed, every link leads somewhere${lint:+: $(paste -sd'|' <<<"$lint")}" test -z "$lint"
check "...not one <script anywhere (this test's own comment holds one: the source browser escaped it)" bash -c '
    ! grep -rqi "<script" "$1" && grep -q "&lt;script&gt;alert(1)&lt;/script&gt;" "$1/source/tools/test-site.sh.html"' _ "$O"
check "the style sheet loads nothing (no url(), @import or web font)" not grep -qE 'url\(|@import|@font-face' "$O/style.css"
check "...light, and dark when the system is" bash -c 'grep -q "prefers-color-scheme: dark" "$1" && grep -q "color-scheme: dark" "$1" && grep -q "color-scheme: light" "$1"' _ "$O/style.css"
check "...every page says it can be either" bash -c '! grep -rL "<meta name=\"color-scheme\" content=\"light dark\">" --include="*.html" "$1" | grep -q .' _ "$O"
spaced=$(sed -E 's/(.{4})/\1 /g; s/ $//' <<<"$WREN_SIGNING_FPR")
check "Verify shows the key pins.sh pins" grep -qF "<code>$spaced</code>" "$O/verify.html"
check "Install's git address is pins.sh's" grep -qF "git clone $WREN_GIT_URL ~/wren" "$O/install.html"
check "a build whose signature wasn't checked says so on every page" bash -c '
    ! grep -rL "a preview: its signature wasn.t checked" --include="*.html" "$1" | grep -q . && ! grep -rq "</code>, signed by the key on" "$1"' _ "$O"
check "the download is the commit, and its SHA-256 matches" bash -c '
    cd "$1" && sha256sum -c --quiet wren-linux.tar.gz.sha256 && tar -tzf wren-linux.tar.gz | grep -qx "wren-linux/pins.sh"' _ "$O"
check "the log lists the commit it was built from" bash -c 'grep -q "$(git -C "$2" rev-parse --short=12 HEAD)" "$1/source/log.html"' _ "$O" "$W"

# What it refuses, and what it leaves alone
mkdir -p "$T/mine"; echo keep >"$T/mine/notes"
check "an --out folder it didn't make is refused, and left as it was" bash -c '
    ! bash "$1/tools/build-site.sh" --out "$2" --pages "$1/site" 2>/dev/null && grep -qx keep "$2/notes"' _ "$HERE" "$T/mine"
check "...one it made is replaced" bash "$HERE/tools/build-site.sh" --out "$O" --pages "$HERE/site"
check "an --onion that isn't an onion address is refused" not bash "$HERE/tools/build-site.sh" --out "$T/o2" --pages "$HERE/site" --onion example.com
ON=$(printf 'a%.0s' {1..56}).onion
bash "$HERE/tools/build-site.sh" --out "$T/o3" --pages "$HERE/site" --onion "$ON" >/dev/null 2>&1
check "...one that is: on every page, and on Verify as a place to compare the key" bash -c '
    grep -q "Also at <code>$2</code>" "$1/index.html" && grep -q "this site.s onion address, <code>$2</code>" "$1/verify.html"' _ "$T/o3" "$ON"
check "the renderer refuses values that aren't what they should be" bash -c '
    ! SITE_FPR="<b>" SITE_GIT_URL=https://x.example/r SITE_COMMIT=$(printf "a%.0s" {1..40}) python3 -I "$1/tools/site.py" "$1/site" "$1" /dev/null "$2/x" 2>/dev/null' _ "$HERE" "$T"
check "--pages (not committed) and --require-signed don't go together" not bash "$HERE/tools/build-site.sh" --out "$T/o4" --pages "$HERE/site" --require-signed
check "the site's source isn't in the package (tools/build-deb.sh leaves it out)" grep -q '"$SHARE/site"' "$HERE/tools/build-deb.sh"

# --require-signed: only a commit the pinned key signed
if command -v gpg >/dev/null; then
    mkdir -m 700 "$T/gh"
    gpg --homedir "$T/gh" --batch --quiet --passphrase '' --quick-gen-key "site test <s@t>" ed25519 sign 1y 2>/dev/null
    F=$(gpg --homedir "$T/gh" --batch --with-colons --list-keys 2>/dev/null | awk -F: '/^fpr/ { print $10; exit }')
    gpg --homedir "$T/gh" --batch --armor --export "$F" >"$W/data/wren-signing-key.asc" 2>/dev/null
    sed -i "s|^WREN_SIGNING_FPR=.*|WREN_SIGNING_FPR=$F|" "$W/pins.sh"
    "${G[@]}" commit -q -am "the test key pinned, unsigned"
    check "--require-signed: an unsigned commit isn't built" bash -c '
        ! bash "$1/tools/build-site.sh" --out "$2" --require-signed 2>/dev/null && [ ! -e "$2" ]' _ "$W" "$T/s1"
    GNUPGHOME=$T/gh git -C "$W" -c user.name=t -c user.email=t@t -c gpg.program=gpg -c user.signingkey="$F" commit -q -S --allow-empty -m signed
    out=$(bash "$W/tools/build-site.sh" --out "$T/s2" --require-signed 2>&1)
    check "...one the pinned key signed is, and its pages say so${out:+: $(tail -1 <<<"$out")}" bash -c '
        grep -q "</code>, signed by the key on <a href=\"verify.html\">Verify</a>" "$1/index.html" && grep -q "</code>, signed by the key on <a href=\"../../verify.html\">" "$1/source/docs/bios.md.html"' _ "$T/s2"
fi

[ "$fails" -eq 0 ]
