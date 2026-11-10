---
type: spec
description: How the coder-ide-baseline template runs the Dev Container repository named by its repo parameter, and how to change, validate, and ship a template version.
generated:
  by: claude-code/opus-5.5
  at: 2026-11-07T18:34:10Z
sources:
- resource: https://github.com/plume-works/agent-devcontainer/blob/ba79bda6/docs/knowledge/data/spec/coder-ide-baseline.md
- resource: template/main.tf
- resource: template/push.sh
---

# Workspace template

`template/main.tf` is published to Coder as the template `coder-ide-baseline`.
It runs the Dev Container repository named by the `repo` parameter, by default
[agent-devcontainer](https://github.com/plume-works/agent-devcontainer). This
spec records what the template owes that repository, and how to work on the
template. The Dev Container repository's side of the contract is
[agent-devcontainer's
spec/coder-ide-baseline](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/coder-ide-baseline.md).

## Requirements

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
such script exists, nothing SHALL run and the script's log SHALL say so. The
template SHALL NOT name any other command in the Dev Container repository; new
agent-start steps belong in `agentdev-runtime coder start`.

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

### Requirement: start scripts never wait for the Dev Container

The agent starts declared Dev Containers only after every `coder_script` on the
outer agent has exited. A start script that needs the Dev Container SHALL detach
its wait (for example `setsid … &`) and return immediately; a blocking wait
deadlocks the workspace start.

#### Scenario: a script needs the running Dev Container

- **WHEN** a start script must act inside the Dev Container
- **THEN** it launches a detached worker that polls `devcontainer exec` and
  exits at once.

### Requirement: workspace state lives in per-workspace volumes

The home directory, `/var/lib/docker`, `/var/lib/containerd`, and the containerd
overlayfs snapshotter directory SHALL each be a Docker volume named after the
workspace ID, with `lifecycle { ignore_changes = all }`, so template changes
never replace them and a restart keeps the built Dev Container image. When a
template version adds a state volume, each workspace created before it SHALL be
reset once on the new version. The reset removes the stale Dev Container
container and runs `docker builder prune -af`, so Docker holds no records that
point at content the new, empty volume lacks.

#### Scenario: the workspace restarts

- **WHEN** a workspace whose Dev Container is built is restarted
- **THEN** the Dev Container comes back without a rebuild.

### Requirement: the workspace engine bounds its own storage

The workspace engine SHALL run with BuildKit garbage collection enabled and a 10
GB build-cache limit, from `/etc/docker/daemon.json` in the base image. A
systemd `docker-gc.timer` in the base image SHALL run `/usr/local/bin/docker-gc`
15 minutes after boot and then hourly. Each run SHALL apply the
garbage-collection pass of [Devcontainer Docker
storage](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/devcontainer-docker-storage.md)
to the workspace engine, with the same image age, build-cache limit, and volume
patterns. A failed step SHALL only warn. The template's startup script SHALL NOT
prune.

#### Scenario: a stopped Dev Container's image survives the collection

- **WHEN** the Dev Container is stopped and the collector runs
- **THEN** the Dev Container's image is kept, because its stopped container
  references it.

#### Scenario: the workspace runs for days

- **WHEN** a workspace stays up for longer than 72 hours
- **THEN** unused images, build cache over 10 GB, and old unused disposable
  volumes are removed within an hour of qualifying, without a restart.

### Requirement: the template offers an OpenCode app

The `coder-ide-baseline` template SHALL attach a subdomain `coder_app` named
`OpenCode` to the Dev Container's sub-agent of every workspace with a
repository. Its URL SHALL be the server root, `http://localhost:4096`, and its
healthcheck SHALL request `http://localhost:4096/site.webmanifest`. The server
it opens is specified in [OpenCode
web](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/opencode-web.md).

#### Scenario: the repository runs OpenCode

- **WHEN** the repository's agent-start command started the OpenCode server
  (`opencode serve`)
- **THEN** the dashboard shows a healthy `OpenCode` app that loads the web UI,
  from whose project picker `/workspaces/<repository>` opens.

#### Scenario: the repository runs no OpenCode server

- **WHEN** nothing listens on port 4096 in the Dev Container
- **THEN** the `OpenCode` app shows unhealthy.

### Requirement: an active template version comes from `main`

Every template change SHALL merge to `main` by pull request; the ruleset
requires the `Docker Build and Push` check and linear history. The version
activated in Coder SHALL be pushed from the merge commit. A change that needs a
live probe before merge SHALL be pushed as a named, inactive draft version.

#### Scenario: probing a change before merge

- **WHEN** a change must be tried in a live workspace before it merges
- **THEN** it is pushed with `--activate=false` under a name, and a probe
  workspace is created from that version; active workspaces are not affected.

## Working on the template

### Checkout

In a Coder workspace, clone the template inside the Dev Container, into the
account's home:

``` bash
git clone https://github.com/plume-works/coder-ide-baseline ~/coder-ide-baseline
```

### Validate

Terraform is not installed in the Dev Container; run it from the
`hashicorp/terraform` image. `init` writes `.terraform/`, so `validate` runs in
a copy:

``` bash
cd ~/coder-ide-baseline/template
docker run --rm -v "$PWD":/w -w /w hashicorp/terraform:1.13.5 fmt -check -diff
docker run --rm -v "$PWD":/src:ro --entrypoint sh hashicorp/terraform:1.13.5 -c \
  'cp -r /src /w && cd /w && terraform init -backend=false -input=false >/dev/null && terraform validate'
```

### Push a version

The Coder CLI is at `/.coder-agent/coder` inside the Dev Container and is not on
`PATH`. `template/push.sh` defaults `TEMPLATE_NAME` to `coder-ide-baseline`.
`coder templates push` activates the new version by default.

``` bash
export PATH="/.coder-agent:$PATH"

# Active version, from the merge commit on main:
TEMPLATE_NAME=coder-ide-baseline template/push.sh

# Inactive draft for a probe, then a workspace on it:
coder templates push coder-ide-baseline --directory template \
  --activate=false --name <draft-name> --yes
coder create <probe-workspace> --template coder-ide-baseline \
  --template-version <draft-name>

coder templates versions list coder-ide-baseline
```

### Roll out and verify

After a new version is activated, existing workspaces report as outdated until
`coder update <workspace>`, which restarts them. A restart ends every session
running inside that workspace, including an agent's own. An agent therefore
verifies restart behavior in a different workspace, such as a probe, or hands
the restart to the operator.

Run `coder update <workspace>` from a different workspace or machine, never from
inside the target. The CLI sends a stop build, then a start build, and the stop
ends the CLI with the workspace, so a self-update leaves it stopped and still
outdated. Recover with `coder update <workspace>` from elsewhere.

A workspace that has not yet restarted on a version that runs
`agentdev-runtime coder start` has no github.com credential helper. There,
`git push` over HTTPS hangs on Coder's `GIT_ASKPASS` ([Bug: HTTPS git push hangs
on Coder's askpass when gh's login is only a session
token](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/bugs/coder-askpass-push-hang.md)).
Push with a one-off helper instead, which changes no git config:

``` bash
GIT_ASKPASS= git -c credential.helper= \
  -c 'credential.helper=!gh auth git-credential' push
```
