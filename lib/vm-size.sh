# shellcheck shell=bash
# lib/vm-size.sh: how much memory and disk claude-vm's VM gets (extras/claude-vm.sh;
# bin/claude-vm-session reads the file). Sourced after lib.sh. Sizes are in MiB.
#
# The choice is kept in a file only root can change, one line per VM user:
# "USER MEMORY DISK". The VM's user can't give itself more. Memory counts from
# the VM's next start, the disk's size from its next build (claude-vm rebuild).
#
# What this computer can spare, so the VM never takes so much that the computer
# itself runs short:
#  - memory: suggested a third of it (2 to 8 GB); at most half, and always
#    4 GB left for the computer;
#  - disk: suggested 40 GB; at most what is free (the VM's own disk counts as
#    free, a rebuild replaces it) less 20 GB. The VM's disk file grows as the
#    VM fills it, so its size is what it may grow to, not what it takes at once;
#  - none at all with less than 4 GB of memory or 25 GB of disk free.

VM_SIZE_FILE=${WREN_VM_SIZE_FILE:-/etc/wren/claude-vm-size}
VM_MEM_DEFAULT=2048 VM_DISK_DEFAULT=20000
VM_MEM_MIN=2048 VM_DISK_MIN=20000
VM_HOST_KEEP_MEM=4096 VM_HOST_KEEP_DISK=20000

# vm_size_limits TOTAL-MEMORY FREE-DISK: "SUGGESTED-MEMORY MOST-MEMORY
# SUGGESTED-DISK MOST-DISK" for a computer with that much (MiB). The most is
# never under the minimum (the VM needs that much to run at all): vm_size_tight
# says when that is more than this computer can spare.
vm_size_limits() {
    local total=$1 free=$2 rec_mem max_mem rec_disk max_disk
    max_mem=$((total / 2))
    [ $((total - VM_HOST_KEEP_MEM)) -ge "$max_mem" ] || max_mem=$((total - VM_HOST_KEEP_MEM))
    max_mem=$((max_mem / 256 * 256))
    [ "$max_mem" -ge "$VM_MEM_MIN" ] || max_mem=$VM_MEM_MIN
    rec_mem=$((total / 3 / 256 * 256))
    [ "$rec_mem" -ge "$VM_MEM_MIN" ] || rec_mem=$VM_MEM_MIN
    [ "$rec_mem" -le 8192 ] || rec_mem=8192
    [ "$rec_mem" -le "$max_mem" ] || rec_mem=$max_mem
    max_disk=$(((free - VM_HOST_KEEP_DISK) / 1000 * 1000))
    [ "$max_disk" -ge "$VM_DISK_MIN" ] || max_disk=$VM_DISK_MIN
    rec_disk=40000
    [ "$rec_disk" -le "$max_disk" ] || rec_disk=$max_disk
    echo "$rec_mem $max_mem $rec_disk $max_disk"
}

# vm_size_fits TOTAL-MEMORY FREE-DISK: fails, saying why, when even the smallest
# VM would leave this computer too little to keep running (2 GB of memory, 5 GB
# of disk)
vm_size_fits() {
    [ $(($1 - VM_MEM_MIN)) -ge 2048 ] ||
        { echo "This computer has $((($1 + 512) / 1024)) GB of memory: the smallest VM ($((VM_MEM_MIN / 1024)) GB) would leave it less than 2 GB, too little to keep running. Claude Code as its own user (wrenctl install claude-code) needs no VM."; return 1; }
    [ $(($2 - VM_DISK_MIN)) -ge 5000 ] ||
        { echo "Only $(($2 / 1000)) GB of disk is free: the smallest VM disk ($((VM_DISK_MIN / 1000)) GB) could fill it. Make room first (at least $(((VM_DISK_MIN + 5000) / 1000)) GB free)."; return 1; }
}

# vm_size_tight TOTAL-MEMORY FREE-DISK: what the minimum leaves too little of, one line each
vm_size_tight() {
    [ $(($1 - VM_MEM_MIN)) -ge "$VM_HOST_KEEP_MEM" ] ||
        echo "This computer has $((($1 + 512) / 1024)) GB of memory: even the smallest VM ($((VM_MEM_MIN / 1024)) GB) leaves it less than $((VM_HOST_KEEP_MEM / 1024)) GB. Close other programs while the VM runs."
    [ $(($2 - VM_DISK_MIN)) -ge "$VM_HOST_KEEP_DISK" ] ||
        echo "Only $(($2 / 1000)) GB of disk is free: a full VM disk ($((VM_DISK_MIN / 1000)) GB) would leave less than $((VM_HOST_KEEP_DISK / 1000)) GB. Make room first."
    return 0
}

