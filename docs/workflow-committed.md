# Status: "committed" (Push and Create PR)

**Goal: Push branch and open pull request**

**IMPORTANT: This is the ONLY state where you should create a new PR. If status is "pushed", the PR already exists - NEVER create a duplicate PR.**

**NOTE: This step happens in the SAME iteration as "pending" → "committed" when all tests pass. Only proceed here if you just transitioned to "committed" in this iteration, OR if you're picking up a story that's already in "committed" status.**

## Steps

1. Change to git repo: `cd [workingDirectory from prd.json config]`

2. Get branch name from story's `branchName` field

3. Push the branch: `git push -u origin <branch-name>`

4. Create PR using gh CLI with structured format:
   ```bash
   gh pr create --title "Story title" --body "$(cat <<'EOF'
## Summary
[Brief description of what this PR does and why]

## Root Cause
[Description of the underlying issue that needed to be fixed]

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

5. **If push or PR creation succeeds:**
   - Update the PRD at `./brave-core-bot/prd.json`:
     - Store PR number in `prNumber` field
     - Store PR URL in `prUrl` field (format: `https://github.com/brave/brave-core/pull/<number>`)
     - Set `status: "pushed"`
     - Set `lastActivityBy: "bot"` (we just created the PR)
   - Append to `./brave-core-bot/progress.txt` (see [progress-reporting.md](./progress-reporting.md))
   - **Mark story as checked:** Add story ID to `run-state.json`'s `storiesCheckedThisRun` array
   - **END THE ITERATION** - Stop processing

6. **If push or PR creation fails:**
   - DO NOT update status in prd.json (keep as "committed")
   - Document failure in `./brave-core-bot/progress.txt`
   - **Mark story as checked:** Add story ID to `run-state.json`'s `storiesCheckedThisRun` array (don't retry endlessly)
   - **END THE ITERATION** - Stop processing
