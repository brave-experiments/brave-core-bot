---
name: commit
description: "Commit changes without Co-Authored-By attribution. Creates logical, atomic commits. Use when the user wants to commit changes without Claude attribution. Triggers on: commit without attribution, commit no attribution, /commit."
---

# Commit Without Attribution

Create git commits without the Co-Authored-By attribution line. Each commit should be a logical unit of work.

---

## The Job

When the user invokes this skill:
1. Run `git status` to see what files are modified
2. Run `git diff` to review the changes
3. Identify logical units of work (may require multiple commits)
4. For each logical unit:
   - Draft an appropriate commit message
   - Stage only the files relevant to that unit with `git add`
   - Commit with the message **WITHOUT** the Co-Authored-By line
   - **DO NOT** use any flags like `--no-verify`, `--no-gpg-sign`, etc.
5. Run `git status` to verify all commits succeeded
6. If the user passed `push` as an argument (e.g., `/commit push`), run `git push` after all commits succeed

---

## Multiple Commits

If the changes span multiple logical units, create separate commits:
- **Good**: One commit for refactoring, another for the new feature
- **Good**: One commit per file if they serve different purposes
- **Bad**: All changes lumped into one commit when they're unrelated

Each commit should be atomic and self-contained.

---

## Fixup Commits

For unpushed commits, you can use fixup commits and rebase to keep history clean:

```bash
# Make a fix to an earlier commit
git add src/component.ts
git commit --fixup=abc1234

# Later, squash fixups into their parent commits
git rebase -i --autosquash HEAD~5
```

Only use fixup commits when:
- The original commit has **NOT** been pushed to remote
- The fix logically belongs to the original commit
- It makes sense to keep them as a single logical unit

---

## Important

- **DO NOT** include the `Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>` line
- **DO NOT** use flags like `--no-verify` or `--no-gpg-sign` unless using `--fixup`
- Follow normal commit message conventions (concise, descriptive, imperative mood)
- Only commit files that are relevant to the logical unit of work
- Never commit sensitive files (.env, credentials, etc.)
- Each commit should stand alone and make sense independently

---

## Example: Single Logical Unit

```bash
git add src/component.ts src/component.test.ts
git commit -m "Fix validation logic in user form"
git status
```

---

## Example: Multiple Logical Units

```bash
# First logical unit: refactoring
git add src/utils/parser.ts
git commit -m "Extract parsing logic to separate utility"

# Second logical unit: new feature using the refactored code
git add src/component.ts src/component.test.ts
git commit -m "Add email validation to signup form"

git status
```

---

## Example: Fixup Commit

```bash
# Original commit
git add src/component.ts
git commit -m "Add email validation to signup form"

# Later, discovered a typo in that same commit
git add src/component.ts
git commit --fixup=HEAD

# Squash the fixup before pushing
git rebase -i --autosquash HEAD~2
```

---

## Commit Message Guidelines

- Keep it concise (under 72 characters for the subject line)
- Use imperative mood ("Add feature" not "Added feature")
- Focus on what and why, not how
- No period at the end of the subject line
- Be specific and descriptive
