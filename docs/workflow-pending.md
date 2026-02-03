# Status: "pending" (Development)

**Goal: Implement and test the story**

**📖 FIRST STEP**: All acceptance criteria begin with "Read ./brave-core-bot/BEST-PRACTICES.md" - this contains critical async testing patterns including:
- Never use EvalJs inside RunUntil() lambdas (causes DCHECK on macOS arm64)
- Never use RunUntilIdle()
- Proper patterns for JavaScript evaluation in tests
- Navigation timing and same-document navigation handling
- Test isolation principles

Read this document BEFORE analyzing the issue or implementing fixes.

## Implementation Steps

1. **IMPORTANT**: All git operations must be done in `[workingDirectory from prd.json config]` directory

2. **CRITICAL BRANCH MANAGEMENT**:
   - Change to the git repo: `cd [workingDirectory from prd.json config]`
   - Checkout master: `git checkout master`
   - Pull latest changes: `git pull origin master`

   **Check if story already has a branch:**
   - If story has `branchName` field with a value: Use that existing branch (`git checkout <branchName>`)
   - If story has NO `branchName` or it's null: Create NEW branch following naming convention below
   - Store the branch name in prd.json `branchName` field

   **Branch Naming Format:**
   - Pattern: `fix-<descriptive-name-in-kebab-case>`
   - Example: `fix-solana-provider-test`, `fix-ai-chat-task-ui`
   - Derive from story title, keeping it concise and descriptive
   - Max length: 50 characters
   - Only lowercase letters, numbers, and hyphens
   - No prefixes like `bot/` or `user/` (keep simple)

   **If branch name already exists remotely:**
   - This indicates a previous incomplete attempt
   - Story should have `branchName` field set - use that instead
   - If push fails due to existing branch, check story's `branchName` field

   **NEVER create a new branch if one already exists for this story!**

3. Implement the user story

   **IMPORTANT: Where to Make Fixes**

   When fixing test failures, the fix can be in:
   - **Production code** (the code being tested) - if the implementation is wrong
   - **Test code** (the test itself) - if the test has bugs, incorrect assumptions, or is testing the wrong thing
   - **Both** - sometimes both the implementation and test need corrections

   Analyze the failure carefully to determine where the actual problem lies. Don't assume the production code is always wrong - tests can have bugs too.

4. **CRITICAL**: Run **ALL** acceptance criteria tests - **YOU MUST NOT SKIP ANY**

   See [testing-requirements.md](./testing-requirements.md) for complete test execution requirements.

5. Update CLAUDE.md files if you discover reusable patterns (see below)

6. **If ALL tests pass:**
   - Commit ALL changes (must be in `[workingDirectory from prd.json config]`)
   - **IMPORTANT**: If fixing security-sensitive issues (XSS, CSRF, buffer overflows, sanitizer issues, etc.), use discretion in commit messages - see [SECURITY.md](../SECURITY.md#public-security-messaging) for guidance
   - Update the PRD at `./brave-core-bot/prd.json`:
     - Set `status: "committed"`
     - Set `lastActivityBy: null` (not yet public)
     - Ensure `branchName` field contains the branch name
   - Append your progress to `./brave-core-bot/progress.txt` (see [progress-reporting.md](./progress-reporting.md))
   - **Continue in same iteration:** Do NOT mark story as checked yet - proceed immediately to push and create PR (see [workflow-committed.md](./workflow-committed.md))

7. **If ANY tests fail:**
   - DO NOT commit changes
   - Keep `status: "pending"`
   - Keep `branchName` (so we can continue on same branch next iteration)
   - Document failure in `./brave-core-bot/progress.txt`
   - **Mark story as checked:** Add story ID to `run-state.json`'s `storiesCheckedThisRun` array (don't retry same story endlessly)
   - **END THE ITERATION** - Stop processing

## Retry Policy for Persistent Test Failures

