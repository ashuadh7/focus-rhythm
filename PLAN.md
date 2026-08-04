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

## Active direction: v0.3 — Landmark planning layer

### Outcome

Plan the next 5–10 days once, around landmarks and their dependencies. Then let the
running day choose what to work on next, so that focus time requires no decisions.

### The separation this phase rests on

- **Rhythm** is time: slots, anchored breaks, day end. Built in v0.2, unchanged here.
- **Plan** is work: landmarks, dependencies, estimates, ordering. It contains no clock times.
- **Binding** happens at runtime: a task is attached to a focus interval when that interval
  begins, never in advance.

Tasks are never scheduled into slots ahead of time. Estimate error is absorbed by the
queue, not by the schedule — that is what lets a rough estimate survive a real day.

### Scope

Plan model

- [ ] Landmark: name, date and time, hue, kind (meeting or deadline)
- [ ] Dependency task: parent landmark, estimate, remaining estimate, order, done state
- [ ] Floating task: no landmark, but a soft by-date so it still appears as a real target
- [ ] Minimum useful chunk per task, defaulting to "needs a full slot"
- [ ] Versioned, serializable plan document so later import needs no migration
- [ ] Landmark pressure: remaining estimate before a landmark versus focus capacity until it

Planning surface

- [ ] Create and edit landmarks and their dependencies
- [ ] Scrollable multi-day landmark graph — landmark in a dark shade, its dependencies in
      lighter shades of the same hue, completed dependencies struck through
- [ ] Replan: close the current horizon and open the next one
- [ ] Morning slate — a derived projection of today's likely tasks, explicitly not a commitment
- [ ] One optional stated day target, checked at day end

Runtime binding

- [ ] Selection rule: highest-priority unfinished task whose minimum chunk fits the time
      remaining; when nothing fits, start the break early rather than invent work
- [ ] Focus screen shows only four things: time left, current target, its landmark, task progress
- [ ] Break decisions: done, still going, or add time — remaining estimates are revised here
- [ ] One-tap "not this one" override of the next pick, available in breaks only
- [ ] Marking done mid-interval pulls the next task in without moving the clock
- [ ] Long breaks show the wider view: remaining slate and landmark pressure
- [ ] Day end reconciles plan against actual and shows which landmarks moved

Test tooling

The existing 20-second **Start test** scenario shortens durations, which verifies
controls and transitions but cannot reach anything that takes a day or a horizon.
v0.3 needs two more mechanisms, built before the features that depend on them.

- [ ] Scaled clock: run a realistic rhythm at 10×–120× so a full day's arc takes minutes
      while durations, ratios, and warning thresholds stay production-shaped
- [ ] Date travel and seeded plan fixtures: jump the app's notion of today forward by
      days and load a plan in a known state, since a 10-day horizon cannot be run through
      even compressed
- [ ] Both gated to debug builds and reachable from one debug surface
- [ ] Manual scenarios in `docs/manual-testing.md` extended per issue, as now

Task-clearer

- [ ] Nested rapid-fire schedule inside one slot: per-item 3/5/10-minute intervals, no breaks between
- [ ] Per item: done, +5, or push to the back; the session end stays fixed, so overrun eats the tail
- [ ] A standing slot in the rhythm rather than an on-demand mode

### Explicitly out of scope for v0.3

- Unstructured task dump and automatic structuring — that is v0.5 import
- Bin-packing or optimizing which combination of tasks best fills a remainder
- A separate filler-task pool; the task-clearer replaces it
- Recurring break routines, now v0.4
- Ranking, scoring, or balancing between work and break tasks
- A general to-do system — tasks exist to serve landmarks

### Open decision

Calendar integration direction, deferred and blocking nothing above: EventKit (read
meetings in as landmark candidates, write focus and break sessions to a dedicated
calendar) versus an in-app history view only.

### Recommended issue order

1. Scaled clock, before anything whose behavior takes a day to observe.
2. Plan model, validation, and persistence.
3. Date travel and seeded plan fixtures, once there is a plan to seed.
4. Landmark pressure and capacity derivation.
5. Planning surface for landmarks and dependencies.
6. Scrollable landmark graph.
7. Runtime task queue and the selection rule.
8. Focus and break target surfaces.
9. Morning slate, stated day target, and replan.
10. Task-clearer nested session.
11. Day-end reconciliation of plan versus actual.

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

A break routine and a task-clearer item share a shape: a small named unit with an
approximate duration and a done state. Build the second on the first rather than
twice, differing only in where each is eligible to appear.

Work targets, previously planned as v0.4, are absorbed into v0.3 — a target is now a
dependency of a landmark rather than a free-standing intention.

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

**v0.5 — JSON import/export**

- Use a versioned representation of the now-stable daily rhythm, generated schedule, and plan
- Validate and preview imported schedules and plans before accepting them
- Accept an unstructured task dump structured externally into landmarks and dependencies
- Allow external services such as ChatGPT or Claude to prepare a schedule without embedding a paid API

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
- Focus shows one thing. Every decision belongs to a break — a choice offered mid-focus
  is a defection opportunity.
- Match spare time against how small a piece of a task is still worth doing, not against
  the size of the task.
- Work that is always correctly ranked last needs a reserved slot, not a higher rank.
- Watch what happens on day 4 and day 14 — that is where personal trackers usually fail.
- If a feature makes the app broadly marketable but does not make the daily rhythm calmer, park it.
