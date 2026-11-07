---
type: feature
stage: implemented
description: On Coder workspaces, the agent-start script runs the OpenCode v2 server and web UI in the background behind a password, reachable from a dashboard app and a printed link, with provider logins and session chats kept per worktree across rebuilds.
generated:
  by: claude-code/opus-5.5
  at: 2026-10-31T21:00:44Z
sources:
- resource: https://github.com/plume-works/agent-devcontainer/blob/2612a847/docs/knowledge/data/features/opencode-web-coder-autostart.md
- resource: .devcontainer/scripts/coder-agent-start.sh
- resource: .devcontainer/devcontainer.json
- resource: https://github.com/plume-works/coder-ide-baseline
- resource: .devcontainer/scripts/opencode-web-start.sh
- resource: https://opencode.ai/v2/docs
---

# OpenCode web UI autostart on Coder

## Purpose

OpenCode's web UI is only available after someone starts its server by hand, and
its provider logins and session chats live in the container's data directory, so
a Dev Container rebuild loses both.

## Behaviour

**Coder starts it.** `coder-agent-start.sh` starts `opencode serve`, which
serves both the API and the web UI, in a detached tmux session on its own tmux
server, `tmux -L opencode`, on every agent start. A live session is reused, not
duplicated. There are no login prechecks: providers are connected from the web
UI's Settings.

**Always behind a password.** The server listens on port 4096, and OpenCode v2
always requires a password, sent as basic auth with the user `opencode`. When
`OPENCODE_SERVER_PASSWORD` is set — for example as a Coder user secret — the
server uses it and binds `0.0.0.0`. Otherwise it binds `127.0.0.1`, reached
through Coder port forwarding, with a random password generated once into
`~/.local/share/opencode/agentdev-server-password` (mode `0600`). The pane reads
that file itself, so the password appears on no command line and in no log; the
printed line names the file.

**One click into the web UI.** The start prints the server's URL, and the Coder
dashboard shows an `OpenCode` app that opens the same address. OpenCode v2's web
UI has no route that opens a folder, so the link opens its home.

**Logins and chats are per worktree.** A Compose-prefixed `agentdev-opencode`
volume mounted at `/root/.local/share/opencode` keeps OpenCode's database, which
holds provider logins and sessions, and the generated server password across
rebuilds. Each worktree logs in once.

## Edge cases

- **The catalog changes after the server started.** `postAttachCommand.sh`
  re-registers the agentdev catalog for every harness; a running server keeps
  the configuration it started with until it restarts.
- **Local Dev Containers and CI.** Nothing starts the server; the volume still
  applies.
- **A worktree that used OpenCode v1.** v2 does not import an OpenAI OAuth login
  from v1's `auth.json`, so the first v2 start logs in again.
- **The project sidebar starts empty.** The web UI keeps its project list in the
  browser, so the workspace folder appears there only after one "Add project"
  per browser.
- **A repository without OpenCode.** The template gives every workspace the
  `OpenCode` app; where no server runs, it shows unhealthy.
- **No provider is logged in.** The server starts anyway; the web UI's Settings
  connects one.

## Open questions

None open.
