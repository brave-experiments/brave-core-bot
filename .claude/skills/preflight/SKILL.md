---
name: preflight
description: "Run all preflight checks (format, gn_check, presubmit, build, tests) to make sure the current work is ready for review."
---

# Preflight Checks

Run all preflight checks to make sure the current work is ready for review. Execute each step sequentially and stop immediately if any step fails.

## Arguments

- **`all`** — Run all test suites (brave_browser_tests, brave_unit_tests, brave_component_unittests) without filters, instead of only running tests affected by the change. Usage: `/preflight all`

## Current State

- Branch: !`git branch --show-current`
- Status: !`git status --short`

## Steps

### 0. Check branch
If on `master`, create a new branch off of master before proceeding (use a descriptive branch name based on the changes).

### 1. Check against best practices

Review the branch's changes against `./brave-core-bot/BEST-PRACTICES.md`. Read the relevant sub-docs based on what the changes modify:

- **C++ code changes**: Read `docs/best-practices/coding-standards.md`
- **Async test changes**: Read `docs/best-practices/testing-async.md`
- **JavaScript test changes**: Read `docs/best-practices/testing-javascript.md`
- **Navigation/timing test changes**: Read `docs/best-practices/testing-navigation.md`
- **Test isolation changes**: Read `docs/best-practices/testing-isolation.md`
- **Front-end (TypeScript/React) changes**: Read `docs/best-practices/frontend.md`
- **Architecture/service changes**: Read `docs/best-practices/architecture.md`
- **Build file changes**: Read `docs/best-practices/build-system.md`
- **chromium_src changes**: Read `docs/best-practices/chromium-src-overrides.md`

Only read the docs relevant to the changes — don't load all of them every time. Compare the diff against master and flag any violations. If violations are found, fix them before proceeding.

### 2. Format code
Run `npm run format`. If formatting changes any files, stage and include them in the commit later.

### 3. GN check
Run `npm run gn_check`. Fix any issues found and re-run until it passes.

**Skip this step** if the only changes are to test filter files (`test/filters/*.filter`) — filter files don't affect GN build configuration.

### 4. Presubmit
Run `npm run presubmit`. Fix any issues found and re-run until it passes.

### 5. Commit if needed
Check `git status`. If there are any uncommitted changes (staged, unstaged, or untracked files relevant to the work), create a commit. The commit message should be short and succinct, describing what was done. If there are no changes, skip this step.

### 6. Build
Run `npm run build` to make sure the code builds. If it fails, fix the build errors, amend the commit, and retry.

### 7. Run tests

**If the `all` argument was provided:** Run all test suites without filters:

- `npm run test -- brave_browser_tests`
- `npm run test -- brave_unit_tests`
- `npm run test -- brave_component_unittests`

**Otherwise (default):** Determine which test targets are affected by the changes in this branch (compare against `master`). Look at the changed files and identify the corresponding test targets and relevant test filters.

- **Browser tests:** `npm run test -- brave_browser_tests --filter=<TestName>`
- **Unit tests:** `npm run test -- brave_unit_tests --filter=<TestName>`
- **Component unit tests:** `npm run test -- brave_component_unittests --filter=<TestName>`

If no tests are affected, note that and move on.

### 8. Re-check best practices if substantial changes were made
If steps 2–7 required fixes that introduced substantial code changes (not just formatting), re-run the best practices check from step 1 against the new changes. Skip this if the only changes were whitespace/formatting.

### 9. Re-run checks if fixes were needed
If any step required fixes (best practices violations, build errors, test failures, format/lint issues), amend the commit with the fixes and re-run all checks from step 1 until everything passes cleanly.

## Important
- Stop and report if any step fails after exhausting reasonable fix attempts.
- Report a summary of results when all steps complete successfully.
