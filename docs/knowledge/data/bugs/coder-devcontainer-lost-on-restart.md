---
type: bug
description: Restarting a coder-ide-baseline workspace discards the nested Docker's containerd image store, so the Dev Container can neither restart nor rebuild from the records left in /var/lib/docker.
generated:
  by: claude-code/opus-5.5
  at: 2026-10-12T23:00:00Z
sources:
- resource: https://github.com/plume-works/agent-devcontainer/blob/b0f0dfed/docs/knowledge/data/bugs/coder-devcontainer-lost-on-restart.md
- resource: https://github.com/plume-works/coder-ide-baseline/blob/1e3ace5/template/main.tf
- resource: https://github.com/plume-works/coder-ide-baseline/blob/349d8d6/template/main.tf
- resource: https://docs.docker.com/engine/storage/containerd/
stage: done
severity: critical
---

# Bug: Coder workspace Dev Container is lost on restart

## Symptom

After `coder restart` on a coder-ide-baseline workspace whose Dev Container was
already built, the Dev Container does not come up. Coder shows it as stopped or
errored with `exit status 1`, and no `repo` sub-agent connects.

- The surviving container refers to an image `vsc-agent-devcontainer-<hash>`
  that no longer exists. The devcontainer CLI tries to `docker pull` it from
  Docker Hub and fails with `pull access denied … repository does not exist`.
- Once that stale container is removed, the rebuild fails at export with
  `failed to extract layer sha256:…: failed to get reader from content store: content digest sha256:… not found`.
  BuildKit reuses `CACHED` steps whose blobs are gone.

## Reproduction

1. Start a workspace from coder-ide-baseline at `349d8d6`. Its nested Docker 29
   uses the containerd image store (`docker info` shows
   `driver-type: io.containerd.snapshotter.v1`).
2. Let the Dev Container build and come up healthy.
3. `coder restart <workspace> --yes`.
4. On the `dev` agent, `/tmp/coder-agent.log` shows
   `devcontainer creation failed … exit status 1`, and `docker images` lists no
   `vsc-agent-devcontainer-*` image.

## Root cause

With the containerd image store, Docker keeps container records and the BuildKit
cache in `/var/lib/docker`, but image content and the image database in
`/var/lib/containerd`. The template persists only `/var/lib/docker`
(`docker_volume.docker_lib`). `/var/lib/containerd` lives in the workspace
container, which every restart recreates. The surviving records in
`/var/lib/docker` then point at content that no longer exists.

## Fix

Fixed in coder-ide-baseline `1e3ace5` by [Persist the Coder workspace containerd
image store](../plans/20261011-persist-coder-workspace-containerd.md). The
template mounts per-workspace volumes at `/var/lib/containerd` and at the
containerd overlayfs snapshotter directory, next to `/var/lib/docker`, so a
restart keeps the image content the surviving Docker records point at. Each
workspace created before those volumes needs a one-time reset on the new
version: remove the stale Dev Container container, run
`docker builder prune -af`, then restart.

## Key references

Verified anchor points (line numbers as of 2026-10-11), in
`plume-works/coder-ide-baseline` at `349d8d6`:

- `template/main.tf:289` — `docker_volume.docker_lib`
- `template/main.tf:326` — `docker_container.workspace`
- `template/main.tf:379` — `runtime = "sysbox-runc"`
- `template/main.tf:392` — the `/var/lib/docker` volume mount, the only
  persisted Docker storage
