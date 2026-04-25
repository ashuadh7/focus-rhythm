# Plan

Working scope, roadmap, and notes-to-self. This file changes often; the [README](README.md) is the stable picture.

## MVP scope (v0.1) — for me, right now

The smallest version that's actually usable for myself:

- [ ] Configurable work timer (default 50 min) and break timer (default 10 min)
- [ ] Auto-start break when work ends; auto-start next work block when break ends *(this is the key differentiator — no manual restart)*
- [ ] **One** integrated break activity: water logging. Break screen shows: "Drink water — log how much" with quick-tap amounts (250ml / 500ml / custom)
- [ ] Local storage of sessions and water logs
- [ ] End-of-day summary: total focus time, number of cycles, total water logged
- [ ] Manual session pause / skip break (escape hatches matter)

That's it. Ship this. Use it for two weeks. Then expand.

## Roadmap (post-MVP, in rough priority order)

**v0.2 — More break activities**
- Pushups counter (tap to log reps)
- Floss check-off
- Stretch / walk timer with prompt

**v0.3 — End-of-day reflection**
- 1–5 day rating
- Free-text note ("what worked, what didn't")
- Productivity self-rating

**v0.4 — Smarter break selection**
- Rotate through activities so you don't get the same prompt every break
- Different prompts based on time of day (morning = pushups, afternoon = walk)
- Longer breaks (15–20 min) get bigger activities; short breaks get water/stretch

**v0.5 — App blocking during work**
- iOS Screen Time API integration to lock distracting apps during focus blocks

**v0.6+ — Maybe**
- HealthKit sync (water, exercise minutes)
- Notion Calendar export of daily summaries
- Apple Watch companion for break prompts
- Widget / Live Activity for current cycle state

## Notes-to-self while building this

- Watch what happens on day 4 and day 14 — that's where most personal trackers die.
- If I find myself adding a feature that makes the app "more useful for other people," stop. Ship for me first.
- The friend's gaming-app project showed: imperfect-and-shipped beats perfect-and-stalled.
