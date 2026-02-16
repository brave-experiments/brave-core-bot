---
name: make-ci-green
description: "Re-run failed CI jobs for a brave/brave-core PR. Detects failure stage and uses WIPE_WORKSPACE for build/infra failures. Triggers on: make ci green, retry ci, rerun ci, fix ci, re-run failed jobs, retrigger ci."
argument-hint: "<pr-number> [--dry-run]"
---

# Make CI Green

Re-run failed Jenkins CI jobs for a brave/brave-core PR. Automatically detects the failure stage and decides whether to use WIPE_WORKSPACE (for build/infra failures) or a normal re-run (for test/storybook failures).

---

## When to Use

- **Flaky test failures** on CI that just need a retry
- **Build/infra failures** that need a workspace wipe to recover
- **After pushing new commits** to retrigger only the failing checks
- **Batch retriggering** when multiple platform checks are failing

---

## Environment Requirements

The following environment variables must be set (e.g., in your `.envrc`):

```bash
export JENKINS_BASE_URL=https://ci.brave.com
export JENKINS_USER=brian@brave.com
export JENKINS_TOKEN=<your-api-token>
```

Get your API token from `$JENKINS_BASE_URL/me/configure`.

---

## The Job

### Step 1: Parse Arguments

Extract the PR number from the user's input. The PR number is required. Check for `--dry-run` flag.

| User says | PR number |
|-----------|-----------|
| `/make-ci-green 33936` | 33936 |
| "retry ci for 33936" | 33936 |
| "make ci green on PR 33936" | 33936 |
| "re-run failed jobs 33936 --dry-run" | 33936 (dry run) |

### Step 2: Analyze Failures

Run the script in dry-run mode to analyze without triggering:

```bash
python3 .claude/skills/make-ci-green/retrigger_ci.py <pr-number> --dry-run --format json
```

### Step 3: Present Findings

Show the user what was found:

- **Failing Jenkins checks**: check name, failed stage, recommended action (normal vs WIPE_WORKSPACE), reason
- **Non-Jenkins failures** (SonarCloud, Socket Security, etc.): listed but not actionable by this tool
- **Pending checks**: still running, listed for awareness
- **No failures**: report that CI is already green

**Example output:**
```
PR 33936: 1 failing Jenkins check(s)

  [DRY-RUN] continuous-integration/linux-x64/pr-head
       Stage: test_brave_unit_tests
       Action: normal
       Reason: Test/post-build stage failure: "test_brave_unit_tests" -> normal re-run
       URL: https://ci.brave.com/job/brave-core-build-pr-linux-x64/job/PR-33936/2/
```

### Step 4: Confirm and Trigger

If the user wants to proceed (and not `--dry-run`), run the script to trigger rebuilds:

```bash
python3 .claude/skills/make-ci-green/retrigger_ci.py <pr-number> --format json
```

Report the results: which checks were retriggered, the action taken, and any errors.

---

## WIPE_WORKSPACE Decision Logic

The script examines which pipeline stage failed:

| Failed Stage | Action | Rationale |
|-------------|--------|-----------|
| init, checkout, install, config, build, compile, setup, sync, gclient, source, deps, fetch, configure, bootstrap, prepare, environment | **WIPE_WORKSPACE** | Infrastructure/build failure; workspace may be corrupted |
| storybook, test(s), audit, lint, upload, publish, or anything else | **Normal re-run** | Test failure likely flaky; no workspace issue |
| Unknown (API error) | **Normal re-run** | Safe default |

Stage matching is case-insensitive substring matching (e.g., "Build (Debug)" matches "build").

---

## Usage Examples

```bash
# Dry run: analyze without triggering
python3 .claude/skills/make-ci-green/retrigger_ci.py 33936 --dry-run

# Trigger rebuilds for all failing checks
python3 .claude/skills/make-ci-green/retrigger_ci.py 33936

# JSON output for programmatic use
python3 .claude/skills/make-ci-green/retrigger_ci.py 33936 --format json

# Dry run with JSON output
python3 .claude/skills/make-ci-green/retrigger_ci.py 33936 --dry-run --format json
```

---

## Exit Codes

- `0`: Success (checks found and processed)
- `1`: Config error (missing JENKINS_TOKEN)
- `2`: API error (GitHub or Jenkins unreachable)
- `3`: No failing Jenkins checks found

---

## Limitations

- Only handles Jenkins CI checks (identified by `ci.brave.com` in the URL)
- Cannot retrigger GitHub Actions or other CI systems (SonarCloud, Socket Security)
- Requires Jenkins API access with a valid token
- Does not handle PENDING checks (still running)
- WIPE_WORKSPACE detection relies on stage name keyword matching
