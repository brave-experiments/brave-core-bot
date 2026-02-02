# Workflow State Machine

## Your Task - State Machine Workflow

**CRITICAL: One Story Per Iteration**

Each iteration follows this model:
1. Pick ONE story based on priority (see below)
2. Execute the workflow for that story
3. Update the PRD and progress.txt
4. **END THE ITERATION** - Stop processing

The next iteration will pick the next highest-priority story. Never continue to multiple stories in a single iteration.

## Iteration Steps

**CRITICAL UNDERSTANDING: What "Next Story" Means**

You work on the NEXT ACTIVE STORY by priority number, REGARDLESS of its status. That story could be:
- `status: "pending"` - you implement it
- `status: "committed"` - you push it and create PR
- `status: "pushed"` - you check for review comments or merge it

**Active stories** are those with status other than "merged", "skipped", or "invalid".

**DO NOT filter to only "pending" stories!** If US-006 has priority 6 and US-008 has priority 8, you work on US-006 first, even though US-008 is "pending" and US-006 is "pushed". The status determines WHAT YOU DO with the story, not WHETHER you work on it.

### Step-by-Step Iteration Process

1. Read the PRD at `./brave-core-bot/prd.json` (in the brave-core-bot directory)
2. Read the progress log at `./brave-core-bot/progress.txt` (check Codebase Patterns section first)
3. **Load run state** from `./brave-core-bot/run-state.json`:
   - If `runId` is `null`, initialize a new run:
     - Set `runId` to current timestamp (e.g., `"2026-01-31T10:30:00Z"`)
     - Set `storiesCheckedThisRun` to empty array `[]`
     - Set `lastIterationHadStateChange` to `true`
     - Write the updated run-state.json
   - Otherwise, use the existing run state
   - **Read the `currentIterationLogPath`** from run-state.json - this is the log file for this iteration

