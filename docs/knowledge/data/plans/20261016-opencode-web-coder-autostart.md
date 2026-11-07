---
type: plan
created: 2026-10-16
stage: done
completed: 2026-10-17
released: 2.0.0
release:
- features/opencode-web-coder-autostart
description: Start the OpenCode web UI from the Coder agent-start script, bound to localhost unless a server password is set, with OpenCode logins on the shared auth volume, its data directory on a per-worktree volume, a printed link that opens the workspace folder, and a Coder dashboard app that opens the web UI.
generated:
  by: claude-code/opus-5.5
  at: 2026-10-17T12:00:00Z
sources:
- resource: https://github.com/plume-works/agent-devcontainer/blob/2612a847/docs/knowledge/data/plans/20261016-opencode-web-coder-autostart.md
- resource: .devcontainer/scripts/coder-agent-start.sh
- resource: .devcontainer/scripts/claude-remote-control-start.sh
- resource: .devcontainer/scripts/link-codex-auth.sh
- resource: .devcontainer/devcontainer.json
- resource: https://github.com/sst/opencode/blob/733b2c627e5aec39cb33cc22373bdce33053ef2c/packages/opencode/src/auth/index.ts
- resource: https://github.com/sst/opencode/blob/733b2c627e5aec39cb33cc22373bdce33053ef2c/packages/opencode/src/cli/cmd/web.ts
- resource: https://github.com/sst/opencode/blob/733b2c627e5aec39cb33cc22373bdce33053ef2c/packages/opencode/src/server/server.ts
- resource: https://github.com/sst/opencode/blob/733b2c627e5aec39cb33cc22373bdce33053ef2c/packages/core/src/util/encode.ts
- resource: https://github.com/sst/opencode/blob/733b2c627e5aec39cb33cc22373bdce33053ef2c/packages/opencode/src/server/shared/public-ui.ts
- resource: https://github.com/plume-works/coder-ide-baseline/blob/473d64a/template/main.tf
- resource: https://coder.com/docs/admin/integrations/devcontainers/integration
---

# Autostart the OpenCode web UI on Coder

## Context

[OpenCode web UI autostart on
Coder](../features/opencode-web-coder-autostart.md) is the feature this plan
builds. Without a started server and a volume under its data directory,
`~/.local/share/opencode`, a Dev Container rebuild would lose OpenCode provider
logins and session chats.

[Agent auth
persistence](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/architecture/agent-auth-persistence.md)
is the split this plan extends to OpenCode: credentials on the shared
`agentdev-agents-auth` volume, path-bearing state on a per-instance volume.
[Coder IDE baseline
template](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/coder-ide-baseline.md)
makes `coder-agent-start.sh` the only start hook and the only place Coder user
secrets reach.

OpenCode v1.19.0 behavior this plan relies on:

- `auth.json` is rewritten in place (`fs.writeFile`, then `chmod 0600`) by every
  writer — CLI and web UI login and logout, OAuth callbacks, plugin token
  refresh — so a symlink at its path survives. Writes take no lock.
- `opencode web` serves the API and the web UI from one process. With no
  `OPENCODE_SERVER_PASSWORD` it serves unauthenticated and warns. It tries to
  open the UI in a browser and ignores a failure.
- Port 0 means "4096 if free, otherwise any port".
- The web UI opens a directory at `/<base64url(directory)>/session`, where the
  encoding is base64url with `=` padding stripped. Its project sidebar is kept
  in the browser's local storage; no server endpoint, configuration key, flag,
  or environment variable adds an entry to it.
- `GET /site.webmanifest` answers without the server password.

