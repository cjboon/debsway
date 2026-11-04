---
name: vm-testing-plan
description: "Owner's plans for testing in a VM with sudo, and a later penetration test of Wren Linux in throwaway VMs (ideas from 2026-11-04, not started)."
metadata:
  node_type: memory
  type: project
  originSessionId: 36c8d8cf-7353-4c98-a6b8-c546bdaac43d
  modified: 2026-11-04T21:47:50.127Z
---

On 2026-11-04 the owner asked for `claude-vm` to get passwordless sudo in the guest (done, needs `claude-vm rebuild` on their machine) so Claude can test real installs there.

Agreed order: real-machine testing of the wallet sandbox first (nothing of it has run under real sudo), then a penetration test, an idea the owner raised.

**Why:** most sandbox checks run with pretend sudo. A test VM gives real results; a pentest checks whether the sandboxes hold against active attack.

**How to apply:** pentest design proposed to the owner: Wren installed in a mockvps-kvm target VM, start from inside (a shell as the firefox, incognito or wallet-* user, trying to get out), Kali only later for attacks over the network. Isolated network with no route to the LAN, fake keys only, snapshots between attacks, attack tools stay in the VM, written scope, nothing outside attacked. One goal per session, since it is expensive. Claude wrote much of this code, so a clean result isn't an independent audit. Fix serious findings before publishing: the repo is public.

Open from 2026-11-04: uncommitted lintian fix in tools/build-deb.sh and tools/test-build-deb.sh (test had timed out at 200s; finish or undo). Owner's ideas, awaiting go: Install and Remove apps at the bottom of the menu's Apps list; after real wallet tests, `electrum`, `feather`, `sparrow` open sandboxed by default, with `-regular` versions (the `claude-regular` pattern) and menu installs setting up the sandbox.

Related: [[whonix-webtunnel-plan]]. Also suggested: Cwtch as one more messenger (Delta Chat if Cwtch fails checks on maintenance, audit or signed releases), and timing the test suite's slowest groups.
