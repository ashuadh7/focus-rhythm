# Manual testing

Use these scenarios after automated tests pass and before committing an issue branch.
Record which scenario was used and any deviations in the pull request verification
checklist. Manual scenarios are intentionally short and deterministic; they are not
production rhythm templates.

## Choosing a mechanism

Three ways to make a scenario observable. Pick the cheapest one that can reach the
behavior under review.

| Mechanism | What it is | Use it for | Cannot reach |
| --- | --- | --- | --- |
| **Start test** | A rhythm built from 20-second blocks | Controls, transitions, labels, persistence across a handful of blocks | Anything depending on realistic ratios — warning thresholds, extension caps, percentage-based behavior |
| **Scaled clock** | A production-shaped rhythm run at 10×–120× | A full day's arc, day end, planned-versus-actual, long-break exit ramp at real proportions | Anything spanning more than one day |
| **Date travel + fixtures** | Jump the app's notion of today; load a plan in a known state | Deadline feasibility, imported-week carryover, day 4 and day 14 behavior | Anything about pacing or feel |

Two standing cautions. Under a scaled clock, local notifications still fire on real
wall-clock time, so notification reconciliation must be verified at 1× or through the
existing 20-second scenario. Under date travel, previously written sessions and water
logs keep their original real dates, so summaries read against the travelled date will
look empty unless the fixture seeds them too.

When backgrounding at a scaled rate, the virtual clock catches up from the real time
spent away multiplied by the selected rate. iOS still schedules and delivers local
notifications against real wall-clock dates, so notification timing during that catch-up
is intentionally not representative; return to 1× for notification checks.

## Rhythm variations

1. Open **Choose today’s rhythm** and tap **New variation** in the Variation section.
2. Name it **Four-session test** and use the focus-time wheel to choose 50-minute
   focus, 10-minute short break, 40-minute long break, and 4 focus sessions before the
   long break. Save the variation.
3. Create and save a second variation with visibly different values. Switch between
   the two and confirm each keeps its own name and cadence.
4. Edit one variation, change a wheel, and choose **Use only for this run**. Confirm
   the preview changes, then reselect the saved variation and confirm its stored value
   did not change.
5. Begin another new variation and cancel. Confirm it does not appear in the picker.
6. Under **Start now**, choose **Focus for** and confirm its focus target also uses
   separate hour and 15-minute increment wheels.
7. At a scaled clock rate, start **Four-session test** and confirm the run gives three
   short breaks between four focus sessions, then a 40-minute long break. Manual
   in-run break adjustment controls should remain the existing +/- controls.

## Fixed commitments (#62)

Use an imported/debug planning fixture with a work window and a fixed meeting inside
it. Start the rhythm before the meeting, then confirm focus stops at the meeting's
fixed start, the meeting is shown as an anchored interval, and cadence resumes only
after it ends. Relaunch during the meeting and confirm its time is never counted as
focus. Repeat with no planning data and confirm the normal rhythm-only start is
unchanged.

## Task work tracking (#63)

Use a saved task catalog with at least two unfinished tasks, one with a known estimate
and one without one, then use **Start test**.

1. Select the known task at the start of **cs 349 assignment**. Switch to the other
   task after several seconds, then switch back before the block ends. Confirm the
   timer still ends on its original schedule and the recorded task work is split at
   each switch rather than assigned entirely to the final task.
2. Mark the selected task done during a focus block. Confirm the countdown does not
   restart; select another task and confirm the remaining focus time is credited to it.
3. Let known work exceed its remaining estimate. Confirm its remaining estimate stops
   at zero but the task is not silently marked complete. Confirm unknown-effort work
   gains actual time without gaining a made-up estimate.
4. Take a mid-focus break, return, and finish the block. Confirm the break itself is
   not credited to either task. Quit and reopen before a later block completes, then
   confirm previously recorded task work is present exactly once.

## Child-task breakdown (#68)

On **Choose today’s rhythm**, add a parent task with **150 minutes** remaining. Add a
one-hour child and select that parent in **Break down work**.

1. Choose **Use existing estimate**. Confirm the parent now shows 90 minutes remaining
   and the combined known total is still 150 minutes. Edit the child to 90 minutes and
   confirm the parent drops to 60 minutes instead of increasing total work.
2. Change that child to **Add to estimate**. Confirm the parent returns to 150 minutes
   and the child adds 90 minutes of newly discovered work. Relaunch and confirm the
   child, its parent breadcrumb, and its accounting choice remain intact.
3. Create a child under a no-estimate parent. Confirm the app explains that total work
   remains unknown and does not invent an estimate. Add a grandchild, then edit its
   parent picker; its own descendant must not be offered as a possible parent.
