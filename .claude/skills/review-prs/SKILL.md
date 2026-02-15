---
name: review-prs
description: "Review recent PRs in brave/brave-core for best practices violations. Supports state filter (open/closed/all). Interactive - drafts comments for approval before posting. Triggers on: review prs, review recent prs, /review-prs, check prs for best practices."
argument-hint: "[days|page<N>] [open|closed|all]"
---

# Review PRs for Best Practices

Scan recent open PRs in `brave/brave-core` for violations of documented best practices. Interactive: review diffs, identify violations, draft comments, get user approval before posting.

---

## The Job

When invoked with `/review-prs [days|page<N>] [open|closed|all]`:

1. **Parse arguments** - Two modes:
   - **Days mode** (default): `[days]` sets lookback period (default 5 days). Fetches PRs created within that period.
   - **Page mode**: `page<N>` (e.g., `page1`, `page2`, `page3`) selects a slice of PRs by position. Page 1 = PRs 1-20, page 2 = PRs 21-40, etc. This mirrors the GitHub PR list pagination. No date filtering in page mode.
   - Second argument controls PR state filter: `open` (default), `closed`, or `all`
2. **Fetch non-draft PRs** matching the state filter, using date cutoff (days mode) or positional slice (page mode)
3. **Skip PRs** that are drafts, uplifts, CI runs, l10n updates, or dependency bumps
4. **Skip already-reviewed PRs** whose `headRefOid` matches the locally cached SHA (see Review Cache below)
5. **Review each PR** one at a time using a Task subagent per PR (see Subagent Review Workflow below)
6. **Present findings** from each subagent interactively as they complete
7. **For each violation**, draft a short comment and ask user to approve before posting

---

## Review Cache

A local cache at `.ignore/review-prs-cache.json` tracks which PRs have been reviewed and the HEAD commit SHA at the time of review. This avoids redundant re-reviews across invocations.

**Cache format:**
```json
{
  "42001": "a1b2c3d4e5f6...",
  "42002": "f6e5d4c3b2a1..."
}
```

Keys are PR numbers (as strings), values are the `headRefOid` (HEAD SHA) of the PR at the time it was reviewed.

**Cache logic (applied per PR after basic filtering):**
1. Load the cache from `.ignore/review-prs-cache.json` (create `{}` if it doesn't exist)
2. Compare the PR's current `headRefOid` against the cached SHA for that PR number
3. **Skip** the PR if the cached SHA matches the current `headRefOid` — it was already reviewed at this exact state
4. **Re-review** if the PR is not in the cache, or the cached SHA differs (author pushed new commits or force-pushed)
5. After a PR is reviewed (subagent returns results), **update the cache** with the PR's current `headRefOid` regardless of whether violations were found
6. Write the updated cache back to `.ignore/review-prs-cache.json`

**Important:** Update the cache entry even when `NO_VIOLATIONS` is returned — the point is to track that we've looked at this SHA, not whether we found issues.

---

## Fetching and Filtering PRs

**Days mode** (default):
```bash
# Use the parsed state argument (open, closed, or all). Default: open
# Include headRefOid for cache comparison
gh pr list --repo brave/brave-core --state <STATE> --json number,title,createdAt,author,isDraft,headRefOid --limit 200 > /tmp/brave_prs.json
```

**Page mode** (`page<N>`):
```bash
# Fetch exactly 20 PRs for the requested page. Page 1 = first 20, page 2 = next 20, etc.
# gh pr list doesn't support offset, so fetch enough PRs to cover the page and slice in jq.
LIMIT=$((PAGE * 20))
gh pr list --repo brave/brave-core --state <STATE> --json number,title,createdAt,author,isDraft,headRefOid --limit $LIMIT > /tmp/brave_prs_all.json
# Slice to just the requested page (0-indexed: page 1 = items 0-19, page 2 = items 20-39)
START=$(((PAGE - 1) * 20))
jq ".[$START:$START+20]" /tmp/brave_prs_all.json > /tmp/brave_prs.json
```

**Load the review cache:**
```bash
# Ensure .ignore directory exists
mkdir -p .ignore
# Load cache or create empty one
if [ -f .ignore/review-prs-cache.json ]; then
  CACHE=$(cat .ignore/review-prs-cache.json)
else
  CACHE='{}'
fi
```

**Skip if:**
- `isDraft` is true
- Created before lookback cutoff (days mode only — page mode has no date filter)
- Title starts with `CI run for` or `Backport` or `Update l10n`
- Title contains `uplift to`
- Title contains `Just to test CI` or similar CI test patterns
- Author is the reviewing user's own GitHub login (don't review own PRs)
- **PR's `headRefOid` matches the cached SHA** for that PR number (already reviewed at this state)

When a PR is skipped due to cache hit, briefly note it: `Skipping PR #NNNNN (already reviewed at this SHA)`

**Note:** The local cache replaces the previous GitHub API-based "prior review" check. There is no longer a need to query `/pulls/{number}/reviews` or `/issues/{number}/timeline` to determine if a re-review is needed.

---

## Progress Reporting

After filtering is complete, print a summary so the user knows what to expect:

```
Found N PRs to review (M skipped: X drafts/filtered, Y cached)
```

Then before each PR review, print a progress line with a clickable link:

```
[1/N] Reviewing PR #NNNNN: <title> — https://github.com/brave/brave-core/pull/NNNNN
```

This lets the user see how far along the process is, how many remain, and click through to the PR.

---

## Subagent Review Workflow

**IMPORTANT:** The main context does NOT load best practices docs or PR diffs. Each PR is reviewed in its own Task subagent to avoid context compaction.

