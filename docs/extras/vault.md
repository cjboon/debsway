# An encrypted vault that locks itself (`extras/vault.sh`)

## SYNOPSIS

```
wrenctl install vault                     install it and make the vault (asks for its password)
wrenctl remove vault                      remove the command (the encrypted files stay)
wrenctl manual vault                      print the manual steps below

vault open                 open ~/Vault for an hour (asks for its password)
vault open --for 2h        ...for two hours (30m, 90 for minutes)
vault open --no-timeout    ...until the screen locks or you close it
vault close                close it now
vault status               open or closed, and for how long
```

An encrypted folder in your home. Its files are kept encrypted by gocryptfs
(from Debian; independently audited) in `~/.local/share/wren-vault`, and
appear in `~/Vault` only while it is open, with a password of its own, not
your login's. The disk's encryption protects a laptop that is switched off;
once it is on, everything on it is readable to whoever gets past the screen
lock or into its memory. The vault narrows that: closed, its key isn't in
memory, so a laptop taken while it is on and locked doesn't give its files
away. It closes itself when its time is up (an hour, unless you say), and
whenever the screen locks: Wren Linux's idle lock and the lock before the laptop
sleeps run `~/.config/wren/on-lock.d/vault` first, and its timer notices
Super+Escape, the lid or the power menu locking within seconds. A program with
a file open in it when it closes loses that file (it closes anyway): save
first. It needs fuse3, whose `fusermount3` is setuid root: one small, widely
used program from Debian, the price of a folder you open without sudo.

## LIMITS

- While it is open, it is as readable as any of your files: to anything running as you, and to someone at the unlocked laptop.
- After a lock by Super+Escape, the lid or the power menu, it can stay open for up to 5 seconds.
- What programs keep about its files outside it stays outside: thumbnails (`~/.cache/thumbnails`), recently used lists, editor backups, swap. Open its files with programs you trust with that.
- Losing both the password and the master key loses the files; keep the master key apart from the laptop.

## MANUAL INSTALL

```
# gocryptfs (it brings fuse3)
sudo apt install --no-install-recommends gocryptfs
# The vault command, and the hook Wren Linux's idle lock runs before locking
install -D -m 0755 @WREN_DIR@/bin/vault ~/.local/bin/vault
mkdir -p ~/.config/wren/on-lock.d
printf '#!/bin/sh\nexec "$HOME/.local/bin/vault" close quiet\n' >~/.config/wren/on-lock.d/vault
chmod 755 ~/.config/wren/on-lock.d/vault
# The encrypted folder: it asks for the vault's password, then shows the
# master key; write that down and keep it apart from the laptop
mkdir -p ~/.local/share/wren-vault ~/Vault
chmod 700 ~/.local/share/wren-vault ~/Vault
gocryptfs -init ~/.local/share/wren-vault
vault open
```

To undo (the encrypted files stay; `gocryptfs ~/.local/share/wren-vault ~/Vault` opens them):

```
# Close it, and take out the command and the hook
vault close
rm ~/.local/bin/vault ~/.config/wren/on-lock.d/vault
# gocryptfs; fuse3 is marked "automatic": autoremove takes it out only if nothing needs it
sudo apt purge gocryptfs
sudo apt-mark auto fuse3
sudo apt autoremove --purge
```
