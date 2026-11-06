# What is an onion site?

An onion site is a website you can reach only through Tor, at an address ending in `.onion`.
Normally, when you visit a website, Tor hides where you are. An onion site hides where the
*site* is too.

## How it works

On the ordinary web, a site has an IP address, which says roughly where its server is and
who pays for it. An onion site doesn't use one. The whole connection stays inside Tor:

1. **The site picks a few Tor relays as introduction points** and keeps connections open to
   them, through other relays, so they don't learn where it is.
2. **It publishes a signed note saying which relays those are** (a *descriptor*), in a directory
   spread across the Tor network.
3. **Your Tor Browser fetches that note and checks the signature** against the address itself.
4. **Your browser picks another relay as a meeting place** (a *rendezvous point*), and sends a
   one-time secret, through an introduction point, to the site.
5. **The site connects to the meeting place**, shows the same secret, and the two are joined.

You and the site each build three hops, the last of yours being the meeting place, so the
connection runs over six relays. Neither side learns the other's IP address.

## The address is the key

A modern onion address is 56 letters and digits, then `.onion`. It looks like gibberish
because it's made from the site's public key. That gives it a property normal web addresses
don't have: **the address proves itself.** If you have the right address, Tor checks that
you've reached the holder of that key, with no certificate company or DNS provider to trust.

The catch is that you need the right address to begin with, and nobody can memorise one.
A fake that shares the first few characters is easy to make. So get an address from somewhere you
trust, and compare all of it. This is why Wren Linux's own site shows its address and
[signing key](../SECURITY.md) in more than one place.

## What it gives you

- **The site's location stays hidden.** IP addresses aren't part of how you reach it.
- **Encryption all the way** from your browser to the site, with no exit relay in the middle to
  see your traffic.
- **The address can't be redirected** by someone who controls DNS.
- **No open ports.** The site only makes outgoing connections, so it can run behind a home router,
  with nothing listening for the internet to attack directly.

## What it doesn't give you

- **It doesn't make the site trustworthy.** "Onion" says nothing about who runs a site. A scam on
  an onion address is still a scam.
- **It doesn't protect you from what you tell it.** Log in with your name, and the site knows your
  name.
- **It can't fix the site's own software.** A bug in the site's code can give away what the server
  knows, including where it is, unless that server can't find out.
- **Timing can give a site away.** A site only up while your computer is on shows when your computer
  is on, and that can link the two. So can your writing style, and metadata in the files you post.
- **It can be slower.** There are more relays in the way.

## In Wren Linux

- **To visit one:** use Tor Browser (`wrenctl install tor-browser`).
- **To run one:** `wrenctl install onion-site` runs your site in a VM with no network at all, so
  whatever the site does, it can't learn this computer's address. It can also be private, so that
  only visitors you give a client key can even find it. [Its page](extras/onion-site.md) has
  the details and limits.
- **To send a file, once:** OnionShare (`wrenctl install onionshare`) makes a temporary onion site
  on your own computer, so the file doesn't pass through anyone's server.

Also see [the history of Tor](history-of-tor.md), and
[what Wren Linux does and doesn't protect against](../THREAT-MODEL.md).

## Sources

- The Tor Project, [How do Onion Services work?](https://community.torproject.org/onion-services/overview/)
  The steps and benefits above come from this page. It doesn't discuss limits: those are this
  page's own reasoning, from Wren Linux's threat model.
