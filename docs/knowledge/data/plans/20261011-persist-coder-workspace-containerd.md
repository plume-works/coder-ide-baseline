---
type: plan
stage: done
created: 2026-10-11
completed: 2026-10-12
released: 2.0.0
description: Mount a persistent volume at /var/lib/containerd in the coder-ide-baseline workspace container so the nested Docker's containerd image store survives a workspace restart alongside /var/lib/docker.
generated:
  by: claude-code/opus-5.5
  at: 2026-10-12T13:10:38Z
sources:
- resource: https://github.com/plume-works/agent-devcontainer/blob/95c94b6d/docs/knowledge/data/plans/20261011-persist-coder-workspace-containerd.md
- resource: https://github.com/plume-works/coder-ide-baseline/blob/349d8d6/template/main.tf
- resource: https://docs.docker.com/engine/storage/containerd/
- resource: https://containerd.io/docs/2.2/snapshotters/readme/
---

# Persist the Coder workspace containerd image store

## Context

Coder workspaces from
[plume-works/coder-ide-baseline](https://github.com/plume-works/coder-ide-baseline)
run a nested Docker engine under Sysbox. Docker 29 uses the containerd image
store by default on fresh installs, and the workspace engine reports
`driver-type: io.containerd.snapshotter.v1`. With that store, Docker keeps
container records, volumes, and the BuildKit cache in `/var/lib/docker`, while
image blobs, manifests, the image database, and unpacked layers live under
`/var/lib/containerd`.

The template persists only `/var/lib/docker` (`docker_volume.docker_lib`). Every
workspace restart recreates the workspace container, which discards
`/var/lib/containerd`. The records that survive in `/var/lib/docker` (the Dev
Container's container and BuildKit cache entries) then refer to image content
that no longer exists, so the Dev Container can neither restart nor rebuild from
them: [Bug: Coder workspace Dev Container is lost on
restart](../bugs/coder-devcontainer-lost-on-restart.md).

The Dev Container therefore does not survive a restart, and nothing that runs in
it on agent start runs either. This blocks the restart-based live check that
[Start Claude Remote Control from the Coder
agent](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/plans/20261011-coder-claude-remote-control.md)
needs.

## Approach

Add a second per-workspace `docker_volume`, shaped like `docker_lib`, and mount
it at `/var/lib/containerd` in `docker_container.workspace`. Both halves of the
engine's storage then persist together. This follows the pattern this
repository's own Dev Container uses: the docker-in-docker feature gives it
separate volumes for `/var/lib/docker` and `/var/lib/containerd`.

Sysbox already mounts a host directory at
`/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs` inside the
workspace. How that mount interacts with a user volume on the parent directory
is unverified. Task 1 settles it before the template changes. If the Sysbox
mount shadows the volume at that path, the snapshotter directory needs its own
persistent volume too, and Task 2 carries whichever layout Task 1 confirms.

Rejected: turning off the containerd image store
(`"features": {"containerd-snapshotter": false}` in the workspace `daemon.json`)
and keeping everything in the persisted `/var/lib/docker`. That would be simpler
and use less disk. But it pins the workspace engine to Docker's legacy storage
path and gives up local multi-platform images and attestations. The maintainer
chose to stay on Docker's default store.

## Implementation Steps

### Task 1: Settle the Sysbox mount layout

**Files:** none (live workspace, in `plume-works/coder-ide-baseline`)

- [x] In a workspace started from a draft template version (not promoted to
  active) that adds the `/var/lib/containerd` volume, record from `mount` inside
  the workspace container whether
  `/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs` is backed by the
  new volume or by a separate Sysbox mount. Record the result under
  `## Verification results`, along with the layout Task 2 adopts.
  - **Evidence:** `findmnt` in `anton/containerd-probe`, created from draft
    template version `containerd-probe-1` (2026-10-12): the snapshotter
    directory is a separate Sysbox mount over the new volume. The layout is
    recorded under `## Verification results`.

### Task 2: Add the containerd volume to the template

**Files:** Modify (in `plume-works/coder-ide-baseline`): `template/main.tf`

- [x] Add `docker_volume.containerd_lib` named
  `coder-${data.coder_workspace.me.id}-containerd`, with the same
  `lifecycle { ignore_changes = all }` and `coder.*` labels as
  `docker_volume.docker_lib`. Mount it in `docker_container.workspace` at
  `/var/lib/containerd`, next to the `/var/lib/docker` mount, plus any
  snapshotter mount that Task 1 requires. `terraform validate` passes.
  - **Evidence:** Coder template version `containerd-probe-2` of
    `coder-ide-baseline` (pushed as a draft, not active) carries the change. It
    adds `containerd_lib` and `containerd_snapshots`, mounted at
    `/var/lib/containerd` and at the overlayfs snapshotter directory. The same
    change merged as coder-ide-baseline `1e3ace5` (see the next task).
    `terraform fmt -check` and `terraform validate` pass under Terraform 1.13.5.
- [x] Push the template version to Coder.
  - **Evidence:**
    [plume-works/coder-ide-baseline#19](https://github.com/plume-works/coder-ide-baseline/pull/19)
    was squash-merged as `1e3ace5` after its required Docker Build and Push
    check passed. `TEMPLATE_NAME=coder-ide-baseline template/push.sh` at
    `1e3ace5` created `condemned_miles04`, now the only active version
    (2026-10-12). Its plan lists `docker_volume.containerd_lib` and
    `docker_volume.containerd_snapshots`. The version also ships #18's
    `vscode-web` module, which the maintainer chose to include.

### Task 3: Prove images survive a restart

**Files:** none (live workspace)

- [x] In a workspace on the new template version whose Dev Container has been
  built, run `coder restart`. The Dev Container comes back up without a rebuild:
  the agent log shows no `Building` step, `docker images` inside the workspace
  still lists the `vsc-agent-devcontainer-*` image, and the `repo` sub-agent
  reports healthy.
  - **Evidence:** run on draft version `containerd-probe-2` in
    `anton/containerd-probe2` (2026-10-12), which the maintainer accepted as the
    new template version. After `coder restart`, the Dev Container's original
    container came back without a rebuild, and both agents were healthy.
    Recorded under `## Verification results`.

### Task 4: Reset workspaces created before the volume

**Files:** none (each existing workspace)

- [x] For each workspace that predates the template change, after its first
  start on the new version: remove the stale Dev Container container and run
  `docker builder prune -af`, so `/var/lib/docker` no longer holds records that
  point at content the new, empty volume lacks. Restart, and confirm that the
  Dev Container builds and comes up healthy.
  - **Evidence:** all five pre-existing workspaces (`agent-dev1` to
    `agent-dev4`, `dr-qp-1`) were reset on `condemned_miles04` (2026-10-12);
    each Dev Container rebuilt with a healthy `repo` sub-agent, and `coder list`
    shows all five healthy and not outdated. Recorded under
    `## Verification results`.

## Spec changes

None — no behavioral change. The change lives in the Coder template, outside
this repository's specs.

## Verification

- `terraform validate` in `coder-ide-baseline/template`.
- Task 3's restart check on a fresh workspace, and Task 4's on each existing
  one.
- After a restart, the Dev Container's agent-start scripts run. One observable
  sign: `tmux -L claude-remote ls` lists the `claude-remote` session in a
  workspace logged in to claude.ai.

## Verification results

### Sysbox mount layout (Task 1)

In a workspace on draft version `containerd-probe-1`, which mounts one volume at
`/var/lib/containerd`, `findmnt` shows:

- `/var/lib/containerd` is backed by the `coder-<workspace-id>-containerd`
  volume.
- `/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs` is a separate
  Sysbox mount over that volume. Its host source is
  `/var/lib/sysbox/containerd/<container-id>`, so the unpacked snapshots are
  lost whenever the workspace container is recreated.
- `/var/lib/docker` is backed only by its volume, with no Sysbox mount.
- The engine reports `driver-type io.containerd.snapshotter.v1`.

Sysbox treats `/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs` as a
special directory, as it does the inner Docker data root. It skips its own mount
there when the container spec already bind-mounts that exact destination
(`getSpecialDirs` and `sysMgrSetupMounts` in `nestybox/sysbox-runc`
`libsysbox/syscont/spec.go`). That is why `/var/lib/docker` carries no Sysbox
mount.

Layout Task 2 adopts: a third per-workspace volume,
`coder-<workspace-id>-containerd-snapshots`, mounted directly at
`/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs`, in addition to the
`/var/lib/containerd` volume.

### Restart survival (Task 3)

In a workspace on draft version `containerd-probe-2`, after the Dev Container
had been built and the workspace restarted with `coder restart`:

- `findmnt -R /var/lib/containerd` shows `/var/lib/containerd` backed by the
  `-containerd` volume and the overlayfs snapshotter directory backed by the
  `-containerd-snapshots` volume, with no `/var/lib/sysbox/containerd` source.
- `docker images` still lists the `vsc-agent-devcontainer-*` image, in use.
- `docker ps -a` shows the Dev Container that was created before the restart
  running again, so it was not rebuilt.
- `coder show` reports the `dev` agent and the `repo` sub-agent connected and
  healthy.

### Existing-workspace reset (Task 4)

On active version `condemned_miles04` (2026-10-12), for the five workspaces that
predate the volume — `agent-dev1` to `agent-dev4` and `dr-qp-1`, whose
repository first took the current agent-devcontainer template
([Dr-QP/Dr.QP#550](https://github.com/Dr-QP/Dr.QP/pull/550)):

- Each failed its first start on the new version as expected: the Dev
  Container's image was missing, and its stale container had exited. On
  `agent-dev1`, `agent-dev4` and `dr-qp-1`, `findmnt` showed the new volumes
  mounted, with no Sysbox source.
- On each, the stale Dev Container container was removed, then
  `docker builder prune -af` ran, then `coder restart`. The Dev Container
  rebuilt, and the `repo` sub-agent came back healthy. `coder list` shows all
  five on `condemned_miles04`, healthy and not outdated.
- `tmux -L claude-remote ls` lists the `claude-remote` session on `agent-dev2`,
  `agent-dev3` and `agent-dev4`. `agent-dev1` is not logged in to claude.ai, so
  the check does not apply there.
- The check does not apply to `dr-qp-1` either: the template's Remote Control
  script expects the checkout at `/workspaces/<repo>` inside the Dev Container,
  and Dr.QP's compose file does not mount it there.

## Out of scope

- Turning off the containerd image store (the rejected alternative).
- Automating Task 4's one-time reset in the template's startup script.
- Disk-usage limits or pruning policy for the workspace volumes.

## Key references

Verified anchor points (line numbers as of 2026-10-11), in
`plume-works/coder-ide-baseline` at `783e98a`:

- `template/main.tf:193` — `coder_devcontainer.repo`
- `template/main.tf:275` — `docker_volume.home_volume`
- `template/main.tf:301` — `docker_volume.docker_lib`, the shape to copy
- `template/main.tf:338` — `docker_container.workspace`
- `template/main.tf:391` — `runtime = "sysbox-runc"`
- `template/main.tf:406` — the `/var/lib/docker` volume mount
