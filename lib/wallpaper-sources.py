#!/usr/bin/python3
"""Wallpapers from free sources, for extras/wallpapers.sh.

Saves pictures that make good wallpapers into DEST, named SOURCE_ID.jpg (or
.png), with a line each in DEST/CREDITS.txt. Sources:
  nasa    NASA's image library (images.nasa.gov); NASA's own are public domain
  hubble  ESA/Hubble's pictures of the week, in ESA's wallpaper size (CC BY 4.0)
  webb    ESA/Webb's pictures of the month, the same way (CC BY 4.0)
  earth   NASA Earth Observatory's images of the day (public domain)
  wild    Wikimedia Commons' featured pictures of wild animals, chosen by its
          community: only free licences (CC0, public domain, CC BY, CC BY-SA),
          each photographer credited; farm animals, pets and artworks skipped
Every picture is at least 1920x1080 and landscape, read from the file itself,
a real JPEG or PNG of at most 40 MB; NASA's also need a credit that names no
other copyright holder. Only https, and only these sources' own hosts, also
after a redirect.

Prints each file it saved, one a line (the script lists them for --remove).
Pictures already there count: a second run tops each source up to COUNT.
Usage: python3 -I wallpaper-sources.py DEST SOURCE [COUNT]
"""
import json
import os
import re
import struct
import sys
import urllib.error
import urllib.parse
import urllib.request

HOSTS = {
    "images-api.nasa.gov", "images-assets.nasa.gov",
    "esahubble.org", "cdn.esahubble.org",
    "esawebb.org", "cdn.esawebb.org",
    "earthobservatory.nasa.gov", "science.nasa.gov", "assets.science.nasa.gov",
    "commons.wikimedia.org", "upload.wikimedia.org", "thumb.wikimedia.org",
}
MIN_W, MIN_H = 1920, 1080
MIN_RATIO, MAX_RATIO = 1.3, 2.4
MAX_BYTES = 40 * 1024 * 1024
FEED_BYTES = 8 * 1024 * 1024
ID_RE = re.compile(r"^[A-Za-z0-9_.-]{1,100}$")
NOT_FREE = re.compile(r"©|\(c\)|copyright|getty|reuters|associated press|"
                      r"ap photo|afp|all rights reserved", re.I)
RIGHTS_KEYS = ("Copyright", "Rights", "Credit", "Artist", "Creator", "Source")
NASA_QUERIES = ["nebula", "galaxy", "earth from space", "aurora", "milky way",
                "jupiter", "saturn", "star cluster"]
NASA_PER_QUERY = 4      # at most this many from one search, for variety
NASA_LOOK_AT = 25       # candidates looked at per search
ESA = {
    "hubble": ("https://esahubble.org/images/potw/feed/", "cdn.esahubble.org", "ESA/Hubble"),
    "webb": ("https://esawebb.org/images/potm/feed/", "cdn.esawebb.org", "ESA/Webb"),
}
EARTH_FEED = "https://earthobservatory.nasa.gov/feeds/image-of-the-day.rss"
COMMONS_API = "https://commons.wikimedia.org/w/api.php"
# Commons' featured pictures of wild animals, by group (insects and spiders
# left out: not everyone wants one on their screen)
WILD_GROUPS = ["Carnivora", "Primates", "Cetacea", "Elephantidae", "Perissodactyla",
               "Artiodactyla", "Marsupialia", "Rodentia", "birds", "reptiles",
               "amphibians", "fish"]
WILD_PER_GROUP = 4      # at most this many from one group, for variety
# titles of farm animals, pets, artworks and remains: not animals in nature
NOT_WILD = re.compile(r"\b(cows?|cattle|calf|calves|ox|oxen|donkeys?|horses?|mules?|ponies|pony|"
                      r"sheep|goats?|pigs?|piglets?|dogs?|puppy|puppies|cats?|kittens?|chickens?|hens?|"
                      r"rooster|domestic|farm|livestock|zoo|museum|mosaic|painting|sculpture|statue|"
                      r"fountain|drawing|illustration|engraving|plate|stamp|skeleton|skull|bones?|"
                      r"fossils?|taxiderm\w*|dead|carcass|market|google art project)\b", re.I)
