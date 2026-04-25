# focus-rhythm

> A focus timer that uses breaks as enforcement points for the small healthy habits you keep meaning to do.

*(Working title — alternatives: `break-ritual`, `flow-loop`, `intervals`. Rename freely.)*

## Why this exists

Most habit trackers fail because logging is a separate, deliberate act — you have to remember, open an app, tap through fields. By day five, the streak breaks and the data feels worthless.

Most focus timers (Pomodoro apps) tell you to take a break, but what you do during that break is on you. So you scroll Twitter and call it "rest."

`focus-rhythm` collapses both problems into one loop: **work blocks are protected, and breaks are pre-loaded with the small things you actually want to do.** Drink water. Stretch. Floss. The break isn't a passive timer — it's a guided 5–10 minutes with a clear, single prompt that auto-transitions back to work when done.

The hypothesis: habits stick when they're *embedded in a rhythm you already need*, not appended as a chore.

## Core insight

Two kinds of habits, two solutions:

- **Real-time / many-times-a-day** (water, posture, micro-movement) → enforced via break-time prompts during a focus session.
- **End-of-day reflection** (rate the day, did I floss, did I do my pushups) → a single 30-second evening check-in.

The app is one rhythm with two phases per cycle (work → break) and one ritual per day (evening review).

## Anti-goals (things this will never have)

- No subscription. No paid tiers. No "premium" features.
- No ads. Anywhere. Ever.
- No social features, leaderboards, or streaks-as-shame.
- No notification spam. The app talks to you only at cycle transitions.
- No data collection beyond device-local storage. Cloud sync is optional and only if/when added.
- No gamification that creates anxiety (no broken-streak guilt-trips).

## Design principles

1. **Friction is the enemy.** Logging an event should never take more than one tap.
2. **The break IS the reminder.** No separate notifications for habits. If you're on a break, the app tells you what to do.
3. **Show up, or don't.** The app doesn't punish missed sessions or broken streaks. Today is today.
4. **Personal first, product later.** Build for one user (me). If others want it, that's a bonus, not the goal.
5. **Ship ugly, then polish.** v0.1 doesn't need beautiful animations. It needs to work and prove the loop.

## Tech stack

**Native iOS (Swift + SwiftUI).** Cross-platform was considered (React Native, Flutter) but iOS-native wins here because:

- Live Activities + Dynamic Island make the work/break state ambient — you can see remaining time without opening the app.
- Local notifications and background timer behavior are more reliable native.
- HealthKit integration (future) is first-class.
- Personal-use-first means polish > portability.

**Core dependencies (kept minimal):**
- SwiftUI for UI
- SwiftData (or Core Data) for local persistence
- UserNotifications for cycle transitions
- ActivityKit for Live Activities (post-MVP)

## Repo structure (planned)

```
focus-rhythm/
├── README.md
├── PLAN.md                   # MVP scope, roadmap, working notes
├── docs/
│   ├── design-notes.md       # Interaction design rationale
│   └── decisions.md          # ADRs — why I chose what I chose
├── FocusRhythm/              # Xcode project root
│   ├── App/
│   ├── Features/
│   │   ├── Timer/
│   │   ├── BreakActivities/
│   │   └── DailySummary/
│   ├── Models/
│   ├── Persistence/
│   └── Resources/
├── FocusRhythmTests/
└── .gitignore
```

## Getting started

*(Will fill in once project is initialized.)*

```bash
# Clone
git clone https://github.com/ashuadh7/focus-rhythm.git
cd focus-rhythm

# Open in Xcode
open FocusRhythm.xcodeproj
```

**Requirements:**
- Xcode 16+
- iOS 17+ deployment target (for SwiftData and Live Activities)
- Apple Developer account (for device testing)

## Status

🌱 **Planning** — repo initialized, no code yet. See [PLAN.md](PLAN.md) for current scope and roadmap.

## License

TBD. Likely MIT for code; CC-BY for design notes.
