---
type: plan
created: 2026-10-11
description: Run setup-gh-credential-helper.sh from a repo-owned Coder agent-start script that the template coder_script calls, so a Coder workspace whose gh login is only GITHUB_TOKEN gets gh as its github.com git credential helper; post-start keeps running it too.
generated:
  by: claude-code/opus-5.5
  at: 2026-10-11T21:30:00Z
sources:
- resource: https://github.com/plume-works/agent-devcontainer/blob/2612a847/docs/knowledge/data/plans/20261011-coder-agent-gh-credential-helper.md
- resource: .devcontainer/scripts/setup-gh-credential-helper.sh
- resource: .devcontainer/scripts/postStartCommand.sh
- resource: .devcontainer/scripts/claude-remote-control-start.sh
- resource: scripts/tests/test_setup_gh_credential_helper.py
- resource: https://github.com/plume-works/coder-ide-baseline/blob/349d8d6/template/main.tf
stage: done
completed: 2026-10-12
released: 2.0.0
---

# Configure the gh credential helper from the Coder agent

## Context

[Bug: HTTPS git push hangs on Coder's askpass when gh's login is only a session
token](../bugs/coder-askpass-push-hang.md). Post-start configures `gh` as the
github.com credential helper only when `gh` is authenticated at that moment. In
a Coder workspace, post-start runs inside `devcontainer up`, before the Coder
agent is injected into the Dev Container. It never sees the Coder user secret
`GITHUB_TOKEN`, so it skips and writes no helper. Sessions started under the
agent do have `GITHUB_TOKEN`, but git has no helper for github.com. It falls
back to `GIT_ASKPASS=/.coder-agent/coder`, which never returns, so `git push`
hangs.

A process started by the template's `coder_script` on the Dev Container's
sub-agent inherits the agent's environment, including `GITHUB_TOKEN`. That
`coder_script` already runs `claude-remote-control-start.sh`.

## Approach

Add a repo-owned `.devcontainer/scripts/coder-agent-start.sh`, the single entry
point the Coder agent runs on every start. It runs
`setup-gh-credential-helper.sh`, then execs `claude-remote-control-start.sh`. A
failed helper setup is reported and does not stop Remote Control from starting.
The template names the agent-start script in a workspace parameter whose default
is `.devcontainer/scripts/coder-agent-start.sh`, relative to the repository
root, so another repository can point it at its own script. The `coder_script`
runs that path and nothing else, so the template carries no knowledge of this
repository's scripts; a checkout that does not ship the configured script starts
nothing. Later agent-start steps then land in this repository, not the template.

Post-start keeps running `setup-gh-credential-helper.sh` (maintainer decision).
That still covers containers where `gh` has a stored login: local Dev Containers
and Codespaces. The script is idempotent, because it keeps any existing
github.com helper, so running it twice in a Coder workspace is harmless.

Rejected:

- Calling the helper setup from `claude-remote-control-start.sh`. That ties git
  credentials to the Remote Control script and to its claude.ai login gate.
- A second template `coder_script` that runs the helper directly. That splits
  agent-start logic across two repositories.

## Implementation Steps

### Task 1: Agent-start script

**Files:** Create: `.devcontainer/scripts/coder-agent-start.sh`,
`scripts/tests/test_coder_agent_start.py`

- [x] Tests first (pytest, fake `setup-gh-credential-helper.sh` and
  `claude-remote-control-start.sh` placed beside a copy of the script). Cover:
  - the helper setup runs before Remote Control;
  - Remote Control still starts, and the script exits 0, when the helper setup
    exits non-zero;
  - the helper setup sees the caller's environment (a `GITHUB_TOKEN` set by the
    caller reaches it).
  - **Evidence:** `scripts/tests/test_coder_agent_start.py` (three tests, one
    per case) in the commit that adds `coder-agent-start.sh`; replacing the
    helper call with `false` fails two of them.
- [x] Script: `#!/usr/bin/env bash`, `set -euo pipefail`. Run
  `"$script_dir/setup-gh-credential-helper.sh"`. On failure, print a one-line
  warning to stderr and continue. Then
  `exec "$script_dir/claude-remote-control-start.sh"`. Executable bit set;
  `shellcheck` clean; the tests pass.
  - **Evidence:** `.devcontainer/scripts/coder-agent-start.sh` (mode 100755) in
    the commit `feat(devcontainer): add the Coder agent-start script`;
    `shellcheck` clean;
    `uv run pytest scripts/tests/test_coder_agent_start.py scripts/tests/test_setup_gh_credential_helper.py`
    9 passed.

### Task 2: Refresh the codebase map

**Files:** Modify: `docs/knowledge/data/codebase/devcontainer/scripts.md`, and
any other `data/codebase/` doc that `stale-map-docs.py` reports

