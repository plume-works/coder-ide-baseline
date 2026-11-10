---
type: architecture
description: How the root-container image, the Terraform template, and the Dev Container sub-agent fit together, and where workspace state lives.
generated:
  by: claude-code/opus-5.5
  at: 2026-11-07T18:33:04Z
sources:
- resource: template/main.tf
- resource: root-container/Dockerfile
- resource: root-container/daemon.json
- resource: root-container/docker-gc.timer
- resource: .github/workflows/root-container.yml
---

# Template layout

A workspace is three nested layers: the Docker host runs the workspace container
on `sysbox-runc`; the workspace container runs systemd, its own Docker engine,
and the Coder agent; that engine runs the repository's Dev Container, which
Coder exposes as a sub-agent.

## Root-container image

`root-container/Dockerfile` builds the workspace image on Ubuntu with Docker
Engine, containerd, the Buildx and Compose plugins, and systemd. systemd is PID
1 and `docker.service` supervises `dockerd`. `daemon.json` caps the BuildKit
cache, and `docker-gc.timer` runs `docker-gc` hourly to prune unreferenced
images, build cache, and disposable volumes. The `Docker Build and Push`
workflow builds each architecture on a native runner and joins them into one
manifest list.

## Workspace container

`template/main.tf` creates `docker_container.workspace` with `/sbin/init` as its
entrypoint: Sysbox sets a container up for systemd only when its first argument
is exactly that, so the Coder agent cannot start from a wrapper shell. The
template uploads the agent's init script, token, and a `coder-agent.service`
unit with a `multi-user.target` drop-in that pulls it in. The container stops on
`SIGRTMIN+3`, systemd's shutdown signal, with a 30-second grace period so
`dockerd` shuts down before the kill.

## State

Four `docker_volume` resources, named by workspace id, hold everything a restart
must keep: the home directory, `/var/lib/docker`, `/var/lib/containerd`, and the
containerd overlayfs snapshotter directory, which Sysbox would otherwise replace
with a per-container host directory. The container itself is disposable.

## Agent start and the Dev Container

The `coder_agent.dev` startup script seeds the home volume from `/etc/skel`
once, waits for Docker, clones the `repo` parameter's repository on first start,
and fast-forwards its current branch. `coder_devcontainer.repo` then brings the
checkout up as a Dev Container and registers it as the `repo` sub-agent.
Everything that must run inside the Dev Container with the agent's environment
runs as a `coder_script` on that sub-agent: `agent_start` runs the
`agent_start_script` command, and the OpenCode `coder_app` targets the same
sub-agent. Start scripts never wait for the Dev Container in the foreground,
because the agent starts it only after every start script exits.
