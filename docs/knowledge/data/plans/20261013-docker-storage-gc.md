---
type: plan
created: 2026-10-13
release:
- features/docker-storage-limits
description: Bound Docker storage in both engines of a Coder workspace — a 10 GB BuildKit cache limit in each daemon and a 72-hour unused-image prune on every agent start.
generated:
  by: claude-code/opus-5.5
  at: 2026-10-13T21:35:00Z
sources:
- resource: https://github.com/plume-works/agent-devcontainer/blob/2612a847/docs/knowledge/data/plans/20261013-docker-storage-gc.md
- resource: ansible/roles/install_docker/tasks/main.yml
- resource: .devcontainer/scripts/coder-agent-start.sh
- resource: .devcontainer/devcontainer.json
- resource: https://github.com/plume-works/coder-ide-baseline/blob/ab1c595/template/main.tf
- resource: https://github.com/plume-works/coder-ide-baseline/blob/ab1c595/root-container/Dockerfile
- resource: https://docs.docker.com/build/cache/garbage-collection/
- resource: https://docs.docker.com/reference/cli/docker/image/prune/
stage: done
completed: 2026-10-13
released: 2.0.0
---

# Cap Docker storage with automatic garbage collection

## Context

Every Coder workspace on the `coder-ide-baseline` template runs two Docker
engines, and all workspaces share one host disk:

- the **workspace engine** — the `dockerd` Sysbox provides inside the workspace
  container, which holds the Dev Container image;
- the **Dev Container engine** — the nested `dockerd` from the [docker-in-docker
  feature](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/architecture/nested-docker-provisioning.md),
  which holds the images and build cache of work done inside the Dev Container.

Neither engine limits its build cache or removes images it no longer uses, so
storage grows until the shared disk fills. A full disk stops any workspace from
pulling or unpacking its Dev Container image, and with no Dev Container its
sub-agent never starts, so nothing in
[coder-agent-start.sh](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/coder-ide-baseline.md)
runs either — including [Claude Remote
Control](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/claude-remote-control.md).

The Dev Container engine stays in place: replacing it with
docker-outside-of-docker breaks bind mounts of Dev Container paths outside the
repository, which running another image's tools against Dev Container files
depends on.

## Approach

Both engines get the same two limits, chosen by the maintainer:

- **Build cache:** BuildKit garbage collection enabled in each daemon's
  `daemon.json`, keeping at most 10 GB.
- **Images:** on every agent start, `docker image prune -af --filter until=72h`
  removes images that no container references and that were created more than 72
  hours ago. `until` compares the image's creation time, not its last use, so an
  unused image built or published more than 72 hours ago is removed even if it
  was pulled today; images referenced by any container, running or stopped, are
  kept.

The Dev Container engine's `daemon.json` comes from the image
(`ansible/roles/install_docker`), so the cache limit applies wherever the image
runs, Codespaces included. Its prune runs from `coder-agent-start.sh`, so it
runs on Coder only. The workspace engine's `daemon.json` ships in the
`coder-ide-baseline` base image, and its prune runs from the template's
`coder_agent` startup script once Docker is ready.

A failed or skipped prune never fails the agent start.

Rejected: turning off the containerd image store to keep all storage under one
directory, since it leaves both limits still needed and gives up Docker's
default store. Rejected: docker-outside-of-docker, for the bind-mount reason in
Context.

Assumption: the build-cache key is Docker's `builder.gc` block, whose field
names depend on the daemon version. Task 1 records the exact keys the installed
daemon accepts, and Tasks 2 and 4 use them.

## Implementation Steps

### Task 1: Settle the daemon configuration

**Files:** none (probe in a running Dev Container and a workspace container)

