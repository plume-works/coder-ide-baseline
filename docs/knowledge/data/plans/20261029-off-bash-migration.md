---
type: plan
created: 2026-10-29
release:
- features/agentdev-runtime-cli
- bugs/workspace-image-lacks-hook-binaries
- bugs/remote-control-watcher-start-loop
- bugs/doctor-fails-healthy-coder-devcontainer
description: Replace the runtime's shell scripts, the Xpra launcher, the firewall script, and two publisher scripts with one agentdev-runtime Python CLI packaged as an embedded uv tool in the runtime images, and remove the Codex Cloud bootstrap.
generated:
  by: claude-code/opus-5.5
  at: 2026-10-31T21:00:00Z
sources:
- resource: https://github.com/plume-works/agent-devcontainer/blob/2612a847/docs/knowledge/data/plans/20261029-off-bash-migration.md
- resource: .devcontainer/scripts/
- resource: docker/devcontainer/agentdev-devcontainer.Dockerfile
- resource: docker/deploy/agentdev-deploy.Dockerfile
- resource: docker/devcontainer/supervisord.conf
- resource: docker/deploy/supervisord.conf
- resource: ansible/roles/validate_agent_files/tasks/main.yml
- resource: ansible/roles/devcontainer_firewall/files/init-firewall.sh
- resource: docker/desktop/start-xpra.sh
- resource: .github/actions/run-claude-responder/action.yml
- resource: docs/knowledge/data/architecture/ci-agent-plugin-availability.md
- resource: docs/knowledge/data/plans/20260905-python-skill-scripts.md
- resource: docs/knowledge/data/bugs/workspace-image-lacks-hook-binaries.md
- resource: .pre-commit-config.yaml
- resource: docs/knowledge/data/bugs/doctor-fails-healthy-coder-devcontainer.md
- resource: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idcontaineroptions
- resource: https://github.com/anthropics/claude-code-action/blob/v1/action.yml
stage: done
completed: 2026-10-31
released: 2.0.0
---

# Replace the runtime shell scripts with one agentdev-runtime CLI

## Context

[agentdev-runtime
CLI](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/features/agentdev-runtime-cli.md)
is the feature this plan implements. [Publish the reusable agentdev Dev
Container
image](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/plans/20261023-reusable-agentdev-devcontainer.md)
moved the lifecycle into the `agentdev-devcontainer` and `agentdev-deploy`
images and sealed it under `/opt/agentdev-runtime`; consumers no longer copy
`.devcontainer/scripts/`. The constraint that kept those scripts shell, a
template artifact that had to run on a stock image, no longer binds the runtime.
[Python skill
scripts](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/plans/20260905-python-skill-scripts.md)
recorded that constraint and the rule that inline Python inside bash is neither
testable nor lintable.

Before this plan the runtime was 41 shell scripts (2647 lines) beside a
1133-line Python supervisor. The scripts read 54 distinct `AGENTDEV_*` settings
against the supervisor's 23, each file declaring its own defaults, and one
variable defaulted to two different paths in two files. The supervisor wrote
`state.json` in Python and `runtime-health.sh` parsed it back with jq. Fourteen
scripts were subcommand dispatchers, and thirteen called one another through
`$script_dir/<name>.sh`, with the environment as the parameter list. Three
scripts ran under `uv run --script` and resolved `tomlkit` and `json5` from PyPI
the first time they ran, inside the deploy profile's core `prepare` phase. A
second, no-supervisor start path for GitHub `container:` jobs and Codex Cloud
kept `setup-keyring.sh`, `codebase-memory-mcp-start.sh`, and `firewall.sh` alive
beside their supervised twins ([CI agent plugin
availability](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/architecture/ci-agent-plugin-availability.md)).
The Codex Cloud bootstrap is removed at the user's decision.

The user decided that the Coder template's agent-start parameter becomes a
command defaulting to `agentdev-runtime coder start`, since a CLI subcommand is
no path the template can test for; the template maps the legacy script path that
existing workspaces stored onto that default.

The user decided that the AI responder installs `agentdev-runtime` from the
checkout when its pinned image lacks it, so the responder keeps working, on this
plan's own pull request and after merge, until the image pin moves to an image
built with the CLI.

The user's decisions for this plan: one Python package installed as a uv tool
the way `validate_agent_files` is; one CLI rather than per-script shims; the
catalog's scripts in their own plan, [Port the catalog's bundled shell scripts
to
Python](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/plans/20261029-catalog-scripts-python.md);
a CBM-only start when no supervisor is present, with the legacy no-supervisor
starters deleted; the firewall script ported rather than wrapped; and the
detection that [Bug: a workspace on a pre-pin image has no gitleaks or
actionlint and nothing says
so](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/bugs/workspace-image-lacks-hook-binaries.md)
asks for, carried by `doctor` and `project hooks`, one of this plan's two
behaviour changes; the other is Task 21's `doctor` checks.

Three other open bugs sit in scripts this plan ports. [Bug: the Remote Control
watcher restarts a session that never comes up on every
tick](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/bugs/remote-control-watcher-start-loop.md)
is fixed in shell as Task 10, before the Remote Control port, so the port's
baseline carries the fix. [Bug: a CBM daemon start failure latches the
standalone runtime
degraded](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/bugs/cbm-start-failure-latches-degraded.md)
and [Bug: Codex login stops being shared between standalone
projects](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/bugs/standalone-codex-auth-unshared.md)
have no settled root cause and are fixed after the port, in the package.

## Approach

One package, `py_packages/agentdev_runtime/`, with its own `pyproject.toml`,
test suite, and one console script, `agentdev-runtime`. Both runtime Dockerfiles
install it with `uv tool install` from the bind-mounted build context onto the
system interpreter, into `/opt/uv-tools` with the entry point on
`/usr/local/bin`, no cache and no interpreter download, mirroring the validator
role. The package pins `supervisor`, `tomlkit`, `json5`, `pyyaml`, and
`setuptools<85`; the apt `supervisor` package leaves both images.
`agentdev-base` stays lifecycle-neutral and never carries the package.

Every script becomes a subcommand of one CLI whose nouns are the runtime's
concerns. One settings module parses every environment value once, with one
default per variable, keyed by profile where the profiles differ. One state
module defines the `state.json`, retry, and failure-record shapes for writer and
reader alike. Except for the two changes below, behaviour behind each command is
unchanged; this plan changes language and packaging, not policy, so every
existing scenario in the affected specs holds as written.

The first exception is the hook-binary detection. After registering the hooks,
`project hooks` warns about each `language: system` hook in the checkout's
`.pre-commit-config.yaml` whose `entry` executable is not on `PATH`, and
`doctor` requires `gitleaks` and `actionlint` in its toolchain section. A
missing hook executable is a warning, not a failure, in both profiles, so a
consumer whose own hooks need tools the image lacks still starts; reading the
hook configuration is why the package needs `pyyaml`.

`doctor` also judges a healthy Compose Dev Container healthy, which the user
directed. Compose passes `COMPOSE_PROFILES` from `.devcontainer/.env` into the
container, and `doctor` checks the `mcp-gateway` sidecar only when that names
the opt-in `mcp` profile, reporting it SKIP otherwise. Its `git user` check
accepts whatever identity git itself resolves for author and committer, so the
`GIT_AUTHOR_*` and `GIT_COMMITTER_*` values Coder sets count.

The migration is incremental. The package installs beside the scripts first, PID
1 and the healthcheck switch to the CLI next, and each service then moves with
its supervisord `command=` and its tests, so the image boots at every task
boundary. The last runtime task removes the `COPY` of the script tree and the
sha256 manifest; integrity moves to the installed distribution's `RECORD`
hashes, which, like the manifest, catches accidental edits by a derived image
but is not a security boundary.

A container with no supervisor socket runs `lifecycle ready --no-wait`, one
function that starts the CBM daemon and then the per-start repairs. Nothing else
starts there: a review job needs CBM and the checkout catalog and never the
keyring, firewall, or a desktop. A GitHub `container:` job runs no image
entrypoint and accepts no `--entrypoint` option, and `claude-code-action` is a
composite action that runs in the job's own runtime, so the supervisor can never
be PID 1 there; this function is the supported start for such a job.

The firewall and the Xpra launcher join the package. The firewall runs as root
from the bootstrap in both profiles, so its sudoers entry and the script in the
Ansible role go; the role keeps the packages. A set `FIREWALL_ALLOWLIST` names
the allowlist in both profiles, as `init-firewall.sh` let it. Unset, the
devcontainer profile reads the checkout's allowlist when present, as
`spec/firewall` promises, and the image copy otherwise; deploy keeps the image
copy.

Rejected: loose stdlib scripts on the system interpreter, which keeps either the
runtime PyPI fetch or an apt dependency hunt and keeps the file manifest; bash
shims preserving the `/opt/agentdev-runtime/*.sh` names, which the user ruled
out in favour of one CLI; porting the legacy no-supervisor starters, which would
preserve a second start path nobody needs; keeping `init-firewall.sh` as bash
behind a Python wrapper, which the user ruled out; starting the supervisor as a
background process inside the responder's container job, which needs a
privileged job container for the profile's core `dockerd` and buys only the
deletion of this one function; and running the responder as a host job through
`devcontainers/ci`, which gives the supervisor PID 1 but loses
`claude-code-action` and its `claude[bot]` authentication.

