---
type: plan
created: 2026-10-11
release:
- features/coder-remote-control-autostart
description: Start Claude Remote Control from a Coder template coder_script on the dev container's sub-agent, on a dedicated tmux server, so the session inherits Coder user secrets and git credentials; remove the postStart autostart and its AGENTDEV_CLAUDE_AUTOSTART flag.
generated:
  by: claude-code/opus-5.5
  at: 2026-10-11T00:00:00Z
sources:
- resource: https://github.com/plume-works/agent-devcontainer/blob/2612a847/docs/knowledge/data/plans/20261011-coder-claude-remote-control.md
- resource: .devcontainer/scripts/claude-remote-control-start.sh
- resource: .devcontainer/scripts/postStartCommand.sh
- resource: .devcontainer/docker-compose.yml
- resource: scripts/tests/test_claude_remote_control_start.py
- resource: scripts/tests/test_preapprove_claude_workspace.py
- resource: https://github.com/plume-works/coder-ide-baseline/blob/577b5fa/template/main.tf
- resource: https://coder.com/docs/admin/integrations/devcontainers/integration
- resource: https://coder.com/docs/v2.37/user-guides/user-secrets
- resource: https://man7.org/linux/man-pages/man1/tmux.1.html
stage: done
completed: 2026-10-12
released: 2.0.0
---

# Start Claude Remote Control from the Coder agent

## Context

[Claude Remote
Control](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/claude-remote-control.md)
autostarts from `postStartCommand.sh`, gated by `AGENTDEV_CLAUDE_AUTOSTART`, a
flag that exists only for Coder workspaces. In Coder, `devcontainer up` waits
for `postStartCommand` (`"waitFor": "postStartCommand"`), and the Coder agent is
injected into the dev container only after `up` returns. The Remote Control
Claude process is therefore never a descendant of the Coder agent and lacks
everything the agent gives its sessions: Coder user secrets such as
`GITHUB_TOKEN`, and the agent's git credentials (`GIT_ASKPASS`,
`CODER_AGENT_URL`, `CODER_AGENT_TOKEN`). `gh` and `git push` are unauthenticated
in the autostarted session.

