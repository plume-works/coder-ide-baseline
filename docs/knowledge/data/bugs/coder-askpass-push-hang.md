---
type: bug
description: In a Coder workspace whose only gh login is a session GITHUB_TOKEN, post-start installs no git credential helper, so HTTPS git push falls through to Coder's GIT_ASKPASS and hangs.
generated:
  by: claude-code/opus-5.5
  at: 2026-10-12T23:30:00Z
sources:
- resource: https://github.com/plume-works/agent-devcontainer/blob/2612a847/docs/knowledge/data/bugs/coder-askpass-push-hang.md
- resource: .devcontainer/scripts/setup-gh-credential-helper.sh
- resource: .devcontainer/scripts/postStartCommand.sh
- resource: .devcontainer/scripts/coder-agent-start.sh
- resource: https://github.com/plume-works/coder-ide-baseline/blob/ab1c595/template/main.tf
- resource: docs/knowledge/data/spec/devcontainer-git-credentials.md
- resource: docker/bin/gh
stage: done
severity: high
---

# Bug: HTTPS git push hangs on Coder's askpass when gh's login is only a session token

## Symptom

`git push` to `https://github.com/...` never returns: `git remote-https` waits
indefinitely, with no output and no error. Reads such as `git ls-remote`
succeed, because the repository is public. `gh` itself works, and
`gh auth status` reports a login from `GITHUB_TOKEN`. Any agent or skill push,
such as the `pr-open` push helper, stalls until it hits a timeout.

## Reproduction

In the devcontainer running as a Coder workspace (`CODER=true`,
`GIT_ASKPASS=/.coder-agent/coder`), where `gh`'s only credential is
`GITHUB_TOKEN` in the session environment:

1. `git config --get-urlmatch credential.helper https://github.com` prints
   nothing (exit 1). `~/.gitconfig` holds the `safe.directory` entry that
   post-start writes, so post-start did run.
2. `env -u GITHUB_TOKEN -u GH_TOKEN gh auth status --hostname github.com` exits
   1, so `gh` has no stored login.
3. `env -u GITHUB_TOKEN -u GH_TOKEN .devcontainer/scripts/setup-gh-credential-helper.sh`
   prints
   `gh is not authenticated to github.com; skipping git credential helper setup.`
4. `git push origin HEAD:refs/heads/<branch>` hangs in `git remote-https`.

A push succeeds when `gh` is passed as the credential helper for that one
process, with no change to any git config file:
`env -u GIT_ASKPASS GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.https://github.com.helper GIT_CONFIG_VALUE_0='!gh auth git-credential' git push ...`

## Root cause

Post-start installs `gh` as the github.com credential helper only when `gh` is
authenticated at that moment. When the only login is a `GITHUB_TOKEN` that the
post-start environment lacks, the auth check fails, the script skips, and no
helper is written. Git then has no github.com helper and falls back to
`GIT_ASKPASS`. Coder sets that to its agent binary, which does not return when
it has no GitHub credential to give. Post-start runs inside `devcontainer up`,
before the Coder agent is injected into the Dev Container, so it never has the
agent's environment. A session started by the template's `coder_script` on the
Dev Container's sub-agent has `GITHUB_TOKEN` set, yet
`git config --get-urlmatch credential.helper https://github.com` finds no
helper: the token exists only after post-start has already skipped.

## Fix

Fixed by [Start the gh credential helper from the Coder
agent](../plans/20261011-coder-agent-gh-credential-helper.md).
`.devcontainer/scripts/coder-agent-start.sh` runs
`setup-gh-credential-helper.sh` with the agent's environment, where
`GITHUB_TOKEN` is set, before it starts Remote Control. The coder-ide-baseline
template's `coder_script` runs it on every agent start from `ab1c595`.
Post-start still runs the setup for logins stored outside Coder.

## Key references

Verified anchor points (line numbers as of 2026-10-10):

- `.devcontainer/scripts/setup-gh-credential-helper.sh:19` — auth gate that
  skips helper setup
- `.devcontainer/scripts/setup-gh-credential-helper.sh:30` — `gh auth setup-git`
- `.devcontainer/scripts/postStartCommand.sh:15` — post-start call site
- `docs/knowledge/data/spec/devcontainer-git-credentials.md:29` — Requirement:
  HTTPS git uses the gh login
- `docker/bin/gh:55` — the `gh` wrapper uses `GH_TOKEN`/`GITHUB_TOKEN` when
  either is set