# vm_size_host USER: "TOTAL-MEMORY FREE-DISK" here, in MiB; the disk is the one
# USER's home is on, its VM's disk file counted as free
vm_size_host() {
    local total free vmdisk
    total=$(awk '$1 == "MemTotal:" { print int($2 / 1024) }' /proc/meminfo)
    free=$(df -Pm /home | awk 'NR == 2 { print $4 }')
    vmdisk=$(sudo du -sm "/home/$1/vm" 2>/dev/null | cut -f1) || vmdisk=0
    echo "$total $((free + ${vmdisk:-0}))"
}

# vm_size_get USER: "MEMORY DISK" kept for USER, or nothing
vm_size_get() {
    awk -v u="$1" '$1 == u && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ { print $2, $3; exit }' "$VM_SIZE_FILE" 2>/dev/null || true
}

# vm_size_set USER MEMORY DISK: keeps it (root's file, readable by all)
vm_size_set() {
    local tmp
    tmp=$(mktemp)
    { awk -v u="$1" '$1 != u' "$VM_SIZE_FILE" 2>/dev/null || true; echo "$1 $2 $3"; } >"$tmp"
    sudo install -d -o root -g root -m 0755 "${VM_SIZE_FILE%/*}"
    sudo install -o root -g root -m 0644 "$tmp" "$VM_SIZE_FILE"
    rm -f "$tmp"
}

# vm_size_remove USER: forgets USER's line
vm_size_remove() {
    [ -f "$VM_SIZE_FILE" ] || return 0
    local tmp
    tmp=$(mktemp)
    awk -v u="$1" '$1 != u' "$VM_SIZE_FILE" >"$tmp"
    if [ -s "$tmp" ]; then sudo install -o root -g root -m 0644 "$tmp" "$VM_SIZE_FILE"; else sudo rm -f "$VM_SIZE_FILE"; fi
    rm -f "$tmp"
}

# vm_size_choose USER [MEMORY] [DISK]: the VM's size. Given ones are checked
# against what this computer can spare; with none given, a size kept already
# stays, and otherwise you are shown this computer's and asked (Enter takes
# the suggestion).
vm_size_choose() {
    local user=$1 mem=${2:-} disk=${3:-} total free rec_mem max_mem rec_disk max_disk have line
    have=$(vm_size_get "$user")
    if [ -z "$mem" ] && [ -z "$disk" ] && [ -n "$have" ]; then
        read -r mem disk <<<"$have"
        note "The VM keeps its size: $mem MB of memory, a disk of up to $disk MB (change it: --memory MB --disk MB)."
        return 0
    fi
    read -r total free <<<"$(vm_size_host "$user")"
    read -r rec_mem max_mem rec_disk max_disk <<<"$(vm_size_limits "$total" "$free")"
    say "How big the VM is"
    note "This computer: $(((total + 512) / 1024)) GB of memory, $((free / 1000)) GB of disk free."
    line=$(vm_size_fits "$total" "$free") || die "$line"
    note "Suggested: $rec_mem MB of memory (at most $max_mem), a disk of up to $rec_disk MB (at most $max_disk)."
    while read -r line; do [ -z "$line" ] || warn "$line"; done < <(vm_size_tight "$total" "$free")
    if [ -z "$mem" ] && [ -z "$disk" ]; then
        tty_read mem "    Memory in MB (Enter for $rec_mem): "
        tty_read disk "    Disk in MB (Enter for $rec_disk): "
    fi
    [ -n "$mem" ] || mem=${have%% *}
    [ -n "$mem" ] || mem=$rec_mem
    [ -n "$disk" ] || disk=${have##* }
    [ -n "$disk" ] || disk=$rec_disk
    [[ $mem =~ ^[0-9]{1,6}$ ]] && [ "$mem" -ge "$VM_MEM_MIN" ] && [ "$mem" -le "$max_mem" ] ||
        die "Memory: $mem MB isn't between $VM_MEM_MIN and $max_mem (more would leave this computer short). Nothing was changed."
    [[ $disk =~ ^[0-9]{1,7}$ ]] && [ "$disk" -ge "$VM_DISK_MIN" ] && [ "$disk" -le "$max_disk" ] ||
        die "Disk: $disk MB isn't between $VM_DISK_MIN and $max_disk (more could fill this computer's disk). Nothing was changed."
    vm_size_set "$user" "$mem" "$disk"
    note "Kept: $mem MB of memory (from the VM's next start), a disk of up to $disk MB (from its next build: claude-vm rebuild)."
}