4. Start a test focus block, select a child, and work briefly. Confirm the child gains
   actual focused time and its parent still shows a roll-up only where displayed—global
   focused time must not double. Mark a parent with unfinished children done or abandon
   it; confirm the action explicitly says it includes the children.

## Current task in focus (#48)

Use a task catalog containing a root task, a child task with a project/context and
deadline, an unknown-effort task, and a task whose remaining estimate is zero but is
not marked done. Start **Start test** and select each task from the queue before or
during focus.

1. Confirm the countdown and task name are readable together without opening a
   planning screen. For the child, confirm the parent breadcrumb is visible but its
   displayed progress is the child's own work, not a duplicated parent total.
2. Confirm project, context, and deadline appear only when supplied. Root and
   unknown-effort tasks should remain clear without empty placeholders; the latter
   says **Time unknown** and may show focused time.
3. For the zero-remaining task, confirm the timer says the estimate is used while the
   task remains open. It must not look completed merely because the estimate ran out.
4. Mark a task done mid-block. Confirm the same countdown continues, the task panel
   becomes a next-task suggestion, and selecting that suggestion credits only the
   remaining focus time to it. Run the rhythm with no selected task as well; the
   normal timer and break controls must remain usable.

## Task decisions at a break or during focus (#49)

Start a test rhythm with three queued tasks: **A** (2.5 hours), **B**, and **C**;
give A a near deadline and include both a local task and an imported task if a fixture
is available. Open **Tasks** from the timer during a break, then repeat while focus is
running.

1. Revise A from unknown to 90 minutes, add 30 minutes, then make it unknown again.
   Confirm each change survives relaunch, no task is completed or lost, and the timer
   and current break keep their original countdowns.
2. Break A into a one-hour child. First choose **Use existing estimate** and confirm
   the parent falls from 2.5 hours to 1.5 hours; then use **Add to estimate** for a
   different child and confirm it is shown as newly discovered work. Creating either
   child must not select it or reset the timer.
3. Move A/B/C earlier and later, postpone A with **Not now**, and choose B. Confirm
   A remains open, appears under Not now with a return time, and its selection never
   means completion, abandonment, or deletion. Repeat several deferrals and confirm
   an at-risk deadline is called out when it returns.
4. Choose a task during a break and verify the break continues; return to focus and
   confirm the selection is shown. Make the same estimate, child, and queue choices
   on imported work where applicable—the controls should not require source metadata.

## Today’s suggested flow (#45)

From the timer, tap **Today**. This is a review surface, not a second planner: task
placement is always a suggestion and selecting a task must not change the current
focus interval.

1. With no imported planning window, add a task and confirm **Today** says that an
   exact day plan is optional. Choose it, move it, and use **Not now**; return to the
   setup queue and confirm the same durable choice is visible there.
2. Load **Imported + local day 1**. Confirm fixed commitments appear separately from
   suggested work, and that known work that cannot fit produces an overflow warning
   rather than silently packing it around a meeting.
3. Use the child-task scenario above to make a one-hour child from a 2.5-hour parent.
   Confirm the child is shown as part of its parent, and the known total still reads
   2.5 hours for **Use existing estimate** and 3.5 hours for **Add to estimate**.
4. Add an unknown-effort task and a late-deadline task. Confirm uncertainty and
   deadline-risk wording remain visible; neither should create duplicated tasks or
   turn a suggestion into a fixed appointment. Start the rhythm and confirm its
   cadence remains unchanged.

## Reviewed external-plan import (#43)

Use a JSON transfer document with a stable plan `sourceID`, stable source IDs on every
task, a fixed meeting, one flexible timed task, one unknown-effort task, and one
unscheduled task. The checked-in synthetic example is a persisted catalog rather than
a transfer document, so remove `localState` and give its local example tasks source IDs
before using it as a file-import fixture.

1. Complete or partially work on a local task, reorder another local task, then choose
   **Import reviewed plan** from **Choose today's rhythm** and select the fixture in the
   Files picker. Confirm the review lists tasks, known and unknown effort, the planning
   window, fixed commitment, and proposed task context before anything is saved.
2. Cancel the review, relaunch, and confirm the local tasks, queue order, progress, and
   active run (if any) are unchanged. Repeat with malformed JSON and with a task missing
   `sourceID`; confirm the error identifies the problem and no data changes.
3. Apply the reviewed import. Confirm imported and local tasks use the same queue,
   Today forecast, and focus behavior; importing must not start, stop, or reshape a
   rhythm interval.
