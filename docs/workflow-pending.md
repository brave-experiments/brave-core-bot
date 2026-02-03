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

3. **Check for existing pull requests**

   Before starting implementation, verify that no one else (including other bots) has already put up a PR for this issue:

   **Extract issue number from story:**
   - Look at the story's `description` field for the issue number (e.g., "issue #50022")
   - Look at the first item in `acceptanceCriteria` (usually "Fetch issue #XXXXX details...")
   - Extract the numeric issue number

   **Check for linked or related pull requests:**
   ```bash
   # Search for PRs that reference this issue number
   gh pr list --repo brave/brave-browser --search "<issue-number>" --json number,title,state,url,author
   ```

   **Also check the brave-core repository (where PRs are created):**
   ```bash
   gh pr list --repo brave/brave-core --search "<issue-number>" --json number,title,state,url,author
   ```

   **Analyze the results:**
   - If an **open** PR exists that clearly addresses this issue:
     - Check the PR author and description to confirm it's for the same issue
     - Update the story in `./brave-core-bot/prd.json`:
       - Set `status: "skipped"`
       - Add or update a `skipReason` field explaining why (e.g., "PR #XXXXX already exists for this issue")
     - Document in `./brave-core-bot/progress.txt` that you found an existing PR
     - **Post a comment on the GitHub issue** (if not already commented):
       ```bash
       gh issue comment <issue-number> --repo brave/brave-browser --body "$(cat <<'EOF'
       This issue is already being addressed by PR #XXXXX (in brave-core repository).

       Skipping duplicate work.
       EOF
       )"
       ```
     - **END THE ITERATION** - Move to next story

   - If a **closed/merged** PR exists:
     - The issue might already be fixed
     - Verify if the issue is still open or if it was properly closed
     - If the issue is still open despite a merged PR, proceed with investigation

   - If **no PR exists** or only unrelated PRs were found:
     - Proceed with implementation (continue to step 4)

4. Implement the user story

   **IMPORTANT: Where to Make Fixes**

   When fixing test failures, the fix can be in:
   - **Production code** (the code being tested) - if the implementation is wrong
   - **Test code** (the test itself) - if the test has bugs, incorrect assumptions, or is testing the wrong thing
   - **Both** - sometimes both the implementation and test need corrections

   Analyze the failure carefully to determine where the actual problem lies. Don't assume the production code is always wrong - tests can have bugs too.

5. **CRITICAL**: Run **ALL** acceptance criteria tests - **YOU MUST NOT SKIP ANY**

   See [testing-requirements.md](./testing-requirements.md) for complete test execution requirements.

6. **CHROMIUM TEST DETECTION** (for filter file modifications only):

   If your fix involves adding a test to a filter file (e.g., `test/filters/browser_tests.filter`), determine if it's a Chromium test:

   **Detection Logic:**
   - Look at which test file the test is defined in:
     - If the test is in `./src/brave/chromium_src/**` or `./src/**` but NOT in `./src/brave/**`:
       - This is a **Chromium test** (upstream test that Brave inherits from Chromium)
     - If the test is in `./src/brave/**` (excluding chromium_src):
       - This is a **Brave test** (Brave-specific test)

   **For Chromium Tests - Additional Verification:**

   1. **Check if Chromium has already disabled this test:**
      ```bash
      # Search in upstream Chromium source for the test being disabled or marked flaky
      cd [workingDirectory]/..
      # Check for DISABLED_ prefix
      git grep "DISABLED_<TestName>" chromium/src/
      # Check Chromium's test expectations/filter files
      git grep "<TestName>" chromium/src/testing/buildbot/filters/
      ```
      - If found: **Document that Chromium has also disabled this test**
      - If not found: Note that this is a Brave-specific disable of a Chromium test

   2. **Verify Brave modifications aren't causing the failure:**
      - Extract the directory path of the test file (e.g., if test is in `./src/chrome/browser/ui/test.cc`, directory is `chrome/browser/ui/`)
      - Check if there are Brave-specific modifications in `./src/brave/chromium_src/` for files in that directory:
        ```bash
        # Example: If test is in chrome/browser/ui/tabs/test.cc
        find ./src/brave/chromium_src/chrome/browser/ui/ -type f 2>/dev/null | head -20
        ```
      - If Brave modifications exist in related directories, analyze whether they could be causing the test failure
      - Document findings - this helps determine if the test fails due to Brave changes or is an upstream issue

   **Store Detection Results for Commit Message and PR:**
   - Make note of whether this is a **Chromium test** or **Brave test**
   - Note whether **Chromium has also disabled it** (include evidence)
   - Note any **Brave modifications** in related code paths
   - This information will be used in step 7 for commit message and later for PR body

7. Update CLAUDE.md files if you discover reusable patterns (see below)

8. **If ALL tests pass:**
   - Commit ALL changes (must be in `[workingDirectory from prd.json config]`)
   - **IMPORTANT**: If fixing security-sensitive issues (XSS, CSRF, buffer overflows, sanitizer issues, etc.), use discretion in commit messages - see [SECURITY.md](../SECURITY.md#public-security-messaging) for guidance
   - **For Chromium test disables (filter file modifications)**: If you detected this is a Chromium test in step 6, include in commit message:
     - State clearly that it's a **Chromium test** (e.g., "Disable Chromium test..." or "This is an upstream Chromium test...")
     - If Chromium has also disabled it, mention that explicitly (e.g., "Chromium has also disabled this test" or "Already disabled upstream")
     - If Brave modifications might be related, mention what was found (e.g., "Brave modifies chrome/browser/ui/ via chromium_src")
   - Update the PRD at `./brave-core-bot/prd.json`:
     - Set `status: "committed"`
     - Set `lastActivityBy: null` (not yet public)
     - Ensure `branchName` field contains the branch name
   - Append your progress to `./brave-core-bot/progress.txt` (see [progress-reporting.md](./progress-reporting.md))
   - **Continue in same iteration:** Do NOT mark story as checked yet - proceed immediately to push and create PR (see [workflow-committed.md](./workflow-committed.md))

8. **If ANY tests fail:**
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
