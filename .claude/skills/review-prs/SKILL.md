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

1. **Fetch and filter PRs** by running the fetch script (pass through all arguments):
   ```bash
   python3 .claude/skills/review-prs/fetch-prs.py [args...]
   ```
   The script handles all fetching, filtering (drafts, uplifts, CI runs, l10n, date cutoff), and cache checking. It outputs JSON:
   ```json
   {
     "prs": [{"number": 42001, "title": "...", "headRefOid": "abc123", "author": "user"}],
     "summary": {"total_fetched": 50, "to_review": 5, "skipped_filtered": 30, "skipped_cached": 15}
   }
   ```
2. **Print progress summary** from the summary stats:
   ```
   Found N PRs to review (M skipped: X drafts/filtered, Y cached)
   ```
3. **Review each PR** one at a time using a Task subagent per PR (see Subagent Review Workflow below)
4. **Present findings** from each subagent interactively
5. **For each violation**, draft a short comment and ask user to approve before posting

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
1. **Update the cache immediately** — run the cache update script right now, before doing anything else (regardless of violations found):
   ```bash
   python3 .claude/skills/review-prs/update-cache.py <PR_NUMBER> <HEAD_REF_OID>
   ```
   **This step is mandatory after every single PR review.**
2. If violations were found, present them to the user for interactive approval before moving to the next PR
3. If no violations, briefly note that and move on

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
