# Plan

Working scope, roadmap, and notes-to-self. This file changes at phase boundaries; the
[README](README.md) is the stable product picture and GitHub Issues hold implementation-level work.

## Completed: v0.1 — Continuous focus loop

The first functional batch proved the basic work/break rhythm:

- [x] Configurable work timer (default 50 min) and break timer (default 10 min)
- [x] Automatic work → break → work transitions without manual restarts
- [x] Water prompt and one-tap logging during breaks
- [x] Local persistence of timer settings, focus sessions, and water logs
- [x] Daily summary of focus time, completed cycles, and water
- [x] Humane, bounded escape hatches:
  - hold to take a short mid-work break and then resume the unfinished work
  - hold to skip a break
  - one time-limited extension near the end of a phase
  - deliberate confirmation before ending the whole cycle
- [x] Wall-clock correction after backgrounding and local transition notifications

The app is now a functional continuous Pomodoro-style loop. The next phase is not
"more Pomodoro features"; it is turning that loop into a finite daily rhythm.

## Completed: v0.2 — Finite daily rhythm

### Outcome

In the morning, select or lightly adjust a normal day, press Start, and let the app
carry the day through short work/break cycles, long breaks, and a definite ending.

### Scope

- [x] Save one reusable default daily rhythm:
  - start and end time
  - work and short-break durations
  - repeating work sections
  - anchored long breaks
- [x] Generate a dated timeline of work, short-break, and long-break intervals
- [x] Preview start/end, expected focus time, session count, and long breaks before starting
- [x] Support "start as planned," "start now," and a today-only adjustment
- [x] Drive the timer from the generated timeline instead of an endless two-phase loop
- [x] Show a quiet `Now / Next` runtime view
- [x] Persist and restore the active daily run after full app termination
- [x] Schedule known transition notifications in advance and reschedule after changes
- [x] Preserve the existing soft landings within the daily timeline:
  - extensions and inserted short breaks shift later flexible intervals
  - long breaks and day end remain fixed anchors
  - overflow trims or drops the final incomplete focus interval rather than eroding every break
- [x] Give long breaks a soft exit ramp:
  - main break
  - five-minute wrap-up warning
  - two-minute final return warning
- [x] Stop automatically at the configured day end and show planned versus actual focus

### Was explicitly out of scope for v0.2

- Break-activity library or automatic chore placement
- Work task management
- Drag-and-drop calendar editing
- LLM/API integration or schedule-file import
- Live Activity / Dynamic Island
- Sophisticated schedule optimization

### Issue order as delivered

1. Model and validate a reusable daily rhythm and generated intervals.
2. Add morning setup and a generated schedule preview.
3. Drive the timer from the finite daily schedule.
4. Persist and restore an active daily run.
5. Schedule and reschedule the day's transition notifications.
6. Integrate existing extensions/interruption controls with fixed anchors.
7. Add long-break exit warnings and intentional day completion.
8. Extend the daily summary with planned-versus-actual focus.
9. Review and continue an intentionally stopped unfinished day.

## Active direction: v0.3 — Follow an imported weekly plan

### Outcome

Bring an externally prepared weekly plan into FocusRhythm and follow it through a
changing day, with only occasional small decisions. Planning happens in Notion;
FocusRhythm supplies the focus/break rhythm, current work target, lightweight
adjustments, and continuity when estimates change.

The first transfer is a reviewed, versioned JSON snapshot prepared externally from
the weekly plan. Direct Notion fetching and continuous two-way synchronization are
not required for this version. The import issue must document the conversion path.

### Product contract

- **Rhythm controls pacing.** For example: 50-minute focus, 10-minute short breaks,
  and a 60-minute long break after four focus sessions. The long break replaces the
  fourth short break. Task estimates do not change Pomodoro durations.
- **Tasks describe work.** Keep original effort, revised remaining effort, actual
  focus spent, and explicit completion separate. A task can span several focus
  intervals, and one interval can contain several tasks. Rest is not task effort.
- **Preferred placement is flexible.** Preserve imported preferred days, suggested
  clock times, and ordering. Forecast assignments can move; they are not commitments.
