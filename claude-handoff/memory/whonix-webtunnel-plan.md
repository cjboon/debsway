---
name: whonix-webtunnel-plan
description: Owner approved an experimental webtunnel option for the Whonix Gateway; not started as of 2026-11-04. Design and open questions.
metadata:
  node_type: memory
  type: project
  originSessionId: 36c8d8cf-7353-4c98-a6b8-c546bdaac43d
  modified: 2026-11-04T20:54:21.048Z
---

Owner approved on 2026-11-04: add webtunnel to `extras/whonix.sh` as an **experimental, opt-in** bridge. Explain the danger of keeping it updated, without scaring users off trying it. obfs4 and Snowflake stay the defaults.

**Why:** people whose network blocks obfs4 and Snowflake can't use Whonix through Wren at all. Whonix doesn't ship lyrebird because it isn't in Debian's packages (whonix.org/wiki/Bridges#lyrebird, "community support only").

**How to apply:** follow the wiki's method, improved by Wren.
- Today `bridge_kinds whonix` is "obfs4 snowflake" and `bridge_unavailable whonix` says no client (`lib/tor.sh`). `tor_bridge_config` already writes the webtunnel lines.
- Wiki steps on the Gateway: `/usr/bin/lyrebird`; `/usr/bin/lyrebird rix,` under a `## lyrebird` comment above `## obfsproxy` in `/etc/apparmor.d/local/system_tor`; uncomment the nameserver in `/etc/resolv.conf.whonix`; torrc lines in `/usr/local/etc/torrc.d/50_user.conf`; Tor Control Panel bridges type "None"; restart `tor@default`, not reload.
- Wren's improvement: get lyrebird and check it on the host (`add_torproject_repo` pins lyrebird from the Tor Project's repo, key `TORPROJECT_FPR`), then write it into the image before first boot with `image_put` (its `--exec` form). This avoids the wiki's catch-22 of downloading inside a Gateway that can't connect, and makes signature checking mandatory.
- The update danger: the Gateway's copy is never updated by Whonix. Tell the user how to update, and warn when the host's lyrebird is newer than the copy written in (record the version).

**Open, and must be stated in the docs if not settled:**
- The KVM DNS address: the wiki's `10.0.2.3` may be VirtualBox's. Not found in the repo.
- Whether Whonix's firewall really limits Gateway DNS to Tor's user. Not read or tested.
- The wiki's last 15,000 characters (offset 100000) were never read; the owner stopped that fetch to save usage.

Owner's ISP question, already answered: the ISP sees only the bridge's hostname, never the sites visited through Tor.

Also pending after this: Firefox VM discussion, and the unfixed review findings from the 2026-11 session.
