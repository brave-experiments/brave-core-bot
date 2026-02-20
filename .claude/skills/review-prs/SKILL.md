---
name: review-prs
description: "Review PRs in brave/brave-core for best practices violations. Supports single PR (#12345), state filter (open/closed/all). Interactive - drafts comments for approval before posting. Triggers on: review prs, review recent prs, /review-prs, check prs for best practices."
argument-hint: "[days|page<N>|#<PR>] [open|closed|all]"
allowed-tools: Bash(gh pr diff:*)
---

# Review PRs for Best Practices

Scan recent open PRs in `brave/brave-core` for violations of documented best practices. Interactive: review diffs, identify violations, draft comments, get user approval before posting.

---

## The Job

When invoked with `/review-prs [days|page<N>|#<PR>] [open|closed|all]`:

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
3. **Review each PR** one at a time using per-category parallel subagents (see Per-Category Review Workflow below)
4. **Aggregate and present findings** from all category subagents interactively
5. **For each violation**, draft a short comment and ask user to approve before posting

---

## Per-Category Review Workflow

**IMPORTANT:** The main context does NOT load best practices docs or PR diffs. Each PR is reviewed by multiple focused subagents — one per best-practice category — running in parallel. This ensures every rule is systematically checked rather than relying on a single subagent to hold 150+ rules in mind.

### Step 1: Classify Changed Files

Before launching subagents, fetch the file list to determine which categories apply:

```bash
gh pr diff --repo brave/brave-core {number} --name-only
```

Classify the changed files:
- **has_cpp_files**: `.cc`, `.h`, `.mm` files
- **has_test_files**: `*_test.cc`, `*_browsertest.cc`, `*_unittest.cc`, `*.test.ts`, `*.test.tsx`
- **has_chromium_src**: `chromium_src/` paths
- **has_build_files**: `BUILD.gn`, `DEPS`, `*.gni`
- **has_frontend_files**: `.ts`, `.tsx`, `.html`, `.css`

### Step 2: Launch Category Subagents in Parallel

Launch one **Task subagent** (subagent_type: "general-purpose") per applicable category. **Use multiple Task tool calls in a single message** so they run in parallel.

| Category | Doc(s) to read | Condition |
|----------|---------------|-----------|
| **coding-standards** | `coding-standards.md` | has_cpp_files |
| **architecture** | `architecture.md`, `documentation.md` | Always |
| **build-system** | `build-system.md` | has_build_files |
| **testing** | `testing-async.md`, `testing-javascript.md`, `testing-navigation.md`, `testing-isolation.md` | has_test_files |
| **chromium-src** | `chromium-src-overrides.md` | has_chromium_src |
| **frontend** | `frontend.md` | has_frontend_files |

All doc paths are under `./brave-core-bot/docs/best-practices/`.

**Always launch at minimum:** architecture (applies to all PRs — layering, dependency injection, factory patterns affect every change).

### Step 3: Subagent Prompt

Each subagent prompt MUST include:

1. **The PR number and repo** (`brave/brave-core`)
2. **Which best practice doc(s) to read** — only the ones for this category (paths above)
3. **Instructions to fetch the diff** via `gh pr diff --repo brave/brave-core {number}`
4. **The review rules** (copied into the subagent prompt):
   - Only flag violations in ADDED lines (+ lines), not existing code
   - Also flag bugs introduced by the change (e.g., missing string separators, duplicate DEPS entries, code inside wrong `#if` guard)
   - Security-sensitive areas (wallet, crypto, sync, credentials) deserve extra scrutiny — type mismatches, truncation, and correctness issues should use stronger language
   - Do NOT flag: existing code the PR isn't changing, template functions defined in headers, simple inline getters in headers, style preferences not in the documented best practices
   - Comment style: short (1-3 sentences), targeted, acknowledge context. Use "nit:" only for genuinely minor/stylistic issues. Substantive issues (test reliability, correctness, banned APIs) should be direct without "nit:" prefix
5. **Best practice link requirement** — for each violation, the subagent MUST include a direct link to the specific rule heading in the best practices doc. The link format is:
   ```
   https://github.com/brave-experiments/brave-core-bot/tree/master/docs/best-practices/<doc>.md#<heading-anchor>
   ```
   Where `<heading-anchor>` is the `##` heading converted to a GitHub anchor (lowercase, spaces to hyphens, special characters removed). For example, `## Don't Use rapidjson` becomes `#dont-use-rapidjson`.
6. **The systematic audit requirement** (below)
7. **Required output format** (below)

### Step 4: Systematic Audit Requirement

**CRITICAL — this is what prevents the subagent from stopping after finding a few violations.**

The subagent MUST work through its best practice doc(s) **heading by heading**, checking every `##` rule against the diff. It must output an audit trail listing EVERY `##` heading with a verdict:

```
AUDIT:
PASS: ✅ Always Include What You Use (IWYU)
PASS: ✅ Use Positive Form for Booleans and Methods
N/A: ✅ Consistent Naming Across Layers
FAIL: ❌ Don't Use rapidjson
PASS: ✅ Use CHECK for Impossible Conditions
... (one entry per ## heading in the doc)
```