4. **Pick the next user story** using this simple algorithm:

   **⚠️ CRITICAL: DO NOT filter by status at this step!**

   Do NOT think "what's the next pending story?" - think "what's the next ACTIVE story by priority number?"

   Example: If US-006 (priority 6, status "pushed") and US-008 (priority 8, status "pending") are both active, you pick US-006 because 6 < 8, even though US-008 is "pending". The status tells you WHAT TO DO, not WHETHER to pick it.

   **⚠️ IMPORTANT: Merged stories can still be candidates!** Stories with `status: "merged"` may need post-merge monitoring. They are NOT automatically excluded - they go through special filtering logic (merge backoff). A merged story in the `mergeBackoffStoryIds` array is an active candidate for selection!

   **Step 1: Load run state filters**
   - Read `run-state.json` to get:
     - `storiesCheckedThisRun` array
     - `skipPushedTasks` flag
     - `enableMergeBackoff` flag (defaults to `true` if not present)
     - `mergeBackoffStoryIds` (array of strings or null)

   **Step 2: Apply filters to get candidate stories**

   Start with all stories from prd.json. Then apply these filters in order:

   **2.1: Filter by completion status**
   - EXCLUDE stories with `status: "skipped"` (intentionally skipped)
   - EXCLUDE stories with `status: "invalid"` (invalid stories that won't be worked on)
   - EXCLUDE stories with `status: "merged"` AND `mergedCheckFinalState: true` (completely done, no more monitoring)
   - **IMPORTANT**: Stories with `status: "merged"` but NO `mergedCheckFinalState` field or `mergedCheckFinalState: false` are NOT automatically excluded - they go through merge backoff filtering below

   **2.2: Filter merged stories (post-merge monitoring)**
   - For stories with `status: "merged"` where `mergedCheckFinalState` is `false` or not present:
     - If `enableMergeBackoff` is `false`: EXCLUDE (post-merge checking disabled globally)
     - If `mergeBackoffStoryIds` is an array AND story ID is NOT in the array: EXCLUDE (only checking specific stories)
     - If `nextMergedCheck` exists and is in the future: EXCLUDE (not time to check yet)
     - Otherwise: **INCLUDE** (needs post-merge recheck)

   **2.3: Filter by run state**
   - EXCLUDE stories whose ID is in `storiesCheckedThisRun` array (already checked this run)
   - If `skipPushedTasks` is `true`, EXCLUDE all stories with `status: "pushed"`

   **2.4: Keep all other statuses**
   - **DO NOT** exclude stories based on status being "pending", "committed", or "pushed" (unless skipPushedTasks is true)

   **Step 3: If NO candidates remain after filtering**
   - Reset run state: Set `runId: null`, `storiesCheckedThisRun: []` in run-state.json
   - Set `lastIterationHadStateChange: false` in run-state.json (run completed without state change)
   - Log in progress.txt: "Run complete - all available stories processed"
   - **END THE ITERATION**

   **Step 4: Select the story with the LOWEST `priority` number**
   - From the remaining candidates, pick the story with the lowest `priority` field value
   - Lower numbers = higher priority (priority 1 comes before priority 2, etc.)
   - **REMEMBER**: The story could have ANY status (pending, committed, pushed) - you pick by priority number ONLY

   **Step 5: Work on the selected story**
   - Proceed with the workflow for the selected story's status (see sections below)
   - The status workflow will determine what actions to take (check reviews, merge, implement, etc.)

**CRITICAL**: Always prioritize responding to reviewers over starting new work. This ensures reviewers aren't kept waiting.

## State Change Tracking

The `lastIterationHadStateChange` field in run-state.json controls whether the work iteration counter increments. This keeps the iteration count meaningful (representing actual work done) while allowing rapid checking of multiple stories without inflating the count.

- **Set to `true`** when a story's status changes (pending→committed, committed→pushed, pushed→merged, or review response with push)
- **Set to `false`** when checking a story but making no changes (test failures, waiting for reviewer, blocked states)

This allows the system to check multiple pushed PRs rapidly without incrementing the work iteration counter for each one, while still using a fresh context for each check.

**Story Priority Within Each Level**: Within each status priority level above, pick stories by their `priority` field value. **Lower numbers = higher priority** (priority 1 is picked before priority 2, which is picked before priority 3, etc.).

## Record Iteration Log Path

5. **Record iteration log path** in the selected story:
   - Get the `currentIterationLogPath` from run-state.json
   - In prd.json, add this path to the selected story's `iterationLogs` array field:
     - If the story doesn't have `iterationLogs`, create it as an array: `"iterationLogs": []`
     - Append the current log path to the array
     - This creates an audit trail of all iterations that worked on this story
   - Write the updated prd.json

## Execute Workflow Based on Status

6. Execute the workflow based on the story's current status:
   - **"pending"**: See [workflow-pending.md](./workflow-pending.md)
   - **"committed"**: See [workflow-committed.md](./workflow-committed.md)
   - **"pushed"**: See [workflow-pushed.md](./workflow-pushed.md)
   - **"merged"**: See [workflow-merged.md](./workflow-merged.md)
   - **"skipped"** or **"invalid"**: See [workflow-skipped-invalid.md](./workflow-skipped-invalid.md)

## Task Selection Priority Summary

When picking the next story, use this priority order:

1. **URGENT (Highest)**: `status: "pushed"` AND `lastActivityBy: "reviewer"`
   - **Why**: Reviewer is waiting for us - respond immediately
   - **Action**: Enter implementation sub-cycle to address feedback

2. **HIGH (Create PRs)**: `status: "committed"`
   - **Why**: Code is ready, make it public for review ASAP
   - **Action**: Push branch and create PR (happens in same iteration as pending → committed)

3. **MEDIUM (Check Reviews)**: `status: "pushed"` AND `lastActivityBy: "bot"`
   - **Why**: Check if reviewer responded or PR is ready to merge
   - **Action**: Check merge status:
     - If ready to merge → merge and end iteration
     - If new comments from reviewer → treat as URGENT (address feedback in this iteration)
     - If still waiting for reviewer → log status check and END iteration

4. **NORMAL (New Work)**: `status: "pending"`
   - **Why**: Start new development work
   - **Action**: Implement and test new stories

5. **LOW (Post-Merge Monitoring)**: `status: "merged"` AND `mergedCheckFinalState: false` AND (`nextMergedCheck` missing OR in the past)
   - **Why**: Monitor merged PRs for post-merge follow-up requests (background task)
   - **Action**: Check for new comments since merge, create follow-up stories if needed, update recheck schedule
   - **Selection**: Pick merged story with OLDEST `nextMergedCheck` timestamp (or missing `nextMergedCheck` if none have timestamps)
   - **Note**: Only runs when enabled via `run-state.json` (`enableMergeBackoff: true`) and filtered by `mergeBackoffStoryIds` if that array exists

6. **SKIP**: `status: "merged"` with `mergedCheckFinalState: true`, `status: "skipped"`, or `status: "invalid"`
   - **Why**: Completely done (all monitoring complete), intentionally skipped, or invalid

**CRITICAL PRINCIPLE**: Always prioritize reviewer responsiveness over starting new work. Reviewers' time is valuable - respond to them before picking up new stories.

**Anti-Stuck Guarantee**: All "pushed" stories are checked every iteration, ensuring approved PRs auto-merge and new review comments are detected immediately.

**Story Priority Field**: Within each status priority level above, pick stories by their `priority` field from prd.json. **Lower numbers = higher priority**: A story with `priority: 1` is picked before a story with `priority: 2`, which is picked before `priority: 3`, etc.

## Error Handling

**GitHub CLI (gh) Failures:**
- If any `gh` command fails, log the error and abort immediately
- Do NOT attempt workarounds or continue without the gh operation
- Document the failure in ./brave-core-bot/progress.txt (story remains at current status)
