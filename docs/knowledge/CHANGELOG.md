# Changelog

All notable changes to this template are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

This is a template you clone, so the entries below double as migration notes: if
you cloned an earlier copy, they tell you what to change in your own workspace.

## [Unreleased]

### Added

- **`rank`, one build order.** Active plans, open bugs, and planned tasks may
  carry a positive integer `rank`; lower builds first, and
  `iwe find --filter '{rank: {$exists: true}}' --sort rank:1` lists the sequence
  across all three types. Ship removes it.
- `data/` is now a conformant [Open Knowledge
  Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
  v0.2 bundle — portable knowledge any OKF consumer can read, not just iwe.
- **Every document carries a `type`.** Work items already had schemas; the
  reference documents and hubs did not, and typing them makes
  `iwe find --filter '{type: feature}'` possible for the first time.
- Six new schemas: `spec`, `architecture`, `concept`, and `someday` for the
  reference documents, plus `hub` for the directory landing pages and `tracker`
  for `data/product.md` and `data/milestone.md`.
- Three conformance schemas in `.iwe/schemas/` — `okf.yaml` (every document
  carries a non-empty `type`), `okf-index.yaml`, and `okf-log.yaml` (the body
  shapes of the reserved files). They stack on top of the per-type schemas, so a
  document is checked by both.
- OKF's optional families on every type: `description` (one sentence, on all 32
  documents), `generated` (who wrote it and when), `sources` (what it was
  derived from — a codebase map cites the code path it describes), `resource`,
  `stale_after` (set on codebase maps, which go stale when the code moves), and
  `tags`.
- `data/log.md` — a date-grouped history of the workspace. The release cut
  appends one dated group per release.
- A GitHub Actions workflow that runs `iwe schema validate` and checks that
  `iwe normalize` is a no-op on every push and pull request.
- Backlog tasks accept `stage: cancelled`.

### Changed

- **Bugs carry a `stage` and a `severity`.** A bug's `stage` is required:
  `pending | planned | done | cancelled`, with "absent means open" retired.
  Capture files a bug at `pending`, or at `done` when the same change fixed it;
  Plan moves a bug its plan lists in `release` to `planned`; Ship moves it to
  `done`, and back to `pending` when it cancels the plan. `severity` is required
  too — `critical | high | medium | low`, the defect's impact, not its urgency.
  To migrate, give every bug without a stage `stage: pending`, or
  `stage: planned` when an active plan lists it, and give every bug a
  `severity`.
- **A bug's `## Fix` is the fix that shipped.** `## Symptom`, `## Reproduction`,
  and `## Root cause` stay required; `## Potential solution` (the intended
  direction) and `## Fix` (written when the bug becomes `done`, by Ship from the
  plan or by the fixer directly) are optional, and `## Key references` is no
  longer required. No section states lifecycle. To migrate, rename an open bug's
  `## Fix` to `## Potential solution` and drop wording such as "Not yet fixed"
  or "Planned in".
- **The task stage `planned` is now `pending`**, so `planned` means only that a
  plan owns a bug. To migrate, change `stage: planned` to `stage: pending` on
  every backlog task.
- **`status` is now `stage`.** OKF reserves `status` for its lifecycle values
  (`draft | stable | deprecated`), so the workflow field moved to `stage` in all
  schemas and every document. OKF's `status` is optional and never set: `stage`
  is the one lifecycle field, so a state change edits one field.
- **Codebase maps use OKF's `verified`.** The date-valued `verified: 2026-07-25`
  became `verified: { by: <actor>, at: <ISO 8601> }`, which is what the field
  always meant — who last confirmed the doc against the code. `source` and
  `commit` are unchanged.
- **Reference documents are validated.** The "hub documents stay unvalidated by
  design" exemption is deliberately retired: OKF conformance requires a `type`
  everywhere. Reference types still carry no `stage` — nothing about them is a
  lifecycle.
- **Links carry `.md`.** `refs_extension` changed from `""` to `".md"` so links
  resolve for readers outside iwe. Run `iwe normalize` after changing it.
- **`data/index.md` is the bundle-root index.** Its only frontmatter is
  `okf_version: "0.2"`, and its body is sections of link bullets carrying each
  target's description.

### Removed

- **`status`.** No document or schema carries OKF's optional `status`; `stage`
  is the only lifecycle field. If you cloned an earlier copy, drop `status:`
  from every document and schema.
- **Hub sections and the unreleased page.** Hubs are one flat list of inclusion
  links sorted by member key without a `YYYYMMDD-` prefix, and a work item's
  state lives only in its frontmatter; Ship writes no hub, release page, or log
  entry. The release cut builds `releases/<X.Y.Z>.md` from the done plans no
  earlier cut took and sets `released: <X.Y.Z>` on each. If you cloned an
  earlier copy, remove the `##` sections from every hub and sort its links,
  `iwe delete data/releases/unreleased` once its entries are in a cut release,
  and set `released` on every done plan a cut release already covers.
- **The codebase map.** The `data/codebase/` lane, its `codebase` schema, and
  the catalog's map skill are gone. If you cloned an earlier copy, delete
  `data/codebase/`, `data/codebase.md`, and `.iwe/schemas/codebase.yaml`, and
  remove `[schemas.codebase]` and `"data/codebase"` from the hub `match` list in
  `.iwe/config.toml`.

### Fixed

- A convention note in `data/codebase/timer.example.md` opened an emphasis span
  that wrapped a bullet list, which `iwe normalize` rewrote differently on
  alternating runs. Rewritten as a plain paragraph so normalization is stable.

### Migration

If you cloned an earlier copy of this template, in your workspace:

1. Rename `status:` to `stage:` in every document and schema.
2. Add `type:` to every document under `data/` — the type name matching its
   directory (`plan`, `feature`, `bug`, `release`, `task`, `codebase`, `spec`,
   `architecture`, `concept`, `someday`, `hub`, `tracker`).
3. Convert `verified:` on codebase maps from a date to `{ by, at }`.
4. Set `refs_extension = ".md"` in `.iwe/config.toml` and run `iwe normalize`
   from inside the workspace directory.
5. Copy the new schemas and their `[schemas.*]` bindings from this template into
   your `.iwe/`.
6. Add `description` and `generated` to your documents — the agent can backfill
   these in one pass.

Requires an `iwe` build with the `exclude` schema-binding key.
