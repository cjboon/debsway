#!/bin/bash
# mat2 removes hidden metadata (GPS position, camera model, author names,
# edit history) from photos, PDFs, office documents, audio and video,
# before you share them. From Debian.
# Usage: bash mat2.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    apt_purge mat2
    exit
fi

say "Installing mat2"
apt_install mat2

cat <<'EOF'

    How to use mat2:
      mat2 --show photo.jpg          list the metadata it finds (removes nothing)
      mat2 photo.jpg                 write photo.cleaned.jpg without metadata
      mat2 *.jpg report.pdf          clean several files at once
      mat2 --inplace photo.jpg       clean the file itself, no copy kept
      mat2 --lightweight report.pdf  gentler: a PDF keeps selectable text,
                                     but some metadata may stay
      mat2 --list                    the file types it handles

    A normal clean turns PDF pages into images, so the text can't be
    selected any more; that's how it makes sure nothing hides in them.
    "--show" finding nothing doesn't prove a file is clean: clean it anyway.
EOF
