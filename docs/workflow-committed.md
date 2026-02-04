# Status: "committed" (Push and Create PR)

**Goal: Push branch and open pull request**

**IMPORTANT: This is the ONLY state where you should create a new PR. If status is "pushed", the PR already exists - NEVER create a duplicate PR.**

**NOTE: This step happens in the SAME iteration as "pending" → "committed" when all tests pass. Only proceed here if you just transitioned to "committed" in this iteration, OR if you're picking up a story that's already in "committed" status.**

## Steps

1. Change to git repo: `cd [workingDirectory from prd.json config]`

2. Get branch name from story's `branchName` field

3. Push the branch: `git push -u origin <branch-name>`

4. Create PR using gh CLI with structured format:

   **SECURITY NOTE**: If this PR fixes a security-sensitive issue, use discretion in the title and description. See [SECURITY.md](../SECURITY.md#public-security-messaging) for detailed guidance on avoiding detailed vulnerability disclosure in public messages.

   **IMPORTANT**: Always create PRs in draft state using the `--draft` flag. This allows for human review before marking ready.

   ```bash
   gh pr create --draft --title "Story title" --body "$(cat <<'EOF'
## Summary
[Brief description of what this PR does and why]

[If this is a Chromium test being disabled, add a clear note:]
**Note: This is a Chromium test** (located in `./src/` not `./src/brave/`).

## Root Cause
[Description of the underlying issue that needed to be fixed]

[If this is a Chromium test, include:]
- **Chromium upstream status**: [Chromium has also disabled this test / Chromium has not disabled this test / Evidence of upstream bug: crbug.com/XXXXX]
- **Brave modifications**: [Brave does not modify this code area / Brave has modifications in ./src/brave/chromium_src/[path] that may affect this test]

## Fix
[Description of how the fix addresses the root cause]

## Test Plan
- [x] Ran npm run format - passed
- [x] Ran npm run presubmit - passed
- [x] Ran npm run gn_check - passed
- [x] Ran npm run build - passed
- [x] Ran npm run test -- [test-name] - passed [N/N times]
- [ ] CI passes cleanly
EOF
)"
   ```

   **IMPORTANT**:
   - Fill in actual test commands and results from acceptance criteria
   - Keep the last checkbox "CI passes cleanly" unchecked
   - Do NOT add "Generated with Claude Code" or similar attribution
   - Capture the PR number from the output

5. **Assign the PR to yourself (the bot account):**

   ```bash
   gh pr edit <pr-number> --add-assignee @me
   ```

   This makes it clear who is responsible for the PR and helps with tracking.

6. **Set appropriate labels on the PR and linked issues:**

   ```bash
   # Add labels to PR
   gh pr edit <pr-number> --add-label "label1,label2"

   # Add labels to linked issue
   gh issue edit <issue-number> --add-label "label1,label2" --repo brave/brave-browser
   ```

   **For test issue fixes:**
   - Add labels to PR: `QA/No`, `release-notes/exclude`, `ai-generated`
   - Add labels to linked issue: `QA/No`, `release-notes/exclude`
   - **If the only change is disabling a test in a filter file** (e.g., adding to `test/filters/` or similar), also add the `CI/skip` label to the PR. This skips unnecessary CI runs for trivial filter-only changes.

   **For other PRs:**
   - Always add to PR: `ai-generated`
   - Add `release-notes/exclude` to both PR and linked issue for changes that typical browser users wouldn't care about (code cleanup, refactors, internal tooling, etc.)
   - Use judgment for `QA/No` based on whether manual QA testing is needed

7. **If push or PR creation succeeds:**
   - Update the PRD at `./brave-core-bot/prd.json`:
     - Store PR number in `prNumber` field
     - Store PR URL in `prUrl` field (format: `https://github.com/brave/brave-core/pull/<number>`)
     - Set `status: "pushed"`
     - Set `lastActivityBy: "bot"` (we just created the PR)
   - Append to `./brave-core-bot/progress.txt` (see [progress-reporting.md](./progress-reporting.md))
   - **Mark story as checked:** Add story ID to `run-state.json`'s `storiesCheckedThisRun` array
   - **END THE ITERATION** - Stop processing

8. **If push or PR creation fails:**
   - DO NOT update status in prd.json (keep as "committed")
   - Document failure in `./brave-core-bot/progress.txt`
   - **Mark story as checked:** Add story ID to `run-state.json`'s `storiesCheckedThisRun` array (don't retry endlessly)
   - **END THE ITERATION** - Stop processing
