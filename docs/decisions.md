# Decisions

Stable architecture and product decisions. Implementation details remain in GitHub Issues.

## The timer grows into a finite daily schedule

**Decision:** v0.2 will generate a dated timeline from a reusable daily rhythm and
drive the timer from that timeline.

**Why:** An endless work/break state machine cannot represent long breaks, a definite
ending, full relaunch recovery, or known transition notifications across a 10–12-hour
day. A schedule also becomes the common foundation for future routine assignment and
external JSON import.

## Fixed anchors, flexible intervals

**Decision:** Long breaks and the configured day end are fixed anchors. Work sessions,
short breaks, extensions, and inserted mid-work breaks are flexible around them.

**Why:** A plan should absorb real-life interruptions without making lunch or the end
of the day unreliable. When flexible time no longer fits before an anchor, the last
partial focus interval is trimmed or removed rather than quietly shortening every break.

## Configure routines once

**Decision:** Recurring break activities will be stored as reusable rules and assigned
when the day is generated. They will not require daily manual placement.

**Why:** Re-entering routine chores recreates the decision load the app exists to
remove. Simple frequency, time-of-day, break-type, and spacing rules cover the initial
cases without requiring an optimization engine.

## External AI stays optional

**Decision:** Do not embed a paid LLM API. v0.3 introduces reviewed, versioned JSON
weekly-plan import prepared externally. Broader export and direct integration can
follow after the execution workflow is proven.

**Why:** A user can ask an AI service they already use to prepare a schedule while the
app remains local, inexpensive, deterministic, and fully useful without that service.

## External weekly planning, local execution

**Decision:** Notion holds the broader weekly plan. FocusRhythm imports a reviewed
snapshot with tasks, estimates, preferred days/times, and explicit fixed commitments.
It offers a lightweight week/day preview and local execution adjustments. Reimport
matches stable IDs, preserves actual work and local progress, and surfaces conflicts.

**Why:** Recreating the week inside the app adds planning work. A preview and small
choices are enough to connect an existing plan to the quiet daily rhythm.

## Task effort stays independent of rhythm

**Decision:** Tasks can span focus intervals or share an interval. Estimates are
revisable and completion is explicit. Finishing or switching a task does not restart
the Pomodoro. Urgent insertion uses existing focus time and preserves interrupted work.

**Why:** Estimates can be wrong by hours; the work/rest cadence should remain useful
through that uncertainty. Attribute actual focus to tasks and never count breaks or
fixed commitments as task effort.

## Flexible preferences and deadline-aware postponement

**Decision:** Suggested task placement can move. Explicit fixed events occupy time;
deadlines constrain completion. “Not now” postpones a task without deleting it, and
the queue offers alternatives before returning it with its deadline considered.
Explain insufficient capacity rather than promising every postponed task still fits.

**Why:** The user needs room to respond to priorities and willingness without losing
unfinished work. Routine decisions belong at breaks, with deliberate mid-focus
exceptions for completion, urgent work, and requested switching. Category tags are
optional in v0.3; quotas and mandatory category choices remain deferred.
