---
type: bug
stage: pending
severity: medium
description: 'Example bug record: the timer drifts after the machine sleeps, with repro and investigation notes.'
generated:
  by: human:author
  at: 2026-08-01T00:00:00Z
---

# Bug: Timer drifts after laptop sleep

*Example document — this shows the shape of an open bug report. The setup skill
deletes `*.example.md` files after onboarding.*

## Symptom

After the laptop sleeps during a focus session, the timer sometimes shows more
remaining time than before sleep, or jumps straight to negative values.

## Reproduction

1. Start a 25-minute session, wait until ~10:00 remaining.
2. Close the lid for 5+ minutes, reopen.
3. Timer shows 10:04, 10:31, or `-42:17` depending on sleep length.

## Root cause

The tick handler recomputes remaining time from `Date.now()` deltas, so the wall
clock leaks into elapsed time across sleep — a direct violation of the
"Wall-clock independence" requirement in the [Timer
spec](../spec/timer.example).

## Potential solution

Compute elapsed time from `performance.now()` (monotonic) and reconcile once on
the wake event instead of every tick.

*Convention notes: `stage` and `severity` live in frontmatter; no section states
lifecycle. When the fix ships, the bug gets `stage: done` and a `## Fix` that
describes the fix that shipped.*
