# Archive tools (`extras/archive-tools.sh`)

## SYNOPSIS

```
debsway install archive-tools                     install them
debsway remove archive-tools                      remove them (bzip2 stays: it is part of Debian's standard system)
debsway manual archive-tools                      print the manual steps below

unzip -l file.zip              list what is inside first
unzip file.zip -d folder       unpack into "folder"
zip -r out.zip folder          pack a folder
7z x file.7z                   unpack (7z also reads zip, rar, iso...)
7z a out.7z folder             pack a folder
tar xf file.tar.gz             unpack tar archives (gz, xz, bz2, zst)
tar czf out.tar.gz folder      pack one
```

Debian already has tar, gzip and xz. This adds the command-line programs for
the other common archive types, all from Debian: `unzip` and `zip`, `7zip`
(the `7z` command), `bzip2` and `zstd`.

## LIMITS

- An archive can write to any folder it names: look inside (`unzip -l`, `7z l`, `tar tf`) before unpacking one from someone you don't know.
- Unpacking doesn't make what is inside safe to open or run.

## MANUAL INSTALL

```
# The archive programs, from Debian
sudo apt install --no-install-recommends unzip zip 7zip bzip2 zstd
```

To undo:

```
# Remove them (not bzip2, which Debian's standard system has)
sudo apt purge unzip zip 7zip zstd
```
