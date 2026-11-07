#!/bin/bash
# Checks how big claude-vm's VM may be (lib/vm-size.sh): the suggestions and
# limits for computers with more and less memory and disk, that a size over
# what the computer can spare is refused, that a kept size stays, and that the
# VM's session reads it from root's file only. With a pretend sudo and pretend
# computers; changes nothing outside a temp folder.
# Run by test.sh, or:  bash tools/test-vm-size.sh
# shellcheck disable=SC2016  # the inner bash expands its own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh"
T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
trap 'rm -rf "$T"' EXIT
export WREN_VM_SIZE_FILE=$T/etc/claude-vm-size
. "$HERE/lib/vm-size.sh"
set +e +o pipefail
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
# (root's install, without the owner, which needs root)
sudo() {
    if [ "$1" = install ]; then
        shift
        local a=()
        while [ $# -gt 0 ]; do case $1 in -o | -g) shift 2 ;; *) a+=("$1"); shift ;; esac; done
        install "${a[@]}"
    else
        "$@"
    fi
}

# (for the checks run in a bash of their own)
export -f vm_size_limits vm_size_tight vm_size_fits
export VM_MEM_MIN VM_DISK_MIN VM_HOST_KEEP_MEM VM_HOST_KEEP_DISK

# ---- suggestions and limits: "SUGGESTED MOST SUGGESTED MOST" (memory, disk) ----
check "12 GB of memory, 300 GB free: about a third suggested (3840 MB), at most half (5888), a 40 GB disk, at most 280 GB" \
    test "$(vm_size_limits 11880 300000)" = "3840 5888 40000 280000"
check "64 GB: at most 8 GB suggested, at most half allowed" test "$(vm_size_limits 64000 300000)" = "8192 32000 40000 280000"
check "6 GB: always 4 GB left for the computer (at most 2048)" test "$(vm_size_limits 6000 300000 | cut -d' ' -f1-2)" = "2048 2048"
check "4 GB: the smallest VM (2048), and a warning that it leaves the computer short" \
    bash -c '[ "$(vm_size_limits 3900 300000 | cut -d" " -f1-2)" = "2048 2048" ] && vm_size_tight 3900 300000 | grep -q "leaves it less than 4 GB"' _
check "a disk with 50 GB free: 20 GB kept free (30 GB at most), 30 GB suggested" test "$(vm_size_limits 11880 50000 | cut -d' ' -f3-4)" = "30000 30000"
check "...with 30 GB free: the smallest disk, and a warning" \
    bash -c '[ "$(vm_size_limits 11880 30000 | cut -d" " -f3-4)" = "20000 20000" ] && vm_size_tight 11880 30000 | grep -q "Make room first"' _
check "2 GB of memory: refused (the computer would be left too little to run), pointing to claude-code" \
    bash -c '! o=$(vm_size_fits 1973 300000) && grep -q "too little to keep running" <<<"$o" && grep -q "wrenctl install claude-code" <<<"$o"' _
check "...and 20 GB free: refused (the VM's disk could fill it)" bash -c '! o=$(vm_size_fits 11880 20000) && grep -q "could fill it" <<<"$o"' _
check "...6 GB and 30 GB free fit (with warnings)" vm_size_fits 6000 30000
check "a computer with room to spare gets no warning" test -z "$(vm_size_tight 11880 300000)"

# ---- choosing ----
vm_size_host() { echo "11880 300000"; }
choose() { # ANSWERS-FILE-LINES... then vm_size_choose's arguments in ARGS
    printf '%s\n' "$@" >"$T/answers"
    # shellcheck disable=SC2086
    (WREN_TEST_ANSWERS=$T/answers vm_size_choose claude-vm $ARGS) 2>&1
}
ARGS='' out=$(choose '' '')
check "the first time: this computer's memory and disk are shown, with the suggestion and the most" \
    bash -c 'grep -q "This computer: 12 GB of memory, 300 GB of disk free" <<<"$1" && grep -q "Suggested: 3840 MB of memory (at most 5888)" <<<"$1"' _ "$out"
check "...Enter takes the suggestion, kept in root's file" test "$(cat "$WREN_VM_SIZE_FILE")" = "claude-vm 3840 40000"
ARGS='' out=$(choose)
check "a kept size stays as it is, without asking" bash -c '[ "$(cat "$2")" = "claude-vm 3840 40000" ] && ! grep -q "Memory in MB" <<<"$1"' _ "$out" "$WREN_VM_SIZE_FILE"
ARGS='8000 40000' out=$(choose) && rc=0 || rc=$?
check "more memory than the computer can spare is refused, and nothing changes" \
    bash -c '[ "$(cat "$2")" = "claude-vm 3840 40000" ] && grep -q "more would leave this computer short" <<<"$1"' _ "$out" "$WREN_VM_SIZE_FILE"
ARGS='4096 290000' out=$(choose)
check "...and a disk that could fill the computer's" grep -q "more could fill this computer's disk" <<<"$out"
ARGS='1024 40000' out=$(choose)
check "...and less than the VM needs to run" grep -q "isn't between 2048" <<<"$out"
# A space typed before the number (the prompt reader keeps leading spaces) is trimmed
rm -f "$WREN_VM_SIZE_FILE"
ARGS='' out=$(choose ' 4096' '  40000  ')
check "a number typed with spaces around it still counts (not failed as out of range)" \
    bash -c '[ "$(cat "$2")" = "claude-vm 4096 40000" ] && ! grep -q "isn.t between" <<<"$1"' _ "$out" "$WREN_VM_SIZE_FILE"
rm -f "$WREN_VM_SIZE_FILE"
ARGS='' out=$(choose '   ' '')
check "...a space-only answer counts as Enter: the suggestion" test "$(cat "$WREN_VM_SIZE_FILE")" = "claude-vm 3840 40000"
ARGS='4096 60000' out=$(choose)
check "a size it can spare is kept (memory from the next start, the disk from the next build)" \
    bash -c '[ "$(cat "$2")" = "claude-vm 4096 60000" ] && grep -q "claude-vm rebuild" <<<"$1"' _ "$out" "$WREN_VM_SIZE_FILE"
echo "claude-vm-work 3072 30000" >>"$WREN_VM_SIZE_FILE"
ARGS='5120 60000' out=$(choose)
check "...and another account's line stays" bash -c 'grep -qx "claude-vm 5120 60000" "$1" && grep -qx "claude-vm-work 3072 30000" "$1"' _ "$WREN_VM_SIZE_FILE"
vm_size_remove claude-vm-work
check "an account removed: its line goes, the others stay" bash -c '[ "$(cat "$1")" = "claude-vm 5120 60000" ]' _ "$WREN_VM_SIZE_FILE"

# ---- where it is read and written ----
S=$HERE/bin/claude-vm-session
check "the VM's session reads its size from root's file, never a path it is given" \
    bash -c 'grep -q "^    /etc/wren/claude-vm-size 2>/dev/null) || true" "$1" && ! grep -q WREN_VM_SIZE_FILE "$1"' _ "$S"
check "...and passes it to the VM engine only if it is within reason" \
    bash -c 'grep -q "\[ \"\$mem\" -ge 1024 \] && \[ \"\$mem\" -le 131072 \]" "$1" && grep -q "export VM_MEMORY=\$mem VM_DISK_SIZE_MB=\$disk" "$1"' _ "$S"
X=$HERE/extras/claude-vm.sh
check "claude-vm.sh asks the size before building, for the first VM and for each account" \
    bash -c '[ "$(grep -c "^ *vm_size_choose \"\$AGENT\" \"\$SIZE_MEM\" \"\$SIZE_DISK\"$" "$1")" = 2 ]' _ "$X"
check "...and forgets it when a VM is removed" bash -c 'grep -q "vm_size_remove claude-vm$" "$1" && grep -q "vm_size_remove \"\$AGENT\"" "$1"' _ "$X"
check "the file is root's: the VM's user can't give itself more" grep -q 'sudo install -o root -g root -m 0644 "$tmp" "$VM_SIZE_FILE"' "$HERE/lib/vm-size.sh"


# How many CPUs
check "CPUs: an 8 CPU computer can give up to 6" test "$(vm_cpus_max 8)" = 6
check "...a 4 CPU one up to 2, the default" test "$(vm_cpus_max 4)" = 2
check "...a 2 CPU one too" test "$(vm_cpus_max 2)" = 2
S=$HERE/bin/claude-vm-session
check "the session reads root's file, and only numbers in reason" \
    bash -c 'grep -q "/etc/wren/claude-vm-cpus 2>/dev/null) || true" "$1" && grep -q "\"\$cpus\" -le 32 \]; then export VM_VCPUS=\$cpus" "$1" && ! grep -q WREN_VM_CPUS "$1"' _ "$S"
nproc() { echo 8; }
cpus() { (vm_cpus_choose "$@") 2>&1; }
cpus claude-vm 4 >/dev/null
check "--cpus 4: kept in root's file" grep -qx 'claude-vm 4' "$T/etc/claude-vm-cpus"
cpus claude-vm 6 >/dev/null
check "...once, for that VM" test "$(grep -c '^claude-vm ' "$T/etc/claude-vm-cpus")" = 1
out=$(cpus claude-vm 7)
check "--cpus 7 of 8: refused, nothing changed" bash -c 'grep -q "isn.t between 1 and 6" <<<"$1" && grep -qx "claude-vm 6" "$2"' _ "$out" "$T/etc/claude-vm-cpus"
out=$(cpus claude-vm 'x; rm')
check "...and what isn't a number" grep -q "isn.t between" <<<"$out"

[ "$fails" -eq 0 ]
