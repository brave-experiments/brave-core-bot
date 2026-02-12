---
name: rebase-downstream
description: "Rebase a chain of dependent branches after upstream changes. Auto-detects downstream branches and rebases each in order. Triggers on: rebase downstream, rebase chain, propagate changes downstream."
---

# Rebase Downstream Chain

Rebase a chain of dependent branches after upstream changes have been made. Auto-detects the downstream branch chain, rebases each branch in order, resolves conflicts when possible, and runs preflight checks on each branch.

## Current State

- Branch: !`git branch --show-current`
- Status: !`git status --short`

## Steps

### 1. Detect current branch

Get the current branch name. This is the branch that was just modified and whose changes need to propagate downstream.

```bash
git branch --show-current
```

### 2. Auto-detect downstream chain

Run the `detect_chain.sh` helper script to find all downstream branches:

```bash
bash .claude/skills/rebase-downstream/detect_chain.sh <current-branch>
```

The script outputs one branch per line in rebase order (direct child first, furthest descendant last). If it outputs warnings about forks (multiple children), present them to the user.

### 3. Confirm the chain

Display the detected chain to the user and ask for confirmation before proceeding.

**If no downstream branches are detected**, report this to the user and stop.

**If branches are detected**, show the chain visually:

```
Detected chain: <current-branch> -> <child1> -> <child2> -> ...
```

Ask the user to confirm before rebasing. If the user declines, stop.

### 4. Rebase each branch in order

For each downstream branch (closest to the current branch first):

1. **Checkout the branch**:
   ```bash
   git checkout <downstream-branch>
   ```

2. **Rebase onto its parent**:
   ```bash
   git rebase <parent-branch>
   ```
   The parent is either the original current branch (for the first child) or the previously rebased branch.

3. **Handle conflicts** (if any):
   - Inspect each conflicted file to understand both sides
   - Attempt to resolve the conflict intelligently
   - After resolving, stage the files and continue:
     ```bash
     git add <resolved-files>
     git rebase --continue
     ```
   - If a conflict cannot be resolved, abort and stop:
     ```bash
     git rebase --abort
     ```
     Report which branch and files had unresolvable conflicts, then stop entirely. Do NOT continue to the next branch.

4. **Run full preflight checks** using `/preflight` on this branch. This includes format, gn_check, presubmit, build, and tests. If preflight fails, stop and report. Do NOT continue to the next branch.

5. **Move to the next branch** only after successful rebase and preflight.

### 5. Return to the original branch

After all branches are rebased successfully, checkout the original starting branch:

```bash
git checkout <original-branch>
```

### 6. Report results

Summarize the results:

- **Rebased branches**: List each branch that was successfully rebased
- **Conflicts resolved**: Note any conflicts that were auto-resolved and how
- **Preflight results**: Summary of preflight status for each branch
- **Chain**: Show the full rebased chain

## Important

- **NEVER skip preflight checks** on any branch in the chain
- Stop immediately if a rebase conflict cannot be resolved
- Stop immediately if preflight fails on any branch
- Always return to the original branch at the end (even on failure)
- Do not force-push any branches — the user will decide when to push