FREE_LICENCE = re.compile(r"^(cc0|pd|pd-.*|cc-by-[0-9.]+|cc-by-sa-[0-9.]+)$")
# Wikimedia asks programs to say who they are, with a way to reach the maker
WIKIMEDIA_AGENT = "debsway-wallpapers/1.0 (https://github.com/cjboon/debsway)"


class HttpsOnly(urllib.request.HTTPRedirectHandler):
    """Follows a redirect only to https on the sources' hosts."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        if not allowed(newurl):
            raise urllib.error.HTTPError(newurl, code, "redirect refused: " + newurl, headers, fp)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


OPENER = urllib.request.build_opener(HttpsOnly)


def allowed(url):
    u = urllib.parse.urlsplit(url)
    return u.scheme == "https" and u.hostname in HOSTS


def fetch(url, limit):
    """The body of URL, at most LIMIT bytes; refuses anything but https to the sources."""
    if not allowed(url):
        raise ValueError("not https on the sources' hosts: " + url)
    # (a path with letters like ’ in it, as Earth Observatory's have)
    u = urllib.parse.urlsplit(url)
    url = urllib.parse.urlunsplit(u._replace(path=urllib.parse.quote(u.path, safe="/%:@")))
    agent = WIKIMEDIA_AGENT if u.hostname.endswith(".wikimedia.org") else "debsway-wallpapers"
    req = urllib.request.Request(url, headers={"User-Agent": agent})
    with OPENER.open(req, timeout=60) as r:
        data = r.read(limit + 1)
    if len(data) > limit:
        raise ValueError("bigger than %d bytes: %s" % (limit, url))
    return data


def picture_kind(data):
    """'jpg' or 'png' by the file's first bytes, else None."""
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png"
    if data.startswith(b"\xff\xd8\xff"):
        return "jpg"
    return None


def picture_size(data):
    """(width, height) read from a PNG's or JPEG's header, else None."""
    if data.startswith(b"\x89PNG\r\n\x1a\n") and data[12:16] == b"IHDR":
        return struct.unpack(">II", data[16:24])
    if not data.startswith(b"\xff\xd8"):
        return None
    i = 2
    while i + 9 < len(data):
        if data[i] != 0xFF:
            return None
        m = data[i + 1]
        if m in (0xD8, 0x01) or 0xD0 <= m <= 0xD7:
            i += 2
            continue
        seg = struct.unpack(">H", data[i + 2:i + 4])[0]
        # the frame header (any SOFn but DHT, JPG, DAC) holds the size
        if 0xC0 <= m <= 0xCF and m not in (0xC4, 0xC8, 0xCC):
            h, w = struct.unpack(">HH", data[i + 5:i + 9])
            return (w, h)
        i += 2 + seg
    return None


def size_ok(w, h):
    """None if W x H suits a screen, else why not."""
    if w < MIN_W or h < MIN_H:
        return "smaller than %dx%d" % (MIN_W, MIN_H)
    if not MIN_RATIO <= w / h <= MAX_RATIO:
        return "not landscape"
    return None


def clean(text):
    """One line of plain text: no control characters (they could be escape codes)."""
    return re.sub(r"[\x00-\x1f\x7f]+", " ", str(text)).strip()


def nasa_why_not(item, meta):
    """None if a NASA library picture suits, else why not. ITEM is the
    search's data, META the picture's metadata.json."""
    try:
        w, h = int(meta.get("File:ImageWidth", 0)), int(meta.get("File:ImageHeight", 0))
    except (TypeError, ValueError):
        return "no size"
    why = size_ok(w, h)
    if why:
        return why
    if meta.get("File:MIMEType") not in ("image/jpeg", "image/png"):
        return "not a JPEG or PNG"
    rights = [str(v) for k, v in meta.items() if any(s in k for s in RIGHTS_KEYS)]
    rights += [str(item.get(k, "")) for k in ("secondary_creator", "photographer", "description")]
    if NOT_FREE.search(" ".join(rights)):
        return "another copyright holder"
    return None


def nasa_original(nasa_id):
    """The ~orig JPEG or PNG in a NASA picture's file list, over https."""
    files = json.loads(fetch("https://images-assets.nasa.gov/image/%s/collection.json" % nasa_id, 1 << 20))
    for f in files:
        f = str(f).replace("http://images-assets.nasa.gov/", "https://images-assets.nasa.gov/", 1)
        if re.search(r"~orig\.(jpe?g|png)$", f, re.I) and allowed(f):
            return f
    return None


