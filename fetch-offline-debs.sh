#!/bin/bash
# Run this NOW, on a Debian 13 amd64 machine that has internet (ideally
# the one you're about to reinstall). It downloads wpasupplicant, iw and
# the firmware your network cards need, with their dependencies, into
# ./debs, so wifi.sh can get a fresh install online with no cable. Copy
# the whole debsway folder to a USB stick afterwards.
#
#   bash fetch-offline-debs.sh            firmware for this machine's cards
#   bash fetch-offline-debs.sh --all      firmware for every common Wi-Fi card
#   bash fetch-offline-debs.sh [--all] firmware-NAME ...   and these too
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

OUT="$DEBSWAY_DIR/debs"
# Debian's firmware package for each kernel driver family
ALL_FIRMWARE=(firmware-iwlwifi firmware-realtek firmware-atheros firmware-brcm80211
    firmware-mediatek firmware-libertas firmware-ti-connectivity firmware-misc-nonfree)

firmware_for_driver() {
    case $1 in
        iwlwifi | iwlmvm | iwldvm) echo firmware-iwlwifi ;;
        rtw88* | rtw89* | rtl8* | rtl_* | r8188eu | r8712u | r8169) echo firmware-realtek ;;
        ath6kl* | ath9k_htc | ath10k* | ath11k* | ath12k* | carl9170) echo firmware-atheros ;;
        brcmfmac | brcmsmac) echo firmware-brcm80211 ;;
        mt76* | mt79*) echo firmware-mediatek firmware-misc-nonfree ;;
        mwifiex* | libertas* | mwl8k) echo firmware-libertas ;;
        wl1251 | wl12xx | wl18xx | wlcore*) echo firmware-ti-connectivity ;;
    esac
}

PKGS=(wpasupplicant iw wireless-regdb)
if [ "${1:-}" = --all ]; then
    shift
    PKGS+=("${ALL_FIRMWARE[@]}")
else
    found=false
    for dev in /sys/class/net/*/device; do
        [ -e "$dev/driver" ] || continue
        drv=$(basename -- "$(readlink -f "$dev/driver")")
        fw=$(firmware_for_driver "$drv")
        note "$(basename -- "$(dirname -- "$dev")"): driver $drv -> ${fw:-no extra firmware needed}"
        # shellcheck disable=SC2206
        [ -z "$fw" ] || { PKGS+=($fw); found=true; }
    done
    $found || warn "No known Wi-Fi firmware for this machine. For another machine use: --all"
fi
PKGS+=("$@")
mapfile -t PKGS < <(printf '%s\n' "${PKGS[@]}" | awk '!seen[$0]++')

[ "$(dpkg --print-architecture)" = amd64 ] || warn "This machine isn't amd64; the packages won't match."
. /etc/os-release
[ "${VERSION_CODENAME:-}" = "$DEBIAN_RELEASE" ] || warn "This machine isn't $DEBIAN_RELEASE; the packages may not install."

command -v apt-ftparchive >/dev/null ||
    die "apt-ftparchive is missing. Install it with: sudo apt install apt-utils"

say "Resolving dependencies"
# Everything they could ever need; on the new system apt only installs
# the ones it's missing.
mapfile -t want < <(
    apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts \
        --no-breaks --no-replaces --no-enhances "${PKGS[@]}" 2>/dev/null |
        grep -v '^[[:space:]<]' | sort -u
)
for p in "${PKGS[@]}"; do
    printf '%s\n' "${want[@]}" | grep -qxF "$p" ||
        warn "$p isn't available (firmware needs non-free-firmware in apt sources)."
done

say "Downloading ${#want[@]} packages to $OUT"
mkdir -p "$OUT"
rm -f "$OUT"/*.deb "$OUT"/Packages "$OUT"/Release
(cd "$OUT" && apt-get download "${want[@]}")

# Make the folder a local apt repo, so wifi.sh can resolve dependencies
(cd "$OUT" && apt-ftparchive packages . >Packages && apt-ftparchive release . >Release)
du -sh "$OUT"
