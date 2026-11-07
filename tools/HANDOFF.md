# Handoff for a new claude-vm (read this first)

Written 2026-11-07, for the Claude in a new `claude-vm` on the owner's second laptop. That VM has none
of the old VM's files or memory. Remove this file, and its line at the top of `CLAUDE.md`, once the
work below is done or has moved on.

This file is public: **no unfixed security findings go in it, or in any commit or doc.**

Greet the owner, say what you found here, and report early and often: they dislike a long silent read.
Their weekly usage was near its limit when this was written, so don't start with a long read.

## The rest of the state is on another branch

The full handoff is on `claude-wip`: the owner's decisions in order, the browser sandboxes, what is
waiting on the owner.

    git fetch origin && git show origin/claude-wip:HANDOFF.md

- `claude-wip` holds **unfinished, untested work** on top of older `claude` commits. Never merge it as
  it is. Bring its work to `claude` piece by piece, each with its tests. Then delete the branch, once
  the owner agrees.
- It breaks the rule "push only to `claude`": an earlier session pushed it to keep the work safe,
  without the owner knowing. The owner found out on 2026-11-07 and chose to keep it for now. Don't
  make other branches on the server.
- `claude-share-20261106-101633` is also on the server, and nobody has looked at it yet. Look before
  saying what it is.

## First: the new VM

- The VM needs no key on GitHub any more: its work goes to the owner with `claude-pull` (2026-11-07).
- **Security findings were never in the repo.** They are in the old VM's private memory, and the owner
  was told them in person. Ask the owner; don't assume there are none because you can't see any.

## To plan and discuss with the owner: Claude Code's settings in the VM

**Decided 2026-11-07: the owner asked for all of these, plus `CLAUDE_CODE_DISABLE_MOUSE`, in every new VM.**
Done in `data/claude-vm-provision.sh` (tested with `tools/test-claude-vm.sh`; not yet in a real VM build).
Questions 2 and 3 below are still open. Before that, nothing here was applied. The owner runs with bypass
permissions on (`claude-vm unattended`). The VM walls off the owner's computer, but a session is also
signed in to the owner's Claude account, which the VM's network wall doesn't cover.

Proposed for `~/.claude/settings.json` in the VM. Names are from the Claude Code docs, read on
2026-11-07 for version 2.1.311; **none of this has been tried**, so check the docs again first:

    {
      "isolatePeerMachines": true,
      "crossSessionInbound": "refuse",
      "remoteControlAtStartup": false,
      "disableClaudeAiConnectors": true,
      "enableArtifact": false,
      "syncClaudeAiSkills": false,
      "syncClaudeAiPlugins": false,
      "env": {
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
        "DISABLE_FEEDBACK_COMMAND": "1"
      }
    }

- `isolatePeerMachines`: asks before a message goes to the owner's sessions on other machines; it still
  asks in bypass mode.
- `crossSessionInbound`: drops messages from the owner's other sessions.
- `remoteControlAtStartup`: no automatic Remote Control. The owner may use Remote Control: ask first.
  `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` can also make it unavailable.
- `disableClaudeAiConnectors`, `enableArtifact`, `syncClaudeAi*`: less passing between the VM and the
  account. Connectors and the Artifact tool go away: ask whether the owner uses them.
- `env`: no telemetry, error reports or surveys, and no `/feedback`, which sends conversation history
  and keeps it for 5 years.

Questions to settle with the owner:

1. Should `extras/claude-vm.sh` write these settings when it builds a VM, for everyone, with a way to
   change them? That is code: failing test first, full suite, and a try in a real VM.
2. Is `--permission-mode auto` better than bypass for sessions that read a lot from the web? The docs
   recommend bypass only without internet access, and this VM has internet.
3. What should be in the VM at all? Web pages and downloads can try to steer a session, so plan as if
   what is here could leak: the deploy key, the Claude login, private notes.

Limits to say plainly: Claude can edit these settings in bypass mode, and with sudo a root-owned
managed settings file wouldn't hold either. They guard against mistakes, not a hijacked session. What
holds is outside the VM: the owner's review, the rulesets on `main`, the signing key, and what the
account is connected to.

For the owner to do on claude.ai (Claude can't): disconnect connectors they don't need, and check
whether model training is on at claude.ai/settings/data-privacy-controls.
