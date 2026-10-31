# w3m, a web browser for the terminal (`extras/w3m.sh`)

You get w3m, a web browser that runs inside the terminal and shows pages as plain text. It is good for reading articles, documentation and search results.

## The problem it solves

Sometimes you want to read a page without opening a full browser, or you have no other browser installed.

## The ideas behind it

**A text-mode browser** shows text and links, not pictures, layouts or scripts. **JavaScript** is the code web pages run in your browser, and w3m runs none. Most of what makes pages tracking-heavy or dangerous lives in JavaScript, so w3m avoids it, but sites that need it will not work.

## How it works, step by step

1. `apt_install w3m`, under the marker package `debsway-w3m`.
2. It prints a short list of keys.

## What it changes on your computer

- Package `w3m`.
- Later, w3m creates `~/.w3m` for its settings and cookies.
- No settings, key bindings or default applications.

## Using it

- `w3m https://example.org`: open a page. `w3m duckduckgo.com` works too.
- Arrows or j/k: scroll. Space and b: page down and up.
- Tab: next link. Enter: follow it. B: back.
- U: type an address. /: search. T: new tab. q: quit.

## What it protects against

Mostly a convenience. The real safety detail is that w3m runs no JavaScript, so most of what makes pages dangerous or tracking-heavy is not there.

## What it doesn't protect against

- **Being seen.** The sites you visit and your network still see your IP address and what you visit.
- **Anything running as you.** w3m is not sandboxed, and it can have bugs like any program reading data from the web.
- **Sites that need JavaScript** simply will not work.
- **HTTPS-Only Mode.** That protection belongs to Firefox, not w3m.

## Removing it

`bash extras/w3m.sh --remove` removes the `w3m` package and what only it needed. Your w3m settings and cookies stay in `~/.w3m`.