- **Only explicit fixed commitments reserve time.** Deadlines constrain completion;
  they do not occupy a meeting-length slot. Availability and chosen run end bound
  the day. Unknown future availability is not assumed to be free time.
- **The queue permits choice.** Reorder persistently, pick another task, or say
  “not now.” A postponed task stays unfinished and returns later with its deadline
  and remaining effort considered. Explain impossible deadlines rather than forcing
  a fit. Never silently switch the active task because a forecast changed.
- **Decisions usually happen during breaks.** Explicit task completion, priority
  changes, and urgent insertion are deliberate mid-focus exceptions. Choosing the
  next task during a break does not end the break.
- **Broad planning stays external.** Local edits are for following and adapting the
  imported plan. A reviewed reimport preserves local progress and surfaces conflicts.

### Scope and issue map

Plan and timing foundation — tracker #38:

- [ ] #39: Versioned weekly model, task identity, split allocations, remaining effort,
  completion, deadlines/dependencies, flexible time preferences, fixed commitments,
  availability, and optional category tags.
- [ ] #40: Persistence, safe reviewed import merge, local overrides, and carryover.
- [ ] #62: Run the cadence around fixed commitments and available windows; define
  boundary/resumption behavior and keep notifications consistent.
- [ ] #41: Forecast suggested placement and deadline feasibility using actual focus
  capacity, without counting breaks or the same capacity twice.

Import and preview — tracker #42:

- [ ] #43: Reviewed JSON snapshot import, conversion instructions, validation,
  repeated import without duplicates, and source/local conflict review.
- [ ] #45: Simple week overview and adjustable today preview; start now, reorder,
  change preferred placement, and see overflow without rebuilding the day.

Execution — tracker #46:

- [ ] #47: Persistent queue with explicit reorder, deliberate selection, and temporary
  postponement; deadline explanations and deterministic resurfacing.
- [ ] #63: Attribute actual task work across interval boundaries and task switches,
  with recovery that does not duplicate time or infer completion from estimates.
- [ ] #48: Quiet focus countdown and current target, with optional context/progress.
- [ ] #49: Done, continue, revise remaining effort, reorder, not now, and pick another.
- [ ] #64: Quick-add urgent work, do now within the current Pomodoro, then resume the
  interrupted task or choose another. No separate mini-timer is required.
- [ ] #50: Remaining-day review, planned-versus-actual task work, and next-day/week
  carryover that preserves revised effort and deadlines.

Verification — tracker #55:

- [x] #56: Shared scaled clock, merged into development.
- [ ] #57: Date travel and synthetic imported-week/progress fixtures.
- [ ] #58: Final manual scenario audit and end-to-end milestone review. Feature
  issues still update their own scenarios and obtain manual approval as they land.

### Required real-day scenarios

1. Grading needs 30 more minutes: revise remaining work; keep the cadence and show
   the changed forecast.
2. An urgent ten-minute email appears: suspend grading, work on the email inside the
   same focus interval, then resume. Attribute time to the correct task. If the
   interval ends first, take the normal break and retain unfinished email work.
3. Priorities change: reorder upcoming work without reconstructing the rhythm.
4. A is suggested but the user wants B: postpone A, select B, and return A to later
   consideration without deletion, immediate repeated suggestions, or a hidden
   deadline conflict.
5. Work finishes three hours early or needs five extra hours: recompute available
   capacity or overflow honestly; protect fixed commitments and chosen day end.
6. Start late, end early, relaunch, and move to tomorrow/next week: preserve actual
   work, remaining estimates, completion, and local choices.

### Sequencing

Use the oldest open, unblocked implementation issue in the active milestone and its
prerequisites, as described in AGENTS.md. GitHub dependency links and the issue bodies
are authoritative; trackers are not implementation tasks and deferred issues are
excluded. Current foundation work can begin with #39, then #40.