- [x] Run `/agentdev:iwe-map` in refresh mode over the touched docs. The scripts
  table lists `coder-agent-start.sh` as the Coder agent's entry point.
  - **Evidence:** commit `b227e33` (#318) updates
    `data/codebase/devcontainer/scripts`, `flow-devcontainer-lifecycle`, and
    `devcontainer`; `stale-map-docs.py` ends `RESULT=SUCCESS`.

### Task 3: Template runs the agent-start script

**Files:** Modify (in `plume-works/coder-ide-baseline`): `template/main.tf`

- [x] After Tasks 1–2 merge, add `data.coder_parameter.agent_start_script`,
  shaped like `data.coder_parameter.second_repo`: `type = "string"`,
  `mutable = true`, `default = ".devcontainer/scripts/coder-agent-start.sh"`,
  and a description saying that the path is relative to the repository root and
  that an empty value runs nothing. `coder_script.claude_remote_control` becomes
  `coder_script.agent_start` with `display_name = "Dev Container agent start"`.
  Its script runs `/workspaces/${local.repo_dir}/<parameter value>` when the
  value is non-empty and the file is executable. Otherwise it prints that the
  repository ships no agent-start script. Update the comment above the resource,
  which says Remote Control inherits the agent's git credential helper.
  `terraform validate` passes and the template version is pushed.
  - **Evidence:**
    [plume-works/coder-ide-baseline#20](https://github.com/plume-works/coder-ide-baseline/pull/20)
    was squash-merged as `ab1c595` after its Docker Build and Push check passed;
    `terraform fmt -check` and `terraform validate` pass under Terraform 1.13.5.
    `TEMPLATE_NAME=coder-ide-baseline template/push.sh` at `ab1c595` created
    `lingering_bell82`, the active version (2026-10-12).

### Task 4: Verify in a live Coder workspace

**Files:** none

- [x] In a Coder workspace on the new template version, after a restart, with
  `GITHUB_TOKEN` supplied only as a Coder user secret: the agent-start script's
  log shows `Configured gh as the git credential helper.`, and inside the Dev
  Container `git config --get-urlmatch credential.helper https://github.com`
  prints the gh helper. A plain `git push` of a scratch branch from a Coder
  terminal and from the Remote Control session completes without waiting. The
  scratch branch is then deleted with `git push --delete`.
  - **Evidence:** `anton/agent-dev2` (2026-10-12), with its checkout at
    agent-devcontainer `ce089de` and gh logged in only through the
    `GITHUB_TOKEN` user secret, was restarted by `coder update` onto
    `lingering_bell82` with the default `agent_start_script`. The agent-start
    log printed `Configured gh as the git credential helper.` and started
    `claude-remote`, and the urlmatch printed
    `!/usr/bin/gh auth git-credential`. With `GIT_ASKPASS=/.coder-agent/coder`
    still set, plain `git push` of a scratch branch exited 0 in seconds from
    `coder ssh agent-dev2.repo` and from a `!git push` inside the Remote Control
    session. Both branches were deleted with `git push --delete`.

## Spec changes

[Devcontainer Git
credentials](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/devcontainer-git-credentials.md):
the helper requirement gains the Coder agent start as a second trigger.

``` markdown
## MODIFIED Requirements

### Requirement: HTTPS git uses the gh login

When `gh` is authenticated to github.com and no git credential helper matches
`https://github.com`, post-start SHALL configure `gh` as the helper, and so
SHALL `coder-agent-start.sh`, which the Coder template's `coder_script` runs on
every agent start. Both SHALL check authentication only after the keyring
session is available, so git never waits at an interactive credential prompt.
An existing helper SHALL be kept. A failed helper setup SHALL NOT stop
`coder-agent-start.sh` from starting Remote Control.

#### Scenario: gh's only login is a Coder user secret

- **WHEN** a Coder workspace supplies `GITHUB_TOKEN` as a user secret, `gh` has
  no stored login, and the agent starts
- **THEN** `coder-agent-start.sh` configures `gh` as the github.com helper, and
  `git push` over HTTPS completes without a prompt.

#### Scenario: gh has a stored login outside Coder

- **WHEN** a container whose `gh` login is stored on disk or in the keyring
  starts
- **THEN** post-start configures `gh` as the github.com helper.

#### Scenario: a helper is already configured

- **WHEN** a git credential helper already matches `https://github.com`
- **THEN** neither post-start nor `coder-agent-start.sh` changes it.

#### Scenario: helper setup fails at agent start

- **WHEN** `setup-gh-credential-helper.sh` exits non-zero during
  `coder-agent-start.sh`
- **THEN** a warning is printed and `claude-remote-control-start.sh` still runs.
```

## Verification

- `uv run pytest scripts/tests/test_coder_agent_start.py scripts/tests/test_setup_gh_credential_helper.py`
- `shellcheck .devcontainer/scripts/coder-agent-start.sh`
- `terraform validate` in `coder-ide-baseline/template`.
- Task 4's live check. Until [Persist the Coder workspace containerd image
  store](20261011-persist-coder-workspace-containerd.md) ships, a workspace
  restart needs the workaround in [Bug: Coder workspace Dev Container is lost on
  restart](../bugs/coder-devcontainer-lost-on-restart.md).

## Out of scope

- Removing the helper setup from post-start.
- Installing the helper whether or not `gh` is authenticated (the bug's other
  candidate fix). That would change the "when `gh` is authenticated" condition.
- Changing Coder's `GIT_ASKPASS` or configuring Coder external auth for GitHub.

## Key references

Verified anchor points (line numbers as of 2026-10-12):

- `.devcontainer/scripts/postStartCommand.sh:15` — post-start runs
  `setup-gh-credential-helper.sh` after the keyring
- `.devcontainer/scripts/setup-gh-credential-helper.sh:19` — the
  `gh auth status` gate that skips without a login
- `.devcontainer/scripts/setup-gh-credential-helper.sh:24` — keeps an existing
  github.com helper
- `.devcontainer/scripts/setup-gh-credential-helper.sh:30` — `gh auth setup-git`
- `scripts/tests/test_setup_gh_credential_helper.py:92` —
  `test_post_start_runs_setup_after_keyring`
- `docs/knowledge/data/codebase/devcontainer/scripts.md:103` — the keyring
  ordering note for the helper script
- `plume-works/coder-ide-baseline` `template/main.tf:95` (at `1e3ace5`) —
  `data.coder_parameter.second_repo`, the parameter shape to copy
- `plume-works/coder-ide-baseline` `template/main.tf:213` (at `1e3ace5`) —
  `coder_script.claude_remote_control`, the resource Task 3 replaces
