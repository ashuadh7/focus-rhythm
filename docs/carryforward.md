# Carry-forward design notes

This file records cross-issue product decisions that future work must check before
changing related behavior. It is not an implementation backlog by itself; GitHub
issues remain the source of assigned scope and dependencies.

## Importing a fresh weekly plan while preserving real work

**Status:** agreed direction; refine #43 before implementing its import UI.

**Tags:** `import`, `task-catalog`, `persistence`, `carryover`, `queue`,
`forecast`, `task-hierarchy`, `external-plan`.

### Product intent

FocusRhythm is the durable record of work actually done. An externally generated JSON
file is a proposed plan, whether it was created by an LLM, a desktop workflow, or a
future connected service. A new source snapshot must never silently erase app-owned
history, actual work, local task breakdown, or queue decisions.

The normal low-friction path is an LLM-assisted desktop brain-dump saved as the
versioned JSON document in a cloud-synced folder (for example iCloud Drive), selected
through the iOS Files picker. A future direct cloud/HTTPS refresh must feed the same
decode → stage → review → apply pipeline; transport does not own reconciliation.

### Required import modes

1. **New weekly batch** — start from a newly generated plan. Incoming tasks are new
   proposals. The app offers unfinished prior tasks in a carryover inbox; it does not
   silently place them in the new queue.
2. **Refresh current plan** — revise the same source plan. Match stable `sourceID`s,
   stage additions/changes/omissions, and require review before persistence.

### Data ownership and reconciliation rules

| Incoming condition | Default resolution |
| --- | --- |
| New task | Add as a staged proposal. |
| Same `sourceID`, changed descriptive fields | Propose source title/context/deadline/tag updates. |
| Same `sourceID`, changed estimate | Show a conflict; never silently overwrite local remaining effort. |
| Absent from the incoming source | Mark as missing from source; never delete automatically. |
| Existing actual work or completion | Preserve permanently as app-owned history. |
| Local task or local child under an imported task | Preserve. Parent-estimate changes require reviewed resolution. |
| Rename, split, merge, or replacement | Let the person map prior task/carryover to incoming task(s), or retain/archive it. |

Source omission is not deletion. The available reviewed outcomes are: carry forward,
revise estimate/deadline, mark complete, explicitly abandon, archive as not-current,
or map the prior task to replacement task(s). Actual work stays attached to the task
where it occurred even when a later plan uses different task names.

### Estimate semantics

Keep these separate:

- **Original source estimate:** the proposed source baseline.
- **Current remaining estimate:** the app-owned working expectation.
- **Actual work:** credited focus already performed; immutable historical fact.

When a source estimate changes, the review must show the proposed source value beside
the local remaining value and actual work. It must not reinterpret prior focus or infer
completion. Child accounting (`usesParentEstimate` versus `addsToParentEstimate`) stays
auditable and cannot be silently recomputed by a source refresh.

### Contract and UI additions to consider for #43

- Add optional source snapshot revision/generation metadata so a refresh can be
  explained to the person.
- Add optional replacement/mapping metadata only if it remains source-neutral; do not
  make the JSON contract specific to any LLM or planning provider.
- Build a staged reconciliation preview with explicit choices before saving.
- Add a carryover inbox to the new-week flow, separate from the active queue.
- Keep continuous/background sync out of v0.3. A deliberate **Refresh plan** action
  is safer and preserves review control.

### Current foundation

The v0.3 model already has stable app IDs, optional `sourceID`, remaining estimates,
completion, deferrals, estimate-adjustment history, work segments, local hierarchy,
and a persisted task catalog. `WeeklyPlan.previewingImport` already preserves local
tasks/children and flags changed source estimates or missing source tasks. It does not
yet provide batch mode, a carryover inbox, mapping choices, archive/abandon state, or
a user-facing import/reconciliation screen.
