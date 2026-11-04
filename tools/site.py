# tools/site.py: renders Wren Linux's website (tools/build-site.sh runs it).
# Usage: python3 -I tools/site.py PAGES SOURCE LOG OUT
#   PAGES   the site's pages: layout.html, style.css and pages/*.html, each
#           page its title on the first line and its body after it
#   SOURCE  the files of the commit, for the source browser
#   LOG     the commit log, one "HASH<tab>DATE<tab>SUBJECT" a line
#   OUT     the folder to write the site into (made, or emptied of nothing)
# The values come from the environment, checked here: SITE_FPR (40 hex),
# SITE_GIT_URL (https), SITE_COMMIT (40 hex), SITE_ONION (optional, a v3 .onion
# name), SITE_SIGNED (yes once build-site.sh checked the commit's signature). Everything taken from the repository is escaped: no file in it, nor
# its name, can become markup or script in the site.
import html
import os
import re
import shutil
import sys
import urllib.parse

pages_dir, source, log_file, out = sys.argv[1:5]


def fail(msg):
    sys.stderr.write("site.py: %s\n" % msg)
    sys.exit(1)


def value(name, pattern, optional=False):
    v = os.environ.get(name, "")
    if not v and optional:
        return ""
    if not re.fullmatch(pattern, v):
        fail("%s isn't what it should be: %r" % (name, v))
    return v


FPR = value("SITE_FPR", r"[0-9A-F]{40}")
GIT_URL = value("SITE_GIT_URL", r"https://[A-Za-z0-9.-]+(/[A-Za-z0-9._-]+)+")
COMMIT = value("SITE_COMMIT", r"[0-9a-f]{40}")
ONION = value("SITE_ONION", r"[a-z2-7]{56}\.onion", optional=True)
e = html.escape

m = re.fullmatch(r"https://github\.com/([A-Za-z0-9-]+)/([A-Za-z0-9._-]+?)(\.git)?", GIT_URL)
GITHUB_SECURITY = "https://github.com/%s/%s/blob/main/SECURITY.md" % (m.group(1), m.group(2)) if m else "source/SECURITY.md.html"
SUBS = {
    "@GIT_URL@": e(GIT_URL),
    "@FPR_SPACED@": " ".join(FPR[i:i + 4] for i in range(0, 40, 4)),
    "@GITHUB_SECURITY@": e(GITHUB_SECURITY),
    "@ONION_COMPARE@": (", and this site's onion address, <code>%s</code>, in Tor Browser" % e(ONION)) if ONION else "",
    "@ONION_LINE@": (" Also at <code>%s</code> in Tor Browser." % e(ONION)) if ONION else "",
    "@COMMIT@": COMMIT[:12],
    # (a link: its depth is filled in with @ROOT@ afterwards)
    "@SIGNED@": ', signed by the key on <a href="@ROOT@verify.html">Verify</a>' if os.environ.get("SITE_SIGNED") == "yes"
    else " (a preview: its signature wasn't checked)",
}

layout = open(os.path.join(pages_dir, "layout.html"), encoding="utf-8").read()


def fill(text):
    for k, v in SUBS.items():
        text = text.replace(k, v)
    return text