4. Add a local child to an imported 2.5-hour parent, allocate or add one hour, do some
   focused work, then reimport the same source with a changed parent estimate. Confirm
   the review shows the source proposal beside the local remaining estimate and actual
   work. Apply it and confirm local child accounting, work history, completion state,
   and queue choice survive without duplicate tasks.
5. Refresh again with that source task omitted. Confirm it is named as missing but is
   not deleted. Import a document with a different plan `sourceID`; confirm unfinished
   earlier tasks appear in **Carryover inbox**, not the active queue, until **Add to
   queue** is chosen for each one.

## Scaled production day

Use this scenario for realistic full-day proportions, long-break warning thresholds,
and planned-versus-actual summary totals.

1. In a debug build, choose a production rhythm and select **60×** in the persistent
   clock control before tapping **Start now**.
2. Confirm **Running at 60×** remains visible throughout the run.
3. Confirm a 50-minute focus interval completes in about 50 real seconds while the
   summary records 50 minutes of actual focus.
4. During a production long break, confirm wrap-up and final-return warnings appear at
   five and two virtual minutes remaining.
5. Background briefly, return, and confirm the timer catches up by approximately 60
   virtual seconds per real second spent away. Ignore local-notification delivery in
   this step; verify notifications separately at 1×.
6. Let the planned day finish in accelerated time. Confirm the summary's planned and
   actual focus totals describe the production day rather than the real minutes spent.
7. Return the clock to **1×** before normal use or notification testing.

## Date travel and task fixtures (#57)

Use a debug build. The bottom debug strip has **‹ Day**, **Day ›**, and **Today**;
it is absent from release builds. Its fixture menu deliberately asks for confirmation
because loading a fixture replaces the saved task catalog, focus sessions, water logs,
and any active or stopped run.

1. Choose **Load debug fixture** → **Local-only day 1**, confirm replacement, and
   verify the date becomes September 28, 2026. Check that the fixture includes an
   unknown-effort task plus child work that both uses and adds to a parent estimate.
2. Tap **Day ›** three times and then ten more times. The travelled dates should be
   day 4 and day 14, while the seeded partial/completed focus and water entries remain
   on their respective dates.
3. Return to day 1, load **Imported + local day 1**, and confirm the imported meeting,
   work segments, local child, added local child, unknown-effort task, reorder, and
   deferral are present in the persisted catalog.
4. Quit and relaunch. Confirm the loaded task catalog persists, then use the date
   controls to revisit the fixture dates. Return to **Today** and set the clock to
   **1×** before notification checks. Fixtures do not make local notifications
   representative of date travel.

## Named soft-landings

Use this scenario for timer transitions, extensions, inserted breaks, skipped breaks,
schedule reflow, active-block labels, persistence, and notification reconciliation.

1. Open **Choose today’s rhythm**.
2. At the bottom of the screen, under **Start now**, tap **Start test**.
3. Confirm the timer runs these focus blocks in order:
   - cs 349 assignment — 20 seconds
   - 10-second short break
   - Flow-sync — 20 seconds
   - 10-second short break
   - Throughline — 20 seconds
   - Lunch — 20-second long break
   - Grading — 20 seconds
   - 10-second short break
   - Scholarship — 20 seconds
4. Confirm the current focus or break name stays visible above the timer.
5. Exercise the behavior under review and verify its effect against the named blocks,
   not only the countdown value.
   When taking a mid-focus break, confirm the picker shows **10 sec** and that the
   current and subsequent block names remain visible afterward.
6. During **Lunch**, confirm the test-scaled wrap-up warning at 10 seconds remaining and
   return warning at 5 seconds remaining, including their background notifications when
   testing notification behavior. Production rhythms continue to use five and two minutes.
7. Let the final block finish and confirm the run ends after 2 minutes 30 seconds.

There is no trailing break after **Scholarship**.

## Long-break return and planned completion

Use **Start test**. Its 20-second **Lunch** break begins after **Throughline**.

1. Enter the long break and confirm the normal rest message appears for its first half.
2. At ten seconds remaining, confirm the timer shows the wrap-up warning.
3. Background the app, reopen it during the final five seconds, and confirm it shows the
   final-return warning without showing the earlier warning again.
4. Confirm notification settings contain no duplicate Focus Rhythm warnings after the
   app is reopened.
5. Let the planned day end pass and confirm the timer stops on the quiet **Day complete**
   surface instead of starting another focus interval.
6. Repeat with **End for today** and confirm the unfinished-day review opens rather
   than seeing an automatically completed day.

## Daily planned-versus-actual summary

