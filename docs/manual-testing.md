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
| **Date travel + fixtures** | Jump the app's notion of today; load a plan in a known state | Landmark pressure, replan carry-forward, a 10-day horizon, day 4 and day 14 behavior | Anything about pacing or feel |

Two standing cautions. Under a scaled clock, local notifications still fire on real
wall-clock time, so notification reconciliation must be verified at 1× or through the
existing 20-second scenario. Under date travel, previously written sessions and water
logs keep their original real dates, so summaries read against the travelled date will
look empty unless the fixture seeds them too.

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
