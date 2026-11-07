# Agent operating manual

You are operating a **dev workspace**: a markdown knowledge graph that is a
software project's memory and system of record. The division of labor:

- **Code** lives in the project's own repository. Writing it is your normal work
  — this workspace doesn't change how you code.
- **Project state** lives here, in `data/` — what the product is, how it must
  behave (specs), how it's designed (architecture), what's planned, shipped,
  broken, and released. Every working session must leave a record in the graph;
  this is your memory across sessions. Never keep project state only in
  conversation.

## Start of every session

1. Read `docs/knowledge/data/product.md`. If it still contains ✏️ placeholders,
   run the setup flow (`/agentdev:iwe-setup`) before anything else — planning
   without product context is guessing. Note `## Constraints` and
   `## Authoring rules`: they bind everything you write.
2. Check the state of work: the build order —
   `iwe find --filter '{rank: {$exists: true}}' --sort rank:1 -f keys` — lists
   active plans, open bugs, and pending tasks together, lowest `rank` first.
   Work not yet sequenced is the second query:
   `iwe find --filter '{rank: {$exists: false}, stage: {$nin: [done, cancelled]}, type: {$in: [plan, bug, task]}}' -f keys`.

## The operating loop

1. **Pick** the next piece of work (the user's request, an active plan, or the
   backlog head).
2. **Consult** before acting: the relevant `data/spec/` docs (intended
   behavior), `data/architecture/` (design and past decisions), and the
   feature/bug doc the work belongs to. If a plan exists, execute the plan; if
   the work deserves one, write it first (plan skill).
3. **Execute** — implement in the codebase, following the plan's tasks (the
   implement skill keeps checkboxes, anchors, and deviations honest while you
   do).
4. **Record** — write the state back:
   - Idea (not a commitment) → `data/someday/<slug>.md` + link from
     `data/someday.md`. An idea that gets real is promoted with
     `/agentdev:iwe-capture task --from someday/<slug>`.
   - Actionable item → `/agentdev:iwe-capture task`: `data/backlog/<slug>.md`
     (`stage: pending`, priority), linked from `data/backlog.md`.
   - Proposed feature → `/agentdev:iwe-capture feature`:
     `data/features/<slug>.md` at `stage: proposed`, linked from
     `data/features.md`.
   - Work starts → plan skill: `data/plans/YYYYMMDD-<slug>.md` (`created`,
     verified code anchors, and `## Spec changes` in the form the risk calls
     for), plus a link in `data/plans.md`, and a `rank` when its place in the
     build order is known. Each bug the plan lists in `release` moves to
     `stage: planned`.
   - Work ships → verify skill green (tasks, requirements, and scenarios checked
     against the code), then ship skill: specs synced first, then `stage: done`
     with `completed` and `rank` removed, feature doc `implemented`, bug
     `stage: done` with a `## Fix` describing the shipped fix. No hub, release
     page, or log entry changes.
   - Plan abandoned → `stage: cancelled` and `rank` removed (it stays listed —
     the record of why is worth keeping); each bug it lists returns to
     `stage: pending`.
   - Bug found → `/agentdev:iwe-capture bug`: `data/bugs/<slug>.md` (Symptom /
     Reproduction / Root cause, optional Potential solution, a `severity`) at
     `stage: pending` + link from `data/bugs.md`. Fixed in the same change →
     filed at `stage: done` with a `## Fix` describing the fix.
   - Behavior defined or changed → the matching `data/spec/` doc
     (Requirement/Scenario format); this happens *inside* the ship flow, not as
     an afterthought.
   - Design decision made → `data/architecture/<slug>.md`, including the
     rejected alternatives.
   - Vision insight → `data/concept/<slug>.md`.
   - Task finished → `stage: done` + `completed` on the task doc, `rank`
     removed.
   - Task dropped → `stage: cancelled` on the task doc, `rank` removed.
   - Release cut → ship skill's release mode: it builds
     `data/releases/<X.Y.Z>.md` from the done plans without `released` and their
     `release` lists, sets `released: <X.Y.Z>` on each, links it from
     `data/releases.md`, and adds one dated group to `data/log.md`. Nothing else
     writes either.
5. **Stamp** — every document you create or meaningfully change gets
   `generated: { by: <producer>/<model-version>, at: <ISO 8601 now> }` (an actor
   as `SCHEMA.md` defines it), a one-sentence `description` if it has none, and
   — when you derived it from code or an external page — a `sources` entry
   naming that path or URL.
6. **Validate & commit** — `iwe normalize`, then `iwe schema validate` must
   pass; commit with a short message describing the state change.

## Conventions

