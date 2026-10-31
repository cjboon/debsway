# Archive tools (`extras/archive-tools.sh`)

You get `unzip`, `zip`, `7z`, `bzip2` and `zstd`, to open and make zip, 7z, bzip2 and zstd files. Debian already has `tar`, `gzip` and `xz`.

## The problem it solves

Zip files arrive often, and a minimal system cannot open them.

## The ideas behind it

**An archive** is many files packed into one, usually compressed. **Compression** is the shrinking; each format (zip, 7z, tar.gz, tar.zst) has its own tool. Unpacking writes files to disk using the paths stored in the archive, so an archive from a stranger is untrusted data: look inside first (`unzip -l`, `7z l`, `tar tf`).

## How it works, step by step

`apt_install unzip zip 7zip bzip2 zstd`, then prints example commands. Nothing else changes.

## What it changes on your computer

- Packages: `unzip`, `zip`, `7zip`, `bzip2`, `zstd`. Removing the extra leaves `bzip2`, which is part of Debian's standard system.

## Using it

`unzip file.zip -d folder`, `zip -r out.zip folder`, `7z x file.7z`, `7z a out.7z folder`, `tar xf file.tar.zst`.