def nasa():
    """(id, url, title, credit) of NASA library pictures that suit."""
    for q in NASA_QUERIES:
        try:
            url = "https://images-api.nasa.gov/search?" + urllib.parse.urlencode(
                {"q": q, "media_type": "image", "page_size": 100})
            items = json.loads(fetch(url, FEED_BYTES))["collection"]["items"]
        except (OSError, ValueError, KeyError) as e:
            print("NASA search for %r failed: %s" % (q, e), file=sys.stderr)
            continue
        given = 0
        for it in items[:NASA_LOOK_AT]:
            if given >= NASA_PER_QUERY:
                break
            try:
                item = it["data"][0]
                nasa_id = str(item["nasa_id"])
                if not ID_RE.match(nasa_id):
                    continue
                meta = json.loads(fetch("https://images-assets.nasa.gov/image/%s/metadata.json" % nasa_id, 1 << 20))
                if nasa_why_not(item, meta):
                    continue
                url = nasa_original(nasa_id)
            except (OSError, ValueError, KeyError, IndexError, TypeError) as e:
                print("Skipped a NASA picture: %s" % e, file=sys.stderr)
                continue
            if not url:
                continue
            credit = meta.get("XMP:Credit") or item.get("secondary_creator") or "NASA"
            given += 1
            yield (nasa_id, url, item.get("title", ""), "%s. https://images.nasa.gov/details/%s" % (clean(credit), nasa_id))


def feed_items(url):
    """The <item> blocks of a feed, as text (Earth Observatory's feed isn't
    well-formed XML, so it is read with patterns, not a parser)."""
    text = fetch(url, FEED_BYTES).decode("utf-8", "replace")
    return re.findall(r"<item>(.*?)</item>", text, re.S)


def tag(item, name):
    m = re.search(r"<%s>(?:<!\[CDATA\[)?(.*?)(?:\]\]>)?</%s>" % (name, name), item, re.S)
    return clean(m.group(1)) if m else ""


def esa(source):
    """ESA/Hubble's or ESA/Webb's pictures, in ESA's 1920x1200 wallpaper cut."""
    feed, cdn, who = ESA[source]
    for item in feed_items(feed):
        m = re.search(r'url="https://%s/archives/images/[a-z0-9]+/([a-z0-9]{1,40})\.jpg"' % re.escape(cdn), item)
        if not m:
            continue
        pid = m.group(1)
        yield (pid, "https://%s/archives/images/wallpaper4/%s.jpg" % (cdn, pid), tag(item, "title"),
               "%s (CC BY 4.0). %s" % (who, tag(item, "link")))


def earth():
    """NASA Earth Observatory's images of the day: their large (_lrg) files."""
    for item in feed_items(EARTH_FEED):
        m = re.search(r'credits">([^<]{1,200})<', item)
        credit = clean(m.group(1)) if m else "NASA Earth Observatory"
        if NOT_FREE.search(credit):
            continue
        seen = set()
        for url in re.findall(r'https://assets\.science\.nasa\.gov/content/dam/[^"\s<>]+?_lrg\.(?:jpe?g|png)(?=["\s<])', item):
            if url in seen:
                continue
            seen.add(url)
            pid = re.sub(r"[^A-Za-z0-9_.-]", "_", url.rsplit("/", 1)[-1].rsplit(".", 1)[0])[:100]
            yield (pid, url, tag(item, "title"), "%s. %s" % (credit, tag(item, "link")))


def wild_why_not(title, info):
    """None if a Commons picture suits, else why not. INFO is its imageinfo."""
    meta = info.get("extmetadata", {})
    if not FREE_LICENCE.match(str(meta.get("License", {}).get("value", ""))):
        return "not a free licence"
    if NOT_WILD.search(title):
        return "not a wild animal in nature"
    if info.get("mime") not in ("image/jpeg", "image/png"):
        return "not a JPEG or PNG"
    try:
        return size_ok(int(info.get("thumbwidth") or info["width"]), int(info.get("thumbheight") or info["height"]))
    except (KeyError, TypeError, ValueError):
        return "no size"


