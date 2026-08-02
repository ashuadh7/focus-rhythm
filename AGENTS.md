# Project Workflow

## Issue Selection

When the user asks to work on the "next issue," select the oldest open GitHub issue
unless it has a new or unresolved dependency that prevents or materially changes the
work. Check the issue's current dependencies before starting. If the oldest issue is
blocked, continue to the next-oldest unblocked issue and tell the user which issue was
skipped and why.

Use this oldest-first policy during the prototype phase. The user may replace it with
explicit prioritization once the prototype is sufficiently mature.

For each GitHub issue assigned in a new chat:

1. Create a new branch dedicated to that issue before development.
2. Implement the issue and run appropriate automated verification.
3. Ask the user to manually review the completed behavior.
4. After manual approval, commit and push the changes and open a pull request that includes a verification checklist.
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
