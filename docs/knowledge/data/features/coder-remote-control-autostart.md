---
type: feature
stage: implemented
description: On Coder workspaces, Claude Remote Control starts from a template coder_script on the Dev Container's sub-agent, so the session inherits Coder user secrets and the agent's git credentials.
generated:
  by: claude-code/opus-5.5
  at: 2026-10-16T12:00:00Z
sources:
- resource: https://github.com/plume-works/agent-devcontainer/blob/2612a847/docs/knowledge/data/features/coder-remote-control-autostart.md
- resource: docs/knowledge/data/plans/20261011-coder-claude-remote-control.md
- resource: .devcontainer/scripts/claude-remote-control-start.sh
- resource: https://github.com/plume-works/coder-ide-baseline
---

# Remote Control autostart on Coder

## Purpose

A Remote Control session started before the Coder agent existed lacked what the
agent gives its sessions — Coder user secrets such as `GITHUB_TOKEN` and the
agent's git credentials — so `gh` and `git push` were unauthenticated in it.

## Behaviour

**Coder starts it.** The `coder-ide-baseline` template attaches a `coder_script`
to the Dev Container's sub-agent that runs
`.devcontainer/scripts/claude-remote-control-start.sh` on every agent start. The
script's presence in the template is the opt-in; autostart is Coder-only.

**Its own tmux server.** The session runs on `tmux -L claude-remote`, so the
Claude process inherits the agent's environment even when another tmux server is
already running.

The contract is [Claude Remote
Control](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/claude-remote-control.md).

## Edge cases

- **The repository does not ship the script.** The `coder_script` does nothing.
- **The operator logs in after the workspace started.** Running the script by
  hand from a Coder terminal, or restarting the workspace, starts the session.
- **A session is already running.** It is reused, not duplicated.

## Open questions

None — the design is settled.

## References

- Plan: [Start Claude Remote Control from the Coder
  agent](../plans/20261011-coder-claude-remote-control.md)
