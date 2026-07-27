# Project Workflow

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
