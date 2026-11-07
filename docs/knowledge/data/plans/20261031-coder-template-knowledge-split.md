---
type: plan
created: 2026-10-31
release: internal
stage: done
completed: 2026-11-07
description: Give plume-works/coder-ide-baseline its own IWE workspace holding the template's requirements and how to work on it, and narrow this repository's Coder spec to what the repository owes the template.
generated:
  by: claude-code/opus-5.5
  at: 2026-11-07T19:40:11Z
sources:
- resource: https://github.com/plume-works/agent-devcontainer/blob/2612a847/docs/knowledge/data/plans/20261031-coder-template-knowledge-split.md
- resource: docs/knowledge/data/spec/coder-ide-baseline.md
- resource: docs/knowledge/data/bugs/coder-devcontainer-lost-on-restart.md
- resource: docs/knowledge/data/plans/20261011-persist-coder-workspace-containerd.md
- resource: docs/knowledge/data/bugs/workspace-image-lacks-hook-binaries.md
- resource: .agents/plugins/agentdev/skills/iwe-bootstrap/SKILL.md
- resource: https://github.com/plume-works/coder-ide-baseline/blob/4a2d980/template/main.tf
- resource: https://github.com/plume-works/coder-ide-baseline/blob/4a2d980/.github/workflows/root-container.yml
- resource: https://github.com/plume-works/coder-ide-baseline/blob/4a2d980/template/push.sh
released: 2.1.0
---

# Move the Coder template's knowledge into coder-ide-baseline

## Context

[Coder IDE baseline
template](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/coder-ide-baseline.md)
specifies two repositories at once. Most of its requirements describe what the
`plume-works/coder-ide-baseline` Terraform template does: run the agent-start
script, keep state in per-workspace volumes, bound the workspace engine, offer
the OpenCode app, ship versions from `main`. Its `## Working on the template`
section is a runbook for that repository. Only one requirement constrains this
repository. The template repository has no project memory, so its contract and
runbook live where its own changes cannot update them.

The maintainer decided:

- Each requirement lives in the repository whose code satisfies it. The
  template's requirements and runbook move to an IWE workspace in
  `coder-ide-baseline`; this repository keeps what it owes the template.
- History stays here. Finished plans, fixed bugs, `log.md`, and release notes
  are not moved or edited. The two documents about template-only work, [Bug:
  Coder restart loses the Dev
  Container](../bugs/coder-devcontainer-lost-on-restart.md) and [Persist the
  Coder workspace containerd
  store](20261011-persist-coder-workspace-containerd.md), are copied into the
  new workspace; the originals stay unchanged.
- The new workspace is bootstrapped, then onboarded with `/agentdev:iwe-setup`.

## Approach

The spec here keeps its key, `spec/coder-ide-baseline`, so the documents that
link it keep resolving; its title and introduction change to say it is this
repository's side of the contract. It keeps
`Coder user secrets reach only agent-started processes` and gains one
requirement: the repository ships the agent-start command the template defaults
to. The six other requirements and the runbook move, as written, to the template
workspace's `data/spec/workspace-template.md`. Links between the repositories
are GitHub URLs on `main`; `## Verification` checks that each one resolves.

The template work lands first, through one pull request in `coder-ide-baseline`,
so every URL this repository adds already resolves. This repository's spec edits
are applied by Ship from `## Spec changes`.

Rejected: moving the whole spec, which leaves the agent-start entry point with
no contract in the repository that ships it; keeping a copy in each repository,
which leaves two texts to drift; and moving every document that touches the
template, which takes this repository's half of mixed plans with it.

This plan starts after the [off-bash migration](20261029-off-bash-migration.md)
ships. That plan replaces `coder-agent-start.sh` with
`agentdev-runtime coder start`, makes the template's `agent_start_script` a
command defaulting to it, and rewrites the hook requirement as
`the agent-start command is the repository's only start hook`. The requirements
that move carry that wording, and the added requirement names the command.

## Implementation Steps

Tasks 1-6 run in a `coder-ide-baseline` checkout (in a Coder workspace,
`/workspaces/coder-ide-baseline`), from its repository root.