Verdicts:
- **PASS**: Checked the diff — no violation found
- **N/A**: Rule doesn't apply to the types of changes in this diff
- **FAIL**: Violation found — must have a corresponding entry in VIOLATIONS

This forces the model to explicitly consider every rule rather than satisficing after a few findings.

### Step 5: Required Output Format

Each subagent MUST return this structured format:

```
CATEGORY: <category name>
PR #<number>: <title>

AUDIT:
PASS: <rule heading>
N/A: <rule heading>
FAIL: <rule heading>
... (one line per ## heading in the doc(s))

VIOLATIONS:
- file: <path>, line: <line_number>, rule: "<rule heading>", rule_link: <full GitHub URL to the rule heading>, issue: <brief description>, draft_comment: <1-3 sentence comment to post>
- ...
NO_VIOLATIONS (if none found)
```

### Step 6: Aggregate and Process Results

Process PRs **one at a time** (sequentially). After ALL category subagents return for a PR:

1. **Update the cache immediately** — run the cache update script right now, before doing anything else (regardless of violations found):
   ```bash
   python3 .claude/skills/review-prs/update-cache.py <PR_NUMBER> <HEAD_REF_OID>
   ```
   **This step is mandatory after every single PR review.**
2. **Aggregate violations** from all category subagents into a single list for the PR
3. If violations were found, present them to the user for interactive approval before moving to the next PR
4. If no violations across all categories, briefly note that and move on

**PR Link Format:** When displaying PR numbers to the user, always use a proper markdown link: `[PR #<number>](https://github.com/brave/brave-core/pull/<number>) - <title>`. Never use bare `#<number>` references — they don't produce clickable links to the correct PR.

---

## Comment Style

- **Short and succinct** - 1-3 sentences max
- **Targeted** - reference specific files and code
- **Acknowledge context** - if upstream does the same thing, say so
- **No lecturing** - state the issue briefly
- **Link to the rule** - when the violation is an explicit best practice rule, append a link to the specific rule at the end of the comment. Example: `[best practice](https://github.com/brave-experiments/brave-core-bot/tree/master/docs/best-practices/coding-standards.md#dont-use-rapidjson)`. Only include the link for explicit documented rule violations, not for general bug/correctness observations.
- **Match tone to severity:**
  - **Genuine nits** (style, naming, minor cleanup): use "nit:" prefix, "worth considering", "not blocking either way"
  - **Substantive issues** (test reliability, correctness, banned APIs, potential bugs): be direct and clear about why it needs to change. Do NOT use "nit:" for these — a `RunUntilIdle()` violation or a banned API usage is not a nit, it's a real problem.

---

## Interactive Posting

For each violation, present the draft and ask:

> **[PR #12345](https://github.com/brave/brave-core/pull/12345)** - `file:line` - [violation description]
> Draft: `[short comment]`
> Post this comment?

Use "nit:" prefix only for genuinely minor/stylistic issues, not for substantive concerns.

**The "Review via brave-core-bot" attribution MUST appear exactly once per review** — on the top-level review body, NOT on each inline comment. Individual inline comments should contain only the comment text itself.

### Posting as Inline Code Comments

After presenting all violations for a PR, collect the approved ones and post them as a **single review with inline comments** using the GitHub API. This places comments directly on the relevant code lines instead of as a general review comment.

```bash
gh api repos/brave/brave-core/pulls/{number}/reviews \
  --method POST \
  --input - <<'EOF'
{
  "event": "COMMENT",
  "body": "Review via brave-core-bot",
  "comments": [
    {
      "path": "path/to/file.cc",
      "line": 42,
      "side": "RIGHT",
      "body": "comment text"
    },
    {
      "path": "path/to/other_file.cc",
      "line": 15,
      "side": "RIGHT",
      "body": "another comment"
    }
  ]
}
EOF
```

**Key details:**
- The `"body": "Review via brave-core-bot"` at the top level provides the attribution once for the entire review
- Individual comment bodies should NOT include the "Review via brave-core-bot: " prefix
- `side: "RIGHT"` targets the new version of the file (added lines)
- `line` is the line number in the new file, which matches what the subagent reports from `+` lines in the diff
- All approved violations for a single PR are batched into one review (one notification to the author)
- If the API call fails (e.g., a line is outside the diff range), retry by splitting: post the valid inline comments and fall back to a general review comment for any that failed. **Only the fallback general comment needs the prefix** since it's standalone:
  ```bash
  gh pr review --repo brave/brave-core {number} --comment --body "Review via brave-core-bot: [file:line] comment text"
  ```

---

## Closed/Merged PR Workflow

When reviewing closed or merged PRs and a violation is found:

1. **Present the finding** to the user as usual (draft comment + ask for approval)
2. **If approved**, try to post inline review comments using the same `gh api` approach as open PRs. If the inline API fails (some merged PRs may not support it), fall back to a general comment:
   ```bash
   gh pr comment --repo brave/brave-core {number} --body "Review via brave-core-bot: [file:line] comment text"
   ```
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
