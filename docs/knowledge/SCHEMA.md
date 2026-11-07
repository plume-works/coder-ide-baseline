# Frontmatter reference

The human-readable companion to the machine schemas. Validation lives in
`.iwe/schemas/*.yaml`, bound to key globs in `.iwe/config.toml` (`[schemas]`
section) — bindings are by path, and **every** document under `data/` is bound,
hubs included. Run `iwe schema validate` before committing — exit 0 is the gate.

The examples below describe one fictional product (Pomodux, a focus-timer app);
the `*.example.md` docs demonstrate each shape in place.

`data/` is a conformant [Open Knowledge
Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
v0.2 bundle. That is why every document carries a `type` and why the reserved
`data/index.md` and `data/log.md` have shapes of their own. The per-type blocks
below show only the fields specific to that type; the shared families come next.

## Fields every type carries

OKF's optional families (SPEC §4.1, §5), declared on every schema and checked by
`.iwe/schemas/okf.yaml`:

- `description` — one sentence. Every document has one; it is what an OKF
  consumer and `data/index.md` show before opening the file.
- `generated` — `{ by, at }`. Write it on **every** edit. `by` is an actor in
  the form [OKF SPEC
  §7](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md#7-actor-convention)
  defines: `<producer>/<model-version>` for agent writes — the agent and the
  model version that wrote the content; `human:<handle>` for hand-authored or
  human-confirmed content; `process:<id>` for automation.
- `sources` — the materials a document derives from, each
  `{ id, resource, title, author, usage_count, last_modified }` with `resource`
  required. A `resource` may be a URL or a repo path. Attribute individual
  claims with a markdown footnote keyed to an entry's `id`.
- `verified` — `{ by, at }` or a list, recording who confirmed the content
  against its sources.
- `resource`, `tags`, `stale_after`, `usage_window` — optional.

`stage` is the only lifecycle field: the per-type enums below. A work item's
state lives only in its own frontmatter; no hub section repeats it. OKF's
optional `status` is never set, so a state change edits one field.

## The build order — `rank`

Active plans, pending and planned bugs, and pending backlog tasks may carry
`rank`, a positive integer: their place in one build order shared across the
three types, lower first.

``` yaml
rank: 300 # optional; positive integer
```

- The sequence is
  `iwe find --filter '{rank: {$exists: true}}' --sort rank:1 -f keys`. An item
  without `rank` is not yet sequenced; that is the separate
  `rank: {$exists: false}` query, never part of the sequence.
- Ranks step by 100; an insertion takes the midpoint of its neighbours. Only a
  reorder pull request renumbers.
- Ship removes `rank` from a plan, bug, or task it marks done or cancelled.
- Equal ranks are valid and break by key; CI warns about them.

## The reserved files — `data/index.md` and `data/log.md`

OKF reserved filenames, not concept documents: they carry no `type` and are
checked by `okf-index.yaml` and `okf-log.yaml` instead.

- `data/index.md` — the bundle-root index. Its only frontmatter is
  `okf_version: "0.2"`. The body is `#` sections of link bullets, each bullet a
  markdown link to a hub followed by `-` and that hub's `description`.
- `data/log.md` — the update history, written only by a release cut: a title
  section over `## YYYY-MM-DD` groups of bullets, newest first.

## Plans — `data/plans/YYYYMMDD-<slug>.md`

Implementation plans, migrations, and design proposals.

``` yaml
---
type: plan # required
stage: done # done | cancelled — omit while active/pending
created: 2026-07-01 # required, YYYY-MM-DD
completed: 2026-07-18 # required when stage: done
released: 0.1.0 # set by the release cut that took this done plan
release: # required while active: internal, or the keys below
- features/focus-sessions
---
```

`release` is the plan's release impact, chosen when the plan is written:
`internal` when no workspace user or template consumer sees a difference,
otherwise the `features/` and `bugs/` keys the work adds, changes, or fixes. The
release cut takes the plan's release entries from it and sets `released` to its
version; a done plan without `released` waits for the next cut.

Body: `## Context`, `## Approach`, `## Implementation Steps` (`### Task N`,
`**Files:**`, checkboxes), `## Spec changes`, `## Depends on` (optional),
`## Verification`, `## Out of scope`, `## Key references` (dated
`path:line — symbol` anchors). Its link in `data/plans.md` never moves.

## Features — `data/features/<slug>.md`

Feature design documents; the stage carries the whole lifecycle.

``` yaml
---
type: feature # required
stage: implemented # proposed | accepted | implemented | deprecated | cancelled — required
---
```

Body: `## Purpose`, `## Behaviour`, `## Edge cases`, `## Open questions`.

## Bugs — `data/bugs/<slug>.md`

Bug reports and investigations. H1 starts with `Bug:`.

``` yaml
---
type: bug # required
stage: pending # pending | planned | done | cancelled — required
severity: high # critical | high | medium | low — required
---
```

- `stage`: Capture files a bug at `pending`, or at `done` when the same change
  fixed it. Plan moves a bug its plan lists in `release` to `planned`; Ship
  moves it to `done`, and returns it to `pending` when it cancels the plan.
- `severity`: the impact of the defect — how bad it is when it happens — not its
  urgency. Descriptive only; it does not set `rank`.

Body: `## Symptom`, `## Reproduction`, `## Root cause`, all required, then the
optional `## Potential solution` — the intended direction, at any stage — and
`## Fix` — the fix that shipped, written when the bug becomes `done`: by the
fixer when a change fixes it directly, by Ship from the plan that fixed it. A
Reproduction or Root cause not yet known records what is known, the hypotheses
eliminated and what eliminated them, and links the backlog task whose spike
settles it. No section states lifecycle; `stage` does.

## Releases — `data/releases/<version>.md`

One page per cut version, written only by the release cut from the done plans no
earlier cut took — those without `released` — and their `release` lists.

``` yaml
---
type: release # required
version: 0.1.0 # required
date: 2026-07-18 # the day the release was cut
stage: released # required, always released
---
```

Body: `## Added` / `## Changed` / `## Fixed` as inclusion links to feature and
bug docs. A feature already released in an earlier version, but which gained
behavior in this one, belongs under `## Changed` rather than `## Added`.

## Backlog tasks — `data/backlog/<slug>.md`

Atomic prioritized work items waiting to become plans.

``` yaml
---
type: task # required
stage: pending # pending | done | cancelled — required
priority: high # high | medium | low
created: 2026-08-01 # required, YYYY-MM-DD
completed: 2026-08-14 # set when done
---
```

## Reference documents — type only

`data/spec/`, `data/architecture/`, `data/concept/`, and `data/someday/` docs
carry a `type` (`spec`, `architecture`, `concept`, `someday`) and nothing else
that is required: they are durable reference, not work items, so no `stage`
applies. Specs use the Requirement/Scenario format (`### Requirement:` + SHALL,
`#### Scenario:` + WHEN/THEN); architecture notes record decisions with their
rejected alternatives.

## Hubs and the trackers

Hub files (`data/plans.md`, `data/features.md`, …) carry `type: hub`;
`data/product.md` and `data/milestone.md` carry `type: tracker`. Both take
`stage: living`. A hub's body is one flat list of inclusion links, one per
member, sorted by the member's key with any `YYYYMMDD-` prefix removed, with no
`##` sections — `.iwe/schemas/hub.yaml` rejects a section, and a test checks the
order. A hub changes only when a member is created, removed, or renamed.
