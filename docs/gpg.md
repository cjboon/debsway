# GPG, in plain words

GPG does two jobs: it **signs** things, so you can check who made them, and it **encrypts** things, so
only the right person can read them. Wren Linux uses the first constantly. Everything it downloads from
outside Debian is checked against a signing key pinned in [`pins.sh`](../pins.sh).

## The one idea

Each person has two matching keys:

- **A public key.** Give it to anyone. It checks your signatures, and lets people encrypt to you.
- **A private key.** Never give it to anyone. It makes your signatures, and decrypts what's sent to you.

Keys have a long **fingerprint**, which identifies them. Names on a key prove nothing, because anyone can
make a key with anyone's name. **The fingerprint is what you check.**

## The most useful thing: check a download

Say you've downloaded a file and its signature, `file.iso` and `file.iso.asc`, and the maker's public key,
`maker.asc`. Using a keyring just for this keeps your own tidy:

```bash
mkdir -m 700 check
gpg --homedir check --import maker.asc
gpg --homedir check --fingerprint
gpg --homedir check --verify file.iso.asc file.iso
```

Now look at two things:

1. **The fingerprint matches one you got somewhere else,** from a place an attacker wouldn't also control:
   the maker's site over https, a printed copy, or a friend. If the key and its fingerprint came from
   the same place as the download, whoever changed the file could have changed those too.
2. **It says `Good signature`,** with that fingerprint. Then delete the folder with `rm -rf check`.

You'll also see this:

```
WARNING: This key is not certified with a trusted signature!
```

It's normal. It means *you* haven't told GPG you trust this key. The check you just did by hand is what
matters. What isn't normal is `BAD signature`: don't use that file.

**Checking Wren Linux itself:** [SECURITY.md](../SECURITY.md) shows the fingerprint, and you can compare
it with what's in your copy:

```bash
gpg --show-keys --fingerprint data/wren-signing-key.asc
```

## Make your own key

```bash
gpg --full-generate-key
```

Press Enter for the default kind of key, and choose an expiry, such as `2y`. You can extend it later, and if
you ever lose the key, it stops being trusted by itself. The name and email go into the public key for
anyone to see, so use only what you want linked to it. Use a long passphrase: it protects the key if
someone copies your files.

Then find your fingerprint, and make a public copy to share:

```bash
gpg --fingerprint you@example.org
gpg --armor --export you@example.org > my-key.asc
```

## Sign and encrypt

Sign a file. This makes `notes.txt.asc`, which anyone with your public key can check:

```bash
gpg --armor --detach-sign notes.txt
gpg --verify notes.txt.asc notes.txt
```

Encrypt a file to someone. First import their key and check its fingerprint, as above:

```bash
gpg --import their-key.asc
gpg --armor --encrypt --recipient them@example.org notes.txt
```

That makes `notes.txt.asc`. Only they can read it, and that includes you, unless you also add
`--recipient you@example.org`. To read one sent to you:

```bash
gpg --output notes.txt --decrypt notes.txt.asc
```

## Keep your key safe

A **revocation certificate** is how you tell the world the key is no longer yours, if you lose it or it's
stolen. GPG makes one when it makes your key, in `~/.gnupg/openpgp-revocs.d/`. You can also make one yourself,
choosing a reason, which is easiest to do now, while you still have the key:

```bash
gpg --output revoke.asc --gen-revoke you@example.org
```

Then back up your private key to an [encrypted USB stick](../encrypt-usb.sh), along with that certificate:

```bash
gpg --armor --export-secret-keys you@example.org > private-key.asc
```

Anyone with `revoke.asc` can cancel your key, and anyone with `private-key.asc` can try your passphrase, so don't
leave either on an unencrypted disk. Delete the copies once they're on the stick.

## What GPG doesn't protect

- **It doesn't hide who's talking.** An encrypted email still shows who it's from, who it's to, its subject and when
  it was sent. It also can't protect old messages if your key is stolen later. For conversation, use something made
  for it, such as Signal or SimpleX (`wrenctl install signal`, `wrenctl install simplex-chat`).
- **A signature says who, not whether it's safe.** It proves the holder of a key signed this. It doesn't prove the
  file is harmless, or that the key wasn't stolen.
- **Malware running as you** can wait for you to type your passphrase. [The threat model](../THREAT-MODEL.md) says more.

## A simpler tool for files

To encrypt a file with a passphrase, or to someone's key, without any of this, Wren Linux includes `age`. It does one job:

```bash
age -p notes.txt > notes.txt.age
age -d notes.txt.age > notes.txt
```

## How Wren Linux uses this

- **`pins.sh`** holds the fingerprint of every key it trusts, with the date each was checked and where.
- **`lib/appimage.sh`** checks downloads in a throwaway keyring holding only the one pinned key, so a second key
  slipped into a file doesn't count. An expired or revoked key's signature fails.
- **`update.sh`** takes an update only if the newest commit is signed by Wren Linux's key.
- **[`extras/security-key.sh`](extras/security-key.md)** and **[`extras/signing-key.sh`](../extras/signing-key.sh)**
  are for keeping keys somewhere a program running as you can't simply read them.
