# Task and planning JSON, version 1

This contract supports a durable local task catalog and an optional imported planning
snapshot. A person can create and use tasks with no source, week, allocation, deadline,
or estimate. Import (#43), persistence (#40), and task-entry UI (#67/#68) build on this
model; decoding data never starts or changes the timer.

Use `WeeklyPlanJSON.decode(_:)` and `WeeklyPlanJSON.encode(_:)` for transfer files.
Dates are Gregorian `YYYY-MM-DD`. Timestamps include seconds and an offset, such as
`2026-09-28T09:00:00-04:00`. Effort values are finite, nonnegative seconds of focus
work. `null` or an omitted estimate means unknown; zero remaining effort is valid but
does not complete a task. Only `completedAt` marks completion.

## Tasks first

Every task has a stable app-owned `id` and a title. `sourceID` is optional provenance
from an import. The optional source ID is never required to use, queue, complete, or
carry a task forward. `order` is optional source ordering; local queue order lives in
`localState.taskOrder`.

`originalEstimateSeconds` and `remainingEstimateSeconds` are supplied together when
known, or both omitted when unknown. Actual focus spans are recorded separately in
`workSegments`. Neither actual time nor an exhausted estimate marks a task complete.

Tasks may have a `parentTaskID`. This containment graph is separate from
`prerequisiteTaskIDs`, and both must be acyclic. A child also records one
`parentEstimateAccounting` value:

| Choice shown to the person | Stored value | Effect of a one-hour child on a parent with 2.5 hours remaining |
| --- | --- | --- |
| Use existing estimate | `usesParentEstimate` | Parent falls to 1.5 hours; combined known work remains 2.5 hours. |
| Add to estimate | `addsToParentEstimate` | Parent stays at 2.5 hours; combined known work becomes 3.5 hours. |

The newest matching `localState.estimateAdjustments` record preserves the current choice
and amount; earlier records remain an audit history.
When a parent is unknown, a child may still be linked; the plan remains uncertain rather
than inventing a parent total. Parent rollups can show descendant work, while global
remaining and actual totals count every task or segment once. Completing a parent never
automatically completes children.

## Optional planning context

`timeZoneIdentifier` and `horizon` are supplied together when the catalog has a planning
window. `availability` and `allocations` require that window. Missing availability means
unknown; a listed day with `windows: []` means unavailable. Fixed commitments are explicit
time ranges; they may exist without a planning window. Suggested allocations are flexible;
they do not add effort, reserve time, or set Pomodoro length. Deadlines are instants, not
meetings.

External snapshots can include source IDs, a planning window, allocations, and fixed
commitments. Reimport must preserve local task IDs, progress, queue decisions, and local
child decomposition for reviewed conflict handling. Source data never owns a local task.

## Required and optional fields

| Object | Required | Optional |
| --- | --- | --- |
| Catalog | `schemaVersion` (1), `id`, `tasks` | source/planning fields, availability, allocations, commitments, local state |
| Task | `id`, `title`, `prerequisiteTaskIDs`, `categoryTags` | source, estimates, order, deadline, parent, project/context, minimum chunk |
| Child adjustment | `id`, parent/child IDs, accounting, `recordedAt` | `amountSeconds` for unknown effort |
| Allocation | `id`, `taskID`, `preferredDay` | suggested range, planned effort |
| Work segment | UUID IDs, run/interval IDs, time | `taskID` for unattributed focus |

The [JSON Schema](weekly-plan.schema.json) validates structure. `WeeklyPlan.validate()`
also checks cross-field rules, IDs, time ranges, source identity, parent and prerequisite
cycles, child-accounting records, and duplicate focus credit. The checked-in
[synthetic example](examples/weekly-plan-v1.json) includes an imported 2.5-hour
literature-review task and a local one-hour child that uses that existing estimate.