For each PR, launch a **Task subagent** (subagent_type: "general-purpose") with a prompt that includes:

1. **The PR number and repo** (`brave/brave-core`)
2. **Instructions to read best practices docs** — the subagent reads these itself:
   - `./brave-core-bot/BEST-PRACTICES.md` (index)
   - `./brave-core-bot/docs/best-practices/architecture.md`
   - `./brave-core-bot/docs/best-practices/coding-standards.md`
   - `./brave-core-bot/docs/best-practices/chromium-src-overrides.md`
   - `./brave-core-bot/docs/best-practices/build-system.md`
   - `./brave-core-bot/docs/best-practices/frontend.md`
   - `./brave-core-bot/docs/best-practices/testing-async.md`
   - `./brave-core-bot/docs/best-practices/testing-javascript.md`
   - `./brave-core-bot/docs/best-practices/testing-navigation.md`
   - `./brave-core-bot/docs/best-practices/testing-isolation.md`
3. **Instructions to fetch the diff** via `gh pr diff --repo brave/brave-core {number}`
4. **The review rules** (copied into the subagent prompt):
   - Only flag violations in ADDED lines (+ lines), not existing code
   - Also flag bugs introduced by the change (e.g., missing string separators, duplicate DEPS entries, code inside wrong `#if` guard)
   - Security-sensitive areas (wallet, crypto, sync, credentials) deserve extra scrutiny — type mismatches, truncation, and correctness issues should use stronger language
   - Do NOT flag: existing code the PR isn't changing, template functions defined in headers, simple inline getters in headers, style preferences not in the documented best practices
   - Comment style: short (1-3 sentences), targeted, acknowledge context. Use "nit:" only for genuinely minor/stylistic issues. Substantive issues (test reliability, correctness, banned APIs) should be direct without "nit:" prefix
5. **Required output format** — the subagent MUST return ONLY a compact structured result:
   ```
   PR #<number>: <title>
   VIOLATIONS:
   - file: <path>, line: <line_number>, issue: <brief description>, draft_comment: <1-3 sentence comment to post>
   - ...
   NO_VIOLATIONS (if none found)
   ```

**Optimization:** The subagent can check which file types are in the diff first. If no test files are changed, it can skip the testing docs (`testing-async.md`, `testing-javascript.md`, `testing-navigation.md`, `testing-isolation.md`). If no `chromium_src/` files, skip `chromium-src-overrides.md`. If no `BUILD.gn`/`DEPS` files, skip `build-system.md`.

Process PRs **one at a time** (sequentially). After each subagent returns:
1. **Update the cache** — write the PR's `headRefOid` to the cache file immediately (regardless of violations found)
2. If violations were found, present them to the user for interactive approval before moving to the next PR
3. If no violations, briefly note that and move on

---

## Reviewing Diffs (Subagent Internal)

The subagent fetches the diff with `gh pr diff --repo brave/brave-core {number}`.

**Only flag violations in ADDED lines (+ lines), not existing code.**

Also flag bugs introduced by the change (e.g., missing string separators, duplicate DEPS entries, code inside wrong `#if` guard).

**Security-sensitive areas** (wallet, crypto, sync, credentials) deserve extra scrutiny. Type mismatches, truncation, and correctness issues in these areas should use stronger language — these aren't nits, they're potential security concerns.

---

## What NOT to Flag

- Existing code the PR isn't changing
- Template functions defined in headers (required by C++)
- Simple inline getters in headers
- Style preferences not in the documented best practices
- Draft PRs (skip entirely)

---

## Comment Style

- **Short and succinct** - 1-3 sentences max
- **Targeted** - reference specific files and code
- **Acknowledge context** - if upstream does the same thing, say so
- **No lecturing** - state the issue briefly
- **Match tone to severity:**
  - **Genuine nits** (style, naming, minor cleanup): use "nit:" prefix, "worth considering", "not blocking either way"
  - **Substantive issues** (test reliability, correctness, banned APIs, potential bugs): be direct and clear about why it needs to change. Do NOT use "nit:" for these — a `RunUntilIdle()` violation or a banned API usage is not a nit, it's a real problem.

---

## Interactive Posting

For each violation, present the draft and ask:

> **PR #12345** - [violation description]
> Draft: `[short comment]`
> Post this comment?

Use "nit:" prefix only for genuinely minor/stylistic issues, not for substantive concerns.

Only post after explicit user approval via:
```bash
gh pr review --repo brave/brave-core {number} --comment --body "Review via brave-core-bot: comment text"
```

**All posted comments MUST be prefixed with "Review via brave-core-bot: "** before the actual comment text.

---

## Closed/Merged PR Workflow

When reviewing closed or merged PRs and a violation is found:

1. **Present the finding** to the user as usual (draft comment + ask for approval)
2. **If approved**, post a comment on the closed PR noting the issue (prefixed with "Review via brave-core-bot: ")
3. **Create a follow-up issue** in `brave/brave-core` to track the fix:
   ```bash
   gh issue create --repo brave/brave-core --title "Fix: <brief description of violation>" --body "$(cat <<'EOF'
   Found during post-merge review of #<PR_NUMBER>.

   <description of the violation and what needs to change>

   See: https://github.com/brave/brave-core/pull/<PR_NUMBER>
   EOF
   )"
   ```
4. **Reference the new issue** back in the PR comment so the PR author can find it:
   ```bash
   gh pr comment --repo brave/brave-core <PR_NUMBER> --body "Created follow-up issue #<ISSUE_NUMBER> to track this."
   ```

This ensures violations on already-merged code don't get lost — they get tracked as actionable issues.
