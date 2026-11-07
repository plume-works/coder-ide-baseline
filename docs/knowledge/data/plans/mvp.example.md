---
type: plan
description: 'Example milestone plan: the MVP, sequencing the child plans that must ship for it.'
created: 2026-06-25
release: internal
generated:
  by: human:author
  at: 2026-06-25T00:00:00Z
---

# MVP

*Example document — this shows an aggregator plan: a milestone is a plan whose
children are plans. The setup skill deletes `*.example.md` files after
onboarding.*

Everything Pomodux needs before the first public build: a working timer and the
one piece of retention surface.

[Focus sessions](20260701-focus-sessions.example)

[Streak widget](20260720-streak-widget.example)

Focus sessions ships first — the streak widget derives from the session log it
creates. Each child's `rank` places it in the build order; the milestone closes
when both child plans carry `stage: done`.

*Convention notes: the child plans are inclusion links, so the milestone's
subtree is queryable
(`iwe retrieve -k data/plans/mvp.example --expand-includes 1`). The milestones
tracker links this document, and the plans hub lists it with every other plan.*