### Task 1: Bootstrap the template workspace

**Files:** Create (in `plume-works/coder-ide-baseline`): `.iwe/`,
`docs/knowledge/`

- [x] Create a work branch in `coder-ide-baseline` from fresh `origin/main` with
  `/agentdev:git-new-branch`.
  - **Evidence:** branch `iwe-knowledge-workspace` of [coder-ide-baseline
    #36](https://github.com/plume-works/coder-ide-baseline/pull/36), created
    with `git checkout -b` from a fresh clone of `origin/main` at e437dc2; the
    `/agentdev:git-new-branch` skill was not loaded in the session.
- [x] `/agentdev:iwe-bootstrap` with `--root` set to the checkout returns
  `RESULT=SUCCESS`.
  - **Evidence:** `bootstrap-iwe.py --root /workspaces/coder-ide-baseline`
    printed `RESULT=SUCCESS`; scaffold committed as coder-ide-baseline 2114c7a
    in [coder-ide-baseline
    #36](https://github.com/plume-works/coder-ide-baseline/pull/36).

### Task 2: Onboard the template workspace

**Files:** Modify (in `plume-works/coder-ide-baseline`):
`docs/knowledge/data/product.md`

- [x] `/agentdev:iwe-setup` fills `product.md`, with the maintainer answering
  its questions; no ✏️ placeholder remains.
  - **Evidence:** coder-ide-baseline ce8b1d5 in [coder-ide-baseline
    #36](https://github.com/plume-works/coder-ide-baseline/pull/36):
    `product.md` filled from the code and the maintainer's answers,
    `architecture/template-layout.md` added, examples removed; `grep -c ✏️`
    prints 0 and `iwe schema validate` passes.

### Task 3: Write the template spec

**Files:** Create (in `plume-works/coder-ide-baseline`):
`docs/knowledge/data/spec/workspace-template.md`; Modify:
`docs/knowledge/data/spec.md`

- [x] `spec/workspace-template` holds these requirements of
  `agent-devcontainer`'s `spec/coder-ide-baseline`, with all their scenarios, as
  they read once the off-bash migration has shipped:
  `the agent-start command is the repository's only start hook`,
  `start scripts never wait for the Dev Container`,
  `workspace state lives in per-workspace volumes`,
  `the workspace engine bounds its own storage`,
  `the template offers an OpenCode app`, and
  `an active template version comes from main`, followed by the whole
  `## Working on the template` section. The text moves unchanged, with three
  exceptions: "this repository" becomes the Dev Container repository named by
  the `repo` parameter, relative links become `agent-devcontainer` URLs on
  `main`, and `### Push a version` states the `TEMPLATE_NAME` default that
  `template/push.sh` has on `main` (`coder-ide-baseline`). Its `sources` name
  the `agent-devcontainer` spec at the commit copied.
  - **Evidence:** coder-ide-baseline 11e00fe in [coder-ide-baseline
    #36](https://github.com/plume-works/coder-ide-baseline/pull/36): six
    requirements and `## Working on the template` copied from
    `spec/coder-ide-baseline` at ba79bda6 by a script that asserts each of the
    three named substitutions matched once.
- [x] The spec's introduction links `agent-devcontainer`'s
  `spec/coder-ide-baseline` as the Dev Container repository's side of the
  contract, and `spec.md` links the new spec.
  - **Evidence:** coder-ide-baseline 11e00fe in [coder-ide-baseline
    #36](https://github.com/plume-works/coder-ide-baseline/pull/36): the
    introduction links `spec/coder-ide-baseline` on `main`, and `spec.md` links
    `spec/workspace-template`.

### Task 4: Copy the template-only history

**Files:** Create (in `plume-works/coder-ide-baseline`):
`docs/knowledge/data/bugs/coder-devcontainer-lost-on-restart.md`,
`docs/knowledge/data/plans/20261011-persist-coder-workspace-containerd.md`;
Modify: `docs/knowledge/data/bugs.md`, `docs/knowledge/data/plans.md`

- [x] Both documents are copied unchanged apart from links: the link between the
  two stays relative, and every other relative link becomes an
  `agent-devcontainer` URL on `main`. Each one's `sources` names its original at
  the commit copied.
  - **Evidence:** coder-ide-baseline 251b664 in [coder-ide-baseline
    #36](https://github.com/plume-works/coder-ide-baseline/pull/36): the bug and
    plan copied from b0f0dfed and 95c94b6d; the only body change is the plan's
    Remote Control link, now an `agent-devcontainer` URL on `main`, and each
    `sources` names its original.
- [x] `bugs.md` links the bug, and `plans.md` links the plan, each as an entry
  in the hub's flat sorted list.
  - **Evidence:** coder-ide-baseline 251b664 in [coder-ide-baseline
    #36](https://github.com/plume-works/coder-ide-baseline/pull/36).

### Task 5: Validate and commit the template workspace

**Files:** none

- [x] `iwe normalize` and then `iwe schema validate` pass in the template
  checkout, and the branch is committed and pushed.
  - **Evidence:** both pass on coder-ide-baseline 251b664, the head pushed as
    branch `iwe-knowledge-workspace` of [coder-ide-baseline
    #36](https://github.com/plume-works/coder-ide-baseline/pull/36).

### Task 6: Merge the template pull request

**Files:** none (in `plume-works/coder-ide-baseline`)

- [x] A pull request carrying Tasks 1-5 passes the required
  `Docker Build and Push` check and merges to `main`.
  - **Evidence:** [coder-ide-baseline
    #36](https://github.com/plume-works/coder-ide-baseline/pull/36) passed
    `Docker Build and Push` ([run
    42402042120](https://github.com/plume-works/coder-ide-baseline/actions/runs/42402042120))
    and merged to `main` as 5ff6817.

## Spec changes

[Coder IDE baseline
template](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/coder-ide-baseline.md)
is retitled `Coder IDE baseline contract`, its description and introduction say
it is this repository's side of the template contract and link
`coder-ide-baseline`'s `spec/workspace-template` on `main`, and its
`## Working on the template` section is removed.
`Coder user secrets reach only agent-started processes` is unchanged.

``` markdown
## ADDED Requirements (spec/coder-ide-baseline)

### Requirement: the repository ships the Coder agent-start command

The repository SHALL ship `agentdev-runtime coder start`, the command the
`coder-ide-baseline` template's `agent_start_script` parameter defaults to.
Every step that runs on a Coder agent start SHALL run from it; the repository
SHALL NOT rely on the template running any other command in it.

#### Scenario: a workspace starts on the default parameter

- **WHEN** a `coder-ide-baseline` workspace starts with the default
  `agent_start_script`
- **THEN** `agentdev-runtime coder start` runs in the Dev Container with the
  Coder user secrets in its environment.

#### Scenario: a new agent-start step

- **WHEN** a setup step must run on every Coder agent start
- **THEN** it is added to `agentdev-runtime coder start`, not to the template.

## REMOVED Requirements (spec/coder-ide-baseline)

Each of these specifies the template, not this repository, and moves unchanged
to `coder-ide-baseline`'s `spec/workspace-template`:

- the agent-start command is the repository's only start hook
- start scripts never wait for the Dev Container
- workspace state lives in per-workspace volumes
- the workspace engine bounds its own storage
- the template offers an OpenCode app
- an active template version comes from `main`
```

Introductions only, no requirement changes: [Devcontainer Docker
storage](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/devcontainer-docker-storage.md)
links the workspace engine's bound, and [OpenCode
web](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec/opencode-web.md)
links the dashboard app, to `coder-ide-baseline`'s `spec/workspace-template`
URL.
[Specifications](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/spec.md)
lists the retitled spec.

## Depends on

- [Replace the runtime shell scripts with one agentdev-runtime
  CLI](20261029-off-bash-migration.md)

## Verification

- In the template checkout on `main`: `iwe schema validate` passes;
  `grep -c '^### Requirement:' docs/knowledge/data/spec/workspace-template.md`
  prints `6`; `product.md` has no ✏️.
- Each requirement removed here appears in `spec/workspace-template` with the
  same SHALL text and scenarios, apart from the exceptions Task 3 names.
- Here, after Ship:
  `grep -c '^### Requirement:' docs/knowledge/data/spec/coder-ide-baseline.md`
  prints `2`, and `iwe schema validate` passes.
- Every `coder-ide-baseline` URL this plan adds returns the file from
  `gh api repos/plume-works/coder-ide-baseline/contents/<path>`.
- `git diff` of this plan's changes touches no plan under `data/plans/` other
  than this one, and no document under `data/bugs/`.

## Out of scope

- Moving or editing finished plans, fixed bugs, `log.md`, or release notes here.
- The documents of this repository's features that run on Coder (Remote Control
  and OpenCode autostart, the shared BuildKit builder) and the active [shared
  BuildKit
  plan](https://github.com/plume-works/agent-devcontainer/blob/main/docs/knowledge/data/plans/20261013-shared-buildkit-workspace.md),
  whose template task keeps naming `coder-ide-baseline`.
- Adopting the agentdev catalog or a root `AGENTS.md` in `coder-ide-baseline`
  (`/agentdev:template-consume`); until then, IWE skills reach that workspace
  only from a session that has the catalog.
- Changing the template's default `agent_start_script` value; the moved hook
  requirement keeps whatever the off-bash migration shipped.

## Key references

Verified anchor points (line numbers as of 2026-11-07):

- `docs/knowledge/data/spec/coder-ide-baseline.md:29` — Requirement: the
  agent-start command is the repository's only start hook
- `docs/knowledge/data/spec/coder-ide-baseline.md:69` — Requirement: Coder user
  secrets reach only agent-started processes
- `docs/knowledge/data/spec/coder-ide-baseline.md:82` — Requirement: start
  scripts never wait for the Dev Container
- `docs/knowledge/data/spec/coder-ide-baseline.md:95` — Requirement: workspace
  state lives in per-workspace volumes
- `docs/knowledge/data/spec/coder-ide-baseline.md:111` — Requirement: the
  workspace engine bounds its own storage
- `docs/knowledge/data/spec/coder-ide-baseline.md:134` — Requirement: the
  template offers an OpenCode app
- `docs/knowledge/data/spec/coder-ide-baseline.md:154` — Requirement: an active
  template version comes from `main`
- `docs/knowledge/data/spec/coder-ide-baseline.md:167` —
  `## Working on the template`
- `docs/knowledge/data/spec/devcontainer-docker-storage.md:25` — workspace
  engine link
- `docs/knowledge/data/spec/opencode-web.md:22` — dashboard app link
- `docs/knowledge/data/spec.md:33` — hub link to the spec
- `docs/knowledge/data/plans/20261029-off-bash-migration.md:1037` — its
  `## Spec changes` entry for this spec
- `docs/knowledge/data/plans/20261029-off-bash-migration.md:385` — Task 7, which
  adds `agentdev-runtime coder start`; `:766` — Task 19
  (`The Coder template starts the agent through the CLI`) and its MODIFIED
  requirement `the agent-start command is the repository's only start hook`
- `.agents/plugins/agentdev/skills/iwe-bootstrap/agent-code/bootstrap-iwe.py` —
  bootstrap helper, `--root <dir>`
- `coder-ide-baseline@e437dc2:template/main.tf:104` — `agent_start_script`
  parameter, default `agentdev-runtime coder start` at `:110`; `:257` —
  `coder_script.agent_start`; `:236` — `coder_app.opencode`; `:327`, `:353`,
  `:378`, `:403` — state volumes; `:144` — startup script leaves garbage
  collection to `docker-gc.timer`
- `coder-ide-baseline@e437dc2:template/push.sh:6` — `TEMPLATE_NAME` defaults to
  `coder-ide-baseline`
- `coder-ide-baseline@e437dc2:.github/workflows/root-container.yml:1` —
  `Docker Build and Push`, runs on every pull request to `main`