- [x] Record under `## Verification results`, for both the Dev Container engine
  and the workspace engine: the `dockerd` version, the `builder.gc` keys it
  accepts for a 10 GB limit (checked with `dockerd --validate --config-file`),
  and whether the docker-in-docker feature's `dockerd` reads
  `/etc/docker/daemon.json`.
  - **Evidence:** `## Verification results` records both engines at `dockerd`
    29.9.0 and `defaultMaxUsedSpace` as the key, read back through
    `docker buildx inspect` from a daemon started with each candidate config.

### Task 2: Limit the Dev Container engine's build cache

**Files:** Modify: `ansible/roles/install_docker/tasks/main.yml`

- [x] Add the Task 1 `builder.gc` block (enabled, 10 GB) to the `daemon.json`
  the role writes, keeping the existing log options.
  - **Evidence:** the role's `Configure Docker daemon` content carries
    `builder.gc` with `defaultMaxUsedSpace: "10GB"` beside the log options;
    `uv run ansible-lint ansible` and the `setup-dev.yml` syntax check pass, and
    the rendered JSON passes `dockerd --validate`. Its effect in a built image
    is Task 7.

### Task 3: Prune unused Dev Container images on agent start

**Files:** Create: `.devcontainer/scripts/docker-image-prune.sh`,
`scripts/tests/test_docker_image_prune.py`; Modify:
`.devcontainer/scripts/coder-agent-start.sh`,
`scripts/tests/test_coder_agent_start.py`

- [x] `docker-image-prune.sh` runs `docker image prune -af --filter until=72h`
  and prints the reclaimed total. It exits 0 without pruning when `docker` is
  missing or the daemon is unreachable, and exits 0 with a warning when the
  prune itself fails. Tests cover all three paths with a stub `docker`.
  - **Evidence:** `uv run pytest scripts/tests/test_docker_image_prune.py` — 4
    passed (prune and reclaimed total, docker missing, daemon unreachable, prune
    failure); `shellcheck` clean.
- [x] `coder-agent-start.sh` runs it before the credential helper, and a prune
  failure does not stop Remote Control from starting. Tests cover the order and
  the failure path.
  - **Evidence:**
    `uv run pytest scripts/tests/test_coder_agent_start.py scripts/tests/test_docker_image_prune.py`
    — 8 passed, including
    `test_prune_and_helper_setup_run_before_remote_control` and
    `test_remote_control_starts_when_prune_fails`; `shellcheck` clean.

### Task 4: Bound the workspace engine in coder-ide-baseline

**Files:** Create: `root-container/daemon.json`; Modify:
`root-container/Dockerfile`, `template/main.tf` (in
`plume-works/coder-ide-baseline`)

- [x] The base image installs `root-container/daemon.json` at
  `/etc/docker/daemon.json` with the Task 1 `builder.gc` block (enabled, 10 GB).
  - **Evidence:** plume-works/coder-ide-baseline@fe8ec1a adds
    `root-container/daemon.json` and its `COPY` to `/etc/docker/daemon.json`;
    the file passes `dockerd --validate`, and the PR #21 image build passed on
    amd64 and arm64 (Actions run 38414197899).
- [x] The `coder_agent.dev` startup script runs
  `docker image prune -af --filter until=72h` after Docker is ready, and only
  warns when it fails.
  - **Evidence:** plume-works/coder-ide-baseline@fe8ec1a runs the prune in the
    `docker info` success branch of the readiness check, with `||` printing a
    warning; `terraform validate` passes.
- [x] Open the pull request in `plume-works/coder-ide-baseline`, with
  `terraform fmt -check` and `terraform validate` passing as [Coder IDE
  baseline](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/coder-ide-baseline.md)
  describes.
  - **Evidence:** plume-works/coder-ide-baseline#21; `terraform fmt -check` and
    `terraform validate` pass under Terraform 1.16.5, and the required
    `Docker Build and Push` check passed.

### Task 5: Probe the template on a draft version

**Files:** none (live Coder deployment)