## Implementation Steps

### Task 1: Install the package beside the scripts

**Files:** Create: `py_packages/agentdev_runtime/pyproject.toml`,
`py_packages/agentdev_runtime/README.md`,
`py_packages/agentdev_runtime/agentdev_runtime/__init__.py`,
`py_packages/agentdev_runtime/agentdev_runtime/cli.py`,
`py_packages/agentdev_runtime/agentdev_runtime/settings.py`,
`py_packages/agentdev_runtime/tests/test_settings.py`,
`py_packages/agentdev_runtime/tests/test_cli.py`; Modify: `pyproject.toml`,
`uv.lock`, `.dockerignore`, `docker/deploy/agentdev-deploy.Dockerfile`,
`docker/devcontainer/agentdev-devcontainer.Dockerfile`

- [x] The package declares `requires-python >= 3.12`, the console script
  `agentdev-runtime`, and dependencies `supervisor==4.3.0`, `setuptools<85`,
  `tomlkit`, `json5`, and `pyyaml`. The root project takes the package as an
  editable dev dependency and drops its direct `supervisor` and `setuptools`
  pins; `uv.lock` is regenerated.
  - **Evidence:** commit cfaac26; `uv lock` and `uv sync` resolve the package
    editable; `uv run pytest py_packages/agentdev_runtime` passes (26 tests).
- [x] Both runtime Dockerfiles install the package with
  `uv tool install --reinstall --python /usr/bin/python3` from the bind-mounted
  build context, with `UV_TOOL_DIR=/opt/uv-tools`,
  `UV_TOOL_BIN_DIR=/usr/local/bin`, `UV_NO_CACHE=1`,
  `UV_PYTHON_DOWNLOADS=never`, and `UV_LINK_MODE=copy`. `.dockerignore` admits
  `py_packages/agentdev_runtime`. The `COPY .devcontainer/scripts/` lines stay
  until Task 14.
  - **Evidence:** commit cfaac26; both images build locally on
    `agentdev-base:edge`, where `agentdev-runtime` resolves to `/usr/local/bin`
    and `/opt/uv-tools/agentdev-runtime/bin/python` imports `supervisor`,
    `tomlkit`, `json5`, and `yaml`.
- [x] `settings.py` parses every environment value the scripts and the
  supervisor read, with one default per variable, keyed by profile where the
  profiles differ; the package README lists each variable, its default, and the
  profiles that read it.
  - **Evidence:** commit cfaac26;
    `py_packages/agentdev_runtime/tests/test_settings.py` checks the profile
    keying and that the README lists every declared variable, passing under
    `uv run pytest py_packages/agentdev_runtime`.

### Task 2: Boot PID 1 and the healthcheck through the CLI

**Files:** Create:
`py_packages/agentdev_runtime/agentdev_runtime/supervisor.py`,
`py_packages/agentdev_runtime/agentdev_runtime/health.py`,
`py_packages/agentdev_runtime/agentdev_runtime/state.py`,
`py_packages/agentdev_runtime/tests/test_state.py`; Modify:
`docker/deploy/agentdev-deploy.Dockerfile`,
`docker/devcontainer/agentdev-devcontainer.Dockerfile`,
`docker/deploy/supervisord.conf`, `docker/devcontainer/supervisord.conf`,
`scripts/tests/test_agent_runtime_supervision.py`,
`scripts/tests/test_agent_runtime_profiles.py`,
`scripts/tests/test_agent_runtime_state.py`,
`scripts/tests/test_agent_runtime_ci.py`; Delete:
`.devcontainer/scripts/runtime-supervisor.py`,
`.devcontainer/scripts/runtime-health.sh`

- [x] `runtime-supervisor.py` becomes
  `agentdev-runtime supervisor run|control|exec|retry` with its behaviour
  unchanged; the `state.json`, retry-request, and failure-record shapes live in
  `state.py` and are the only way the package reads or writes them.
  - **Evidence:** commit facf454; `test_agent_runtime_supervision.py`,
    `test_agent_runtime_profiles.py`, and `test_state.py` pass through the CLI,
    and the deploy acceptance suite passes (24, one skipped for want of a
    previous image) against `agentdev-deploy` built from that commit.
- [x] `runtime-health.sh` becomes
  `agentdev-runtime health <service>|ready|status`, reading state through
  `state.py`; user-scope probes still re-exec as the runtime user; probes call
  the service modules as they land and the remaining scripts until then.
  - **Evidence:** commit facf454; the supervision tests' `health ready` and
    `health status` cases pass, and the deploy acceptance suite and
    `test_agentdev_devcontainer_image.py` (5 passed) pass against images built
    from that commit, whose user-scope probes run as the runtime account.
- [x] `ENTRYPOINT`, `HEALTHCHECK`, the controller listener, and every `command=`
  in both supervisord configurations name the CLI, and the `exec` wrapper keeps
  its output capture and failure record. Both images stop installing the apt
  `supervisor` package, which PID 1 needs until it runs from the CLI.
  - **Evidence:** commit facf454;
    `test_shipped_config_runs_user_services_unprivileged_and_logs_to_stdout` and
    the failure-record supervision tests pass, and both images built from that
    commit boot to ready in the acceptance and image suites. The same commit
    adds `py_packages/agentdev_runtime/**` to the image path filter, points
    `ci.yml`, `devcontainer-ready.sh`, and `environment-health.sh` at the CLI,
    and renames the deleted paths in the later tasks' lifecycle, image,
    repository, migration, and acceptance tests.

### Task 3: Bootstrap and distribution integrity

**Files:** Create: `py_packages/agentdev_runtime/agentdev_runtime/bootstrap.py`,
`py_packages/agentdev_runtime/agentdev_runtime/integrity.py`,
`py_packages/agentdev_runtime/tests/test_integrity.py`; Modify:
`scripts/tests/test_agent_runtime_identity.py`,
`scripts/tests/test_agentdev_devcontainer_image.py`,
`docker/devcontainer/agentdev-devcontainer.Dockerfile`; Delete:
`.devcontainer/scripts/runtime-bootstrap.sh`

- [x] `agentdev-runtime bootstrap` reproduces both profiles: identity validation
  and account reuse or creation, the sudoers entry through `visudo`,
  instance-storage claims that chown only an empty mount root, the shared-auth
  lock, the runtime-directory reset, and the docker group. Account and privilege
  changes stay subprocess calls to `groupadd`, `useradd`, `usermod`, `visudo`,
  and `setpriv`.
  - **Evidence:** commit c8fff30; `test_agent_runtime_identity.py` (19 passed)
    runs the bootstrap from source in containers for both profiles, and the
    deploy acceptance suite (24 passed, one skipped for want of a previous
    image) passes against `agentdev-deploy` built from that commit.
- [x] `integrity.py` verifies the installed `agentdev_runtime` distribution
  against its `RECORD` hashes and file set before the bootstrap continues, and
  refuses with the remedy `integrity.REMEDY` names, extending the runtime only
  through `/etc/agentdev/hooks` and documented environment. The sha256 manifest
  step leaves the Dockerfile, and the derived-image test patches a package file
  instead of a script.
  - **Evidence:** commit c8fff30; `test_integrity.py` covers patched, added, and
    removed files, a patched entry point, and a missing `RECORD`;
    `test_a_derived_image_cannot_replace_the_managed_runtime` passes in
    `test_agentdev_devcontainer_image.py` (5 passed) against
    `agentdev-devcontainer` built from that commit. Commit 0cd36222 refuses a
    deleted `METADATA` and bytecode for no recorded module:
    `test_a_removed_metadata_file_is_refused` and
    `test_bytecode_for_no_recorded_module_is_refused` pass under
    `uv run pytest py_packages/agentdev_runtime` (91 passed).

### Task 4: Firewall

**Files:** Create: `py_packages/agentdev_runtime/agentdev_runtime/firewall.py`,
`py_packages/agentdev_runtime/tests/test_firewall_allowlist.py`; Modify:
`ansible/roles/devcontainer_firewall/tasks/main.yml`,
`scripts/tests/test_agent_runtime_firewall.py`; Delete:
`ansible/roles/devcontainer_firewall/files/init-firewall.sh`,
`ansible/roles/devcontainer_firewall/files/devcontainer-firewall-sudoers`,
`.devcontainer/scripts/runtime-firewall.sh`, `.devcontainer/scripts/firewall.sh`

