---
name: uplift
description: "Create an uplift PR that cherry-picks intermittent test fixes and crash fixes from closed PRs into the beta branch. Triggers on: /uplift, create uplift, uplift PRs."
argument-hint: [github-username]
disable-model-invocation: true
allowed-tools: Bash, Read, WebFetch, Grep, Glob
---

# Uplift PR Creator

Create an uplift pull request that cherry-picks intermittent test fixes and crash fixes from a contributor's recently closed/merged PRs into the current beta branch.

## Inputs

- **GitHub username**: `$ARGUMENTS` (the author whose closed PRs to review)

---

## Step 1: Gather Information

Run these in parallel:

1. **Fetch closed PRs**: Use `gh pr list --repo brave/brave-core --author $ARGUMENTS --state closed --limit 50 --json number,title,mergedAt,mergeCommit,labels,body,url --jq 'sort_by(.mergedAt)'` to get all recently closed PRs sorted chronologically. The `mergedAt` field is a GitHub API property — if it is `null`, the PR was closed without being merged and should be skipped.

2. **Determine the beta branch**: Fetch the content at `https://github.com/brave/brave-browser/wiki/Brave-Release-Schedule` and find the "Current channel information" table. Look for the **Beta** row to get the branch name (e.g., `1.88.x`). This branch is:
   - The base branch to create the uplift PR against
   - The branch to cherry-pick commits into

---

## Step 2: Classify PRs

Review each **merged** PR (skip any where `mergedAt` is null) and classify it as either **include** or **exclude** for the uplift:

**INCLUDE** if the PR is any of:
- Intermittent/flaky test fix (titles often contain "Fix flaky", "Fix test:", "Fix intermittent", "Disable flaky")
- Crash fix (titles mention "crash", "null dereference", "EXCEPTION_ACCESS_VIOLATION", etc.)
- Test filter updates (disabling broken upstream tests, updating stale filter entries)

**EXCLUDE** if the PR is:
- A feature addition (not a fix)
- A refactor unrelated to test stability or crashes
- Already has the `uplift/beta` label (check the `labels` array in the PR JSON)
- Not merged (`mergedAt` is null)

---

## Step 3: Cherry-Pick in Chronological Order

1. Fetch the beta branch: `git fetch upstream <beta-branch>`
2. Create a new branch from the beta branch: `git checkout -b uplift_<username>_<beta-branch> upstream/<beta-branch>`
3. Cherry-pick each included PR's merge commit in chronological order (earliest first):
   ```bash
   git cherry-pick <merge_commit_sha>
   ```
4. If a cherry-pick has conflicts, try to resolve them. If unresolvable, skip that PR and note it in the summary.

---

## Step 4: Create the Uplift PR

### Title Format

```
Uplift intermittent test fixes and crash fixes to <beta-branch>
```

### Body Format

Only list the PRs being uplifted. Do NOT mention excluded PRs in the PR body.

Use a HEREDOC for correct formatting:

```bash
gh pr create --repo brave/brave-core --base <beta-branch> --title "<title>" --body "$(cat <<'EOF'
Uplift of #XXXX, #YYYY, #ZZZZ

## Included PRs
- #XXXX - <PR title>
- #YYYY - <PR title>
...

Pre-approval checklist:
- [ ] You have tested your change on Nightly.
- [ ] This contains text which needs to be translated.
    - [ ] There are more than 7 days before the release.
    - [ ] I've notified folks in #l10n on Slack that translations are needed.
- [ ] The PR milestones match the branch they are landing to.


Pre-merge checklist:
- [ ] You have checked CI and the builds, lint, and tests all pass or are not related to your PR.

Post-merge checklist:
- [ ] The associated issue milestone is set to the smallest version that the changes is landed on.
EOF
)"
```

### Labels

- If **all** included PRs are test filter-only changes (i.e., only modifying files in `test/filters/`), add the `CI/skip` label to the uplift PR.
- Do NOT add `CI/skip` if any included PR contains code changes beyond filter files.

### Push and Create

```bash
git push -u origin uplift_<username>_<beta-branch>
```

---

## Step 5: Label the Base PRs

After the uplift PR is created, add the `uplift/beta` label to **each base PR** that was included in the uplift:

```bash
gh pr edit <PR_NUMBER> --repo brave/brave-core --add-label "uplift/beta"
```

Do this for every PR that was successfully cherry-picked and included.

---

## Step 6: Summary

After creating the PR, output a clear summary to the user:

### Uplifted:
List each included PR with its number, title, and merge commit SHA.

### Not Uplifted:
List each excluded PR with its number, title, and the reason it was excluded (e.g., "not merged", "already uplifted (has uplift/beta label)", "not a test fix or crash fix", "cherry-pick conflict").

### PR Link:
Provide the URL of the newly created uplift PR.