If a story keeps failing tests across multiple iterations:

1. **First Failure**: Document the failure, keep trying
2. **Second Failure**: Analyze root cause more deeply, try different approach
3. **Third+ Failure**: If tests keep failing after 3+ attempts:
   - Add a detailed comment to `./brave-core-bot/progress.txt` explaining:
     - What was tried
     - Why tests are failing
     - What blockers exist (missing dependencies, environment issues, etc.)
   - Mark story with a special note: "BLOCKED - Requires manual intervention"
   - Skip this story in subsequent iterations until the blocker is resolved

**Important**: Count failures per implementation approach, not just per iteration. If you try a completely different fix strategy, that's a new attempt.

The goal is to avoid infinite loops on impossible tasks while still giving sufficient retry attempts for legitimate intermittent failures or initial misunderstandings.

## Problem-Solving Approach

**CRITICAL: No Workarounds or Band-Aids**

- **NEVER use workarounds** - Every fix must address the root cause
- **NEVER add arbitrary waits or sleep statements** - If you think you need a wait, you don't understand the problem
- **NEVER make changes that "fix" the test by altering execution timing** - This is the most common type of fake fix. The problem disappears locally but the race condition still exists and will inevitably return. Examples include (but are not limited to):
  - Adding logging, console.log(), or debug output
  - Adding meaningless operations (variable assignments, loops, function calls)
  - Reordering unrelated code
  - Adding includes or forward declarations that change compilation order
  - Refactoring code in ways that accidentally change execution order
  - **ANY change where you cannot explain the synchronization mechanism it provides**
- **If your "fix" works but you can't explain WHY it addresses the race condition, it's not a real fix**
- **Understand the problem deeply** before attempting a fix:
  - Read relevant code thoroughly
  - Understand the data flow and control flow
  - Identify the actual root cause, not just symptoms
  - **Determine whether the issue is in production code, test code, or both** - don't assume the production code is always at fault
- **Fixes must be high-confidence solutions** that address the core issue
- If you cannot understand the root cause with high confidence, keep the story as `status: "pending"` and document why
- Temporary hacks or arbitrary timing adjustments are NOT acceptable solutions

## Update CLAUDE.md Files

Before committing, check if any edited files have learnings worth preserving in nearby CLAUDE.md files:

1. **Identify directories with edited files** - Look at which directories you modified
2. **Check for existing CLAUDE.md** - Look for CLAUDE.md in those directories or parent directories
3. **Add valuable learnings** - If you discovered something future developers/agents should know:
   - API patterns or conventions specific to that module
   - Gotchas or non-obvious requirements
   - Dependencies between files
   - Testing approaches for that area
   - Configuration or environment requirements

**Examples of good CLAUDE.md additions:**
- "When modifying X, also update Y to keep them in sync"
- "This module uses pattern Z for all API calls"
- "Tests require the dev server running on PORT 3000"
- "Field names must match the template exactly"

**Do NOT add:**
- Story-specific implementation details
- Temporary debugging notes
- Information already in progress.txt

Only update CLAUDE.md if you have **genuinely reusable knowledge** that would help future work in that directory.

## Consolidate Patterns

If you discover a **reusable pattern** that future iterations should know, add it to the `## Codebase Patterns` section at the TOP of ./brave-core-bot/progress.txt (create it if it doesn't exist):

```
## Codebase Patterns
- Example: Use `sql<number>` template for aggregations
- Example: Always use `IF NOT EXISTS` for migrations
- Example: Export types from actions.ts for UI components
```

Only add patterns that are **general and reusable**, not story-specific details.

## Browser Testing (If Available)

For any story that changes UI, verify it works in the browser if you have browser testing tools configured (e.g., via MCP):

1. Navigate to the relevant page
2. Verify the UI changes work as expected
3. Take a screenshot if helpful for the progress log

If no browser tools are available, note in your progress report that manual browser verification is needed.