Use **Start test**. The summary opens automatically when the run reaches its planned
end; after choosing **End for today**, discard the remainder and then start a fresh run
to inspect the prior terminal summary with **Today**.

1. Confirm the summary shows planned focus time, actual focus time, sessions completed
   out of planned sessions, and water logged.
2. End during a focus block after some elapsed work, then explicitly discard the
   remainder. Confirm that work contributes to **Focus actual** but does not increase
   the completed-session count, and the summary says **Ended for today**.
3. Let a fresh test run reach its end. Confirm the summary instead says
   **Completed at the planned end** and does not double-count completed focus after
   leaving and reopening the app.
4. Confirm each named focus block has its own planned and actual time. Take a mid-work
   break, skip a break, and extend a focus block or long break; confirm each adjustment
   appears in the detail below the totals.
5. End a run early, return to setup, then start another run that same day. Confirm the
   top totals include both runs and the detail shows **Session 1**, **Session 2**, and
   their activities and adjustments separately.

## Stop, review, and continue an unfinished day

Use **Start test** so the named remainder is easy to verify.

1. Let **cs 349 assignment** finish, then use **End for today** partway through
   **Flow-sync** and enter the required reasoning.
2. Confirm **Review unfinished day** shows completed focus, the original target,
   remaining focus, and the remaining named focus/break blocks in order. The partial
   **Flow-sync** remainder should be shorter than its original 20 seconds.
3. Force-quit and relaunch. Confirm the review returns instead of showing a completed
   day or silently restarting the timer.
4. Turn off one later named block and continue. Confirm the timer begins with the
   partial **Flow-sync** remainder and follows only the selected plan without creating
   another record for **cs 349 assignment**.
5. Repeat the stop flow and choose **Discard remaining plan**. Relaunch and confirm the
   discarded plan is no longer offered.

## Break controls

1. During a short or long break, hold the main control for about one second. Confirm its
   label says **Skip** and that the remaining break is removed without an accidental tap
   doing anything.
2. In the final 10% of a long break, confirm **Add time** appears. Use it once and
   confirm the next focus block begins after the added grace time while the day still
   ends at its planned time.

## Task model review (#39)

There is no phone screen for this yet. This review checks the rules that the later
task-entry screen will use. The sample is in
[weekly-plan-v1.json](examples/weekly-plan-v1.json).

Read this one example:

- **Literature review** is an imported task with **2.5 hours** of work left.
- You discover **Review X**, a new one-hour piece of that work.
- You choose **Use existing estimate**. That means Review X is part of the original
  2.5 hours, rather than extra work.
- The app records Literature review as **1.5 hours** left and Review X as **1 hour**.
  Together, they still equal **2.5 hours**.

The other choice is **Add to estimate**. In that case, Literature review stays at
2.5 hours and Review X adds another hour, for **3.5 hours total**.

Check that these rules feel right:

1. A task can be created in the app without Notion, a date, or an estimate.
2. A child task can use part of its parent's estimate or add more work to it.
3. If the parent has no estimate, a child can still be linked to it. The app should say
   that the total is unknown instead of making up a number.
4. Imported tasks and locally created tasks can appear together. A later re-import must
   not remove a child that was created locally.
5. After task entry and import screens land, create a parent and local child, reorder
   them, leave one unfinished, relaunch, and preview a refreshed source plan. Confirm
   the local child, its remaining estimate, and the queue order remain intact; a changed
   source estimate must be shown for review rather than silently replacing local work.

The automated tests also cover an example meeting, suggested work times, task order,
postponing a task, and recorded focus time. Those details matter to the data model, but
they are not needed to decide whether the child-task behavior above makes sense.

## Forecasting capacity (#41)

With the local task fixture, check the forecast explanation rather than expecting the
app to force work into the day: known effort uses only generated focus capacity, a
child using its parent's estimate leaves the combined total unchanged, and added work
increases the total. Unknown-effort work remains visible as uncertain. A deadline or
prerequisite conflict should remain explicit, with unplaced work shown as carryover
rather than silently completed or assigned through a fixed commitment.

## Persistent task queue (#47)

Use **Load debug fixture** → **Local-only day 1**. On **Choose today’s rhythm**, find
the **Task queue** section.

1. Confirm **Grade assignments** is offered ahead of the postponed coordinator email;
   the email appears under **Not now** and says when it will return.
2. Open the options for **Grade assignments**, choose **Not now**, then choose another
   task. Confirm postponing does not mark grading complete or remove it from the list.
3. Move a task earlier or later, quit and relaunch, then load the same fixture state
   again only if you need to reset it. Confirm the order chosen during the run remains
   after a normal relaunch.
