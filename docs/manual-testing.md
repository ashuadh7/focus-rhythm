# Manual testing

Use these scenarios after automated tests pass and before committing an issue branch.
Record which scenario was used and any deviations in the pull request verification
checklist. Manual scenarios are intentionally short and deterministic; they are not
production rhythm templates.

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
6. Repeat with **End for today** and confirm it returns to setup rather than showing an
   automatically completed day.