- [x] `agentdev-runtime firewall apply` reproduces `init-firewall.sh` and
  `runtime-firewall.sh`: the `ENABLE_FIREWALL` gate, allowlist validation,
  Docker DNS rule capture and restore, host SSH, loopback, the `allowed-domains`
  ipset from resolved A records and GitHub meta ranges collapsed with
  `ipaddress`, default DROP, established, allowlist accept, reject, the IPv6
  block, the `DOCKER-USER` chain, deploy proxy ingress, and the two
  self-verification requests. `iptables` and `ipset` run as argument lists
  through subprocess.
  - **Evidence:** commit 052196c; `test_agent_runtime_firewall.py` (14 passed)
    checks the rule sequence against a fake system and, in
    `test_proxy_ingress_egress_and_nested_docker_together`, applies the real
    rules in a privileged container on the pinned Dev Container image: egress
    blocked, GitHub and nested pulls allowed, proxy-only ingress. Deploy
    acceptance (24 passed) and the Dev Container image suite (5 passed) pass
    against images built from merge ecf005c. The network test now sets
    `AGENTDEV_RUNTIME_MODE=deploy`: against the current image pin it never
    reached proxy ingress.
- [x] With `FIREWALL_ALLOWLIST` unset, the devcontainer profile reads
  `<workspace>/.devcontainer/firewall-allowlist.txt` when it exists and
  `/etc/agentdev/firewall-allowlist.txt` otherwise; deploy reads the image copy.
  - **Evidence:** commit 052196c; `test_firewall_allowlist.py` covers the
    checkout copy, the image fallback, and deploy's setting and image copy,
    passing under `uv run pytest py_packages/agentdev_runtime`.
- [x] A set `FIREWALL_ALLOWLIST` names the allowlist in both profiles, ahead of
  the checkout and image copies. `test_firewall_allowlist.py` proves it in the
  devcontainer profile with a checkout copy present.
  - **Evidence:** commit bdcbd9ca;
    `test_a_set_allowlist_wins_over_the_checkout_copy_in_a_devcontainer` and
    `test_deploy_reads_the_image_copy_or_the_setting` pass under
    `uv run pytest py_packages/agentdev_runtime` (89 passed).
- [x] The Ansible role keeps `iptables` and `ipset`, drops the script, the
  sudoers file, and any package only the script used once a repository grep
  confirms no other user.
  - **Evidence:** commit 052196c; the role installs only `iptables` and `ipset`.
    `dnsutils`, `iproute2`, and `aggregate` had no other user once the network
    test resolved with `getent`; `jq` and `curl` stay installed by `dev_tools`
    and `basic_prereqs`. `uv run ansible-lint ansible` and the playbook syntax
    check pass.

### Task 5: Docker and keyring services

**Files:** Create: `py_packages/agentdev_runtime/agentdev_runtime/docker.py`,
`py_packages/agentdev_runtime/agentdev_runtime/keyring.py`; Modify:
`docker/deploy/supervisord.conf`, `docker/devcontainer/supervisord.conf`,
`scripts/tests/test_agent_runtime_docker.py`,
`scripts/tests/test_agent_runtime_keyring.py`,
`scripts/tests/test_docker_image_prune.py`; Delete:
`.devcontainer/scripts/runtime-docker.sh`,
`.devcontainer/scripts/docker-image-prune.sh`,
`.devcontainer/scripts/runtime-keyring.sh`,
`.devcontainer/scripts/setup-keyring.sh`

- [x] `agentdev-runtime docker run` performs the privilege, storage, private
  endpoint, and single-engine preflights and then execs `dockerd`;
  `agentdev-runtime docker prune` keeps the 72-hour filter and warning-only
  failures.
  - **Evidence:** commit cc0313b; `test_agent_runtime_docker.py` (guards, the
    exact `dockerd` argv, and a real nested engine on the pinned image) and
    `test_docker_image_prune.py` pass; deploy acceptance (24 passed) and the Dev
    Container image suite (5 passed) pass against images built from that commit.
- [x] `agentdev-runtime keyring dbus|keyring|check|wait` execs `dbus-daemon` and
  `gnome-keyring-daemon` after the bus wait, creates the login keyring once and
  never overwrites it, and `setup-keyring.sh` is deleted without a replacement.
  - **Evidence:** commit cc0313b; `test_agent_runtime_keyring.py` runs the real
    bus and keyring through the CLI (secrets served to a child, surviving
    replacement, keyring never overwritten, the bus wait); both images built
    from that commit start their supervised keyring to ready.

### Task 6: Xpra

**Files:** Create: `py_packages/agentdev_runtime/agentdev_runtime/xpra.py`;
Modify: `docker/deploy/supervisord.conf`,
`docker/devcontainer/supervisord.conf`, `docker/base/agentdev-base.Dockerfile`;
Delete: `docker/desktop/start-xpra.sh`

- [x] `agentdev-runtime xpra --supervised|--background|--stop` with `--host`,
  `--port`, and `--display` reproduces the launcher: display normalisation and
  lock clearing, orphaned X server reclaim, GPU detection and VirtualGL setup,
  the password through the environment, signal cleanup, and `exec` in supervised
  mode. The base image stops copying `/start-xpra.sh`.
  - **Evidence:** commit a595858; the supervised-Xpra cases of
    `test_agent_runtime_ingress.py` (password-gated sessions, no password on the
    command line, duplicate refusal, display reclaim after a crash) pass against
    a real Xpra through the CLI; deploy acceptance (24 passed) and the Dev
    Container image suite (5 passed) pass against images built from ba9a48d. The
    base image's own build is left to the plan's Verification.

### Task 7: OpenCode and the Coder start

**Files:** Create: `py_packages/agentdev_runtime/agentdev_runtime/opencode.py`,
`py_packages/agentdev_runtime/agentdev_runtime/coder.py`; Modify:
`docker/deploy/supervisord.conf`, `docker/devcontainer/supervisord.conf`,
`scripts/tests/test_agent_runtime_ingress.py`,
`scripts/tests/test_opencode_web_start.py`,
`scripts/tests/test_coder_agent_start.py`,
`scripts/e2e/iwe-workflows/opencode_credential.py`; Delete:
`.devcontainer/scripts/opencode-web-command.sh`,
`.devcontainer/scripts/opencode-web-start.sh`,
`.devcontainer/scripts/coder-agent-start.sh`

- [x] `agentdev-runtime opencode serve|probe|link|coder-start` keeps the
  password requirement, the 0600 generated password file, the Coder tmux
  session, and the authenticated `/api/info` probe.
  - **Evidence:** commit ba9a48d; `test_opencode_web_start.py` (fake and real
    tmux) and the serve and probe cases of `test_agent_runtime_ingress.py` pass
    through the CLI; deploy acceptance (24 passed), whose OpenCode is supervised
    and probed by `opencode serve` and `opencode probe`, passes against
    `agentdev-deploy` built from that commit.
- [x] `agentdev-runtime coder start` runs prune, the credential helper, and the
  OpenCode start as warnings on failure, then execs the Remote Control start.
  - **Evidence:** commit ba9a48d; `test_coder_agent_start.py` (6 passed) covers
    the order, each step's failure as a warning, and the caller environment
    reaching the credential helper and the OpenCode start.

### Task 8: CBM

**Files:** Create: `py_packages/agentdev_runtime/agentdev_runtime/cbm.py`,
`py_packages/agentdev_runtime/agentdev_runtime/codex_hooks.py`,
`py_packages/agentdev_runtime/tests/test_codex_hooks.py`; Modify:
`docker/deploy/supervisord.conf`, `docker/devcontainer/supervisord.conf`,
`scripts/tests/test_agent_runtime_cbm.py`,
`scripts/tests/test_codebase_memory_mcp_index.py`,
`scripts/tests/test_repair_codex_cbm_hooks_block.py`; Delete:
`.devcontainer/scripts/runtime-cbm.sh`,
`.devcontainer/scripts/codebase-memory-mcp-install.sh`,
`.devcontainer/scripts/codebase-memory-mcp-index.sh`,
`.devcontainer/scripts/codebase-memory-mcp-start.sh`,
`.devcontainer/scripts/repair-codex-cbm-hooks-block.py`

- [x] `agentdev-runtime cbm install|start|check|index <repo>|run|stop` keeps the
  daemon generation as PID plus `/proc` start time, the user-owned binary copy,
  the `~/.claude.json` materialise-and-restore as a context manager,
  `hooks.json` creation, the Codex hooks-block repair as a module, and the async
  index request with its acceptance check.
  - **Evidence:** commit 8e12cec; `test_agent_runtime_cbm.py` and
    `test_repair_codex_cbm_hooks_block.py` (29 passed) drive the pinned CBM
    binary through the CLI as an isolated account, including the offline
    install; `test_codebase_memory_mcp_index.py` and `test_codex_hooks.py` pass.
    `cbm install --config-only` carries the Dev Container's nonfatal wiring, and
    settings derived from the home directory follow `$HOME`, as every script
    read it. Deploy acceptance (24 passed) and the Dev Container image suite (5
    passed) pass against images built from that commit.

### Task 9: Agent state and catalog registration

