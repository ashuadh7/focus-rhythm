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

## Active direction: v0.2 — Finite daily rhythm

### Outcome

In the morning, select or lightly adjust a normal day, press Start, and let the app
carry the day through short work/break cycles, long breaks, and a definite ending.

### Scope

- [ ] Save one reusable default daily rhythm:
  - start and end time
  - work and short-break durations
  - repeating work sections
  - anchored long breaks
- [ ] Generate a dated timeline of work, short-break, and long-break intervals
- [ ] Preview start/end, expected focus time, session count, and long breaks before starting
- [ ] Support "start as planned," "start now," and a today-only adjustment
- [ ] Drive the timer from the generated timeline instead of an endless two-phase loop
- [ ] Show a quiet `Now / Next` runtime view
- [ ] Persist and restore the active daily run after full app termination
- [ ] Schedule known transition notifications in advance and reschedule after changes
- [ ] Preserve the existing soft landings within the daily timeline:
  - extensions and inserted short breaks shift later flexible intervals
  - long breaks and day end remain fixed anchors
  - overflow trims or drops the final incomplete focus interval rather than eroding every break
- [ ] Give long breaks a soft exit ramp:
  - main break
  - five-minute wrap-up warning
  - two-minute final return warning
- [ ] Stop automatically at the configured day end and show planned versus actual focus

### Explicitly out of scope for v0.2

- Break-activity library or automatic chore placement
- Work task management
- Drag-and-drop calendar editing
- LLM/API integration or schedule-file import
- Live Activity / Dynamic Island
- Sophisticated schedule optimization

### Recommended issue order

1. Model and validate a reusable daily rhythm and generated intervals.
2. Add morning setup and a generated schedule preview.
3. Drive the timer from the finite daily schedule.
4. Persist and restore an active daily run.
5. Schedule and reschedule the day's transition notifications.
6. Integrate existing extensions/interruption controls with fixed anchors.
7. Add long-break exit warnings and intentional day completion.
8. Extend the daily summary with planned-versus-actual focus.

## Next: v0.3 — Recurring break routines

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

## Later: v0.4 — Work targets

Define this phase only after the work-side requirements are understood. The current
direction is deliberately narrower than a task manager:

- Give each large work section one intended outcome
- Optionally show one current target during a focus interval
- Between intervals, continue, select the next target, or mark it complete

Avoid importing or duplicating a full to-do system until the daily rhythm and
break-routine loop have proved useful in real use.

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

- Use a versioned representation of the now-stable daily rhythm and generated schedule
- Validate and preview imported schedules before accepting them
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
- Watch what happens on day 4 and day 14 — that is where personal trackers usually fail.
- If a feature makes the app broadly marketable but does not make the daily rhythm calmer, park it.