- [x] Push the Task 4 branch as a named draft template version
  (`--activate=false`), create a probe workspace from it, and record under
  `## Verification results` that `docker buildx inspect` in the workspace engine
  reports the GC policy and that the startup log shows the prune.
  - **Evidence:** draft version `docker-storage-gc-pr21` (inactive) and probe
    workspace `probe-docker-gc` on image
    `ghcr.io/plume-works/coder-ide-baseline:pr-21`; recorded under
    `## Verification results`.

### Task 6: Activate the template and update the workspaces

**Files:** none (live Coder deployment)

- [x] After the Task 4 pull request merges, push the activated version from the
  merge commit and `coder update` each workspace, one at a time.
  - **Evidence:** active version `motionless_ortega54` from
    plume-works/coder-ide-baseline@473d64a runs on every workspace; recorded
    under `## Verification results`.

### Task 7: Confirm the Dev Container engine in a rebuilt image

**Files:** none (published image, live workspace)

- [x] Once the published `agent-desktop` image carries Task 2 and its pin in
  `devcontainer-compose-pins.yml` is bumped, record under
  `## Verification results` that `docker buildx inspect` inside a rebuilt Dev
  Container reports the GC policy and that the agent-start log shows the prune.
  - **Evidence:** `agent-desktop:edge@sha256:12d03e8…` (revision `72094a3`),
    pinned by #331; recorded under `## Verification results`.

## Spec changes

[Coder IDE
baseline](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/coder-ide-baseline.md)
gains a requirement for the workspace engine; the Dev Container engine gets a
new spec, [Devcontainer Docker
storage](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/devcontainer-docker-storage.md).
Both delete data, so they carry full deltas.

``` markdown
## ADDED Requirements (spec/coder-ide-baseline)

### Requirement: the workspace engine bounds its own storage

The workspace engine SHALL run with BuildKit garbage collection enabled and a
10 GB build-cache limit, from `/etc/docker/daemon.json` in the base image. The
`coder_agent` startup script SHALL, once Docker is ready, remove images that no
container references and that were created more than 72 hours ago. A failed
prune SHALL NOT fail the startup script.

#### Scenario: a stopped Dev Container's image survives the prune

- **WHEN** the workspace restarts and the startup script prunes before the Dev
  Container is started again
- **THEN** the Dev Container's image is kept, because its stopped container
  references it.

#### Scenario: an old image is unreferenced

- **WHEN** an image created more than 72 hours ago is referenced by no container
  at agent start
- **THEN** the startup script removes it.
```

``` markdown
## ADDED Requirements (spec/devcontainer-docker-storage)

### Requirement: the Dev Container engine limits its build cache

The image's `/etc/docker/daemon.json` SHALL enable BuildKit garbage collection
with a 10 GB build-cache limit, and the nested `dockerd` SHALL run with it.

#### Scenario: the build cache passes the limit

- **WHEN** builds inside the Dev Container push the build cache past 10 GB
- **THEN** BuildKit garbage collection reduces it to at most 10 GB.

### Requirement: the agent start prunes unused Dev Container images

`coder-agent-start.sh` SHALL run `docker-image-prune.sh`, which removes images
in the Dev Container engine that no container references and that were created
more than 72 hours ago. The prune SHALL NOT prevent the rest of the agent start,
including Remote Control.

#### Scenario: Docker is unavailable

- **WHEN** `docker` is missing or its daemon does not answer
- **THEN** the script prunes nothing and exits successfully.

#### Scenario: the prune fails

- **WHEN** `docker image prune` exits non-zero
- **THEN** the script warns and exits successfully, and Remote Control still
  starts.

#### Scenario: an image is in use

- **WHEN** an image older than 72 hours is referenced by a running or stopped
  container
- **THEN** it is kept.
```

## Verification

- `uv run pytest scripts/tests/test_docker_image_prune.py scripts/tests/test_coder_agent_start.py`
- `shellcheck .devcontainer/scripts/docker-image-prune.sh`
- `terraform fmt -check` and `terraform validate` in
  `coder-ide-baseline/template`.
