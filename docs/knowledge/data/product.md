---
type: tracker
description: What the coder-ide-baseline Coder template is, who uses it, and the constraints every plan and spec derives from.
stage: living
generated:
  by: claude-code/opus-5.5
  at: 2026-11-07T18:32:47Z
sources:
- resource: README.md
- resource: template/main.tf
- resource: root-container/Dockerfile
- resource: .github/workflows/root-container.yml
---

# Product

## What is it

A Coder workspace template that runs a repository's Dev Container inside a
Docker-in-Docker workspace.

`coder-ide-baseline` is two things that ship together: the root-container image,
`ghcr.io/plume-works/coder-ide-baseline`, which a workspace runs on with systemd
and its own Docker engine, and the Terraform template under `template/`, which
creates that workspace, clones the repository named by the `repo` parameter,
brings it up as a Dev Container, and exposes it as a Coder sub-agent that
editors attach to. The default repository is
[agent-devcontainer](https://github.com/plume-works/agent-devcontainer), whose
side of the contract is its
[spec/coder-ide-baseline](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/coder-ide-baseline.md).

## Users

The maintainer, running `agent-devcontainer` and other Dev Container
repositories as Coder workspaces on their own Docker host. It is not a
general-purpose public template: changes are judged by that deployment, and
adopting it elsewhere is not a goal.

## Platforms

- Coder, with the `coder/coder` Terraform provider (`~> 2.19`) and the
  `kreuzwerker/docker` provider (`~> 4.6`) against a Docker host that has the
  Sysbox runtime (`sysbox-runc`) installed.
- The root-container image is built for `linux/amd64` and `linux/arm64` and
  published to GHCR: `latest` from `main`, a tag per published release, and
  `pr-<number>` per pull request.
- A template version is pushed to Coder with `template/push.sh` (`TEMPLATE_NAME`
  defaults to `coder-ide-baseline`).

## Stack

- `template/main.tf` — the Coder template: parameters (`image`, `repo`,
  `second_repo`, `agent_start_script`), the `coder_agent`, the
  `coder_devcontainer` sub-agent, apps and scripts, per-workspace Docker
  volumes, and the workspace container.
- `template/push.sh` — creates or updates the template in Coder.
- `root-container/` — the workspace image: an Ubuntu `Dockerfile` with Docker
  Engine, containerd and systemd, `daemon.json`, and the `docker-gc` service and
  timer; `build.sh` builds it locally for the current architecture.
- `.github/workflows/root-container.yml` — `Docker Build and Push`: builds each
  architecture on a native runner and merges a manifest list; it runs on every
  pull request to `main` and is the required check.

## Constraints

- Workspaces run on `sysbox-runc` and never require a privileged container.
- The root-container image builds and publishes for both `amd64` and `arm64`.
- Workspace state survives a stop and start: home, Docker and containerd state
  live in per-workspace volumes.

## Authoring rules

- all documents — follow `agent-devcontainer`'s `AGENTS.md` rules: record
  durable knowledge only, never a working logbook; name every actor and artifact
  by its real name. For the Dev Container repository's side of the contract,
  link `agent-devcontainer`'s `spec/coder-ide-baseline` on `main` instead of
  restating it.
- plans — a plan that changes `root-container/` verifies the pull request's
  `pr-<number>` image in a real workspace before merge.

## Changelog

- 2026-11-07 — filled from the repository and the maintainer's answers during
  onboarding.