def wild():
    """Commons' featured pictures of wild animals, at 2560 wide (Wikimedia
    makes that copy; the originals can be 13,000 wide)."""
    for group in WILD_GROUPS:
        try:
            url = COMMONS_API + "?" + urllib.parse.urlencode({
                "action": "query", "format": "json", "generator": "search",
                "gsrsearch": 'deepcat:"Featured pictures of %s" filetype:bitmap' % group,
                "gsrnamespace": 6, "gsrlimit": 30, "gsrsort": "random",
                "prop": "imageinfo", "iiprop": "url|size|mime|extmetadata",
                "iiextmetadatafilter": "License|LicenseShortName|Artist", "iiurlwidth": 2560})
            pages = json.loads(fetch(url, FEED_BYTES)).get("query", {}).get("pages", {})
        except (OSError, ValueError) as e:
            print("Commons search for %s failed: %s" % (group, e), file=sys.stderr)
            continue
        given = 0
        for p in pages.values():
            if given >= WILD_PER_GROUP:
                break
            try:
                title = str(p["title"])
                info = p["imageinfo"][0]
            except (KeyError, IndexError, TypeError):
                continue
            if wild_why_not(title, info):
                continue
            url = info.get("thumburl") or info.get("url", "")
            if not allowed(url):
                continue
            name = title.split(":", 1)[-1].rsplit(".", 1)[0]
            meta = info.get("extmetadata", {})
            artist = clean(re.sub(r"<[^>]*>", "", str(meta.get("Artist", {}).get("value", "")))) or "unknown"
            licence = clean(meta.get("LicenseShortName", {}).get("value", ""))
            given += 1
            yield (re.sub(r"[^A-Za-z0-9_.-]", "_", name)[:80].strip("._") or "picture", url, name,
                   "%s (%s), Wikimedia Commons. https://commons.wikimedia.org/wiki/%s"
                   % (artist, licence, urllib.parse.quote(title.replace(" ", "_"))))


SOURCES = {"nasa": nasa, "hubble": lambda: esa("hubble"), "webb": lambda: esa("webb"),
           "earth": earth, "wild": wild}


def main():
    if len(sys.argv) not in (3, 4) or sys.argv[2] not in SOURCES:
        sys.exit("usage: wallpaper-sources.py DEST nasa|hubble|webb|earth|wild [COUNT]")
    dest, source = sys.argv[1], sys.argv[2]
    want = int(sys.argv[3]) if len(sys.argv) == 4 else 12
    os.makedirs(dest, exist_ok=True)
    mine = re.compile(r"^%s_.*\.(jpg|png)$" % source)
    have = len([f for f in os.listdir(dest) if mine.match(f)])
    credits = []
    try:
        for pid, url, title, credit in SOURCES[source]():
            if have >= want:
                break
            if not ID_RE.match(pid):
                continue
            if any(os.path.exists(os.path.join(dest, "%s_%s.%s" % (source, pid, e))) for e in ("jpg", "png")):
                continue
            try:
                data = fetch(url, MAX_BYTES)
            except (OSError, ValueError) as e:
                print("Skipped %s: %s" % (pid, e), file=sys.stderr)
                continue
            kind, size = picture_kind(data), picture_size(data)
            if not kind or not size or size_ok(*size):
                continue
            name = "%s_%s.%s" % (source, pid, kind)
            tmp = os.path.join(dest, "." + name + ".part")
            with open(tmp, "wb") as f:
                f.write(data)
            os.chmod(tmp, 0o644)
            os.replace(tmp, os.path.join(dest, name))
            credits.append("%s: %s. Credit: %s" % (name, clean(title), credit))
            print(name, flush=True)
            have += 1
            # on the screen as it goes: each picture takes a few lookups
            print("    %d/%d %s" % (have, want, clean(title)[:70]), file=sys.stderr, flush=True)
    except (OSError, ValueError) as e:
        print("%s: %s" % (source, e), file=sys.stderr)
    if credits:
        with open(os.path.join(dest, "CREDITS.txt"), "a") as f:
            f.write("\n".join(credits) + "\n")
    print("    %s: %d pictures" % (source, have), file=sys.stderr)
    if have == 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