- Task 5 and Task 7 live checks: `docker buildx inspect` reports the GC policy
  in each engine, and the start logs show the prune.

## Verification results

Both engines run `dockerd` 29.9.0 (build `a5b58c9`), and neither passes
`--config-file`, so both read `/etc/docker/daemon.json`: the Dev Container
engine as started by the docker-in-docker feature, and the workspace engine from
its systemd unit. New containers in the Dev Container engine get the role's
`log-opts`. The workspace engine has no `daemon.json` today.

The 10 GB limit is
`"builder": {"gc": {"enabled": true, "defaultMaxUsedSpace": "10GB"}}`, which
caps every default GC rule at 10 GiB. The older `defaultKeepStorage` key sets
each rule's Reserved Space instead, which is a floor and not a cap.
`dockerd --validate` accepts unknown keys and malformed sizes under
`builder.gc`, so the effective policy has to be read back with
`docker buildx inspect`; `docker info` does not report it.

On the draft template version `docker-storage-gc-pr21`, a workspace from image
`pr-21` (index digest
`sha256:37408335405cfdcbd5ab15dba8f2915bf09babff67ac28320b652998cce0d6e4`) has
the template's `daemon.json` at `/etc/docker/daemon.json`. In that workspace
engine, `docker buildx inspect` reports every default GC rule at
`Max Used Space: 10GiB`, and the startup log follows `Docker is ready` with the
prune's `Total reclaimed space: 0B`.

Active version `motionless_ortega54`, pushed from
plume-works/coder-ide-baseline@473d64a, runs on `agent-dev1`, `agent-dev2`,
`agent-dev4`, `dr-qp-1`, and `agent-dev3`. In each, `docker buildx inspect`
reports the 10 GiB policy, the startup log shows the prune, and the stopped Dev
Container's image survived it, so the Dev Container restarted without a rebuild.

A workspace on that version whose Dev Container was built fresh from
`agent-desktop:edge@sha256:12d03e855edeba479dc08a51456baa250c0aa39d1c7036186b0981585bc81609`
(revision `72094a3`, pinned by #331) carries the role's `builder.gc` block in
`/etc/docker/daemon.json`. Its nested engine reports every default GC rule at
`Max Used Space: 10GiB` in `docker buildx inspect`, and the agent-start log
opens with the prune's `Total reclaimed space: 0B`, ahead of the credential
helper.

## Out of scope

- Pruning Docker volumes, containers, or networks.
- Replacing the Dev Container engine with docker-outside-of-docker.
- Sharing build cache between workspaces: [Share one BuildKit builder across
  Coder
  workspaces](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/plans/20261013-shared-buildkit-workspace.md).
- Deduplicating storage at the host filesystem: [Deduplicate Docker storage at
  the host
  filesystem](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/someday/host-filesystem-dedup.md).

## Key references

Verified anchor points (line numbers as of 2026-10-13):

- `ansible/roles/install_docker/tasks/main.yml:46` — `Configure Docker daemon`
  writes `/etc/docker/daemon.json`
- `.devcontainer/devcontainer.json:17` — docker-in-docker feature
- `.devcontainer/scripts/coder-agent-start.sh:9` — `docker-image-prune.sh` call;
  `:13` — credential helper call; `:17` — `exec` of
  `claude-remote-control-start.sh`
- `.devcontainer/scripts/docker-image-prune.sh` — the Dev Container engine prune
- `scripts/tests/test_coder_agent_start.py:43` —
  `test_prune_and_helper_setup_run_before_remote_control`
- `coder-ide-baseline` `template/main.tf:113` — `coder_agent.dev`; `:136` —
  Docker readiness wait in `startup_script`
- `coder-ide-baseline` `root-container/Dockerfile:47` —
  `systemctl enable docker`