- **Inclusion link** = a markdown link on its own line — it makes the target a
  child in the graph. Hubs (`data/plans.md`, `data/features.md`, …)
  inclusion-link their members. Inline links (inside sentences/list items) are
  soft references for cross-cutting relationships.
- **`data/index.md` lists hubs, not documents.** Adding a document to an
  existing hub never touches it — the hub's own inclusion links are what change.
  Update `data/index.md` only when you add or remove a *hub* itself. Never put a
  plan task on `data/index.md` for ordinary document work.
- **Hubs are flat sorted membership lists**: one inclusion link per member, no
  `##` sections, sorted by the member's key with any `YYYYMMDD-` prefix removed.
  Edit a hub only when a member is created, removed, or renamed — never to
  record a stage or priority change. Every item stays listed forever. The hub
  set is closed: adding a hub means adding it to `[schemas.hub]` in
  `.iwe/config.toml`.
- **Frontmatter is the only record of state.** `stage`, `priority`, `completed`,
  and `rank` live in the item's own document; queries select documents by `type`
  and these fields, not by hub membership.
- **One build order, `rank`**: active plans, open bugs, and pending tasks share
  an optional positive integer `rank`, lower first. Ranks step by 100 and an
  insertion takes the midpoint of its neighbours; renumber only in a reorder
  pull request. An item without `rank` is not yet sequenced. Ship removes it.
  Equal ranks are valid, break by key, and CI warns about them.
- **Stage vocabularies** (schema-enforced, human reference in `SCHEMA.md`):
  plans `done|cancelled` (absent = active, `done` requires `completed`);
  features `proposed|accepted|implemented|deprecated|cancelled`; bugs
  `pending|planned|done|cancelled` (open = `pending` or `planned`); releases
  `released`; backlog `pending|done|cancelled`. Reference docs
  (spec/architecture/concept/someday) carry a `type` and no stage.
