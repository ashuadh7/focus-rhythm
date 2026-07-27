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

**Decision:** Do not embed a paid LLM API. After the native schedule representation
stabilizes, support validated, versioned JSON import/export.

**Why:** A user can ask an AI service they already use to prepare a schedule while the
app remains local, inexpensive, deterministic, and fully useful without that service.