#60 (rhythm variations, PR #61) is existing review work and a prerequisite for #62.
It remains subject to its current manual/merge approval gates. The new plan does not
authorize merging it. #56 is already complete. Remaining dependencies lead through
fixed-commitment scheduling, forecasting, queue/runtime, and integrated verification.

### Deferred from v0.3

- Full in-app weekly plan authoring.
- Landmark/dependency graph (#44).
- Standing rapid-fire task-clearer and nested mini-timers (#51–#54). Urgent task
  insertion is supported independently by #64.
- Category time quotas, automatic balancing, and forced choices after repeated
  skips. Optional category tags and per-task actual time are included; policy ideas
  remain in ideas-parking-lot.md.
- Continuous/two-way Notion sync, direct connector integration, and in-app prose/LLM
  parsing. Snapshot import is included now.
- Schedule optimization and automatic placement of recurring break routines.

## Next: v0.4 — Recurring break routines

Add a small reusable activity library so routine chores and healthy habits are
configured once, then assigned automatically to compatible breaks.

Each routine may define:

- Name and approximate active duration
- Frequency: every eligible break, a number of times per day, or once per day
- Period: morning, midday, afternoon, or anytime
- Eligible break type: short, long, or either
- Optional minimum spacing between repetitions
- Enabled/disabled state

Examples include boiling water several times in the morning, flossing once during
the day, or preparing lunch during a long midday break.

The remainder of a break stays real rest. Completing a two-minute routine must not
end a ten-minute break, and skipping an activity must not require an explanation.

Do not add randomization, ranking, mood selection, or drag-and-drop placement in
this phase. Water logging should eventually become one activity in this general
system rather than a permanent special case.

Work targets are included in v0.3 as imported tasks; they do not require a landmark.
The deferred task-clearer may reuse task/routine concepts if explicitly promoted,
but it is not a prerequisite for recurring break routines.

## Later: Scheduled launch ritual

Help the user arrive near an intended start time without treating unattended time as
focus. The alarm begins preparation rather than work; focus starts only after the user
explicitly confirms that they are present.

- Schedule a next-day alarm and choose a bounded preparation runway
- Optionally give the runway a simple intention such as waking up, eating, showering,
  or clearing the desk
- Keep preparation visually distinct from an active focus session
- At the expected focus time, offer a ready check to start, take one short bounded
  delay, or rebuild the day from now
- Generate the finite rhythm from the actual confirmed start time, whether early or late
- Track arrival within the intended window separately from completed focus time
- Preserve the selected rhythm's focus cadence, long breaks, and break intentions after
  the runtime begins

Do not build a fully clock-anchored future-day schedule, record scheduled time as work,
or add punitive missed-alarm streaks or unlimited snoozing.

## Later roadmap

**v0.5 — Broader import/export and optional integration**

- Reviewed weekly-plan JSON import is already part of v0.3.
- Extend export/round-trip support for plans, daily rhythms, and generated schedules
  once the execution model has been proven.
- Consider direct Notion fetching or synchronization only with explicit rules for
  source changes versus local progress; do not require a paid embedded LLM API.

**v0.6 — Ambient system surfaces**

- Live Activity / Dynamic Island countdown (GitHub issue #15)
- Lock Screen presentation
- Widget only if it supports the same quiet `Now / Next` interaction

**v0.7 — End-of-day reflection**

- Optional 1–5 day rating
- Optional short note about what worked
- No streaks, shame states, or productivity score optimization

## Notes-to-self while building

- Build for one real day before building for every possible routine.
- Configure recurring constraints once; generate repetition automatically.
- A plan must survive lateness and interruption without demanding a new planning session.
- Fixed anchors should be trustworthy. Flexible intervals may move or disappear.
- Focus shows one thing. Put routine decisions in breaks, with deliberate exceptions
  for task completion, urgent work, and user-requested switching.
- Match spare time against how small a piece of a task is still worth doing, not against
  the size of the task.
- Work that is always correctly ranked last needs a reserved slot, not a higher rank.
- Watch what happens on day 4 and day 14 — that is where personal trackers usually fail.
- If a feature makes the app broadly marketable but does not make the daily rhythm calmer, park it.
