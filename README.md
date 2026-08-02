# focus-rhythm

> A focus timer that uses breaks as enforcement points for the small healthy habits you keep meaning to do.

*(Working title — alternatives: `break-ritual`, `flow-loop`, `intervals`. Rename freely.)*

## Why this exists

Most habit trackers fail because logging is a separate, deliberate act — you have to remember, open an app, tap through fields. By day five, the streak breaks and the data feels worthless.

Most focus timers (Pomodoro apps) tell you to take a break, but what you do during that break is on you. So you scroll Twitter and call it "rest."

`focus-rhythm` collapses both problems into one loop: **work blocks are protected, and breaks can carry the small things you actually want to do.** Drink water. Stretch. Floss. The goal is a finite daily rhythm that can be set in the morning and trusted to move through work, short breaks, long breaks, and the end of the day without repeated planning.

The hypothesis: decisions become easier and habits become more consistent when they
are *embedded in a reusable rhythm you already need*, not negotiated again every hour.

## Core insight

Two kinds of habits, two solutions:

- **Real-time / many-times-a-day** (water, posture, micro-movement) → enforced via break-time prompts during a focus session.
- **End-of-day reflection** (rate the day, did I floss, did I do my pushups) → a single 30-second evening check-in.

The app begins with a repeating work → break cycle and grows into one finite daily
rhythm with larger work sections, long breaks, recurring routines, and an intentional end.

## Design north star: ambient, not appy

`focus-rhythm` should feel like a clock you dock on the side of your phone, not an app you open and navigate. Most of the time it's just *there* — passively showing what phase of the cycle you're in (work / break / idle). It only asks for active interaction at cycle transitions, and even then, ideally one tap.

The aesthetic goal is "a good watch face," not "a productivity dashboard." This shapes every interface decision downstream:

- **The home screen IS the timer.** No tabs, no nav bar, no "dashboard." The default view is the current state.
- **Live Activities and Dynamic Island are the primary interface,** not optional polish. They're how you interact with the app most of the day. The full app is the "settings + history" layer behind the ambient surface.
- **Break activity prompts are full-screen takeovers during the break,** not screens you have to navigate to. The break IS the prompt.
- **Avoid every visual pattern that screams "engagement-driven app":** no streaks-as-dopamine, no badges, no notification spam, no home-screen-grabbing.
- **Spatial separation from work is a feature.** The phone is the right home for this app *because* it's not the desktop where the focus work happens.

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
- UserDefaults with Codable models for current local persistence
- UserNotifications for cycle transitions
- ActivityKit for Live Activities (post-MVP)

## Repository structure

```
focus-rhythm/
├── README.md
├── PLAN.md                   # Active scope, roadmap, working notes
├── FocusRhythm.xcodeproj
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
│   └── Persistence/
├── FocusRhythmTests/
└── .gitignore
```

## Getting started

```bash
# Clone
git clone https://github.com/ashuadh7/focus-rhythm.git
cd focus-rhythm

# Open in Xcode
open FocusRhythm.xcodeproj
```

**Requirements:**
- Xcode 16+
- iOS 17+ deployment target
- Apple Developer account (for device testing)

**Build from the command line:**

```bash
xcodebuild \
  -project FocusRhythm.xcodeproj \
  -scheme FocusRhythm \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

Manual product checks use the reusable scenarios and workflow in
[docs/manual-testing.md](docs/manual-testing.md).

## Status

✅ **v0.1 continuous focus loop complete** — the app has configurable and automatic
work/break timers, water logging, local persistence, a daily summary, bounded
interruption/extension controls, and background-time correction with notifications.

The active product phase is **v0.2: finite daily rhythm** — generating and running a
recoverable day with work sections, short breaks, long breaks, and a definite end.
See [PLAN.md](PLAN.md) for scope and sequencing.

## License

TBD. Likely MIT for code; CC-BY for design notes.