def page(rel, title, body):
    """Writes OUT/rel: body (markup made here or a page of the site) in the layout."""
    depth = rel.count("/")
    root = "../" * depth
    frame = fill(layout).replace("@TITLE@", e(title)).replace("@ROOT@", root)
    left = re.findall(r"@[A-Z_]+@", frame.replace("@BODY@", ""))
    if left:
        fail("layout.html: nothing fills %s" % ", ".join(sorted(set(left))))
    text = frame.replace("@BODY@", body)
    path = os.path.join(out, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


os.makedirs(out, exist_ok=True)
shutil.copyfile(os.path.join(pages_dir, "style.css"), os.path.join(out, "style.css"))

# The site's own pages
for name in sorted(os.listdir(os.path.join(pages_dir, "pages"))):
    if not re.fullmatch(r"[a-z0-9-]+\.html", name):
        continue
    title, _, body = open(os.path.join(pages_dir, "pages", name), encoding="utf-8").read().partition("\n")
    body = fill(body)
    left = re.findall(r"@[A-Z_]+@", body)
    if left:
        fail("pages/%s: nothing fills %s" % (name, ", ".join(sorted(set(left)))))
    page(name, title.strip(), body)

# The source browser: one page a folder, one a file, every name and line escaped
SAFE = re.compile(r"[A-Za-z0-9._+-]+")
skipped = []


def href(*parts):
    return "/".join(urllib.parse.quote(p) for p in parts)


def breadcrumb(parts, depth):
    up = "../" * depth
    crumbs = ['<a href="%sindex.html">wren-linux</a>' % up]
    for i, p in enumerate(parts):
        crumbs.append('<a href="%s%sindex.html">%s</a>' % (up, href(*parts[: i + 1]) + "/", e(p)))
    return " / ".join(crumbs)


def text_of(path):
    if os.path.getsize(path) > 512 * 1024:
        return None
    data = open(path, "rb").read()
    if b"\0" in data:
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


for top, dirs, files in os.walk(source):
    rel_dir = os.path.relpath(top, source)
    parts = [] if rel_dir == "." else rel_dir.split(os.sep)
    dirs[:] = sorted(d for d in dirs if d != ".git" and SAFE.fullmatch(d))
    depth = len(parts) + 1  # pages under OUT/source/
    items = []
    for d in dirs:
        items.append('<li class="dir"><a href="%s/index.html">%s/</a></li>' % (href(d), e(d)))
    for name in sorted(files):
        full = os.path.join(top, name)
        if not SAFE.fullmatch(name):
            skipped.append(os.path.join(rel_dir, name))
            continue
        items.append('<li><a href="%s.html">%s</a></li>' % (href(name), e(name)))
        if os.path.islink(full):
            body = "<p>A link to <code>%s</code>.</p>" % e(os.readlink(full))
        else:
            text = text_of(full)
            if text is None:
                body = '<p>Not shown here (not text, or too long): it is in the <a href="%swren-linux.tar.gz">download</a>.</p>' % ("../" * depth)
            else:
                body = '<div class="file"><pre><code>%s</code></pre></div>' % e(text)
        file_parts = parts + [name]
        page(
            "source/" + "/".join(file_parts) + ".html",
            "/".join(file_parts) + " - Wren Linux",
            '<p class="path">%s / %s</p>\n%s' % (breadcrumb(parts, len(parts)), e(name), body),
        )
    head = ""
    if not parts:
        head = (
            "<h1>Source</h1>\n<p>Every file of Wren Linux at commit <code>%s</code>, the one the key on "
            '<a href="../verify.html">Verify</a> signed. Download it all: <a href="../wren-linux.tar.gz">wren-linux.tar.gz</a> '
            '(<a href="../wren-linux.tar.gz.sha256">SHA-256</a>), or <code>git clone %s</code>. '
            'The latest changes: <a href="log.html">the log</a>.</p>\n' % (COMMIT[:12], e(GIT_URL))
        )
    else:
        head = '<p class="path">%s</p>\n' % breadcrumb(parts[:-1], len(parts)) + "<h1>%s/</h1>\n" % e(parts[-1])
    page(
        "source/" + "/".join(parts + ["index.html"]),
        ("/".join(parts) + "/ - " if parts else "Source - ") + "Wren Linux",
        head + '<ul class="files">\n%s\n</ul>' % "\n".join(items),
    )

# The log
rows = []
for line in open(log_file, encoding="utf-8", errors="replace"):
    h, _, rest = line.rstrip("\n").partition("\t")
    date, _, subject = rest.partition("\t")
    if re.fullmatch(r"[0-9a-f]{40}", h):
        rows.append("<tr><td>%s</td><td>%s</td><td>%s</td></tr>" % (h[:12], e(date), e(subject)))
page(
    "source/log.html",
    "Log - Wren Linux",
    "<h1>Log</h1>\n<p>The latest commits, newest first.</p>\n<table class=\"log\">\n%s\n</table>" % "\n".join(rows),
)
if skipped:
    sys.stderr.write("site.py: not shown (names with unusual characters): %s\n" % ", ".join(skipped))
