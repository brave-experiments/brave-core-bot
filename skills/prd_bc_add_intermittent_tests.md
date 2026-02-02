---
name: prd_bc_add_intermittent_tests
description: "Fetch intermittent test failures from brave/brave-browser GitHub issues with bot/type/test label and add missing ones to the Brave Core PRD. Triggers on: update prd with tests, add intermittent tests, sync test issues, fetch bot/type/test issues."
---

# PRD Brave Core - Add Intermittent Tests

Automatically fetch open test failure issues from the brave/brave-browser repository and add any missing ones to the Brave Core Bot PRD.

---

## The Job

1. Fetch all open issues with the `bot/type/test` label from brave/brave-browser
2. Compare with existing issues in the PRD (`./brave-core-bot/prd.json`)
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

## Step 2: Extract Existing Issues from PRD

Read the PRD and extract all existing issue numbers from user story descriptions:

```python
import json

with open('./brave-core-bot/prd.json') as f:
    prd = json.load(f)

existing_issues = set()
for story in prd['userStories']:
    desc = story['description']
    if 'issue #' in desc:
        issue_num = desc.split('issue #')[1].split(')')[0]
        existing_issues.add(issue_num)
```

---

## Step 3: Identify Missing Issues

Compare the GitHub issues with the existing PRD issues to find which ones are missing.

---

## Step 4: Add Missing Issues to PRD

For each missing issue, create a new user story with:

- **id**: Next available US-XXX number
- **title**: "Fix test: [TestName]"
- **description**: "As a developer, I need to fix the intermittent failure in [TestName] (issue #[number])."
- **testType**: Determine from test name:
  - Contains "BrowserTest" → "browser_test"
  - Contains "AlternateTestParams" or "PartitionAlloc" → "unit_test"
  - Default → "browser_test"
- **testFilter**: The full test name from the issue title
- **acceptanceCriteria**: Follow the standard pattern:
  ```json
  [
    "Read ./brave-core-bot/BEST-PRACTICES.md for async testing patterns and common pitfalls",
    "Fetch issue #[number] details from brave/brave-browser GitHub API",
    "Analyze stack trace and identify root cause",
    "Implement fix for the intermittent failure",
    "Run npm run build from src/brave (must pass)",
    "Run npm run format from src/brave (must pass)",
    "Run npm run presubmit from src/brave (must pass)",
    "Run npm run gn_check from src/brave (must pass)",
    "Run npm run test -- brave_browser_tests --gtest_filter=[TestName] (must pass - run 5 times to verify consistency)"
  ]
  ```
  Note: Use `brave_unit_tests` instead of `brave_browser_tests` for unit tests.
- **priority**: Next sequential number after highest existing priority
- **status**: "pending"
- **prNumber**: null
- **lastActivityBy**: null
- **branchName**: null
- **prUrl**: null

---

## Step 5: Update PRD File

Use `jq` to append the new stories to the userStories array:

```bash
jq --slurpfile new_stories /tmp/new_stories.json '.userStories += $new_stories[0]' ./brave-core-bot/prd.json > /tmp/prd_updated.json && mv /tmp/prd_updated.json ./brave-core-bot/prd.json
```

---

## Step 6: Provide Recap

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
- If `./brave-core-bot/prd.json` doesn't exist, report error and exit
- If GitHub API rate limit is hit, report error with retry time
- If `jq` is not available, report error and exit