**Files:** Create:
`py_packages/agentdev_runtime/agentdev_runtime/agent_state.py`,
`py_packages/agentdev_runtime/agentdev_runtime/catalog.py`,
`py_packages/agentdev_runtime/agentdev_runtime/codex_config.py`,
`py_packages/agentdev_runtime/agentdev_runtime/opencode_config.py`,
`py_packages/agentdev_runtime/agentdev_runtime/claude_state.py`,
`py_packages/agentdev_runtime/tests/test_codex_config.py`,
`py_packages/agentdev_runtime/tests/test_opencode_config.py`,
`py_packages/agentdev_runtime/tests/test_claude_state.py`; Modify:
`scripts/tests/test_configure_codex.py`,
`scripts/tests/test_configure_opencode.py`,
`scripts/tests/test_preapprove_claude_workspace.py`,
`scripts/e2e/iwe-workflows/harness_codex.py`; Delete:
`.devcontainer/scripts/setup-agent-state.sh`,
`.devcontainer/scripts/runtime-paths.sh`,
`.devcontainer/scripts/link-codex-auth.sh`,
`.devcontainer/scripts/preapprove-claude-workspace.sh`,
`.devcontainer/scripts/configure-codex.py`,
`.devcontainer/scripts/configure-opencode.py`,
`.devcontainer/scripts/reinstall-agentdev-claude.sh`,
`.devcontainer/scripts/reinstall-agentdev-codex.sh`,
`.devcontainer/scripts/reinstall-agentdev-opencode.sh`

- [x] `agentdev-runtime state create|links|agent-policy|cbm` runs under one
  configuration lock, keeps deploy's fatal and the devcontainer's nonfatal CBM
  install, the user-tool registration, the auth directories, the
  `~/.claude.json` link, the Codex `auth.json` link repair, and the Claude
  pre-approval with its skip variable.
  - **Evidence:** commit 39045fa; `test_agent_runtime_state.py` (17 passed,
    including the lock taking turns across processes), `test_claude_state.py`,
    `test_codex_config.py`, `test_opencode_config.py`, and the reworked
    `test_configure_*` and `test_preapprove_claude_workspace.py` pass. Deploy
    acceptance (24 passed) and the Dev Container image suite (5 passed) pass
    against images built from 9732df9.
- [x] `agentdev-runtime catalog install <root> [--claude-scope user|local]`
  registers the Claude marketplace and plugins, the Codex marketplace with the
  already-registered short-circuit and the agents installer, and the OpenCode
  bridge entry; the complete-catalog test is one function in the package.
  - **Evidence:** commits 39045fa and 9732df9;
    `test_switching_catalogs_replaces_managed_registrations_only` and
    `test_rerunning_codex_registration_leaves_config_byte_identical` pass
    against the real Claude and Codex CLIs; deploy acceptance (24 passed,
    including the fake-`claude` Remote Control cases whose config phase
    registers the catalog) passes against `agentdev-deploy` built from 9732df9.
    `catalog complete <root>` exposes the one complete-catalog test to the shell
    lifecycle scripts until Tasks 12 and 13 replace them.

### Task 10: Remote Control watcher ends on a start that never comes up

**Files:** Modify: `.devcontainer/scripts/runtime-remote-control.sh`,
`scripts/tests/test_runtime_remote_control.py`,
`docs/knowledge/data/bugs/remote-control-watcher-start-loop.md`

- [x] When the start script returns 0 and no live `claude-remote` session
  follows, `runtime-remote-control.sh run` logs it and exits non-zero, the way a
  seen session that disappears already does, so the runtime's recovery budget
  bounds the retries; the retry that clears `checked` is gone.
  - **Evidence:** commit f8b992c; `test_runtime_remote_control.py` and
    `test_claude_remote_control_start.py` pass (38).
- [x] A test in `test_runtime_remote_control.py` runs a start that leaves no
  session and asserts the watcher exits non-zero after one start; the bug's
  `## Fix` records the fix.
  - **Evidence:** commit f8b992c;
    `test_a_start_that_never_comes_up_ends_the_watcher` asserts one start and a
    non-zero exit naming the session that did not come up; the bug's `## Fix`
    records the change.

### Task 11: Remote Control

**Files:** Create:
`py_packages/agentdev_runtime/agentdev_runtime/remote_control.py`; Modify:
`docker/deploy/supervisord.conf`, `docker/devcontainer/supervisord.conf`,
`scripts/tests/test_runtime_remote_control.py`,
`scripts/tests/test_claude_remote_control_start.py`,
`scripts/tests/test_claude_remote_control_session.py`,
`scripts/tests/test_claude_remote_control_pin.py`; Delete:
`.devcontainer/scripts/runtime-remote-control.sh`,
`.devcontainer/scripts/claude-remote-control-start.sh`,
`.devcontainer/scripts/claude-remote-control-session.sh`,
`.devcontainer/scripts/claude-remote-control-pin.sh`

- [x] `agentdev-runtime remote-control run|check|start|session [name]|pin` keeps
  the credential-signature watch, the mode and spawn validation, the
  `tmux -L claude-remote` server, the pinned-conversation resume, and the
  SessionStart hook, whose command in `--settings` becomes
  `agentdev-runtime remote-control pin`.
  - **Evidence:** commit e457d98; `test_runtime_remote_control.py`,
    `test_claude_remote_control_start.py` (fake and real tmux),
    `test_claude_remote_control_session.py`, and
    `test_claude_remote_control_pin.py` pass through the CLI. Deploy acceptance
    (24 passed, including the Remote Control login, start, and recovery cases)
    and the Dev Container image suite pass against images built from merge
    f3c202d.

### Task 12: Workspace, project, and git helpers

**Files:** Create: `py_packages/agentdev_runtime/agentdev_runtime/workspace.py`,
`py_packages/agentdev_runtime/agentdev_runtime/project.py`,
`py_packages/agentdev_runtime/agentdev_runtime/git.py`,
`py_packages/agentdev_runtime/tests/test_project_hooks.py`; Modify:
`docker/deploy/supervisord.conf`,
`scripts/tests/test_agent_runtime_workspace.py`,
`scripts/tests/test_setup_gh_credential_helper.py`, `AGENTS.md`,
`.agents/plugins/agentdev/skills/microvm-sandbox/SKILL.md`; Delete:
`.devcontainer/scripts/runtime-workspace.sh`,
`.devcontainer/scripts/uv-sync.sh`, `.devcontainer/scripts/setup-pre-commit.sh`,
`.devcontainer/scripts/setup-git-safe-directory.sh`,
`.devcontainer/scripts/setup-gh-credential-helper.sh`

- [x] `agentdev-runtime workspace checkout|project|catalog|config|prepare` keeps
  the clone marker, worktree validation, credential redaction, and deploy-only
  cloning.
  - **Evidence:** commit 4773feb; `test_agent_runtime_workspace.py` (25 passed,
    including the real Claude and Codex catalog registration and the offline
    hook registration) runs the command with the other modules' steps recorded.
    Deploy acceptance (24 passed), whose prepare, config, and project phases run
    it, and the Dev Container image suite (5 passed) pass against images built
    from that commit. The forced-prepare acceptance case now swaps the phase
    through `AGENTDEV_SUPERVISOR_CONFIG`, since the CLI's entry point is a
    symlink into the integrity-checked tool.
- [x] `agentdev-runtime project sync|hooks` and
  `agentdev-runtime git safe-directory|credential-helper` keep the managed
  `.venv` link cleanup, deploy's refusal to replace custom hooks, the skip
  variables, and the keyring-session environment read; root `AGENTS.md` and the
  microvm-sandbox skill stop naming `uv-sync.sh`.
  - **Evidence:** commit 4773feb; the project cases of
    `test_agent_runtime_workspace.py` and `test_setup_gh_credential_helper.py`
    pass through the CLI;
    `uv run validate_agent_files --recommend . --require-marketplace claude codex`
    passes after the skill edit.
- [x] `agentdev-runtime project hooks`, after registering the hooks, writes one
  warning to stderr for each `language: system` hook whose `entry` executable is
  not on `PATH`, naming the hook and the executable, and keeps its exit status;
  tests cover a missing and a present executable in both profiles.
  - **Evidence:** commit 4773feb; `test_project_hooks.py` covers a missing and a
    present executable in both profiles, a non-system hook, and deploy's
    custom-hook refusal, which exits 1 before any warning.

### Task 13: Lifecycle commands, hooks, and the no-supervisor start

**Files:** Create: `py_packages/agentdev_runtime/agentdev_runtime/lifecycle.py`,
`py_packages/agentdev_runtime/agentdev_runtime/hooks.py`,
`py_packages/agentdev_runtime/tests/test_hooks.py`; Modify:
`docker/devcontainer/agentdev-devcontainer.Dockerfile`,
`docker/devcontainer/supervisord.conf`,
`.github/actions/run-claude-responder/action.yml`,
`scripts/tests/test_agentdev_devcontainer_lifecycle.py`,
`scripts/tests/test_agentdev_devcontainer_image.py`,
`scripts/tests/test_agentdev_devcontainer_repository.py`,
`scripts/tests/test_template_consume_migration.py`; Delete:
`.devcontainer/scripts/devcontainer-created.sh`,
`.devcontainer/scripts/devcontainer-ready.sh`,
`.devcontainer/scripts/devcontainer-attached.sh`,
`.devcontainer/scripts/run-agentdev-hooks.sh`,
`.devcontainer/scripts/postCreateCommand.sh`,
`.devcontainer/scripts/postStartCommand.sh`,
`.devcontainer/scripts/postAttachCommand.sh`

