# Structure

Current file map for the native iOS app after the v0.2 finite-daily-rhythm phase.

## App

- `FocusRhythm.xcodeproj/` — Xcode project and shared `FocusRhythm` scheme.
- `FocusRhythm/App/FocusRhythmApp.swift` — SwiftUI app entry point.

## Features

- `FocusRhythm/Features/Timer/` — timer-first home surface and the work/break runtime state model, including automatic transitions, bounded interruptions, extensions, end-cycle confirmation, and foreground catch-up.
- `FocusRhythm/Features/BreakActivities/` — full-screen water prompt and one-tap/custom water logging shown during breaks.
- `FocusRhythm/Features/DailySummary/` — quiet daily totals for completed focus time, cycle count, and water, plus planned-versus-actual focus for a finished day.
- `FocusRhythm/Features/RhythmSetup/` — morning rhythm selection, today-only adjustment, and the generated-schedule preview.

## Shared

- `FocusRhythm/Models/` — cross-feature domain models (`FocusPhase`, `WaterLogEntry`, `FocusSession`), the `DailyRhythm` definition with its work sections and anchored long breaks, the `DailyScheduleGenerator` that turns one into dated intervals, and the saved `RhythmLibrary`.
- `FocusRhythm/Persistence/` — UserDefaults-backed timer settings, water logs, focus sessions, the saved rhythm library, the active daily run, and local notification scheduling.

## Planned v0.3 additions

- A plan model of landmarks, dependency tasks, and estimates, holding no clock times.
- Derived landmark pressure comparing remaining estimates against focus capacity.
- A planning surface and a scrollable multi-day landmark graph.
- A runtime task queue that binds one task to a focus interval as it begins.
- A nested rapid-fire task-clearer session inside a single slot.

## Tests

- `FocusRhythmTests/` — unit test target scaffold.
