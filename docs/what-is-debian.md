# What is Debian?

Debian is one of the oldest free operating systems still being made. It's the system underneath
Wren Linux: when you use Wren Linux, almost every program on your computer came from Debian.

The name means two things:

- **The operating system:** the Linux kernel, the GNU tools, and over 70,000 packages of software,
  ready to install.
- **The Debian Project:** the people who make it, almost a thousand active developers around the
  world. They're volunteers, and no company owns it.

"Free" here means freedom, not price: you may run the software, read its source code, change it and
share it.

## What holds it together

Debian's [Social Contract](https://www.debian.org/social_contract) is a public promise to its users:

1. **Debian will remain 100% free.** The system will never require a non-free part.
2. **It gives back** what it fixes to the people who wrote the software.
3. **It doesn't hide problems.** Its bug database is public.
4. **Its users and free software come first.**
5. **Works that aren't free** are kept apart, in separate areas that aren't part of Debian, though they
   can still be used.

Alongside it, the Debian Free Software Guidelines set out what counts as free.

One practical exception you may run into is **firmware**, the small programs some hardware needs, such
as many Wi-Fi cards. It often isn't free, so it lives in its own `non-free-firmware` area. Debian's
official install media may include it, so that hardware can work. Wren Linux's `wifi.sh` can install
it for your card.

## The three Debians

Debian comes in three branches, each named after a character or toy from *Toy Story*:

| Branch | Now (November 2026) | What it's for |
|---|---|---|
| **stable** | 13, *trixie* | The official release. Changes little, apart from fixes. **This is what Wren Linux uses.** |
| **testing** | 14, *forky* | Packages waiting to become the next stable release. |
| **unstable** | *sid*, always | Where development happens. For developers, and people who like to live on the edge. |

"Stable" doesn't mean old or fragile. It means the system doesn't change under you, which is what
you want from something you're relying on. The trade-off is that programs can be older than
their newest versions, with fixes added on top.

A release gets about three years of full support, then two years of Long Term Support. Debian 13 came out
on August 9, 2025, with full support planned until August 9, 2028, and Long Term Support until June 30, 2030.

## What is a package?

A package is a program with everything needed to install it, update it and remove it. You rarely have to
download a program from a website and hope for the best, because `apt` gets it from Debian:

```bash
sudo apt install w3m
sudo apt update && sudo apt upgrade
sudo apt purge w3m
```

Debian signs the list of its packages, and that list holds the hash of every package, so apt can tell if one
has been changed on the way to you. [lib/offline.sh](../lib/offline.sh) explains how that chain works, since
Wren Linux checks it by hand for packages carried on a USB stick.

## Why Wren Linux is based on Debian

"Based on Debian" means Wren Linux doesn't make its own operating system. It's a set of scripts you run on an
ordinary Debian 13, which set it up in a careful way. Some reasons that fits:

- **Trust stays where it can be checked.** Most of your software comes from Debian's signed archive. Wren Linux
  adds only scripts you can read, and a few signed programs from outside, each pinned in
  [`pins.sh`](../pins.sh).
- **Security fixes keep coming, without Wren Linux.** Debian's security team fixes the packages, and they install
  themselves every day (`parts/unattended-upgrades.sh`). This small project doesn't need to do that work.
- **It holds still.** Scripts that change system files need a system that doesn't change under them, so
  `stable` suits them.
- **Debian has AppArmor, Unbound, nftables, Tor and much more** already packaged and maintained.
- **Others can check it.** Debian's work on reproducible builds aims to let anyone confirm that a package comes
  from its source. Wren Linux's own package is built the same way.

Wren Linux isn't affiliated with or endorsed by Debian. A problem with Wren Linux should be reported
[to Wren Linux](../SECURITY.md), not to Debian.

## What Debian doesn't do for you

- **Debian doesn't choose what you install.** A package from outside its archive doesn't have its checks.
- **It doesn't harden everything by default.** It's made for many kinds of computers, which is part of why Wren Linux
  exists: [its threat model](../THREAT-MODEL.md) says what it adds and what it doesn't.
- **Updates need to reach you.** Those fixes protect you only once they're installed, and restarted programs use them.

Next: [a short history of Debian](history-of-debian.md).

## Sources

- Debian: [About Debian](https://www.debian.org/intro/about), the
  [Social Contract](https://www.debian.org/social_contract), and [releases](https://www.debian.org/releases/).
- Reproducible Builds: [participating projects](https://reproducible-builds.org/who/projects/).
- The reasons Wren Linux is based on Debian are this page's own reading of how its scripts work.
