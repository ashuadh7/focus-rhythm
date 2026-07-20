# Ideas parking lot

A holding pen for future ideas and feature impulses that should **not** be built now but might be revisited later.

This file is a guardrail against scope creep. When a tempting idea shows up mid-build, it goes here instead of into the active [PLAN.md](PLAN.md). The act of writing it down is the release valve — it gets to exist without derailing the current phase.

Rules:
- Anything in here is **not** scheduled. It will be reconsidered only when the current phase is genuinely working.
- Each entry should say *why it's deferred*, not just what it is. Future-me needs the reasoning to judge whether to promote it.
- Promoting an entry to PLAN.md is a deliberate decision, not a default.

## Entries

- **Task organizer / to-do integration.** Strong impulse to expand focus-rhythm into a full task management tool. Defer until at least v0.4 and only revisit if the core focus/break/habit loop is genuinely working and sticking. The risk is bloating the app and losing the tight, single-purpose feel that makes it valuable.
- **Scatter-brain circuit breakers.** Personalized "snag routines" for when focus collapses mid-session — short physical/sensory jolts the user has pre-registered as effective for them (e.g. spicy food, ice water, 30s exercise, cold shower, walk outside). App would surface a tailored suggestion instead of a generic break. Defer until the base focus loop is proven; this needs a profile/preferences system and risks turning into a coaching app. Worth revisiting once there's enough usage data to know what kinds of snags actually happen.
- **Audio Visual recommender.** Suggest accompanying podcast, video essays, news, etc. that you can listen to during breaks like food time, eating time, cleaning time, etc. The length of the activity and the other medium should match so that you don't continue listening/watching beyond the length of original task (either a single thing itself is too long or it is too short and another video is opened and it cascades.)
- **Ingest Previous Information.** Scan saved notes of good points to remember such as communication skills, tips for research, tips for presentation, etc. Fetch that information during the weekly planning time. Then, surface those points or even make me practice those "good" points in real time.
- **Productive Breaks have rank.** Use randomizer to substitute productive break if you don't feel like it. But all are not equal. Depedning on the ELO score of work work and productive break balance it so that you don't feel like you are slacking through "productive break", nor are you too overwhelmed with work.
 - **Minitask** I get distracted by the details and spend too much in smaller tasks... create a list of task with 3, 5, 10 mins timer for each for a burst of 1 hour work... 7 different mini-tasks that takes an hour so everything is dealt with... the timer states the short goal and moves quickly to the next - call it task-clearer
 - **Theme of the day** **Daily Narrative Prompt**

        I have these tasks for tomorrow: [list all tasks with project names]

        For each task, tell me:

        - What project is it for?
        - What's the immediate output or deliverable?
        - Who am I accountable to, or what's the downstream impact?

        Then generate for me:

        1. A single tagline (2-3 words, or a short phrase) that captures the unifying theme of the day
        2. A brief explanation of how each task connects to that theme
        3. The cognitive mode for each block (deep work vs. exploratory vs. synthesis)

        This helps me see the day as one coherent quest instead of fragmented tasks, and know in advance which blocks should have breakthrough potential vs. steady progress.

        ---

        Key insight to keep in mind: you're not after a long narrative. You want a punchy tagline that reframes scattered tasks as chapters of one story. Today's was *"Grounding myself in the problem space"* — that's the template.


- **Break Timer Sequence (Flow Exit Ramp).** When taking a longer break mid-work session, automatically trigger a three-phase timer: a main break timer for the full break duration, followed by a five-minute soft exit ramp to begin wrapping up and pruning tabs/distractions, followed by a two-minute hard cutoff to fully stop and return to work. The goal is to remove the decision of "when do I stop the break" — the structure handles it so the transition back to work happens automatically and without negotiation.