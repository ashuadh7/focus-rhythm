# Structure

Current file map for the native iOS app after the v0.1 continuous-loop phase.

## App

- `FocusRhythm.xcodeproj/` — Xcode project and shared `FocusRhythm` scheme.
- `FocusRhythm/App/FocusRhythmApp.swift` — SwiftUI app entry point.

## Features

- `FocusRhythm/Features/Timer/` — timer-first home surface and the work/break runtime state model, including automatic transitions, bounded interruptions, extensions, end-cycle confirmation, and foreground catch-up.
- `FocusRhythm/Features/BreakActivities/` — full-screen water prompt and one-tap/custom water logging shown during breaks.
- `FocusRhythm/Features/DailySummary/` — quiet daily totals for completed focus time, cycle count, and water.

## Shared

- `FocusRhythm/Models/` — cross-feature domain models (`FocusPhase`, `WaterLogEntry`, `FocusSession`).
- `FocusRhythm/Persistence/` — UserDefaults-backed timer settings, water logs, focus sessions, and local notification scheduling.

## Planned v0.2 additions

- A daily-rhythm model describing flexible work sections and fixed long-break/day-end anchors.
- A schedule generator producing dated work, short-break, and long-break intervals.
- Persistence for the generated day and active run, not only completed sessions.
- Morning setup/preview and a runtime `Now / Next` presentation.

## Tests

- `FocusRhythmTests/` — unit test target scaffold.