4. Choose a deferred task directly. Confirm it becomes the selected next task and is
   no longer shown under **Not now**.
5. Use the mixed-origin fixture too. Confirm imported and local child tasks appear in
   one queue and can be selected or postponed the same way.

## Urgent work without restarting focus (#64)

Start a rhythm with **Grade assignments** selected and the scaled clock enabled.

1. While focus is running, open **Tasks** → **Add urgent task and do it now**. Add
   **Reply to student** with a ten-minute estimate. Confirm the countdown continues
   from its current time and the timer card now says **Working on Reply to student**.
2. Let a short amount of scaled focus time pass, then reopen **Tasks** and choose
   **Resume Grade assignments**. Confirm the original countdown continues rather than
   starting a new Pomodoro, and that the reply remains open in the queue.
3. Quit and relaunch while the reply is active. Confirm **Resume Grade assignments**
   is still offered; resume it and finish the focus interval. Confirm the normal break
   begins when the interval ends.
4. In the task details after the interval, confirm both tasks show focused time. The
   time spent on the email must be credited to the email, and the rest to grading.

## Day-end work review and carryover (#50)

Use **Load debug fixture** → **Mixed-origin tasks**, select a task, and run a short
scaled rhythm. Complete one task, leave a parent with a local child unfinished, and
postpone another task.

1. At day end, or after choosing **End for today** and discarding the remaining rhythm,
   open **Today**. Confirm **Work review** lists completed and unfinished tasks, actual
   focused time, known remaining work, and any time-unknown work without counting a
   child twice in the total.
2. Check a parent with children. Its own focused time and its child-inclusive rollup
   should be visibly distinct. Completing a child must not silently complete its parent
   or sibling.
3. On an unfinished local child, choose **Carry forward for review**, relaunch, and
   confirm it still shows **For later**. Its parent relationship, estimate choice,
   deadline/tags, and focused-time history must remain unchanged.
4. Choose **Return to active queue**. Confirm the task reappears without being marked
   complete and can be selected normally. Repeat with a task with no estimate; it must
   continue to say that its time is unknown.
5. Confirm stopping early or taking breaks never credits rest as task work. The next-day
   forecast may flag capacity, deadline, or prerequisite concerns, but it must not
   silently schedule or complete anything.

## Create local tasks (#67)

On **Choose today’s rhythm**, open **Task queue** and choose **Add task**.

1. Create **Draft outline** with a 45-minute estimate, a project, and one tag. Create
   **Investigate** with no estimate. Confirm both appear in the same queue and that
   the second one says **Time unknown** rather than appearing complete.
2. Choose one task, start a rhythm, then quit and relaunch. Confirm the tasks and the
   selected queue item remain available.
3. Add a task while a rhythm is active. Confirm it joins the queue; do not expect the
   running focus interval to switch automatically.
4. From a local task’s options, choose **Abandon task**. Confirm it leaves the active
   queue without marking it complete. Postpone a different task and confirm it stays
   active and returns under **Not now** instead.
5. Load the mixed-origin fixture, add one local task, then reload/import the fixture.
   Confirm the local task remains alongside imported work.

## Planned v0.3 verification coverage

These are acceptance targets for features not implemented yet. Each implementation
issue must turn the applicable target into a short runnable scenario with actual UI
labels; #58 audits the complete workflow after the features land.

| Coverage | Mechanism | Issue |
| --- | --- | --- |
| Reviewed weekly import and reimport with local progress/conflicts | Synthetic JSON fixture and normal UI | #40, #43 |
| Fixed versus suggested placement, late start, multiple available windows | Scaled clock + fixtures; notifications at 1× | #62, #41, #45 |
| Grading needs 30 more minutes while the 50/10/60 cadence stays intact | Scaled clock | #63, #49 |
| Insert ten-minute email, attribute its work, resume grading without resetting focus | Scaled clock; relaunch during interruption | #63, #64 |
| Reorder, postpone A, pick B, and let A return with a deadline explanation | Fixtures + interaction at normal speed | #47, #49 |
| Finish three hours early or need five extra hours; show honest overflow | Scaled clock + fixtures | #41, #45, #50 |
| End early, relaunch, carry revised unfinished work into tomorrow/next week | Date travel + fixtures | #40, #50, #57 |

Final review must confirm that optional categories do not require quotas, task choices
do not consume breaks, and estimate expiry does not mark a task complete. Verify the
default focus screen stays readable in about two seconds. Pure queue and capacity
calculations belong in unit tests; manual checks focus on user-visible behavior.
