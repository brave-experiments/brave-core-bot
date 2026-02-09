---
name: review-prs
description: "Review recent open PRs in brave/brave-core for best practices violations. Interactive - drafts comments for approval before posting. Triggers on: review prs, review recent prs, /review-prs, check prs for best practices."
argument-hint: "[days]"
---

# Review PRs for Best Practices

Scan recent open PRs in `brave/brave-core` for violations of documented best practices. Interactive: review diffs, identify violations, draft comments, get user approval before posting.

---

## The Job

When invoked with `/review-prs [days]`:

1. **Parse arguments** - default 5 days lookback, or use provided `[days]`
2. **Fetch open non-draft PRs** created within the lookback period
3. **Skip PRs** that are drafts, uplifts, CI runs, l10n updates, or dependency bumps
4. **Skip already-reviewed PRs** where the configured git user posted a review and no new pushes since
5. **Read all best practices docs** (see list below)
6. **Review each PR diff** against best practices (only ADDED lines)
7. **Present findings** in a summary table
8. **For each violation**, draft a short comment and ask user to approve before posting

---

## Fetching and Filtering PRs

```bash
gh pr list --repo brave/brave-core --state open --json number,title,createdAt,author,isDraft --limit 200 > /tmp/brave_prs.json
```

**Skip if:**
- `isDraft` is true
- Created before lookback cutoff
- Title starts with `CI run for` or `Backport` or `Update l10n`
- Title contains `uplift to`
- Title contains `Just to test CI` or similar CI test patterns
- Author is the reviewing user's own GitHub login (don't review own PRs)

**Check for prior reviews:**
```bash
GIT_USER=$(git config user.name)
# Get last review by this user
gh api repos/brave/brave-core/pulls/{number}/reviews --jq '[.[] | select(.user.login == "USERNAME")] | sort_by(.submitted_at) | last | .submitted_at'
# Get last push time from timeline (more reliable than events API which returns 404)
gh api repos/brave/brave-core/issues/{number}/timeline --paginate --jq '[.[] | select(.event == "committed")] | sort_by(.committer.date) | last | .committer.date'
```

Skip if user already reviewed AND no commits after that review.

**Note:** The `/pulls/{number}/events` endpoint returns 404 for some PRs. Use the `/issues/{number}/timeline` endpoint instead, which reliably includes commit events.

---

## Best Practices Docs to Read

- `./brave-core-bot/BEST-PRACTICES.md` (index)
- `./brave-core-bot/docs/best-practices/architecture.md`
- `./brave-core-bot/docs/best-practices/coding-standards.md`
- `./brave-core-bot/docs/best-practices/chromium-src-overrides.md`
- `./brave-core-bot/docs/best-practices/build-system.md`
- `./brave-core-bot/docs/best-practices/testing-async.md`
- `./brave-core-bot/docs/best-practices/testing-javascript.md`
- `./brave-core-bot/docs/best-practices/testing-navigation.md`
- `./brave-core-bot/docs/best-practices/testing-isolation.md`

These are the source of truth. Only flag violations of rules documented in these files.

---

## Reviewing Diffs

Fetch each diff with `gh pr diff --repo brave/brave-core {number}`.

Use Task tool to launch parallel review agents in batches of ~8 PRs for efficiency. Pass the best practices rules to each agent.

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
gh pr review --repo brave/brave-core {number} --comment --body "comment text"
```
