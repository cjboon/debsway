# Security

Wren Linux is a small project with one maintainer. This page says how to report a
problem, how to check that what you have came from the project, and what the
project will and won't do. [THREAT-MODEL.md](THREAT-MODEL.md) says what Wren Linux
protects against and what it doesn't.

## Reporting a problem

Please write to **wrenlinux@tutamail.com**, and don't open a public issue for a hole
that could hurt people before it is fixed. Say:

- what goes wrong, and how to make it happen
- what someone could do with it
- which version you have (`wrenctl --version`), and whether you installed from a
  stick or by hand

Mail between Tuta addresses is end-to-end encrypted. From anywhere else it is
ordinary email, so leave the details out of your first message if they are
sensitive, and ask for a safer way to send them. The signing key below only signs;
it can't encrypt mail to the project.

You can expect an answer within a few days, and a fix in the next release. This is
one person's project, so a hard problem can take longer, and you will be told if it
does. You will be credited with the fix if you want that, and left out if you don't.

### What counts

Scripts, settings, sandboxes and firewall rules in this repository, and any place
where the documents claim protection the scripts don't give. A hole in a program
Wren Linux installs (Firefox, Tor, Debian's packages) belongs with that program's
makers, though tell us too if Wren Linux's settings make it worse.

Only the newest commit on `main`, on Debian 13, is supported.

## Checking what you have

Every published update is signed by Wren Linux's own key:

```
DE09 E9B9 E956 5B2B DA9D  5FF5 F0F1 9D6C EF46 5DC5
```

As one word, as `pins.sh` has it: `DE09E9B9E9565B2BDA9D5FF5F0F19D6CEF465DC5`. Its
public part is `data/wren-signing-key.asc`.

- **Updates check this for you.** `update.sh` and `git-helper.sh` take only what this
  key signed, and the newest commit's signature vouches for the commits under it.
- **The first copy is the one to be careful with.** A check can only be as good as
  the copy doing the checking, and a copy someone changed could name a key of theirs.
  Compare the fingerprint in `pins.sh` with this page on GitHub, and with another
  place when there is one.
- **To look for yourself**, in a git copy:
  ```
  git log --show-signature -1
  gpg --show-keys --with-fingerprint data/wren-signing-key.asc
  ```

The part of the key that can make new signing keys is kept offline, on an encrypted
stick and nowhere else. It is never on a server.

## If the key is stolen or lost

The key will be revoked, and the project will say so here and in the git history.
A new key means a new fingerprint, which you should check as you did the first one.
A computer with the old pin stops taking updates rather than trusting something
unsigned: it is safe, but it needs you to step in.

## If someone demands a backdoor

The project will not sign an update that weakens Wren Linux on someone's orders.
If it could not refuse, it would stop publishing and say so, rather than publish one.
A demand to sign a backdoor is a demand to break this public promise.
