# Progress Reporting

APPEND to ./brave-core-bot/progress.txt (never replace, always append):

## For status: "pending" → "committed"

```
## [Date/Time] - [Story ID] - Status: pending → committed
- What was implemented
- Files changed
- Branch created: [branch-name]
- [If filter file modification] **Test Type**: [Chromium test / Brave test]
- [If Chromium test] **Chromium Status**: [Chromium has also disabled this test / Not disabled by Chromium / Upstream bug: crbug.com/XXXXX]
- [If Chromium test] **Brave Modifications**: [No Brave modifications in this area / Brave modifies [path] via chromium_src]
- **Test Results** (REQUIRED):
  - [List all acceptance criteria tests and their results]
  - All tests MUST pass before transitioning to "committed"
- **Learnings for future iterations:**
  - Patterns discovered
  - Gotchas encountered
  - Useful context
---
```

## For status: "committed" → "pushed"

```
## [Date/Time] - [Story ID] - Status: committed → pushed
- Pushed branch: [branch-name]
- Created PR: #[pr-number]
- PR URL: [url]
---
```

## For status: "pushed" (handling reviews)

```
## [Date/Time] - [Story ID] - Status: pushed (review iteration)
- Review comments addressed:
  - [Summary of feedback from Brave org members]
  - [Changes made]
- **Test Results** (REQUIRED):
  - [Re-ran all acceptance criteria tests]
  - All tests MUST pass before pushing review changes
- Commit strategy: [Amended last commit / Created new commit]
- Posted reply to PR #[pr-number] explaining fixes
- Pushed changes to PR #[pr-number]
---
```

## For status: "pushed" (status check - waiting for reviewer)

```
## [Date/Time] - [Story ID] - Status: pushed (checked - waiting for reviewer)
- Checked PR #[pr-number]
- Review Decision: [APPROVED/REVIEW_REQUIRED/etc]
- CI Status: [summary of checks]
- Latest activity: Bot went last (no new comments from reviewers)
- Time waiting: [X hours/days since last push]
- Reviewer reminder: [Sent ping to @reviewer1, @reviewer2 / Not needed yet (< 24hrs) / Already pinged recently / No reviewers assigned]
- Action: Waiting for reviewer feedback - ending iteration
---
```

## For status: "pushed" → "merged"

```
## [Date/Time] - [Story ID] - Status: pushed → merged
- PR #[pr-number] merged successfully
- Final approvals: [list of approvers]
- Post-merge monitoring initialized: First check in 1 day
---
```

## For status: "merged" (post-merge check)

```
## [Date/Time] - [Story ID] - Status: merged (post-merge check #[N])
- Checked PR #[pr-number] for post-merge follow-up comments
- Comments found since merge: [count]
- New comments from Brave org members: [list usernames or "none"]
- Follow-up work needed: [Yes/No]
- [If yes: Created follow-up work:
  - Story US-XXX: "[title]" (GitHub issue #YYYY - [issue URL])
    - Replied to @[username] on PR with issue link
  - Story US-ZZZ: "[title]" (GitHub issue #WWWW - [issue URL])
    - Replied to @[username] on PR with issue link
]
- [If no: No follow-up action required]
- Next check scheduled: [timestamp] ([interval] from now)
- [Or if final: "Post-merge monitoring complete - reached final state"]
---
```

## For status: [any] → "skipped"

```
## [Date/Time] - [Story ID] - Status: [previous-status] → skipped
- **Reason for skipping:** [Brief explanation - e.g., "blocked by missing dependency", "intentionally deferred"]
- **Root Cause Analysis:** [What you discovered about why this story is being skipped]
- **Resolution:** [What's blocking it, or why it's deferred]
- **GitHub Notification:** [Posted comment on issue #XXXX / No issue referenced / Comment already exists]
- **Note:** [Any additional context for future reference]
---
```

## For status: [any] → "invalid"

```
## [Date/Time] - [Story ID] - Status: [previous-status] → invalid
- **Reason for invalid:** [Brief explanation - e.g., "duplicate of #XXXX", "already fixed by PR #YYYY", "not a bug - working as intended", "PR was closed without merging"]
- **Analysis:** [What you discovered about why this story is invalid]
- **GitHub Notification:** [Posted comment on issue #XXXX / No issue referenced / Comment already exists]
- **Note:** [Any additional context for future reference]
---
```
