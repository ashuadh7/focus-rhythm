# focus-rhythm — agent guide

Minimal, token-conscious. Update only at phase transitions or workflow changes — not per issue.

## Where things live

- [README.md](README.md) — why the project exists, principles, anti-goals, tech stack. Stable.
- [PLAN.md](PLAN.md) — high-level steering: MVP scope, roadmap by version. Read when prioritizing.
- [ideas-parking-lot.md](ideas-parking-lot.md) — deferred ideas. Do not pull from here without explicit ask.
- GitHub Issues — low-level technical work. Use `gh issue list` / `gh issue view N`. Do not duplicate here.
- `STRUCTURE.md` — file/feature map. Will exist once code lands. Read it before searching the tree.

## Current phase

v0.1 and v0.2 are complete. The active direction is v0.3: follow an externally
prepared weekly plan through the existing focus/break rhythm. Read PLAN.md before
creating or restructuring issues. Import, flexible preferences, fixed commitments,
task selection/postponement, urgent insertion, and carryover are in scope. The
landmark graph, task-clearer, category quotas, and continuous Notion sync are deferred.

## Workflow

- There are two issue workflows:
  - **Working on an issue:** user asks the agent to work a specific issue. Agent tries to solve it, then reports when done. User manually checks the implementation. User gives explicit go-ahead before push and merge. If there are problems, user either gives fix instructions or creates a separate sub-issue / issue to handle them.
  - **Working on issues:** user asks the agent to look at the overview. Agent reviews existing issues, dependencies, and structure, then helps change, split, merge, reprioritize, or otherwise restructure issues as directed.
- One issue at a time in the "working on an issue" workflow. Follow `AGENTS.md` for oldest-unblocked issue selection, active-milestone scope, branch strategy, and approval gates. GitHub dependencies replace any historical `ORDER.txt` ordering.
- The user usually names the files an issue touches up front. If not, consult `STRUCTURE.md` before searching.
- New branch per issue. **Never commit to main.**
- User tests the implementation manually. Do not claim success on UI work without their confirmation.
- When user says PR: open the PR, stop. Do not push, merge, or close without explicit ask.
- On session start: wait for instruction. Do not pre-run `git status` or read files speculatively.

## Commit / PR rules

- No `Co-Authored-By` or "Generated with Claude" footers.
- Stop after committing. No push or merge without approval.
- Hooks must not be skipped (`--no-verify` etc.) without explicit ask.
