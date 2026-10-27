#!/bin/bash
# Copies debsway onto a USB stick (or any folder): the committed files, plus
# the saved downloads in offline/. Nothing from ignore/ (personal files) or
# untracked files goes along, and a stick that already has a debsway folder
# gets only the downloads that changed.
#
#   bash tools/pack-usb.sh /media/you/STICK
#
# It copies the last commit, so commit what you want on the stick first.
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
not_root

dest=${1:-}
[ -n "$dest" ] && [ -d "$dest" ] || die "Usage: bash tools/pack-usb.sh /path/to/the/stick"
command -v git >/dev/null || die "git is missing."
git -C "$DEBSWAY_DIR" rev-parse --git-dir >/dev/null 2>&1 || die "$DEBSWAY_DIR isn't a git checkout."
if [ -n "$(git -C "$DEBSWAY_DIR" status --porcelain --untracked-files=no)" ]; then
    warn "You have changes that aren't committed; the stick gets the last commit without them."
fi

target="$dest/debsway"

say "Copying the committed files to $target"
mkdir -p "$target"
# The old copy goes, except the big downloads
find "$target" -mindepth 1 -maxdepth 1 ! -name offline -exec rm -rf {} +
git -C "$DEBSWAY_DIR" archive --format=tar HEAD | tar -x --no-same-permissions -C "$target"
# A stick's filesystem may not keep permissions, which is why the README
# says to run scripts with bash.

if [ -d "$DEBSWAY_DIR/offline" ]; then
    say "Copying the saved downloads (offline/)"
    mkdir -p "$target/offline"
    cp -ru --no-preserve=mode,ownership "$DEBSWAY_DIR/offline"/. "$target/offline"/
    # Downloads that were replaced or deleted here
    (cd "$target/offline" && find . -type f | while read -r f; do
        [ -e "$DEBSWAY_DIR/offline/$f" ] || rm -f "$f"
    done)
fi
sync
note "Done: $target"
note "On the new system: copy it to your home folder, then bash wifi.sh and bash install-base.sh"