Coder delivers env user secrets to new shells, apps, SSH sessions, and startup
scripts at agent start; a process already running keeps its environment. A
template `coder_script` attached to the dev container's sub-agent through
`coder_devcontainer.subagent_id` runs under the agent with that environment. The
workspace template lives in
[plume-works/coder-ide-baseline](https://github.com/plume-works/coder-ide-baseline),
which already declares `coder_devcontainer.repo` with nothing attached to its
sub-agent.

The maintainer decided that Remote Control autostart is a Coder-only feature:
the postStart path and its flag are removed, not kept as a non-Coder fallback.

## Approach

The template gains a `coder_script` on `coder_devcontainer.repo[0].subagent_id`
that runs `.devcontainer/scripts/claude-remote-control-start.sh` from the cloned
repository on every agent start, doing nothing when the repository does not ship
the script. The presence of that `coder_script` is the opt-in; the script drops
its `AGENTDEV_CLAUDE_AUTOSTART` gate and keeps its claude.ai login gate,
single-session reuse, and `CLAUDE_CODE_OAUTH_TOKEN` removal.

tmux gives a new session its server's global environment; from the client it
copies only the `update-environment` variables. The script runs `claude-remote`
on a dedicated server, `tmux -L claude-remote`, so the server is always started
by the script and the Claude process inherits the caller's environment even when
another tmux server is already live on the default socket.

Rejected: keeping postStart and having one entry point yield to the other.
postStart always runs first in Coder, so either the generic entry needs a Coder
signal it cannot observe before the agent exists, or the Coder entry must kill a
live session it did not start.

Assumption: an operator who logs in after the workspace started runs the script
by hand from a Coder terminal, which carries the same environment as the
`coder_script`; a workspace restart also starts it.

## Implementation Steps

Merge order: this repository's change (Tasks 1–3) merges before the template
change (Task 4). The reverse order would start Remote Control from postStart
first and leave the `coder_script` reusing that session.

### Task 1: Ungated start on a dedicated tmux server

**Files:** Modify: `.devcontainer/scripts/claude-remote-control-start.sh`,
`scripts/tests/test_claude_remote_control_start.py`

Runtime behavior: implement through the Principal Engineer with TDD.

- [x] Tests: drop the `autostart-unset` case and the `AGENTDEV_CLAUDE_AUTOSTART`
  environment from the helpers; assert every tmux call carries
  `-L claude-remote`; in the real-tmux test with a live default-socket server,
  assert a marker variable from the caller's environment reaches the Claude
  process.
  - **Evidence:** commit "Start Remote Control ungated on a dedicated tmux
    server": `assert_dedicated_socket` and the `CLAUDE_TMUX_TEST_MARKER` check
    in `test_claude_remote_control_start.py`; against the previous script the
    fake-tmux and real-tmux cases fail (no `-L claude-remote`, marker absent
    with a live default server).
- [x] Script: remove the `AGENTDEV_CLAUDE_AUTOSTART` gate and its wording in the
  skip messages; run `has-session`, `start-server`, and `new-session` against
  `tmux -L claude-remote`.
  - **Evidence:** commit "Start Remote Control ungated on a dedicated tmux
    server" (`claude-remote-control-start.sh:13,25,32,38,42`).
- [x] `shellcheck` clean;
  `uv run pytest scripts/tests/test_claude_remote_control_start.py` green.
  - **Evidence:** commit "Start Remote Control ungated on a dedicated tmux
    server": `shellcheck` clean; the test file 9 passed, both real-tmux cases
    run under tmux 3.4.

### Task 2: Remove the postStart autostart path

**Files:** Modify: `.devcontainer/scripts/postStartCommand.sh`,
`.devcontainer/docker-compose.yml`,
`scripts/tests/test_claude_remote_control_start.py`,
`scripts/tests/test_preapprove_claude_workspace.py`

- [x] Delete the `claude-remote-control-start.sh` call from
  `postStartCommand.sh`.
  - **Evidence:** commit "Remove the postStart Remote Control autostart":
    `postStartCommand.sh` no longer names the script; `shellcheck` clean.
- [x] Delete the `AGENTDEV_CLAUDE_AUTOSTART` passthrough from
  `docker-compose.yml`.
  - **Evidence:** commit "Remove the postStart Remote Control autostart":
    `docker-compose.yml` `environment:` goes from the secrets socket straight to
    the `GIT_*` entries.
- [x] Reduce `test_compose_passes_only_nonsecret_autostart_environment` to its
  `CLAUDE_CODE_OAUTH_TOKEN` assertion, renamed for what it then checks; drop
  `AGENTDEV_CLAUDE_AUTOSTART` from the ignore set in
  `test_preapprove_claude_workspace.py`.
  - **Evidence:** commit "Remove the postStart Remote Control autostart":
    `test_compose_does_not_pass_setup_token`;
    `uv run pytest scripts/tests/test_claude_remote_control_start.py scripts/tests/test_preapprove_claude_workspace.py`
    15 passed.
- [x] `grep -rn AGENTDEV_CLAUDE_AUTOSTART` outside `docs/knowledge/data/plans/`
  finds only the spec text Ship replaces.
  - **Evidence:** at commit "map: refresh devcontainer docs for coder_script
    Remote Control", the grep (excluding `.git` and `.tmp`) matches only
    `data/spec/claude-remote-control.md:36,86,101,106`.

### Task 3: Refresh the codebase map

**Files:** Modify: `docs/knowledge/data/codebase/devcontainer/scripts.md`,
`docs/knowledge/data/codebase/flow-devcontainer-lifecycle.md`,
`docs/knowledge/data/codebase/devcontainer.md` (compose anchors shifted by Task
2), `docs/knowledge/data/log.md`

- [x] Run `/agentdev:iwe-map` in refresh mode over the touched docs: the scripts
  table row and the lifecycle flow's Remote Control note describe a
  `coder_script` trigger and the dedicated tmux server.
  - **Evidence:** commit "map: refresh devcontainer docs for coder_script Remote
    Control": `devcontainer/scripts.md` row and `## How it works`,
    `flow-devcontainer-lifecycle.md` step 4 and failure mode;
    `stale-map-docs.py` `RESULT=SUCCESS`; `iwe schema validate` clean.

### Task 4: Template `coder_script` in coder-ide-baseline

**Files:** Modify (in `plume-works/coder-ide-baseline`): `template/main.tf`

A separate pull request in the template repository, after Tasks 1–3 merge. Shape
of the resource, following the existing `coder_script.second_repo`:

``` hcl
resource "coder_script" "claude_remote_control" {
  count              = data.coder_parameter.repo.value != "" ? data.coder_workspace.me.start_count : 0
  agent_id           = coder_devcontainer.repo[0].subagent_id
  display_name       = "Claude Remote Control"
  run_on_start       = true
  start_blocks_login = false
  script             = <<-EOT
    s=/workspaces/${local.repo_dir}/.devcontainer/scripts/claude-remote-control-start.sh
    if [ -x "$s" ]; then exec "$s"; fi
    echo "This repository ships no Remote Control start script."
  EOT
}
```

- [x] Raise the template's version constraints to their latest releases: the
  `coder/coder` and `kreuzwerker/docker` providers and the `code-server` module.
  The maintainer approved moving to latest; `coder/coder` must expose
  `coder_devcontainer.subagent_id`.
  - **Evidence:** coder-ide-baseline commit 4e28f6f (draft PR
    plume-works/coder-ide-baseline#15): `coder/coder` `~> 2.19`,
    `kreuzwerker/docker` `~> 4.6`, `code-server` `~> 1.6`; `terraform init` with
    Terraform 1.16.5 resolves 2.19.0, 4.6.0, and 1.6.0, and 2.19.0 documents
    `coder_devcontainer.subagent_id`.
- [x] Add the resource; `terraform validate` passes and the template pushes.
  - **Evidence:** plume-works/coder-ide-baseline#15 merged as a2b1cff after
    plume-works/agent-devcontainer#311 (9da499d); `terraform validate` passes
    with Terraform 1.16.5; `coder templates push coder-ide-baseline` from
    a2b1cff produced the active version `lemony_ray27`, and a workspace built on
    it creates `coder_script.claude_remote_control[0]`.

### Task 5: Verify in a live Coder workspace

- [x] After a workspace restart on the new template:
  `tmux -L claude-remote list-sessions` shows one `claude-remote`; the Claude
  process's environment variable names include `GITHUB_TOKEN` and `GIT_ASKPASS`
  and exclude `CLAUDE_CODE_OAUTH_TOKEN`; `gh auth status` succeeds from the
  Remote Control session; no Claude process descends from the postStart tmux
  server.
  - **Evidence:** live check on 2026-10-11 in a workspace built from template
    version `lemony_ray27` (coder-ide-baseline a2b1cff) with agent-devcontainer
    97a59ea checked out, after a workspace restart and a Dev Container recreate:
    the sub-agent's `coder_script` log reads "Started Claude Remote Control in
    tmux session 'claude-remote'"; `tmux -L claude-remote list-sessions` lists
    only `claude-remote`; the `claude /remote-control` process's parent is that
    tmux server, and its environment names include `GITHUB_TOKEN`,
    `GIT_ASKPASS`, `CODER_AGENT_URL`, `CODER_AGENT_TOKEN` but not
    `CLAUDE_CODE_OAUTH_TOKEN`; `gh auth status` run in a window of that server
    exits 0 via `GITHUB_TOKEN`; no default-socket tmux server exists; the pane
    shows `/rc active`.
- [x] Record the sub-agent's name; if it differs from the folder-derived
  `agent-devcontainer`, anything addressing the dev container by name is
  updated.
  - **Evidence:** on template version `lemony_ray27` the sub-agent is named
    `repo`, after `coder_devcontainer.repo` (`coder ssh <ws>.agent-devcontainer`
    reports `available agents: [dev repo]`). The only reference by name, the
    coder-ide-baseline README's `coder ssh <workspace>.<repo-name>`, became
    `<workspace>.repo` in plume-works/coder-ide-baseline#16 (349d8d6); nothing
    in this repository addresses the sub-agent by name.

### Task 6: Retire the Coder secret

- [x] The maintainer deletes the `AGENTDEV_CLAUDE_AUTOSTART` Coder user secret.
  - **Evidence:** on the maintainer's direction,
    `coder secret delete AGENTDEV_CLAUDE_AUTOSTART` on 2026-10-11;
    `coder secret list` no longer lists it.

## Spec changes

[Claude Remote
Control](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/claude-remote-control.md):
the autostart requirement changes trigger and tmux server, a requirement is
added for the inherited environment, and the pre-approval requirement's scenario
that named the flag is restated.

``` markdown
## MODIFIED Requirements

### Requirement: Remote Control autostarts only on a live claude.ai login

`claude-remote-control-start.sh` SHALL start `claude --remote-control` in
exactly one detached tmux session named `claude-remote`, on the dedicated tmux
server `tmux -L claude-remote`, naming the Remote Control session after
`CODER_WORKSPACE_NAME` when it is set, only when `claude auth status --json` reports
`loggedIn: true` with `authMethod: "claude.ai"`. The Coder template's
`coder_script` on the dev container's sub-agent runs it on every agent start;
no devcontainer lifecycle hook runs it. Repeated or concurrent runs SHALL reuse
a live session rather than create another. It SHALL skip startup when `claude`
or `tmux` is unavailable. The Claude process SHALL NOT receive
`CLAUDE_CODE_OAUTH_TOKEN`.

#### Scenario: the Coder agent restarts

- **WHEN** the `coder_script` runs while `claude-remote` is already live
- **THEN** it leaves the existing session running and creates no additional
  Claude process.

#### Scenario: the saved login has expired

- **WHEN** the credential file exists but `claude auth status --json` reports
  `loggedIn: false`
- **THEN** no session is started and the script exits successfully.

#### Scenario: only a setup token is available

- **WHEN** `claude auth status --json` reports `loggedIn: true` with an
  `authMethod` other than `claude.ai`
- **THEN** no session is started.

#### Scenario: the operator logs in after the workspace started

- **WHEN** an operator completes `/login` and runs the script from a Coder
  terminal
- **THEN** `claude-remote` starts without a workspace restart.

#### Scenario: the session starts in a Coder workspace

- **WHEN** the script starts `claude-remote` with `CODER_WORKSPACE_NAME` set
- **THEN** claude.ai/code lists the Remote Control session under that
  workspace name.

### Requirement: every container pre-approves first-run Claude state

Unless `AGENTDEV_SKIP_CLAUDE_PREAPPROVE` is non-empty, post-create SHALL record
in Claude's state file (`~/.claude.json`, written through its symlink into the
persistent volume) that onboarding is complete, the Remote Control confirmation
was seen, and the workspace is trusted. It SHALL set
`enableAllProjectMcpServers` in the workspace's `.claude/settings.local.json`
and SHALL keep any existing `disabledMcpjsonServers` list. Existing keys in both
files SHALL be preserved. The CI responder SHALL set the opt-out.

#### Scenario: a new workspace autostarts Remote Control

- **WHEN** a Coder workspace is created on a template whose `coder_script`
  starts Remote Control, with a valid claude.ai login in the shared volume
- **THEN** `claude-remote` reaches `/rc active` with no terminal interaction and
  every project `.mcp.json` server enabled except those listed in
  `disabledMcpjsonServers`.

#### Scenario: Remote Control is not started

- **WHEN** a container is created where nothing starts Remote Control
- **THEN** the first interactive `claude` session shows no onboarding, trust, or
  project-MCP prompt.

#### Scenario: the CI responder runs the lifecycle scripts

- **WHEN** `postCreateCommand.sh` runs with `AGENTDEV_SKIP_CLAUDE_PREAPPROVE`
  set
- **THEN** neither `~/.claude.json` nor `.claude/settings.local.json` is
  modified.

## ADDED Requirements

### Requirement: Remote Control inherits the Coder agent's environment

The Claude process in `claude-remote` SHALL receive the environment of the
process that ran `claude-remote-control-start.sh`, including when another tmux
server is live on the default socket. Started by the `coder_script`, it SHALL
carry the Coder user secrets and the agent's git credential helper.

#### Scenario: a GitHub token is a Coder user secret

- **WHEN** the workspace owner has a `GITHUB_TOKEN` env user secret and the
  `coder_script` starts `claude-remote`
- **THEN** `gh auth status` succeeds from the Remote Control session.

#### Scenario: a default tmux server is already running

- **WHEN** a tmux server is live on the default socket before the script runs
- **THEN** `claude-remote` starts on its own server and its Claude process
  receives the script's environment.
```

The spec's setup procedure changes with it: step 1 (`coder secret create` for
`AGENTDEV_CLAUDE_AUTOSTART`) becomes the template `coder_script` from Task 4;
step 2 starts the script by hand from a Coder terminal; step 3 and the
verification commands attach and list with `tmux -L claude-remote`.

## Verification

- `uv run pytest scripts/tests/test_claude_remote_control_start.py scripts/tests/test_preapprove_claude_workspace.py`
  passes; `shellcheck .devcontainer/scripts/claude-remote-control-start.sh` is
  clean.
- `grep -rn AGENTDEV_CLAUDE_AUTOSTART --exclude-dir=.git .` matches only plan
  documents.
- A container started by `devcontainer up` outside Coder runs no Claude process
  after postStart.
- Task 5's live checks pass in a Coder workspace on the updated template.

## Out of scope

- Autostart on non-Coder hosts (local VS Code, Codespaces); the script stays
  runnable there by hand but nothing starts it.
- A `GIT_ASKPASS` fallback in the `gh` wrapper: `GITHUB_TOKEN` is a Coder user
  secret, stable for the life of the agent, so an inherited copy does not go
  stale.
- Changes to `preapprove-claude-workspace.sh` beyond its test's ignore set.

## Key references

Verified anchor points (line numbers as of 2026-10-11):

- `.devcontainer/scripts/claude-remote-control-start.sh:13,25` — login-gate skip
  messages
- `.devcontainer/scripts/claude-remote-control-start.sh:29-50` — session name,
  `tmux -L claude-remote` `has-session` reuse, `tmux_start` launch
- `.devcontainer/devcontainer.json:256` — `"waitFor": "postStartCommand"`
- `scripts/tests/test_claude_remote_control_start.py:32-64` —
  `run_with_fake_tmux`
- `scripts/tests/test_claude_remote_control_start.py:77-80` —
  `assert_dedicated_socket`
- `scripts/tests/test_claude_remote_control_start.py:83-95` —
  `test_skips_without_live_claude_ai_login`
- `scripts/tests/test_claude_remote_control_start.py:98-99` —
  `test_compose_does_not_pass_setup_token`
- `scripts/tests/test_claude_remote_control_start.py:110-158` —
  `test_real_tmux_starts_claude_without_setup_token`
- `scripts/tests/test_preapprove_claude_workspace.py:18` — environment ignore
  set
- `docs/knowledge/data/codebase/devcontainer/scripts.md:42` — scripts table row
- `docs/knowledge/data/codebase/flow-devcontainer-lifecycle.md:44-50,71-75` —
  Remote Control lifecycle notes
- `coder-ide-baseline@577b5fa:template/main.tf:8` — `coder/coder` provider
  constraint
- `coder-ide-baseline@577b5fa:template/main.tf:12` — `kreuzwerker/docker`
  provider constraint
- `coder-ide-baseline@577b5fa:template/main.tf:186` — `code-server` module
  version
- `coder-ide-baseline@577b5fa:template/main.tf:44` — `local.repo_dir`
- `coder-ide-baseline@577b5fa:template/main.tf:193` — `coder_devcontainer.repo`
- `coder-ide-baseline@577b5fa:template/main.tf:202` — `coder_script.second_repo`