- [x] `agentdev-runtime lifecycle created [--wait]`, `ready [--no-wait]`,
  `attached`, and `hooks <phase>` keep each phase's content and ordering, the
  hook-directory containment check, and the readiness wait. `ready --no-wait` is
  one function: start the CBM daemon, then the per-start repairs.
  - **Evidence:** commit 70828d2; `test_agentdev_devcontainer_lifecycle.py` (19
    passed) and `test_hooks.py` cover each phase's order, idempotence, the
    readiness wait and its failure, the hook order, skips, failure, and
    containment, and `ready --no-wait` starting CBM before the per-start
    repairs. The Dev Container image suite (5 passed) runs the label's commands
    against an image built from 76a1836.
- [x] The `devcontainer.metadata` label, the `created` wait program, and the
  responder action's lifecycle step name the CLI; the responder keeps its
  environment and the client-state directory creation.
  - **Evidence:** commit 70828d2;
    `test_the_responder_runs_each_phase_through_the_cli` and the profiles test
    on the `created` program pass, and the label names
    `agentdev-runtime lifecycle created|ready|attached`; the responder step
    keeps its environment and its `mkdir -p` of the client-state directories.
- [x] The lifecycle tests replace filename stubs with monkeypatched module
  functions, and the image, repository, and migration tests call the CLI.
  - **Evidence:** commit 70828d2; the lifecycle tests patch `agentdev_runtime`
    module functions in a subprocess bootstrap, and the image, repository, and
    migration tests reach the runtime only through `agentdev-runtime`.

### Task 14: Remove the script tree, the health report, and the acceptance wrapper

**Files:** Create: `py_packages/agentdev_runtime/agentdev_runtime/doctor.py`,
`scripts/tests/conftest.py`; Modify: `.github/workflows/ci.yml`,
`.dockerignore`, `docker/deploy/agentdev-deploy.Dockerfile`,
`docker/devcontainer/agentdev-devcontainer.Dockerfile`,
`scripts/tests/test_environment_health.py`,
`scripts/tests/test_agent_runtime_acceptance.py`; Delete:
`.devcontainer/scripts/environment-health.sh`,
`.devcontainer/scripts/ci-hooks-repro.sh`,
`.devcontainer/scripts/test-agent-runtime.sh`

- [x] `agentdev-runtime doctor` reproduces the health report's sections, its
  PASS/FAIL/SKIP tabulation, and its exit status.
  - **Evidence:** commit 76a1836; `test_environment_health.py` (13 passed) runs
    the CLI against stub tools for both profiles, the firewall values, missing
    tools, failures, timeouts, and the redaction.
- [x] `doctor`'s toolchain section also requires `gitleaks` and `actionlint`,
  reporting `required tool not installed` for either when it is absent.
  - **Evidence:** commit 76a1836;
    `test_a_missing_hook_binary_fails_the_toolchain` passes for each.
- [x] `ci.yml` runs the acceptance suite through `uv run pytest`; a conftest
  fixture labels and removes the containers, volumes, and networks the suite
  creates, and a session hook fails the run when every test skipped.
  - **Evidence:** commit 76a1836;
    `uv run pytest -n 4 scripts/tests/test_agent_runtime_acceptance.py` passes
    (24, one skipped) against `agentdev-deploy` built from that commit and
    leaves no labelled container behind; selecting only the skipped upgrade case
    with the image set prints `every acceptance test was skipped` and exits 1.
- [x] The `COPY .devcontainer/scripts/` lines and the `.dockerignore` exception
  leave; `.devcontainer/scripts/` is gone from the tree, and
  `git ls-files ':(glob).devcontainer/**/*.sh'` lists only
  `.devcontainer/devcontainer-init.sh`.
  - **Evidence:** commit 76a1836; both images build without the copy, and
    `git ls-files ':(glob).devcontainer/**/*.sh'` lists only
    `.devcontainer/devcontainer-init.sh`. Git's default pathspec needs the
    `:(glob)` magic for `**` to match no directory.

### Task 15: Remove Codex Cloud

**Files:** Modify: `.codex/README.md`,
`docs/knowledge/data/architecture/template-boundary.md`,
`.agents/plugins/agentdev/skills/template-consume/references/consumption-guide.md`,
`docs/knowledge/data/backlog/remove-agentdev-session-start-hook.md`; Delete:
`.codex/setup-codex-cloud.sh`

- [x] The script and every reference to it are gone;
  `git grep -iE 'codex[ -]cloud'` outside `data/plans/`, `data/log.md`, and the
  feature document that describes the removal prints nothing.
  - **Evidence:** commit ab09896; `git grep -iE 'codex[ -]cloud'` with the four
    exclusions as pathspecs prints nothing and exits 1;
    `uv run validate_agent_files --recommend . --require-marketplace claude codex`
    and `iwe schema validate` pass.

### Task 16: Publisher scripts

**Files:** Create: `scripts/download-claude-responder-runs.py`,
`scripts/renovate-post-upgrade.py`,
`scripts/tests/test_download_claude_responder_runs.py`; Modify:
`.github/renovate.json`, `.github/workflows/renovate.yml`,
`scripts/analyze-claude-responder-costs.py`,
`scripts/tests/test_renovate_post_upgrade.py`,
`docs/knowledge/data/architecture/renovate-post-upgrade.md`; Delete:
`scripts/download-claude-responder-runs.sh`, `scripts/renovate-post-upgrade.sh`,
`py_packages/validate_agent_files/tests/test_download_claude_responder_runs.py`

- [x] Both scripts are Python with the same usage and output; the responder
  download test moves out of the validator package into `scripts/tests/`; the
  Renovate `postUpgradeTasks.commands`, the `managerFilePatterns` entry, and
  `RENOVATE_ALLOWED_COMMANDS` name the `.py` file.
  - **Evidence:** commit 07bf978; `test_renovate_post_upgrade.py` (now with a
    check that the custom manager's pattern still reads the CLI pin from the
    `.py` file) and the moved
    `scripts/tests/test_download_claude_responder_runs.py` pass, and the
    renovate-config-validator hook passes on `.github/renovate.json`.

### Task 17: Record the decisions and refresh the references

**Files:** Create:
`docs/knowledge/data/architecture/agentdev-runtime-package.md`; Modify:
`docs/knowledge/data/architecture.md`,
`docs/knowledge/data/architecture/ci-agent-plugin-availability.md`,
`docs/knowledge/data/architecture/standalone-opencode-runtime.md`,
`docs/knowledge/data/architecture/cbm-daemon-lifecycle.md`,
`docs/knowledge/data/architecture/template-boundary.md`,
`docs/knowledge/data/architecture/module-layout.md`,
`docs/knowledge/data/architecture/uv-environment-location.md`,
`docs/knowledge/data/product.md`, `README.md`, `docker/deploy/README.md`,
`AGENTS.md`,
`.agents/plugins/agentdev/skills/template-consume/references/consumption-guide.md`,
`.devcontainer/devcontainer.json`, `.devcontainer/docker-compose.yml`,
`ansible/roles/basic_prereqs/tasks/main.yml`,
`ansible/roles/dev_tools/defaults/main.yml`

- [x] The architecture document records the package over loose scripts, the
  `RECORD` integrity check, the firewall leaving the base image, the CBM-only
  no-supervisor start with the container-job alternatives rejected in its
  favour, and the other rejected alternatives above.
  - **Evidence:** commit ec9a98d;
    `data/architecture/agentdev-runtime-package.md`, linked from
    `data/architecture.md`, records the package, the `RECORD` integrity check,
    the firewall run from the bootstrap with the role keeping only its packages,
    the CBM-only no-supervisor start with the container-job alternatives
    rejected, and the other rejected alternatives; `iwe schema validate` passes.
- [x] Every document and comment that names a runtime script names the CLI
  subcommand instead; `product.md` describes the package in its stack and the
  firewall constraint by its command; root `AGENTS.md` points
  devcontainer-related code at the package.
  - **Evidence:** commits ec9a98d and d977ad2; a `git grep` for every retired
    script name finds none outside the plan records, `data/log.md`, the specs
    `## Spec changes` sends to Ship, the bugs, the implemented features and done
    backlog items that record past work, and three tests that assert the old
    tree is gone. `product.md` describes the package in its stack and the
    firewall by its command, and root `AGENTS.md` points devcontainer runtime
    code at the package.

### Task 18: The responder runs on an image without the CLI

**Files:** Modify: `.github/actions/run-claude-responder/action.yml`

- [x] When `agentdev-runtime` is not on `PATH`, the responder's lifecycle step
  installs it from the checkout's `py_packages/agentdev_runtime` as a uv tool
  before running `agentdev-runtime lifecycle created|ready|attached`, so a
  `container:` job on a pinned image built before this plan still runs its
  lifecycle; an image that ships the CLI skips the install.
  - **Evidence:** commit 5fb232d. The install builds from a temporary copy of
    the package, so no `build/` tree is left in the checkout under review. The
    step's script, run in this plan's Dev Container image, which ships the CLI,
    exits 0 without invoking `uv tool install`.
