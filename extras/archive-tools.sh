#!/bin/bash
# Programs for zip, 7z, bzip2 and zstd files (Debian's tar, gzip and xz are
# already there): unzip, zip, 7zip, bzip2 and zstd, all command-line.
# Usage: bash archive-tools.sh [--remove]
# summary: unzip, zip, 7z, bzip2 and zstd for archives
# status: apt:unzip apt:zip apt:7zip apt:bzip2 apt:zstd
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    apt_purge unzip zip 7zip zstd
    # bzip2 is part of Debian's standard system; it stays
    exit
fi

say "Installing archive tools"
apt_install unzip zip 7zip bzip2 zstd

cat <<'EOF2'

    How to use them:
      unzip file.zip                 unpack into the current folder
      unzip -l file.zip              list what is inside first
      unzip file.zip -d folder       unpack into "folder"
      zip -r out.zip folder          pack a folder
      7z x file.7z                   unpack (7z also reads zip, rar, iso...)
      7z a out.7z folder             pack a folder
      tar xf file.tar.gz             unpack tar archives (gz, xz, bz2, zst)
      tar czf out.tar.gz folder      pack one
    Look at what is inside (unzip -l, 7z l, tar tf) before unpacking one that
    came from someone you don't know: it can write to any folder it names.
EOF2
