#!/bin/bash
# Checks extras/zram.sh's pieces: the settings, its page and its promises. A real install, under
# real memory pressure, was tried by hand (docs/maintaining.md has ways to, in a VM).
# Run by test.sh, or:  bash tools/test-zram.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
E=$HERE/extras/zram.sh
C=$HERE/data/zram-generator.conf
check "it is up to half of memory, squeezed with zstd" bash -c 'grep -qx "zram-size = ram / 2" "$1" && grep -qx "compression-algorithm = zstd" "$1"' _ "$C"
check "the page's manual steps say the same" bash -c 'grep -q "zram-size = ram / 2. .compression-algorithm = zstd" "$1"' _ "$HERE/docs/extras/zram.md"
check "taking it off stops at a swapoff that fails, so nothing is lost" grep -q 'sudo swapoff /dev/zram0 || die' "$E"
check "it stops if it didn't really start" grep -q "grep -qs '^/dev/zram0 ' /proc/swaps || die" "$E"
check "nothing makes a swap file" bash -c '! grep -Eq "mkswap|fallocate|/swapfile" "$1" "$2"' _ "$E" "$C"
[ "$fails" -eq 0 ]
