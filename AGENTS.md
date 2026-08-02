# Project Workflow

## Issue Selection

When the user asks to work on the "next issue," select the oldest open GitHub issue
unless it has a new or unresolved dependency that prevents or materially changes the
work. Check the issue's current dependencies before starting. If the oldest issue is
blocked, continue to the next-oldest unblocked issue and tell the user which issue was
skipped and why.

Use this oldest-first policy during the prototype phase. The user may replace it with
explicit prioritization once the prototype is sufficiently mature.

## Branch and Milestone Strategy

`development` is the integration branch for all work in the current milestone. `main`
must remain the stable branch and must not receive individual issue branches directly.

- Create every issue branch from the latest `development` branch.
- Open issue pull requests against `development`, not `main`.
- Merge approved issue pull requests into `development` throughout the milestone.
- Merge `development` into `main` only when the entire milestone is complete, has been
  reviewed as a whole, and the user has explicitly approved the milestone merge.
- After a milestone is merged, synchronize `development` with `main` before starting
  work on the next milestone.

For each GitHub issue assigned in a new chat:

1. Switch to the local `development` branch, synchronize it with `origin/development`
   when the remote branch exists, then create a branch dedicated to that issue from
   `development` before beginning development.
2. Implement the issue and run appropriate automated verification.
3. Ask the user to manually review the completed behavior.
4. After manual approval, commit and push the changes and open a pull request targeting
   `development` that includes a verification checklist.
5. Wait for the user to double-check and explicitly approve merging.
6. Merge the pull request only after that approval.
7. Delete the merged local and remote issue branches.

Do not skip the manual-review or double-verification gates. Do not merge merely because
automated checks pass.

## GitHub Authentication

The GitHub CLI credentials for this repository are stored in the macOS Keychain. A
`gh auth status` command run inside the restricted workspace sandbox may be unable to
read that keyring and can incorrectly report that the token is invalid.

Before asking the user to authenticate again:

1. Run `gh auth status -h github.com` with system/Keychain access.
2. Treat that result as authoritative.
3. Request a new login only if the system-access check also fails.

Do not infer that authentication has expired from the sandboxed check alone.