- **`data/` is an OKF v0.2 bundle** — the graph is portable knowledge any [Open
  Knowledge
  Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
  consumer can read, and CI checks conformance on every commit. Three rules keep
  it true: every document under `data/` has frontmatter with a non-empty `type`;
  `data/index.md` carries no frontmatter beyond `okf_version` and stays sections
  of link bullets; `data/log.md` stays date-grouped bullets under
  `## YYYY-MM-DD`. `okf.yaml`, `okf-index.yaml`, and `okf-log.yaml` enforce all
  three — never work around them by unbinding a schema.
- **The workspace diverges from OKF only to cut merge and upkeep cost.** It
  never sets OKF's optional `status`: `stage` is the one lifecycle field, so a
  state change edits one field in one file.
- **Links carry `.md`** — `refs_extension = ".md"`, so a link resolves for
  readers outside iwe. Run `iwe normalize` after bulk edits rather than
  hand-writing link targets.
- **Specs are the durable truth** and use `### Requirement:` + SHALL +
  `#### Scenario:` WHEN/THEN. The ship skill syncs them whenever a plan ships —
  a plan is not done while the specs it touched describe the old behavior. Scale
  rigor with risk: low-risk behavior gets two lines, contract behavior gets full
  scenarios.
- **A plan states its spec impact at the fidelity the risk deserves.** The three
  forms of `## Spec changes` are an explicit `None — no behavioral change`; a
  linked spec plus a concise normative outcome; or a fenced `ADDED` / `MODIFIED`
  / `REMOVED Requirements` delta carrying complete post-change requirements and
  every surviving scenario. The plan skill owns the threshold. What a plan
  records is *intent*: the durable spec keeps describing released behavior until
  ship succeeds, which is why verify judges code against the durable spec plus
  the plan's intent rather than expecting an unshipped change to already be
  synced. The delta lives inside the one plan document — there is no change
  bundle, no separate delta file, and no engine that applies it; ship reads it
  and merges deliberately, and stops when intent and verified behavior disagree.
- **Code anchors**: `path:line — symbol` lists under `## Key references`,
  stamped `Verified anchor points (line numbers as of YYYY-MM-DD):` — always
  from the current checkout, never from memory.
- **A ticked task carries the evidence that closed it**: every `- [x]` under a
  plan's `## Implementation Steps` has an indented `- **Evidence:**` child
  naming the commit, test run, or CI run behind it, written in the same edit as
  the tick. A check and its result count only together with the commit that
  holds the change they check, so the code is committed first and the tick
  follows in a commit of its own. One edit ticks one box — a sweep across the
  file is the defect, not a shortcut. Unticked boxes stay bare.
- **Naming**: plans are `YYYYMMDD-<kebab-slug>`; everything else is a short
  kebab slug; releases are `<semver>`. One topic per file.
- **Markdown links only, never wiki links.** References are extension-less
  (`[Timer](spec/timer)`), relative to the containing file.
- **Example docs**: files suffixed `.example.md` demonstrate each directory's
  document shape (a fictional product; schema-validated so they can't rot).
  Ignore them when reporting real project state; the setup skill deletes them at
  the end of onboarding.
- **Frontmatter shapes are enforced** — `.iwe/schemas/*.yaml` is the validation
  gate, bound to key globs in `.iwe/config.toml`.

## Where narrative is the format

Best Practice 8 in the repository `AGENTS.md` binds every file: record what is
settled, not the path taken to settle it. Three places in `data/` are the
exception, by design, and only these:

- `data/bugs/` requires Reproduction and Root cause.
- `data/log.md` is retrospective — one dated group per release cut, after the
  fact.
- A plan's `## Verification results` holds results of the `## Verification`
  checks and findings that change what the plan claims.

Each records a *conclusion*, written once, in its own document. What has no home
anywhere is the running account written *while* you are still finding out.

Plans are where this fails most often, because the plan is the document already
open. A plan that doubles in length during implementation has almost certainly
absorbed a logbook; the fix is to route each finding to its own document (see
the implement skill's `## Capturing`) and cut the narration.

## iwe basics

The graph is managed by [IWE](https://iwe.md) — the `iwe` CLI. What you must
know:

- A document's **key** is its extension-less path relative to `[workspace].path`
  in `.iwe/config.toml` (`docs/knowledge` in this repo) — e.g. `data/product`,
  `data/plans/20260801-dark-mode` — that's what `-k` and the structural flags
  take. `iwe` must be invoked with the repo root as the working directory; it
  does not search upward for `.iwe/`.
- A document's title resolves from its H1 header.
- **Never `mv` or hand-delete a document** — use `iwe rename` / `iwe delete`,
  which update every link in the graph; a plain `mv` silently breaks references.
  After a rename or delete, check `git diff`: the reference updates are part of
  the change.
- Run `iwe normalize` after any manual edit — it keeps formatting, links, and
  structure consistent.
- If `iwe` isn't installed (command not found): the workspace is still plain
  markdown — reading and editing work fine — but renames, queries, and
  validation need the CLI. Ask the user to install it
  (https://iwe.md/quick-start/) before restructuring anything.

## iwe CLI cheatsheet

``` bash
iwe retrieve -k data/spec/timer                                  # read a doc
iwe retrieve -k data/plans --expand-includes 1                   # hub + children
iwe find --fuzzy timer -f keys                                   # fuzzy title+key match
iwe find --lexical "session log storage" -f keys                 # full-text ranking
iwe find --filter '{type: plan}' -f keys                         # every plan
iwe find --references data/spec/timer -f keys                    # backlinks
iwe find --filter '{type: plan, stage: done}' -f keys           # frontmatter query
iwe find --filter '{rank: {$exists: true}}' --sort rank:1 -f keys   # the build order
iwe tree -k data/plans -d 2                                      # subtree overview
iwe new --key data/plans/20260801-my-plan                        # create at an explicit key
iwe update -k data/features/foo --set stage=implemented         # set frontmatter
iwe rename <old-key> <new-key>                                   # move; references auto-update
iwe delete <key>                                                 # delete + reference cleanup
iwe normalize                                                    # run after manual edits
iwe schema validate                                              # the commit gate (exit 0 = clean)
iwe stats                                                        # counts, orphans, broken links
```

Filters are YAML (`$eq`, `$ne`, `$in`, `$gte`, `$exists`, …), not jq. Structural
anchors: `--includes`, `--included-by`, `--references`, `--referenced-by`,
`--roots`.

## Workspace skills

| Skill                       | What it does                                                           |
| --------------------------- | ---------------------------------------------------------------------- |
| `/agentdev:iwe-setup`       | Brownfield onboarding: scans the codebase, drafts product/architecture |
| `/agentdev:iwe-explore`     | Thinking partner from an idea or a GitHub issue; never writes code     |
| `/agentdev:iwe-plan`        | Files a plan: discovery, verified anchors, spec impact, hub link, rank |
| `/agentdev:iwe-capture`     | Files a complete bug, proposed feature, or backlog task, deduplicated  |
| `/agentdev:iwe-implement`   | Executes a plan task-by-task: tests, checkbox ticks, clean boundaries  |
| `/agentdev:iwe-branch-name` | Names a plan's next `iwe/` iteration branch, never creates it          |
| `/agentdev:iwe-verify`      | Pre-ship gate + drift audit: claims in the graph checked against code  |
| `/agentdev:iwe-ship`        | Closes the loop: spec sync, stage flips, release cut                   |
| `/agentdev:iwe-weekly`      | Read-only digest: shipped, in flight, bugs, backlog, graph health      |
