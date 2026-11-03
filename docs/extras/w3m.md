# w3m (`extras/w3m.sh`)

## SYNOPSIS

```
wrenctl install w3m                     install it
wrenctl remove w3m                      remove it (~/.w3m stays)
wrenctl manual w3m                      print the manual steps below

w3m https://example.org                 open a page (w3m duckduckgo.com works too)
w3m -no-cookie https://example.org      no cookies at all, for one run
  arrows or j/k scroll   Space/b page down/up   Tab next link   Enter follow it
  B back   U type an address   / search   T new tab   q quit
```

w3m is a web browser that runs inside the terminal and shows pages as plain
text with their links: good for articles, documentation and search results,
and for getting a page when no other browser is installed. It runs no
JavaScript and shows no images in foot, so most of what makes pages
tracking-heavy or dangerous isn't there, and sites that need JavaScript don't
work. Cookies last only while it is open: the `w3m` command Wren Linux puts in
`~/.local/bin` deletes the ones w3m keeps (`~/.w3m/cookie`) when it starts and
when it ends, also when its window is closed, so logins work while you browse
but no site recognises you the next time. It comes from Debian's own archive
and is updated with the rest of the system.

## LIMITS

- The sites you visit and your network see your address and what you visit.
- It isn't sandboxed: it runs as you, and a bug in it could reach your files.
- Firefox's HTTPS-Only Mode doesn't apply; type `https://` yourself.
- Cookies are cleared only by Wren Linux's `w3m` command: `/usr/bin/w3m` by its full path keeps them.

## MANUAL INSTALL

```
# Install w3m from Debian, without the extras it only recommends
sudo apt install --no-install-recommends w3m
# The w3m command that clears its cookies when it starts and ends
install -D -m 0755 @WREN_DIR@/bin/w3m ~/.local/bin/w3m
# Try it
w3m https://www.debian.org
```

To undo (your settings stay in `~/.w3m`):

```
rm ~/.local/bin/w3m
# Remove w3m and what only it needed
sudo apt purge w3m
sudo apt autoremove --purge
```
