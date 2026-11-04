# The website on a VPS

Wren Linux's website, a mirror of its code, and an onion address for both,
on a rented server, set up by `tools/setup-vps.sh`. GitHub stays the main home;
the server is a mirror. Everything here runs as your user except where it says
the server.

## What you need

- **A VPS** with Debian 13, KVM-based, with a **web console** (your way in if
  SSH ever fails). One CPU and 1 GB of RAM are plenty. For privacy, look at
  where the company is and what it hands over: Iceland, Switzerland and
  Sweden are often chosen; check the current terms yourself.
- **A domain** (optional at first): a registrar with WHOIS privacy and
  DNSSEC. Without one the site is still reachable at its onion address.
- **On your computer:** this git copy, with the signing key set up
  (`wren-key status`), and `ssh`.

## 1. Try it first, in a VM here

```bash
bash tools/try-vps.sh            # 5-15 minutes the first time: a Debian VM, then setup-vps.sh in it
bash tools/try-vps.sh --publish  # this copy's site on it
bash tools/try-vps.sh --status   # its onion addresses: open the site one in Tor Browser
bash tools/try-vps.sh --uninstall
```

The VM is reachable from this computer only. The sandboxed Firefox can't
open `127.0.0.1` (its firewall keeps it off this computer's own services):
use Tor Browser at the test site's onion address, or `curl`.

## 2. Your keys

```bash
bash tools/vps-client.sh ssh-key   # ~/.ssh/wren-vps, with a passphrase; prints its public line
bash tools/vps-client.sh keygen    # the onion client key; prints its public half
```

Back up `~/.ssh/wren-vps` and `~/.config/wren/vps/wren-vps.key` with your
other keys (KeePassXC can hold the files). The public halves aren't secret.

## 3. Set up the server

Most providers let you log in as root with a key or a password the first
time. Copy the script there and run it:

```bash
scp tools/setup-vps.sh root@SERVER:
ssh -t root@SERVER bash setup-vps.sh
```

(`-t` gives it a terminal to ask on.)

It asks what it needs, each question explaining its choice: your user's name,
your SSH public key (from step 2), the domain, the email for certificate
notices, the onion site, onion SSH and your onion client key (from step 2).
It asks a password for your user (sudo, and the web console; SSH never takes
it). Keep it in your password manager.

To set it up without questions, or the same way on a second server, put the
answers in a file (the names are in the script's header) and run
`bash setup-vps.sh --config FILE --yes`.

**Then confirm, from a second terminal**, while the first stays open:

```bash
ssh -i ~/.ssh/wren-vps wren@SERVER
sudo wren-vps --confirm
```

Until you do, the new SSH and firewall settings undo themselves after ten
minutes, so a mistake can't lock you out. If the second login fails, wait:
the old settings come back.

## 4. The domain's DNS

At your registrar, for `example.org` (yours):

- **A** (and **AAAA** for IPv6): the server's address, for `example.org` and `www`.
- **CAA**: `0 issue "letsencrypt.org"`: no other company may issue a
  certificate for your domain.
- **DNSSEC**: on, so nobody on the way can fake these answers.

Caddy fetches the HTTPS certificate by itself once the A record points at the
server. If you set the domain later, add it with `VPS_DOMAIN=example.org` in
`/etc/wren-vps.conf`, and run `sudo wren-vps` again.

## 5. SSH through the onion, then close port 22

The script printed the SSH onion address. On your computer:

```bash
bash tools/vps-client.sh tor-auth ONION.onion      # prints a few sudo commands: run them
bash tools/vps-client.sh ssh-config wren ONION.onion   # add what it prints to ~/.ssh/config
ssh wren-vps                                       # through Tor
```

Once that login works, from it:

```bash
sudo wren-vps --ssh-onion-only
```

Port 22 then closes to the whole internet: nobody can find SSH, scan it or
guess at it, and the server's logs no longer see your home address. Confirm
from another onion login (`ssh wren-vps`, `sudo wren-vps --confirm`). If Tor
is ever down, the provider's web console still lets you in;
`sudo wren-vps --ssh-public` opens port 22 again.

## 6. Publish

```bash
mkdir -p ~/.config/wren/vps
printf 'VPS_HOST=wren-vps\nVPS_SITE_ONION=%s\n' SITE-ONION.onion >~/.config/wren/vps/site.conf
bash tools/git-push.sh       # pushes to GitHub, signing the newest commit
bash tools/publish-site.sh   # the same commit to the server: the site, and the mirror at /git/
```

`publish-site.sh` builds the site only from a commit your key signed, so the
site shows exactly what the key vouched for, and its pages say so.

## What it sets up, and why

| What | Why |
|---|---|
| Your own user; SSH keys only, no root, no passwords | Nothing to guess: without your key file, SSH can't be got into. |
| nftables: only SSH (rate-limited) and the web in | Nothing else on the server can be reached, even by mistake. |
| Caddy, with HTTPS from Let's Encrypt, renewed by itself | Visitors get an encrypted, checked connection with no work from you. |
| Strict headers: no script, frame or outside resource | A page can't be turned into an attack, even if a file on it is changed. |
| No log of visitors | There is nothing to hand over about who read what. |
| Caddy locked down by systemd | A hole in the web server reaches little: it can read the site and nothing more. |
| The onion site, and `Onion-Location` | Tor Browser visitors stay inside Tor: nobody on the way sees what they read. |
| Onion SSH with a client key | Only your key can even find SSH, and port 22 can close for good. |
| Daily security updates, a nightly reboot when needed | Known holes close by themselves. |
| The never-locked-out switch | Every SSH or firewall change must prove itself from a new login. |

## What it doesn't protect

- **The provider can see everything.** It runs the machine: it can read the
  disk and the memory. Keep nothing on the server that the site doesn't
  need, and never the signing key.
- **The onion site hides the readers, not the server.** The same site is on
  the normal web at the server's address.
- **A first download is only as good as its check.** If the server were ever
  broken into, computers with Wren Linux's pin would still refuse anything
  the key didn't sign; but someone downloading for the first time must
  compare the fingerprint somewhere else too (the Verify page says so).
- **Traffic analysis.** The provider and the networks on the way still see
  that the server is visited, when, and how much.
