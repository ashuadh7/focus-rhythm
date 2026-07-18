# Structure

Current file map for the native iOS scaffold.

## App

- `FocusRhythm.xcodeproj/` — Xcode project and shared `FocusRhythm` scheme.
- `FocusRhythm/App/FocusRhythmApp.swift` — SwiftUI app entry point.

## Features

- `FocusRhythm/Features/Timer/` — timer home surface and timer state model.
- `FocusRhythm/Features/BreakActivities/` — water logging prompt shown during breaks.
- `FocusRhythm/Features/DailySummary/` — placeholder for end-of-day summary.

## Shared

- `FocusRhythm/Models/` — cross-feature domain models (`FocusPhase`, `WaterLogEntry`).
- `FocusRhythm/Persistence/` — local storage (timer settings, water logs).
- `FocusRhythm/Resources/` — placeholder for app resources and assets.

## Tests

- `FocusRhythmTests/` — unit test target scaffold.