Coder v2.37.1 behavior this plan relies on: Coder does not apply the
`customizations.coder.apps` of `devcontainer.json` to a Dev Container the
template declares with `coder_devcontainer`, so a dashboard app for the Dev
Container's sub-agent is a `coder_app` in the
[plume-works/coder-ide-baseline](https://github.com/plume-works/coder-ide-baseline)
template. A subdomain `coder_app` joins every request path onto its `url`'s
path, so an app whose `url` carries a path proxies the page's root-relative
`/assets/…` requests below that path too.

## Approach

Six pieces, each following an existing pattern:

- **Login symlink.** `link-opencode-auth.sh` mirrors `link-codex-auth.sh`: it
  moves a regular `~/.local/share/opencode/auth.json` into
  `/root/.agents-auth/opencode/` and symlinks it back. It does not create the
  target; OpenCode's first login writes through the dangling link.
  `postCreateCommand.sh` and `postStartCommand.sh` run it, as they run the Codex
  one.
- **Per-worktree data volume.** `devcontainer.json` mounts a Compose-prefixed
  `agentdev-opencode` volume at `/root/.local/share/opencode`.
- **Server start.** `opencode-web-start.sh` mirrors the tmux handling of
  `claude-remote-control-start.sh`, minus its login gate: a detached session
  `opencode` on `tmux -L opencode` in the workspace folder, reused when live.
  The pane runs `opencode web --port 4096` with `--hostname 0.0.0.0` when
  `OPENCODE_SERVER_PASSWORD` is non-empty and `--hostname 127.0.0.1` otherwise.
  It skips when `opencode` or `tmux` is missing.
- **Coder wiring.** `coder-agent-start.sh` runs it after the credential helper
  and before the final `exec`; a failure warns and Remote Control still starts.
- **Direct link.** `opencode-web-start.sh` prints the server's base URL followed
  by `/<base64url(workspace folder)>/session`, both when it starts the session
  and when it finds one live, so the agent-start log carries a link that opens
  the workspace folder. The base URL is Coder's port URL for 4096:
  `VSCODE_PROXY_URI`, which the Coder agent sets to a template such as
  `https://{{port}}--repo--<workspace>--<owner><wildcard domain>`, with
  `{{port}}` replaced by `4096`. Where `VSCODE_PROXY_URI` is unset, the base URL
  is `http://127.0.0.1:4096`.
- **Dashboard app.** The template gains a `coder_app` named `OpenCode` on
  `coder_devcontainer.repo[0].subagent_id`, a subdomain app whose URL is the
  server root, `http://localhost:4096`, with a healthcheck on
  `http://localhost:4096/site.webmanifest`. It opens the web UI's project
  picker; the workspace folder is added there once per browser, and the printed
  link opens it directly. Every workspace with a repository gets it; where no
  OpenCode server runs, the healthcheck marks it unhealthy.

Assumptions:

- The pane runs with `DISPLAY` removed, so `opencode web` cannot open a browser
  window on the Xpra desktop at every workspace start.
- The port is passed explicitly, so a taken port fails the start rather than
  moving the server to a port Coder's forwarding does not expect.

Rejected:

- **Sharing the whole data directory across worktrees.** It holds a WAL-mode
  SQLite database and per-project snapshot repositories; concurrent containers
  writing one copy risk corruption.
- **Moving the data directory with `XDG_DATA_HOME`.** It moves every XDG-aware
  tool's data, not just OpenCode's, and still leaves logins unshared.
- **Starting from `postStartCommand.sh`.** It runs before the Coder agent
  exists, so the server would miss Coder user secrets, including
  `OPENCODE_SERVER_PASSWORD`.
- **Declaring the app in `devcontainer.json`.** Coder ignores those apps for a
  template-declared Dev Container.
- **Seeding the project sidebar.** It lives in browser storage, reachable only
  by a page on the server's own origin, which would need a proxy in front of
  `opencode web`.
- **A template parameter gating the app.** Repositories without an OpenCode
  server show an unhealthy app instead.
- **The workspace folder's path in the app's `url`.** The subdomain proxy
  prefixes every request with it, so the page's assets return the web UI's HTML
  and the page never loads.
- **An external app linking to the folder through the port URL.** The template
  would need the deployment's wildcard domain as new configuration; the
  maintainer chose the root app over it.
- **`/global/health` as the healthcheck.** It requires the server password once
  one is set.

## Implementation Steps

### Task 1: Share the OpenCode login through the auth volume

**Files:** Create: `.devcontainer/scripts/link-opencode-auth.sh`,
`scripts/tests/test_link_opencode_auth.py`; Modify:
`.devcontainer/scripts/postCreateCommand.sh`,
`.devcontainer/scripts/postStartCommand.sh`

- [x] Tests first, with the auth directory and data directory overridable by
  environment so no test touches `/root`:
  - no local file: the local path becomes a symlink to the shared target; the
    target is not created;
  - a regular local file: its content moves to the shared target, mode `0600`,
    and the local path becomes the symlink;
  - an existing symlink: a rerun leaves it pointing at the shared target and the
    target's content unchanged;
  - the shared directory ends at mode `0700`.
  - **Evidence:** commit "feat(devcontainer): share the OpenCode login through
    the auth volume": `scripts/tests/test_link_opencode_auth.py`, one test per
    case, overriding `HOME` and `AGENTDEV_AGENTS_AUTH_DIR`; all four fail before
    the script exists.
- [x] Script, shellcheck clean; the tests pass.
  - **Evidence:** commit "feat(devcontainer): share the OpenCode login through
    the auth volume": `link-opencode-auth.sh`; `shellcheck` clean;
    `uv run pytest scripts/tests/test_link_opencode_auth.py` 4 passed.
- [x] `postCreateCommand.sh` creates `/root/.agents-auth/opencode` beside the
  Claude and Codex directories and runs the script after `link-codex-auth.sh`;
  `postStartCommand.sh` runs it after `link-codex-auth.sh`.
  - **Evidence:** commit "feat(devcontainer): share the OpenCode login through
    the auth volume": both hooks call `link-opencode-auth.sh` right after
    `link-codex-auth.sh`; `shellcheck` clean on both.

### Task 2: Keep OpenCode's data directory on a per-worktree volume

**Files:** Modify: `.devcontainer/devcontainer.json`

- [x] Add a `mounts` entry `agentdev-opencode` → `/root/.local/share/opencode`,
  `type: volume`, after `agentdev-codex`, with a comment pointing at
  `architecture/agent-auth-persistence` and `link-opencode-auth.sh`.
  - **Evidence:** commit "feat(devcontainer): keep OpenCode's data directory on
    a per-worktree volume": the `agentdev-opencode` mount follows
    `agentdev-codex`;
    `bunx --bun json5 --validate .devcontainer/devcontainer.json` passes.

### Task 3: Start `opencode web` in a reusable tmux session

**Files:** Create: `.devcontainer/scripts/opencode-web-start.sh`,
`scripts/tests/test_opencode_web_start.py`

- [x] Tests first, against a fake `tmux` and a fake `opencode` in the manner of
  `test_claude_remote_control_start.py`:
  - no password: the pane command runs
    `opencode web --port 4096 --hostname 127.0.0.1` in the workspace folder,
    without `DISPLAY`;
  - `OPENCODE_SERVER_PASSWORD` set: `--hostname 0.0.0.0`, and the password
    reaches the pane's environment;
  - `OPENCODE_SERVER_PASSWORD` set but empty: `127.0.0.1`;
  - a live `opencode` session on `tmux -L opencode`: no new session, exit 0;
  - `opencode` or `tmux` missing: exit 0 with a skip message.
  - **Evidence:** commit "feat(devcontainer): start the OpenCode web UI in a
    reusable tmux session": `scripts/tests/test_opencode_web_start.py`; the
    fake-tmux cases cover the bind, reuse, and skip cases, and a real-tmux case
    shows the password reaching the pane without `DISPLAY`; all seven fail
    before the script exists.
- [x] Script, shellcheck clean; the tests pass.
  - **Evidence:** commit "feat(devcontainer): start the OpenCode web UI in a
    reusable tmux session": `opencode-web-start.sh`; `shellcheck` clean;
    `uv run pytest scripts/tests/test_opencode_web_start.py` 7 passed, the
    real-tmux case run.

### Task 4: Run the start script from the Coder agent start

**Files:** Modify: `.devcontainer/scripts/coder-agent-start.sh`,
`scripts/tests/test_coder_agent_start.py`

- [x] Tests: the call order is prune, credential helper,
  `opencode-web-start.sh`, Remote Control; a failing `opencode-web-start.sh`
  warns on stderr and Remote Control still starts; the OpenCode start sees the
  caller's environment.
  - **Evidence:** commit "feat(devcontainer): start the OpenCode web UI from the
    Coder agent start": `test_coder_agent_start.py` gains the
    `opencode-web-start.sh` fake, the call-order assertion, and two new tests;
    four fail against the previous script.
- [x] Script change; `uv run pytest scripts/tests/test_coder_agent_start.py`
  passes.
  - **Evidence:** commit "feat(devcontainer): start the OpenCode web UI from the
    Coder agent start": `coder-agent-start.sh` runs `opencode-web-start.sh`
    after the credential helper with a warn-and-continue guard; `shellcheck`
    clean; 6 passed.

### Task 5: Record OpenCode in the auth-persistence architecture

**Files:** Modify: `docs/knowledge/data/architecture/agent-auth-persistence.md`

- [x] The Decision section names OpenCode's shared `auth.json` symlink and its
  `agentdev-opencode` volume beside Claude and Codex, and Consequences records
  that concurrent OpenCode login writes are last-writer-wins.
  - **Evidence:** commit "docs(kb): record OpenCode in the agent auth
    persistence decision": both Decision bullets name OpenCode, and a new
    Consequences bullet records the in-place, lock-free `auth.json` write.

### Task 6: Refresh the codebase map

**Files:** Modify: `docs/knowledge/data/codebase/devcontainer/scripts.md`, and
any other `data/codebase/` doc `stale-map-docs.py` reports

- [x] Run `/agentdev:iwe-map` in refresh mode over the docs covering the changed
  scripts and `devcontainer.json`, adding rows for the two new scripts.
  - **Evidence:** commit "map: refresh devcontainer docs for the OpenCode web UI
    autostart": `data/codebase/devcontainer/scripts.md` gains rows for
    `link-opencode-auth.sh` and `opencode-web-start.sh`; `devcontainer` and
    `flow-devcontainer-lifecycle` re-digested; `stale-map-docs.py` ends
    `RESULT=SUCCESS`.

### Task 7: Verify in a live Coder workspace

- [x] On a Coder workspace whose checkout carries this change, after a rebuild:
  `tmux -L opencode capture-pane -p -t opencode` shows the web interface on port
  4096; the UI opens through Coder port forwarding; a provider connected from
  Settings appears in `/root/.agents-auth/opencode/auth.json` with
  `~/.local/share/opencode/auth.json` still a symlink; after a second rebuild
  the provider is still connected and the earlier session is listed.
  - **Evidence:** live check on Coder workspace `agent-dev3`, template version
    `motionless_ortega54`, OpenCode 1.19.0, 2026-10-17, checkout at commit "map:
    refresh devcontainer docs for the OpenCode web UI autostart". After the
    first rebuild the pane showed `Web interface: http://127.0.0.1:4096/`, the
    server listened on `127.0.0.1:4096` only, and the UI loaded through Coder's
    port link. An `openai` login from Settings wrote
    `/root/.agents-auth/opencode/auth.json` at mode `600` through the unchanged
    symlink. After the second rebuild, the sessions created before it were still
    in `opencode.db` on the `agentdev-opencode` volume, and new chats ran on the
    same `openai` login.

### Task 8: Verify the password-protected bind

- [x] With `OPENCODE_SERVER_PASSWORD` set as a Coder user secret and the
  workspace restarted, the server listens on `0.0.0.0:4096` and an
  unauthenticated request gets `401`.
  - **Evidence:** live check on Coder workspace `agent-dev3`, 2026-10-17, with
    the secret set and the workspace restarted: the agent-started server
    listened on `0.0.0.0:4096`; `GET /global/health` returned `401` without
    credentials on `127.0.0.1` and on the container's network address, and `200`
    with the password; `GET /site.webmanifest` returned `200` without
    credentials.

### Task 9: Print the direct link to the workspace folder

**Files:** Modify: `.devcontainer/scripts/opencode-web-start.sh`,
`scripts/tests/test_opencode_web_start.py`

- [x] Tests: with `DEV_WORKSPACE_FOLDER=/workspaces/example`, both a fresh start
  and a live-session reuse print the link, whatever the bind address:
  - `VSCODE_PROXY_URI=https://{{port}}--repo--ws--me.example.com`:
    `https://4096--repo--ws--me.example.com/L3dvcmtzcGFjZXMvZXhhbXBsZQ/session`;
  - the same template with a trailing `/`: the same link, with no `//`;
  - `VSCODE_PROXY_URI` unset or empty:
    `http://127.0.0.1:4096/L3dvcmtzcGFjZXMvZXhhbXBsZQ/session`;
  - a skip for a missing `opencode` or `tmux` prints no link.
  - **Evidence:** commit "feat(devcontainer): print a Coder link into the
    OpenCode workspace": `test_opencode_web_start.py` gains the start-and-reuse,
    trailing-slash, fallback, and skip cases; the seven link cases fail against
    the previous script.
- [x] Script, shellcheck clean;
  `uv run pytest scripts/tests/test_opencode_web_start.py` passes.
  - **Evidence:** commit "feat(devcontainer): print a Coder link into the
    OpenCode workspace": `opencode-web-start.sh` builds the link from
    `VSCODE_PROXY_URI` with the `127.0.0.1` fallback and prints it on start and
    reuse; `shellcheck` clean; 16 passed. With agent-dev3's `VSCODE_PROXY_URI`
    it yields the port URL that opened the workspace folder in the browser.

### Task 10: Refresh the codebase map for the link

**Files:** Modify: `docs/knowledge/data/codebase/devcontainer/scripts.md`, and
any other `data/codebase/` doc `stale-map-docs.py` reports

- [x] Run `/agentdev:iwe-map` in refresh mode; `stale-map-docs.py` ends
  `RESULT=SUCCESS`.
  - **Evidence:** commit "map: refresh the lifecycle scripts doc for the
    OpenCode workspace link": `data/codebase/devcontainer/scripts.md` describes
    the printed link and re-anchors `opencode-web-start.sh`; `devcontainer` and
    `flow-devcontainer-lifecycle` re-digested; `stale-map-docs.py` ends
    `RESULT=SUCCESS`.

### Task 11: Establish whether a subdomain app keeps the path in its URL

**Files:** none in this repository; a template version of
plume-works/coder-ide-baseline pushed without being made active

- [x] A template version carrying a subdomain `coder_app` whose `url` is
  `http://localhost:4096/<base64url("/workspaces/${local.repo_dir}")>/session`,
  pushed without promoting it, run on one workspace of this repository: opening
  the app either loads the web UI in `/workspaces/agent-devcontainer` with its
  assets served (subdomain form holds), or does not (the plan goes back to
  revise mode before Task 12). The workspace returns to the active version
  afterwards.
  - **Evidence:** live check on Coder workspace `agent-dev3`, 2026-10-17,
    inactive template version `opencode-app-probe` (Coder v2.37.1): the app
    registered on the `repo` sub-agent and was healthy, but the subdomain form
    does not hold. Coder joins every request path onto the app URL's path, so
    `/assets/index-*.js` and `/site.webmanifest` returned OpenCode's HTML page
    rather than the asset. `agent-dev3` was then updated back to
    `motionless_ortega54`.

### Task 12: Add the OpenCode app to the Coder template

**Files:** Modify: `template/main.tf` in plume-works/coder-ide-baseline

- [x] A `coder_app` `opencode`, display name `OpenCode`, counted like
  `module "vscode-web"`, on `coder_devcontainer.repo[0].subagent_id`, with
  `subdomain = true`, `share = "owner"`, `url = "http://localhost:4096"`, and
  the healthcheck from `## Approach`, merged to that repository's `main` by pull
  request and published as the active template version.
  - **Evidence:** plume-works/coder-ide-baseline PR #22, squash-merged as commit
    98f892b "feat(template): add an OpenCode app to the Dev Container sub-agent
    (#22)", its CI image builds passing; published from that commit as template
    version `opencode-app`, active since 2026-10-17.

### Task 13: Verify the OpenCode app in a live Coder workspace

- [x] On a workspace of this repository running the new template version, the
  dashboard's `OpenCode` app is healthy and loads the web UI with its assets
  served, and `/workspaces/agent-devcontainer` opens from its project picker; on
  a workspace of a repository whose agent-start script starts no OpenCode
  server, the app shows unhealthy.
  - **Evidence:** live check on 2026-10-17, template version `opencode-app`. On
    `agent-dev3` the app was healthy; through its subdomain the page, its
    `/assets/*.js` (`text/javascript`), and `/site.webmanifest` loaded with the
    server password, and a request without it got `401`. The maintainer opened
    the dashboard button and opened `/workspaces/agent-devcontainer` from the
    project picker. On `dr-qp-1` (Dr-QP/Dr.QP, no OpenCode server) the app
    reported `unhealthy`.

## Spec changes

A new spec, [OpenCode
web](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/opencode-web.md),
holds the server contract; it exposes a network service, so the full
requirements are stated. [Catalog
lifecycle](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/catalog-lifecycle.md)
widens its credential-sharing requirement to OpenCode. [Coder IDE baseline
template](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/coder-ide-baseline.md)
gains the OpenCode app.

``` markdown
## ADDED Requirements

### Requirement: the Coder agent start runs the OpenCode web UI

`coder-agent-start.sh` SHALL run `opencode-web-start.sh` on every agent start,
before Remote Control starts. The script SHALL start `opencode web` in exactly
one detached tmux session named `opencode` on the dedicated tmux server
`tmux -L opencode`, in the workspace folder, without checking for a provider
login. Repeated runs SHALL reuse a live session. It SHALL skip startup when
`opencode` or `tmux` is unavailable. A failure SHALL NOT stop Remote Control
from starting. On a start or a reuse it SHALL print
`<base>/<base64url(workspace folder)>/session`, base64url without `=` padding,
where `<base>` is `VSCODE_PROXY_URI` with `{{port}}` replaced by `4096` and any
trailing `/` removed, or `http://127.0.0.1:4096` when `VSCODE_PROXY_URI` is
unset or empty.

#### Scenario: a workspace starts

- **WHEN** the Coder agent starts and no `opencode` session is live
- **THEN** `opencode web` runs in the `opencode` session on `tmux -L opencode`.

#### Scenario: the agent start runs again

- **WHEN** the `opencode` session is already live
- **THEN** no second session or server starts.

#### Scenario: the start prints a link into the workspace folder

- **WHEN** the script starts or reuses the `opencode` session
- **THEN** its output carries the link built on Coder's port URL for 4096,
  which opens a session in the workspace folder through Coder.

#### Scenario: the start runs outside Coder

- **WHEN** `VSCODE_PROXY_URI` is unset
- **THEN** the printed link starts with `http://127.0.0.1:4096`.

#### Scenario: the OpenCode start fails

- **WHEN** `opencode-web-start.sh` exits non-zero
- **THEN** the agent start warns and Remote Control still starts.

### Requirement: the server is exposed only behind a password

The server SHALL listen on port 4096. It SHALL bind `0.0.0.0` only when
`OPENCODE_SERVER_PASSWORD` is non-empty in the agent's environment, and
`127.0.0.1` otherwise.

#### Scenario: no password is set

- **WHEN** `OPENCODE_SERVER_PASSWORD` is unset or empty
- **THEN** the server listens on `127.0.0.1:4096` only.

#### Scenario: a password is set

- **WHEN** `OPENCODE_SERVER_PASSWORD` is non-empty
- **THEN** the server listens on `0.0.0.0:4096` and rejects a request without
  the password.

### Requirement: OpenCode logins and chats survive a rebuild

`~/.local/share/opencode/auth.json` SHALL be a symlink to
`/root/.agents-auth/opencode/auth.json`, restored on every container create and
start, with a pre-existing regular file moved to the target first. The rest of
`~/.local/share/opencode` SHALL live on the per-instance `agentdev-opencode`
volume.

#### Scenario: a provider is connected and the container is rebuilt

- **WHEN** a provider is connected from the web UI's Settings and the Dev
  Container is rebuilt
- **THEN** the provider is still connected and earlier sessions are listed.

#### Scenario: a second worktree starts

- **WHEN** another worktree's Dev Container starts on the same host
- **THEN** it sees the same provider logins and none of the first worktree's
  sessions.

### Requirement: the template offers an OpenCode app

The `coder-ide-baseline` template SHALL attach a subdomain `coder_app` named
`OpenCode` to the Dev Container's sub-agent of every workspace with a
repository. Its URL SHALL be the server root, `http://localhost:4096`, and its
healthcheck SHALL request `http://localhost:4096/site.webmanifest`.

#### Scenario: the repository runs OpenCode

- **WHEN** the repository's agent-start script started `opencode web`
- **THEN** the dashboard shows a healthy `OpenCode` app that loads the web UI,
  from whose project picker `/workspaces/<repository>` opens.

#### Scenario: the repository runs no OpenCode server

- **WHEN** nothing listens on port 4096 in the Dev Container
- **THEN** the `OpenCode` app shows unhealthy.

## MODIFIED Requirements

### Requirement: only agent credentials are shared across worktrees

The `agentdev-agents-auth` volume SHALL hold only each agent's authentication
state (mounted at `/root/.agents-auth/<agent>`); all other plugin/install state
lives in the per-devcontainer-instance `agentdev-claude` / `agentdev-codex` /
`agentdev-opencode` volumes.

#### Scenario: two worktrees of the same repository are opened as separate devcontainers

- **WHEN** both attach
- **THEN** each gets its own catalog install (scoped per instance) but shares
  the same logged-in Claude/Codex/OpenCode credentials (scoped to the shared
  auth volume).
```

## Verification

- `uv run pytest scripts/tests/test_link_opencode_auth.py scripts/tests/test_opencode_web_start.py scripts/tests/test_coder_agent_start.py`
  passes.
- `shellcheck` is clean on the new and changed scripts.
- Tasks 7, 8, 11, and 13 pass on live Coder workspaces.
- `iwe normalize` and `iwe schema validate` pass.

## Verification results

- **A second worktree starts.** On 2026-10-17 the maintainer opened two local
  Dev Containers of this repository on one host, `agent-devcontainer` and a
  second worktree, OpenCode 1.19.2. Each ran `coder-agent-start.sh`. The second
  worktree's web UI showed the OpenAI provider connected and answered a chat on
  it, and it listed none of the first worktree's sessions.

## Out of scope

- **Picking up catalog changes in a running server.** Coder-started servers keep
  the catalog they read at start until restart; the feature records this as an
  edge case.
- **Locking concurrent `auth.json` writes.** OpenCode takes no lock; this plan
  accepts last-writer-wins.
- **Autostart outside Coder.** Local Dev Containers and CI do not start the
  server.
- **Firewall entries for OpenCode.** The firewall stays opt-in and untouched.
- **Adding the workspace folder to the web UI's project sidebar.** It stays a
  one-time "Add project" per browser; the feature records this as an edge case.

## Key references

Verified anchor points (line numbers as of 2026-10-17):

- `.devcontainer/scripts/coder-agent-start.sh:9-21` — prune, credential helper,
  OpenCode start, `exec` of Remote Control
- `.devcontainer/scripts/opencode-web-start.sh:13` — `workspace`; `:29-32` —
  live-session reuse; `:48` — start message
- `.devcontainer/scripts/claude-remote-control-start.sh:29` — `session`; `:37` —
  live-session check; `:43` — `tmux_start`
- `.devcontainer/scripts/link-codex-auth.sh:19-31` — move-then-symlink of a
  shared `auth.json`
- `.devcontainer/scripts/postCreateCommand.sh:72-73` — shared auth
  subdirectories; `:79` — `link-codex-auth.sh`
- `.devcontainer/scripts/postStartCommand.sh:27` — `link-codex-auth.sh`
- `.devcontainer/devcontainer.json:60` — `mounts`; `:97-99` — `agentdev-codex`
  mount
- `scripts/tests/test_coder_agent_start.py:14` — `run_agent_start`; `:47` —
  call-order test
- `scripts/tests/test_claude_remote_control_start.py:33` — `run_with_fake_tmux`
- `docs/knowledge/data/spec/catalog-lifecycle.md:122` — credential-sharing
  requirement
- plume-works/coder-ide-baseline `template/main.tf:207-211` (commit 473d64a) —
  `coder_devcontainer.repo`; `:215-223` — `module "vscode-web"` on the
  sub-agent; `:227-239` — `coder_script.agent_start`
