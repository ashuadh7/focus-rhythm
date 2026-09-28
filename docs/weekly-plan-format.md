# Weekly plan JSON, version 1

This is the canonical transfer contract for externally prepared weekly work (#39).
The [JSON Schema](weekly-plan.schema.json) describes field types; the cross-field
rules below are enforced by `WeeklyPlan.validate()`. The
[synthetic example](examples/weekly-plan-v1.json) is also the unit-test fixture, so it
is decoded and round-tripped on every test run. File import, reviewed merging, and
storage arrive in #43/#40. This model does not alter the running rhythm.

## Encoding and identity

Use `WeeklyPlanJSON.decode(_:)` and `WeeklyPlanJSON.encode(_:)` for external files.
Dates are Gregorian `YYYY-MM-DD`. Timestamps include seconds and a timezone offset,
for example `2026-09-28T09:00:00-04:00` or `2026-09-28T13:00:00Z`. Optional fractional
seconds have at most three digits. Export normalizes timestamps to UTC with
millisecond precision; native Codable persistence can retain finer Date precision.
All effort values are **seconds of focus work**, finite and nonnegative, excluding
breaks and fixed commitments. Unknown estimates must be reviewed before conversion;
do not replace missing information with invented zero estimates or timestamps.

IDs are nonblank, case-sensitive, opaque strings. Preserve them across exports and
carryover; do not derive task identity from title, position, day, or an allocation.
`id` identifies the plan snapshot lineage (reuse for refreshes of the same week);
`sourceID` identifies its stable external source. A task's `id` persists across
weeks, while its optional `sourceID` identifies the external task/page and is absent
for local tasks. In the synthetic example `notion:` strings illustrate opaque IDs;
they are not real Notion links or credentials. Source task IDs must be unique within
a snapshot. Commitments have their own ID/source-ID namespace.

Fields marked optional may be omitted or null. Required arrays must be present even
when empty. Unknown fields are ignored and not retained; a semantic contract change
requires a new `schemaVersion`. Unknown versions fail before their payload is read.
Errors identify a field or collection and the reason; decoding never repairs data
or invents references. Programmatically edited models must be validated before use;
the external encoder and every root `WeeklyPlan` decoder validate automatically.

## Fields

| Object | Required fields | Optional fields |
| --- | --- | --- |
| Plan | `schemaVersion` (1), `id`, `sourceID`, `timeZoneIdentifier`, `horizon`, `tasks`, `allocations`, `fixedCommitments` | `availability`, `localState` |
| Horizon | `startDay`, `endDayExclusive` | — |
| Daily availability | `day`, `windows` (time ranges) | — |
| Time range | `start`, `end` (timestamps, start inclusive/end exclusive) | — |
| Task | `id`, `title`, `originalEstimateSeconds`, `remainingEstimateSeconds`, `order`, `prerequisiteTaskIDs`, `categoryTags` | `sourceID`, `completedAt`, `deadline`, `project`, `context`, `minimumChunkSeconds` |
| Allocation | `id`, `taskID`, `preferredDay` | `suggestedTime` (time range), `plannedEffortSeconds` |
| Fixed commitment | `id`, `title`, `time` (time range) | `sourceID` |
| Local state | `deferrals`, `workSegments` | `taskOrder` |
| Deferral | `taskID`, `deferredAt`, `until` | — |
| Work segment | `id` (UUID), `runID` (UUID), `focusIntervalID` (UUID), `time` | `taskID` (absent means unattributed focus) |

The explicit timezone is a Foundation-recognized identifier; use an IANA region such
as `America/Toronto` or `UTC`, not the exporting device's implicit timezone. Date-only
preferences are interpreted there. Timestamp offsets specify instants and need not
match the region's written offset (UTC exports are equivalent).

The horizon starts inclusively and ends exclusively. Availability entries must be
within it and unique per local day. Windows must be nonempty, nonoverlapping ranges
within that day; adjacent windows are valid. Split overnight availability at local
midnight. Calendar-day boundaries respect daylight saving changes, including 23/25-hour
days. No availability, an empty availability array, or a missing day means **unknown**;
a listed day with `windows: []` explicitly means **unavailable**. Never infer capacity
from an empty calendar. Availability includes space that may later be occupied by
commitments or breaks; scheduling subtracts these in #62.

## Work, suggestions, and commitments

- `originalEstimateSeconds` is the baseline task effort. `remainingEstimateSeconds`
  is separately stored current effort; it can exceed the original after revision.
  A fresh conversion explicitly supplies both values, usually equal.
- Only a non-null `completedAt` marks a task done. Zero remaining effort with no
  completion is valid and sets `needsEstimateRevision`. Completion before an estimate
  is used up preserves the unused estimate for history; remaining-work totals exclude
  completed tasks. Decoding does not deduct work again or infer completion.
- `order` is a unique nonnegative integer for source ordering; gaps are allowed.
  Optional `localState.taskOrder` is a complete permutation of all task IDs, including
  completed tasks, overriding source order. Deferrals retain the task and its history;
  `until` must be later than `deferredAt`. These fields define data, not selection policy.
- Prerequisites must reference retained task IDs, cannot repeat, and must be acyclic.
  Keep completed prerequisites in the snapshot. Optional project/context and category
  tags carry labels only; they introduce no quotas or hidden scheduling rules.
- Each allocation references one task, with a preferred day and optionally a time
  range and a portion of focus effort. Multiple daily entries for one weekly goal use
  the same task ID. The suggested range must fit its preferred local day. Its wall-clock
  length is not an effort estimate, occupied time, or a Pomodoro length. Allocations
  never add to task totals, deduct remaining effort, or record actual work.
- Fixed commitments alone reserve protected time. Their nonempty ranges can cross
  midnight. Deadlines are instants attached to tasks, never occupied intervals.
- Past deadlines, past allocations, completed history, and zero remaining unfinished
  tasks stay valid. Preferences may extend outside the horizon for carryover. Overlapping
  commitments, suggested/fixed collisions, and overallocated work remain representable;
  #62/#41 will explain feasibility problems rather than move or erase them at decode.

## Local actual work

A segment records a **closed** span of actual focus, referencing the owning run and
`ScheduledInterval.id`. End the span at a task switch, pause, or break and open another
when focus resumes. A task can have many segments across intervals and days; one focus
interval can have several tasks. No segments represent rest. Segment IDs persist so
#40/#63 can reconcile writes without generating a new identity for already credited work.
This issue defines the representation; atomic persistence, active/open segment recovery,
and reviewed merge policies belong to those follow-up issues.

`TaskWorkSegment` construction requires a real focus interval and bounds-checks the
span. `WeeklyPlan.validate()` verifies task references, positive ranges, unique segment
IDs, and no overlapping actual spans (even across different runs). It cannot authenticate
an arbitrary external interval UUID. The owning run must also call
`validateWorkSegments(in:runID:)` against its schedule to verify interval membership,
focus kind, bounds, and the total credited-duration limit. The runtime must close spans
around interruptions: an interval's aggregate `excludedDuration` does not locate its
rest gaps. An external snapshot's `localState` is not automatically trusted or installed;
#40/#43 must review it and preserve existing local progress. Omit `localState` entirely
for fresh source-only exports; it decodes to empty local state.

## Reading the synthetic example

The week begins September 28, 2026, in Toronto. Monday has seven available hours,
Tuesday is explicitly unavailable, and Wednesday's availability is unknown. Grading
is one three-hour task with two suggested allocations; its Monday suggestion overlaps
a 10:00 meeting so future forecasting must adjust it. The suggestion never moves the
meeting. Reading has no slot. Last week's notes are overdue, unfinished, and need an
estimate revision despite having zero remaining seconds.

Recorded focus is grading 20 minutes, email 10, grading 20: **40 minutes grading and
10 minutes email**, all inside one 50-minute interval. Email was explicitly completed
with five estimated minutes unused. The original task estimates total **265 minutes**;
remaining unfinished effort totals **180 minutes**. Neither allocations nor actual-work
records inflate those estimates. Local ordering and the overdue task's deferral survive
a Codable round trip independently of the source ordering.