- [x] `actionlint` and `zizmor` pass through pre-commit, and the step's install
  path runs in a container from the currently pinned `agentdev-devcontainer`
  image.
  - **Evidence:** commit 5fb232d. `pre-commit run actionlint` and `zizmor` pass
    on the action and `ai-responder.yml`. The test used the step's script in the
    pinned `edge@sha256:d1acc7f1…` image, run as a container job: the workspace
    was mounted and the step's environment set. There, `agentdev-runtime` is
    absent before the step; the step installs it to
    `/usr/local/bin/agentdev-runtime`, then runs `lifecycle created`,
    `ready --no-wait`, and `attached`, and exits 0. The package directory in the
    checkout gains no `build/` tree.

### Task 19: The Coder template starts the agent through the CLI

**Files:** Modify, in
[plume-works/coder-ide-baseline](https://github.com/plume-works/coder-ide-baseline):
`template/main.tf`

- [x] The `agent_start_script` parameter becomes a command run in the repository
  checkout, defaulting to `agentdev-runtime coder start`; its `display_name` and
  `description` say so. `coder_script.agent_start` runs the value when its first
  word resolves through `command -v`, runs the default in place of the legacy
  value `.devcontainer/scripts/coder-agent-start.sh` that existing workspaces
  stored, runs the checkout's executable
  `.devcontainer/scripts/coder-agent-start.sh` when the command does not resolve
  but that script exists, and otherwise logs that the repository ships no
  agent-start command and exits 0.
  - **Evidence:** coder-ide-baseline commit 4a2d980 (squash of
    [#31](https://github.com/plume-works/coder-ide-baseline/pull/31)), whose
    `push.sh` also defaults the template name to `coder-ide-baseline`.
    `terraform fmt -check` and `terraform validate` pass. The rendered script,
    run under `sh`, takes every branch: default, legacy, script fallback, custom
    command, empty, and unresolvable. On template version `main-4a2d980`:
    - Case (a): `anton/agent-dev3` was updated with the parameter set to the
      default, on its current image, which has no CLI. Its agent-start log at
      05:53:44 shows `coder-agent-start.sh` running through the fallback: "A git
      credential helper for github.com is already configured", "Started OpenCode
      web …", "Started Claude Remote Control …". `opencode serve` and
      `claude remote-control` restarted at 05:53:43, and Remote Control reports
      Ready.
    - Case (b): `anton/agent-dev4` was updated without a parameter change, so it
      keeps the stored legacy value. It takes the same path, with the same three
      lines at 05:55:14 and both processes restarted at 05:55:13. Its locked
      worktree `bridge-cse_01Q7BhLtd7Zx6jbm3HGXyvW7` is still listed at 4b2302d
      with no changes.
    - Case (c): the default command was run in this plan's Dev Container image,
      started under its supervisor with `health ready` passing and no script in
      the checkout. It ran `agentdev-runtime coder start` and exited 0 with
      "Started OpenCode web …"; gh and Claude, not logged in, were skipped as
      logged.
- [x] The template change merges through its own pull request with its
  `Docker Build and Push` check passing, and the new template version is pushed
  to Coder before this plan's pull request merges.
  - **Evidence:** [coder-ide-baseline
    #31](https://github.com/plume-works/coder-ide-baseline/pull/31) merged as
    4a2d98085e34f0a7b4d266d86b90add036bf32f3, with `Docker Build and Push`
    passing ([run
    41172671181](https://github.com/plume-works/coder-ide-baseline/actions/runs/41172671181)).
    `coder templates push coder-ide-baseline --directory template --name main-4a2d980`
    from that commit made version `main-4a2d980` the active version at
    2026-10-31T05:51:33Z, while this plan's pull request was still a draft.

### Task 20: Verify the published image family

**Files:** None.

- [x] **Closed by: CI on the current head.** Both architectures build the three
  images, the deploy and Dev Container acceptance jobs pass, and the canonical
  tags move.
  - **Evidence:** [CI run
    41234466679](https://github.com/plume-works/agent-devcontainer/actions/runs/41234466679)
    on 6efe8ea0 (PR #591), the head holding every code change; later commits
    edit documents only. The run includes:
    - `Development image` builds `agentdev-base`, `agentdev-deploy`, and
      `agentdev-devcontainer` on amd64 and arm64, and `Merge development image`
      merges them.
    - `Devcontainer image`, `Deploy runtime acceptance`, and
      `Dev Container runtime acceptance` pass on both architectures.
    - `Promote development image` moves `pr-591` on all three images, and
      `CI finished` passes. CI collects every test tree in one pytest session,
      so the runtime's CLI tests are `tests/test_runtime_cli.py` and
      `ACCEPTANCE_LABEL` lives in `scripts/tests/acceptance_label.py` (commit
      f25e9e2b).

### Task 21: doctor passes a healthy Coder Dev Container

**Files:** Modify: `py_packages/agentdev_runtime/agentdev_runtime/doctor.py`,
`.devcontainer/docker-compose.yml`, `scripts/tests/test_environment_health.py`

- [x] In the devcontainer profile, `doctor` checks `mcp-gateway` DNS and `:8811`
  only when `COMPOSE_PROFILES` names `mcp`, and otherwise reports `mcp-gateway`
  SKIP; the Compose `devcontainer` service passes `COMPOSE_PROFILES` through.
  `test_environment_health.py` covers both.
  - **Evidence:** commit 27c1ab21; `test_devcontainer_mode_checks_sidecars` and
    `test_the_gateway_is_skipped_without_the_mcp_profile` pass in
    `test_environment_health.py` (15 passed); `docker compose config` renders
    `COMPOSE_PROFILES: mcp` with the profile enabled and `""` without it.
- [x] `git user` passes when `git var GIT_AUTHOR_IDENT` and
  `git var GIT_COMMITTER_IDENT` both resolve, so an identity set only through
  `GIT_AUTHOR_*` and `GIT_COMMITTER_*` passes and a missing one still fails.
  `test_environment_health.py` covers both.
  - **Evidence:** commit 666da330;
    `test_an_identity_git_resolves_passes_the_git_user_check` and
    `test_an_identity_git_cannot_resolve_fails_the_git_user_check` pass in
    `test_environment_health.py` (17 passed).
- [x] `agentdev-runtime doctor` ends `Overall: PASS` in this repository's
  Compose Dev Container under Coder with credentials.
  - **Evidence:** commit 666da330; `uv run agentdev-runtime doctor` from the
    package at that commit, in the Coder workspace's Compose Dev Container,
    whose image predates the CLI, reports 45 PASS, 0 FAIL, 6 SKIP and
    `Overall: PASS`, with `mcp-gateway` SKIP and `git user` PASS.

## Spec changes

### [Firewall](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/firewall.md)

``` markdown
## MODIFIED Requirements

### Requirement: the firewall is inert unless explicitly enabled

`agentdev-runtime firewall apply` SHALL apply egress rules only when
`ENABLE_FIREWALL` is `true`. The runtime's bootstrap SHALL run it as root
before supervisord starts, in both profiles, so no sudoers entry is needed, and
with any other value it SHALL report that the firewall stays inert and exit 0.

#### Scenario: a container starts with no `ENABLE_FIREWALL` set

- **WHEN** the container starts
- **THEN** no egress restriction is applied.

### Requirement: enabled firewall default-DROPs IPv4 and blocks IPv6 entirely

When enabled, `agentdev-runtime firewall apply` SHALL set IPv4
`INPUT`/`FORWARD`/`OUTPUT` policies to `DROP` and block IPv6 entirely, while
preserving Docker's embedded DNS NAT rules and allowing only hosts on the
allowlist. When `FIREWALL_ALLOWLIST` is set, both profiles SHALL read the file
it names. Otherwise the devcontainer profile SHALL read
`<workspace>/.devcontainer/firewall-allowlist.txt` when it exists, so
per-branch edits take effect on the next start without an image rebuild, and
`/etc/agentdev/firewall-allowlist.txt` otherwise; the deploy profile SHALL read
the image copy.

#### Scenario: a host not on the allowlist is requested

- **WHEN** code in the container tries to reach a non-allowlisted host
- **THEN** the connection is dropped.

#### Scenario: the checkout edits its allowlist

- **WHEN** a devcontainer restarts after `.devcontainer/firewall-allowlist.txt`
  changed in the checkout
- **THEN** the new allowlist is in force without an image rebuild.

#### Scenario: `FIREWALL_ALLOWLIST` is set in a devcontainer

- **WHEN** a devcontainer starts with `FIREWALL_ALLOWLIST` naming a file and a
  checkout allowlist present
- **THEN** the firewall applies the file `FIREWALL_ALLOWLIST` names.

### Requirement: the firewall self-verifies at start and fails loudly

`agentdev-runtime firewall apply` SHALL check, immediately after applying
rules, that a known-blocked host (`example.com`) fails and that
`https://api.github.com/zen` succeeds, exiting non-zero if either check goes the
wrong way, so a misconfigured firewall never silently passes as enabled while
actually open or actually blocking required traffic.

#### Scenario: the allowlist accidentally omits `api.github.com`

- **WHEN** the self-verification runs
- **THEN** the `api.github.com/zen` reachability check fails and the command
  exits non-zero, surfacing the misconfiguration at container start.

#### Scenario: the DROP policy fails to apply

- **WHEN** `example.com` is still reachable after the rules are applied
- **THEN** the verification step exits non-zero.
```

### [agentdev runtime images](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/agentdev-runtime-images.md)

Normative outcome: the stable lifecycle commands SHALL be
`agentdev-runtime lifecycle created`, `agentdev-runtime lifecycle ready`, and
`agentdev-runtime lifecycle attached`, published through the image's Dev
Container metadata; `agentdev-base` SHALL NOT carry the package;
`agentdev-runtime project hooks` SHALL warn, without failing, about each
`language: system` pre-commit hook whose executable is not on `PATH`; and
`agentdev-runtime doctor` SHALL report `gitleaks` and `actionlint` as required
tools; and in the devcontainer profile `doctor` SHALL check the `mcp-gateway`
sidecar only when the Compose `mcp` profile is enabled and SHALL accept the git
identity git resolves, including one set through `GIT_AUTHOR_*` and
`GIT_COMMITTER_*`.

The integrity check that replaces the manifest over `/opt/agentdev-runtime`
guards what a derived image may change, so it is a delta:

``` markdown
## MODIFIED Requirements

### Requirement: consumers do not copy lifecycle implementation

A direct or derived consumer SHALL be able to obtain the complete managed
lifecycle by referencing `agentdev-devcontainer` and SHALL customize it through
documented environment values and executable files in explicit ordered hook
directories.

#### Scenario: a direct consumer has no lifecycle scripts

- **WHEN** its descriptor selects the image, mounts, workspace, and editor
  settings without repository-local agentdev scripts
- **THEN** managed startup, lifecycle commands, tools, and the staged catalog
  remain available

#### Scenario: a derived image adds a hook

- **WHEN** it installs an executable hook in a documented phase directory
- **THEN** the hook runs in deterministic order after the managed phase without
  changing, adding, or removing any file of the installed `agentdev_runtime`
  distribution

#### Scenario: a mounted repository contains a similarly named script

- **WHEN** no explicit image hook registers that script
- **THEN** mounting or attaching the repository does not execute it

## ADDED Requirements

### Requirement: the bootstrap refuses a changed runtime package

While the installed `agentdev_runtime` distribution's metadata is present, the
root bootstrap SHALL refuse to run when a file its `RECORD` lists differs from
the recorded hash or is missing, or a file was added beside the recorded files,
and SHALL name the file and direct the consumer to the hook directories and
documented environment. The check catches accidental or partial edits to the
runtime and is not a security boundary: a derived image that deliberately
deletes the distribution's metadata or rewrites its `RECORD` passes it.

#### Scenario: a derived image edits a package file

- **WHEN** a derived image replaces a file of the installed `agentdev_runtime`
  distribution and the container starts
- **THEN** the bootstrap fails naming that file and the extension points

#### Scenario: a derived image adds a file to the package

- **WHEN** a derived image adds a file below the installed distribution's
  package directory
- **THEN** the bootstrap fails naming the added file

#### Scenario: an unmodified image starts

- **WHEN** the installed distribution matches its `RECORD`
- **THEN** the bootstrap continues
```

### Specs that name a script

Normative outcome for each: the specification SHALL name the `agentdev-runtime`
subcommand in place of the script it names today, and every requirement and
scenario keeps its behaviour.

| Spec                                                                                                                                                 | Today                                                                                                                                                                     | Subcommand                                                                                          |
| ---------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| [Standalone OpenCode runtime](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/standalone-opencode-runtime.md)   | `runtime-health.sh status`, `runtime-supervisor.py retry`                                                                                                                 | `health status`, `supervisor retry`                                                                 |
| CBM startup integration                                                                                                                              | `codebase-memory-mcp-index.sh`, `codebase-memory-mcp-install.sh`, `codebase-memory-mcp-start.sh`, `runtime-cbm.sh`, `repair-codex-cbm-hooks-block.py`                     | `cbm index`, `cbm install`, `cbm start`, `cbm run`, the `codex_hooks` module                        |
| [Claude Remote Control](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/claude-remote-control.md)               | `claude-remote-control-start.sh`, `-session.sh`, `-pin.sh`, `runtime-remote-control.sh`, `coder-agent-start.sh`, `preapprove-claude-workspace.sh`, `postCreateCommand.sh` | `remote-control start`, `session`, `pin`, `run`, `coder start`, `state create`, `lifecycle created` |
| [Catalog lifecycle](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/catalog-lifecycle.md)                       | `postCreateCommand.sh`, `postAttachCommand.sh`, `reinstall-agentdev-*.sh`, `setup-agent-state.sh`, `runtime-workspace.sh`, `codebase-memory-mcp-install.sh`               | `lifecycle created`, `lifecycle attached`, `catalog install`, `state`, `workspace`, `cbm install`   |
| [Devcontainer git credentials](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/devcontainer-git-credentials.md) | `coder-agent-start.sh`, `postStartCommand.sh`, `setup-gh-credential-helper.sh`                                                                                            | `coder start`, `lifecycle ready`, `git credential-helper`                                           |
| [OpenCode web](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/opencode-web.md)                                 | `coder-agent-start.sh`, `opencode-web-start.sh`, `opencode-web-command.sh`                                                                                                | `coder start`, `opencode coder-start`, `opencode serve`, `opencode probe`, `opencode link`          |
| [Devcontainer Docker storage](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/devcontainer-docker-storage.md)   | `coder-agent-start.sh`, `docker-image-prune.sh`                                                                                                                           | `coder start`, `docker prune`                                                                       |
| Devcontainer Codex policy                                                                                                                            | `postStartCommand.sh`, `configure-codex.py`                                                                                                                               | `lifecycle ready`, `state agent-policy`                                                             |
| [Devcontainer OpenCode policy](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/devcontainer-opencode-policy.md) | `postStartCommand.sh`, `configure-opencode.py`                                                                                                                            | `lifecycle ready`, `state agent-policy`                                                             |
| [Xpra port forwarding](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/xpra-port-forwarding.md)                 | `start-xpra.sh`                                                                                                                                                           | `xpra`                                                                                              |
| [Dependency updates](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/dependency-updates.md)                     | `scripts/renovate-post-upgrade.sh`                                                                                                                                        | `scripts/renovate-post-upgrade.py`                                                                  |

[Claude Remote
Control](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/claude-remote-control.md),
Task 10: the requirement "the standalone runtime starts Remote Control when a
mode is set" gains a normative outcome. A start that returns without leaving a
live `claude-remote` session SHALL count as the session exiting, so the runtime
restarts it and, once the recovery budget is exhausted, reports degraded naming
`remote-control`, or latches failed under strict startup.

[Coder IDE
baseline](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/coder-ide-baseline.md),
Task 19 — the start hook becomes a command, so the script requirement is removed
and a command requirement added, and every other mention of
`coder-agent-start.sh` in the spec names `agentdev-runtime coder start`:

``` markdown
## REMOVED Requirements

### Requirement: the agent-start script is the repository's only start hook

Retired: the start hook is a command rather than a script path, which the added
requirement below states.

## ADDED Requirements

### Requirement: the agent-start command is the repository's only start hook

The template SHALL run, on every start of the Dev Container's sub-agent, the
command that the `agent_start_script` workspace parameter names, in the
repository checkout. The value defaults to `agentdev-runtime coder start`. The
command SHALL run under the sub-agent, so it inherits the agent's environment,
including Coder user secrets. The legacy value
`.devcontainer/scripts/coder-agent-start.sh`, the template's former default,
SHALL run the default command. When the command does not resolve but the
checkout ships an executable `.devcontainer/scripts/coder-agent-start.sh`, that
script SHALL run, so a workspace on an image without the CLI keeps its start.
When the value is empty, or its first word does not resolve to a command and no
such script exists, nothing SHALL run and the script's log SHALL say so. The template SHALL NOT name any other command in
this repository; new agent-start steps belong in `agentdev-runtime coder start`.

#### Scenario: the repository ships the CLI

- **WHEN** the workspace starts with the default parameter value
- **THEN** `agentdev-runtime coder start` runs in the Dev Container with the
  Coder user secrets in its environment.

#### Scenario: a workspace stored the legacy script path

- **WHEN** the workspace starts with `agent_start_script` set to
  `.devcontainer/scripts/coder-agent-start.sh`
- **THEN** `agentdev-runtime coder start` runs, as it would for the default.

#### Scenario: an image without the CLI still ships the script

- **WHEN** `agentdev-runtime` does not resolve and the checkout ships an
  executable `.devcontainer/scripts/coder-agent-start.sh`
- **THEN** that script runs with the Coder user secrets in its environment.

#### Scenario: another repository has no agent-start command

- **WHEN** the configured command does not resolve in the Dev Container
- **THEN** the start script logs that the repository ships no agent-start
  command and exits without error.
```

## Depends on

[Publish the reusable agentdev Dev Container
image](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/plans/20261023-reusable-agentdev-devcontainer.md)

## Verification

- `uv run pytest py_packages/agentdev_runtime`
- `uv run pytest scripts/tests/test_agent_runtime_supervision.py scripts/tests/test_agent_runtime_profiles.py scripts/tests/test_agent_runtime_state.py scripts/tests/test_agent_runtime_identity.py scripts/tests/test_agent_runtime_firewall.py scripts/tests/test_agent_runtime_docker.py scripts/tests/test_agent_runtime_keyring.py scripts/tests/test_agent_runtime_cbm.py scripts/tests/test_agent_runtime_workspace.py scripts/tests/test_agent_runtime_ingress.py scripts/tests/test_runtime_remote_control.py scripts/tests/test_agentdev_devcontainer_lifecycle.py scripts/tests/test_environment_health.py scripts/tests/test_renovate_post_upgrade.py scripts/tests/test_download_claude_responder_runs.py`
- `uv run ruff check py_packages/agentdev_runtime scripts` and
  `.agents/plugins/agentdev/bin/python_lint_check.py`
- `shellcheck` on every remaining shell file;
  `git ls-files ':(glob).devcontainer/**/*.sh' ':(glob)docker/**/*.sh' ':(glob).codex/**' ':(glob)scripts/*.sh' ':!.codex/README.md'`
  prints exactly `.devcontainer/devcontainer-init.sh`,
  `docker/ansible/setup-ansible.sh`, and `docker/desktop/entrypoint.sh`
- `uv run ansible-lint ansible` and
  `uv run ansible-playbook --syntax-check ansible/playbooks/setup-dev.yml`
- Build the three-image family locally through the repository's image-build
  action or the microVM sandbox; confirm `dpkg -l supervisor` reports nothing,
  `/opt/uv-tools/agentdev-runtime/bin/python -c 'import supervisor, tomlkit, json5, yaml'`
  succeeds, the `devcontainer.metadata` label names the CLI, and
  `agentdev-runtime doctor` passes inside a started Dev Container
- Run the direct and derived fixtures through create, stop/start, rebuild, and
  repeated attach; confirm a derived image that edits a package file fails the
  bootstrap
- Run the acceptance suite against the deploy image through the `ci.yml`
  invocation, offline for the CBM cases
- In a started Dev Container with `gitleaks` moved off `PATH`,
  `agentdev-runtime doctor` fails its toolchain section naming it, and
  `agentdev-runtime project hooks` warns about the `gitleaks` hook and exits 0
- `iwe normalize`, `iwe schema validate`, and the knowledge-base tests
- CI on the current head builds and accepts both architectures

## Verification results

- `agentdev-runtime doctor` ends `Overall: PASS` in this repository's Compose
  Dev Container under Coder with credentials, run from the package because the
  workspace image predates the CLI: 45 PASS, 0 FAIL, 6 SKIP (Task 21).
- The task commits landed on `main` squashed as c96e1ef1 (#573); the per-task
  SHAs the evidence cites are reachable on
  `origin/iwe/off-bash-migration/iter-1-impl`.

## Out of scope

- The catalog's bundled scripts and
  `scripts/validate-super-linter-tool-versions.sh`, which sources the catalog's
  Super-Linter defaults: [Port the catalog's bundled shell scripts to
  Python](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/plans/20261029-catalog-scripts-python.md).
- `.devcontainer/devcontainer-init.sh` (runs on the host under `/bin/sh -c`,
  where Python is not guaranteed), `docker/desktop/entrypoint.sh`,
  `docker/bin/gh` (a PATH shim on every `gh` call),
  `docker/ansible/setup-ansible.sh` (runs before the toolchain exists), the test
  fixtures' hook scripts, and the self-improve plugin's `si` launcher.
- Running the responder's `container:` jobs under the supervisor, decided
  against in `## Approach`; and re-pinning the toolchain-only `renovate` and
  `validate-renovate-config` jobs to `agentdev-base`, which the image-pinning
  change of [Publish the reusable agentdev Dev Container
  image](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/plans/20261023-reusable-agentdev-devcontainer.md)
  keeps on the Dev Container pin.
- Publishing `agentdev_runtime` to PyPI or installing it anywhere but the two
  runtime images.
- Any other behaviour change beyond the hook-binary detection and Task 21's
  `doctor` checks: profile service sets, recovery budgets, catalog policy, the
  managed `.venv` link cleanup, or any spec scenario.
- The fixes for the CBM start latch and the Codex auth link, which land after
  this plan, in the package.
- Shims for the retired `/opt/agentdev-runtime/*.sh` names.

## Key references

Verified anchor points (line numbers as of 2026-10-31):

- `py_packages/agentdev_runtime/agentdev_runtime/firewall.py:97` —
  `allowlist_path`: `FIREWALL_ALLOWLIST` first, in both profiles
- `py_packages/agentdev_runtime/tests/test_firewall_allowlist.py:67` —
  `test_deploy_reads_the_image_copy_or_the_setting`; `:76` —
  `test_a_set_allowlist_wins_over_the_checkout_copy_in_a_devcontainer`
- `py_packages/agentdev_runtime/agentdev_runtime/remote_control.py:249` — a seen
  session that is gone ends the watcher; `:258` — a start that never comes up
  ends it
- `scripts/tests/test_runtime_remote_control.py:187` —
  `test_a_session_that_disappears_ends_the_watcher`; `:197` —
  `test_a_start_that_never_comes_up_ends_the_watcher`
- `docker/devcontainer/agentdev-devcontainer.Dockerfile:14` — the
  `agentdev_runtime` uv tool install
- `docker/devcontainer/agentdev-devcontainer.Dockerfile:38` —
  `devcontainer.metadata` lifecycle commands
- `docker/devcontainer/agentdev-devcontainer.Dockerfile:54` — `HEALTHCHECK`
  command
- `docker/devcontainer/agentdev-devcontainer.Dockerfile:57` — `ENTRYPOINT`
- `docker/deploy/agentdev-deploy.Dockerfile:19` — the `agentdev_runtime` uv tool
  install
- `docker/deploy/agentdev-deploy.Dockerfile:62` — `HEALTHCHECK` command
- `docker/deploy/agentdev-deploy.Dockerfile:65` — `ENTRYPOINT`
- `docker/devcontainer/supervisord.conf:25` — controller listener command
- `docker/devcontainer/supervisord.conf:38` — first service `command=`
- `docker/deploy/supervisord.conf:84` — `prepare` one-shot
- `.github/workflows/ai-responder.yml:424` — review job `container:` block
- `.github/actions/run-claude-responder/action.yml:159` — composite
  `claude-code-action` step
- `.github/actions/run-claude-responder/action.yml:95` — lifecycle step
- `py_packages/agentdev_runtime/agentdev_runtime/lifecycle.py:141` — `ready`:
  the no-supervisor branch starts CBM through `start_cbm` (`:130`)
- `ansible/roles/validate_agent_files/tasks/main.yml:61` — uv tool install the
  runtime images mirror
- `ansible/roles/validate_agent_files/defaults/main.yml:17` — `/opt/uv-tools`
- `.github/workflows/ci.yml:325` — `agentdev-runtime health ready` in the Dev
  Container image check
- `.github/workflows/ci.yml:399` — the acceptance suite through `uv run pytest`
- `.github/renovate.json:6` — `postUpgradeTasks.commands`
- `.github/workflows/renovate.yml:110` — `RENOVATE_ALLOWED_COMMANDS`
- `scripts/tests/test_agentdev_devcontainer_lifecycle.py:29` — module-function
  stubs recording each step
- `AGENTS.md:13` — `agentdev-runtime project sync` reference
- `README.md:205` — `agentdev-runtime health status` operator command
- `docker/deploy/README.md:101` — `agentdev-runtime health status` operator
  command
- `docs/knowledge/data/product.md:112` — firewall constraint
- `docs/knowledge/data/architecture/template-boundary.md:114` — `.codex/` row
- `py_packages/agentdev_runtime/agentdev_runtime/integrity.py:55` — `verify`:
  changed, missing, or added package files against `RECORD`
- `py_packages/agentdev_runtime/agentdev_runtime/bootstrap.py:351` — the
  bootstrap's integrity call
- `docs/knowledge/data/spec/agentdev-runtime-images.md:97` — the hook scenario
  naming `/opt/agentdev-runtime`
- `docs/knowledge/data/spec/coder-ide-baseline.md:28` — the agent-start script
  requirement the Task 19 delta removes
- `py_packages/agentdev_runtime/agentdev_runtime/doctor.py:142` — `gateway`:
  `mcp-gateway` checked only when `COMPOSE_PROFILES` names `mcp`; `:233` —
  `git user` resolving identity through `git var`
- `.devcontainer/docker-compose.yml:70` — `COMPOSE_PROFILES` passed into the
  `devcontainer` service
- `py_packages/agentdev_runtime/agentdev_runtime/doctor.py:19` —
  `REQUIRED_TOOLS`, with `gitleaks` (`:30`) and `actionlint` (`:31`)
- `py_packages/agentdev_runtime/agentdev_runtime/project.py:82` — `hooks`:
  deploy and devcontainer hook registration; `:46` — `missing_executables`
- `.pre-commit-config.yaml:56` — `gitleaks`, a `language: system` hook; `:62` —
  `actionlint`
