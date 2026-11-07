---
type: hub
description: Implementation plans, migrations, and design proposals, one document per unit of work.
stage: living
generated:
  by: human:author
  at: 2026-08-01T00:00:00Z
---

# 🗺️ Plans

*Every plan lives in `plans/YYYYMMDD-<slug>.md` and is listed here, always, in
one list sorted by slug without the date prefix. A plan's stage and its place in
the build order (`rank`) live only in its frontmatter, so shipping or cancelling
a plan never edits this page.*

[Configure the gh credential helper from the Coder
agent](plans/20261011-coder-agent-gh-credential-helper.md)

[Start Claude Remote Control from the Coder
agent](plans/20261011-coder-claude-remote-control.md)

[Move the Coder template's knowledge into
coder-ide-baseline](plans/20261031-coder-template-knowledge-split.md)

[Cap Docker storage with automatic garbage
collection](plans/20261013-docker-storage-gc.md)

[Collect Docker garbage hourly in both workspace
engines](plans/20261101-docker-storage-periodic-gc.md)

[Replace the runtime shell scripts with one agentdev-runtime
CLI](plans/20261029-off-bash-migration.md)

[Autostart the OpenCode web UI on
Coder](plans/20261016-opencode-web-coder-autostart.md)

[Persist the Coder workspace containerd image
store](plans/20261011-persist-coder-workspace-containerd.md)
