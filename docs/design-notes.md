# Design Notes

## Morning setup

The morning surface should ask for as few decisions as possible:

- Use the saved normal day.
- Adjust today only.
- Start now.

The preview should emphasize start, end, expected focus time, session count, and long
breaks. A fully editable calendar is not the default surface.

## Runtime

The primary presentation remains timer-first and ambient:

- **Now:** current phase or activity and remaining time.
- **Next:** the next meaningful transition and its time.
- **Day end:** always visible enough to remain trustworthy.

The generated timeline is a runtime mechanism, not an invitation to monitor a dense
productivity dashboard.

## Changes during the day

When an extension or inserted break changes the forecast, explain the consequence in
one sentence. For example:

> Adding 10 minutes removes the final partial focus session. The day still ends at 6:00.

Avoid silently cascading changes through the day.

## Breaks remain breaks

A routine occupies only its active duration. Completing a two-minute chore during a
ten-minute break leaves eight minutes of rest; it does not end the break or immediately
start work. Skips are neutral and do not require justification.

Long breaks use a soft exit ramp: a main rest period, a five-minute wrap-up warning,
and a two-minute final return warning.

## Scheduling vocabulary

- **Daily rhythm:** reusable constraints such as start/end, work cadence, work sections, and long breaks.
- **Generated schedule:** the concrete dated intervals for one day.
- **Anchor:** a fixed long break or day end.
- **Flexible interval:** work or short-break time that may shift around anchors.
- **Routine:** a reusable activity rule assigned to eligible breaks in a later phase.
