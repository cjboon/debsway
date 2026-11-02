# w3m (`extras/w3m.sh`)

## SYNOPSIS

```
bash ~/debsway/extras/w3m.sh            install it
bash ~/debsway/extras/w3m.sh --remove   remove it (~/.w3m stays)
bash ~/debsway/extras/w3m.sh --manual   print the manual steps below

w3m https://example.org                 open a page (w3m duckduckgo.com works too)
  arrows or j/k scroll   Space/b page down/up   Tab next link   Enter follow it
  B back   U type an address   / search   T new tab   q quit
```

w3m is a web browser that runs inside the terminal and shows pages as plain
text with their links: good for articles, documentation and search results,
and for getting a page when no other browser is installed. It runs no
JavaScript and shows no images in foot, so most of what makes pages
tracking-heavy or dangerous isn't there, and sites that need JavaScript don't
work. It comes from Debian's own archive and is updated with the rest of the
system.

## LIMITS

- The sites you visit and your network see your address and what you visit.
- It isn't sandboxed: it runs as you, and a bug in it could reach your files.
- Firefox's HTTPS-Only Mode doesn't apply; type `https://` yourself.

## MANUAL INSTALL

```
# Install w3m from Debian, without the extras it only recommends
sudo apt install --no-install-recommends w3m
# Try it
w3m https://www.debian.org
```

To undo (your settings and cookies stay in `~/.w3m`):

```
# Remove w3m and what only it needed
sudo apt purge w3m
sudo apt autoremove --purge
```
