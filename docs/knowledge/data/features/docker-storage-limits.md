---
type: feature
stage: implemented
description: Both Docker engines of a Coder workspace bound their storage — a 10 GB BuildKit cache limit in each daemon and an hourly garbage collection of unused images, build cache and disposable volumes — so workspaces sharing one host disk do not fill it.
generated:
  by: claude-code/opus-5.5
  at: 2026-10-16T12:00:00Z
sources:
- resource: https://github.com/plume-works/agent-devcontainer/blob/2612a847/docs/knowledge/data/features/docker-storage-limits.md
- resource: docs/knowledge/data/plans/20261013-docker-storage-gc.md
- resource: ansible/roles/install_docker/tasks/main.yml
- resource: py_packages/agentdev_runtime/agentdev_runtime/docker.py
- resource: docs/knowledge/data/plans/20261101-docker-storage-periodic-gc.md
---

# Docker storage limits

## Purpose

A Coder workspace runs two Docker engines — the workspace engine and the nested
Dev Container engine — and every workspace shares one host disk. Unbounded build
caches and unused images fill it, and a full disk stops any workspace from
starting its Dev Container.

## Behaviour

**Build cache.** Each engine's `daemon.json` enables BuildKit garbage collection
and keeps at most 10 GB of cache. The Dev Container engine's limit comes from
the image, so it applies wherever the image runs.

**Hourly collection.** Each engine runs a garbage-collection pass when it starts
and then hourly. A pass:

- removes images that no container references and that were created more than 72
  hours ago;
- trims the build cache that no kept image shares to 10 GB;
- removes volumes that no container references, whose names mark them as
  disposable, and that were created more than 72 hours ago.

The Dev Container engine's pass is a supervised service of the image, so it runs
wherever the image runs. The workspace engine's pass is a systemd timer.

The contract is [Devcontainer Docker
storage](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/devcontainer-docker-storage.md).

## Edge cases

- **An unused image pulled today but built long ago** is removed: the 72-hour
  window compares creation time, not last use.
- **An image a stopped container references** is kept.
- **Build cache a kept image shares** is kept until the image is removed.
- **A volume with any other name**, such as a login volume, is never removed.
- **A step fails or Docker is unreachable.** The pass warns and carries on;
  nothing else fails.

## Open questions

None — the design is settled.

## References

- Plan: [Cap Docker storage with automatic garbage
  collection](../plans/20261013-docker-storage-gc.md)
- Plan: [Collect Docker garbage hourly in both workspace
  engines](../plans/20261101-docker-storage-periodic-gc.md)
