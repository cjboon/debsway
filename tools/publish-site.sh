#!/bin/bash
# publish-site.sh: puts Wren Linux's website on the server tools/setup-vps.sh
# set up, and its git mirror, from this copy's newest commit, and only if
# Wren Linux's key signed it (tools/git-push.sh signs it as you push): the
# site then shows exactly what that key vouched for.
#  - It builds the site (tools/build-site.sh --require-signed), copies it to
#    /srv/wren-site on the server with rsync over SSH, files the server has
#    that the site no longer has deleted, and pushes the commit to the mirror
#    (/srv/wren-git/wren-linux.git, at https://DOMAIN/git/wren-linux.git).
#  - The server is an ssh name: the entry tools/vps-client.sh ssh-config
#    prints (through Tor), or user@address.
#  - Your settings, if you like, in ~/.config/wren/vps/site.conf:
#      VPS_HOST=wren-vps
#      VPS_SITE_ONION=....onion   (the site's onion address, shown on its pages)
# Usage: bash tools/publish-site.sh [--host HOST] [--onion ADDRESS] [--dry-run]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
not_root

g() { git -C "$WREN_DIR" "$@"; }
usage() { die "Usage: bash tools/publish-site.sh [--host HOST] [--onion ADDRESS] [--dry-run]"; }
# (a test points these at a pretend rsync and two local folders)
RSYNC=${WREN_RSYNC:-rsync}
CONF=${XDG_CONFIG_HOME:-$HOME/.config}/wren/vps/site.conf

host='' onion='' dry=false
while [ $# -gt 0 ]; do
    case $1 in
        --host) host=${2:-}; shift 2 || usage ;;
        --onion) onion=${2:-}; shift 2 || usage ;;
        --dry-run) dry=true; shift ;;
        *) usage ;;
    esac
done
if [ -f "$CONF" ]; then
    while IFS='=' read -r k v; do
        case $k in
            VPS_HOST) [ -n "$host" ] || host=$v ;;
            VPS_SITE_ONION) [ -n "$onion" ] || onion=$v ;;
            '' | \#*) ;;
            *) die "$CONF: unknown setting \"$k\"." ;;
        esac
    done <"$CONF"
fi
[ -n "$host" ] || die "Which server? --host wren-vps (the name from tools/vps-client.sh ssh-config), or VPS_HOST in $CONF"
[[ $host =~ ^([a-z][a-z0-9-]{0,30}@)?[A-Za-z0-9.-]+$ ]] || die "\"$host\" isn't an ssh name (wren-vps, or user@address)."
[ -z "$onion" ] || [[ $onion =~ ^[a-z2-7]{56}\.onion$ ]] || die "\"$onion\" isn't an onion address."
site_dest=${WREN_PUBLISH_SITE:-$host:/srv/wren-site/}
git_dest=${WREN_PUBLISH_GIT:-$host:/srv/wren-git/wren-linux.git}
[ -n "${WREN_RSYNC:-}" ] || need_tools rsync:rsync

commit=$(g rev-parse --verify HEAD)
say "Building the site from commit ${commit:0:12}"
out=${XDG_CACHE_HOME:-$HOME/.cache}/wren/site
mkdir -p "${out%/*}"
bash "$WREN_DIR/tools/build-site.sh" --out "$out" --commit "$commit" --require-signed ${onion:+--onion "$onion"} ||
    die "Nothing was published. (An unsigned commit? bash tools/git-push.sh signs it as it pushes.)"

say "Copying it to $host"
# -rlt: the files and their dates, not this computer's owners; --delete: what
# the site no longer has goes from the server too
flags=(-rlt --delete --exclude=.wren-site "--chmod=D755,F644")
if $dry; then flags+=(--dry-run); fi
"$RSYNC" "${flags[@]}" -e ssh "$out/" "$site_dest" ||
    die "The copy didn't go through (can you log in? ssh $host)."
if $dry; then note "(--dry-run: nothing was copied, and the mirror wasn't pushed)"; exit 0; fi

say "Pushing the commit to the mirror"
g push --quiet "$git_dest" "$commit:refs/heads/main" ||
    die "The site is up, but the mirror wasn't pushed (ssh $host, then look at /srv/wren-git)."
note "Published commit ${commit:0:12} to $host${onion:+ (and $onion)}."
