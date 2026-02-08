---
name: add-intermittent-tests
description: "Fetch intermittent test failures from brave/brave-browser GitHub issues with bot/type/test label and add missing ones to the Brave Core PRD. Triggers on: update prd with tests, add intermittent tests, sync test issues, fetch bot/type/test issues."
allowed-tools: Bash(gh issue list:*), Bash(gh issue view:*), Bash(gh pr list:*), Bash(gh pr view:*), Read, Grep, Glob
---

# PRD Brave Core - Add Intermittent Tests

Automatically fetch open test failure issues from the brave/brave-browser repository and add any missing ones to the Brave Core Bot PRD.

---

## The Job

1. Fetch all open issues with the `bot/type/test` label from brave/brave-browser
2. Compare with existing issues in the PRD (`./prd.json`)
3. Add any missing issues as new user stories
4. Provide a recap of what was added

**Important:** This skill is specifically for the Brave Core Bot PRD format.

---

## Step 1: Fetch GitHub Issues

Use the GitHub CLI to fetch issues:

```bash
gh issue list --repo brave/brave-browser --label "bot/type/test" --state open --json number,title,url,labels --limit 100
```

---

## Step 2: Process Issues and Update PRD

Two helper scripts are available in `.claude/skills/add-intermittent-tests/`:

### If PRD doesn't exist yet:

```bash
gh issue list --repo brave/brave-browser --label "bot/type/test" --state open --json number,title,url,labels --limit 100 | \
  .claude/skills/add-intermittent-tests/create_prd_from_issues.py > ./prd.json
```

This creates a new PRD with all the open test issues.

### If PRD already exists:

```bash
gh issue list --repo brave/brave-browser --label "bot/type/test" --state open --json number,title,url,labels --limit 100 | \
  .claude/skills/add-intermittent-tests/update_prd_with_issues.py ./prd.json > /tmp/prd_updated.json && \
  mv /tmp/prd_updated.json ./prd.json
```

This updates the existing PRD with any new issues that aren't already tracked.

### What the scripts do:

- Extract test names from issue titles
- **Determine test location at generation time** by running `git grep` to find if the test is in `src/brave` or `src` (Chromium)
- Generate proper user story structure with:
  - Sequential US-XXX IDs
  - `testLocation` field: 'brave', 'chromium', or 'unknown'
  - Correct test binary based on location (`brave_browser_tests` for Brave, `browser_tests` for Chromium)
  - Standard acceptance criteria including BEST-PRACTICES.md read
  - Correct priority ordering
- Skip issues already in the PRD (update script only)

**Key improvement:** Test location is determined DURING prd.json generation, so acceptance criteria contain the correct test command directly (no conditional `[For Brave tests only]` annotations).

---

## Step 3: Provide Recap

Generate a comprehensive recap showing:

1. **New Issues Added**: List each new user story with:
   - US-XXX number
   - Test name
   - Issue number
   - Test type
   - Status

2. **Existing Issues Status Overview**: Summarize existing stories by status:
   - Merged
   - Pushed
   - Pending
   - Skipped
   - Invalid

3. **Total PRD Statistics**:
   - Total count before and after
   - Count by status

---

## Example Output Format

```markdown
# PRD Update Recap

## Summary
Successfully fetched 15 open issues from the `bot/type/test` label and added 7 missing issues to the PRD.

## New Issues Added (US-016 to US-022)

1. **US-016** - Fix test: BraveSearchTestEnabled.DefaultAPIVisibleKnownHost (issue #52439)
   - Type: browser_test
   - Status: pending
   - Priority: 16

[... more entries ...]

## Existing Issues Status Overview

### Merged (6 issues)
- US-001: SolanaProviderTest.AccountChangedEventAndReload (#50022)
[... more entries ...]

### Pushed (1 issue)
[... entries ...]

### Skipped (7 issues)
[... entries ...]

### Invalid (1 issue)
[... entries ...]

### Pending (7 new issues)
[... entries ...]

## Total PRD Statistics
- Total user stories: 22 (was 15, added 7)
- Merged: 6
- Pushed: 1
- Pending: 7
- Skipped: 7
- Invalid: 1
```

---

## Important Notes

- Always preserve the exact structure of existing user stories
- All new stories should include the BEST-PRACTICES.md read step
- Test type determination is critical for generating correct test commands
- Priority numbers must be sequential and not conflict with existing ones
- All new stories start in "pending" status

---

## Error Handling

- If `gh` CLI is not available, report error and exit
- If `./prd.json` doesn't exist, report error and exit
- If GitHub API rate limit is hit, report error with retry time
- If `jq` is not available, report error and exit
