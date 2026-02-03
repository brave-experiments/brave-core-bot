#!/usr/bin/env python3
import json
import sys

# Read GitHub issues from stdin
github_issues = json.loads(sys.stdin.read())

# Initialize PRD structure
prd = {
    "projectName": "Brave Core Test Fixes",
    "description": "Automated fixing of intermittent test failures from brave/brave-browser repository",
    "config": {
        "workingDirectory": "/home/bbondy/projects/brave-browser/src/brave"
    },
    "userStories": []
}

# Process each issue
for idx, issue in enumerate(github_issues, start=1):
    issue_num = issue['number']
    title = issue['title']

    # Extract test name from title (remove "Test failure: " prefix)
    test_name = title.replace("Test failure: ", "")

    # Determine test type based on test name
    if "AlternateTestParams" in test_name or "PartitionAlloc" in test_name:
        test_type = "unit_test"
        test_binary = "brave_unit_tests"
    else:
        test_type = "browser_test"
        test_binary = "brave_browser_tests"

    # Create user story
    user_story = {
        "id": f"US-{idx:03d}",
        "title": f"Fix test: {test_name}",
        "description": f"As a developer, I need to fix the intermittent failure in {test_name} (issue #{issue_num}).",
        "testType": test_type,
        "testFilter": test_name,
        "acceptanceCriteria": [
            "Read ./brave-core-bot/BEST-PRACTICES.md for async testing patterns and common pitfalls",
            f"Fetch issue #{issue_num} details from brave/brave-browser GitHub API",
            "Analyze stack trace and identify root cause",
            "Implement fix for the intermittent failure",
            "Run npm run build from src/brave (must pass)",
            "Run npm run format from src/brave (must pass)",
            "Run npm run presubmit from src/brave (must pass)",
            "Run npm run gn_check from src/brave (must pass)",
            f"Run npm run test -- {test_binary} --gtest_filter={test_name} (must pass - run 5 times to verify consistency)"
        ],
        "priority": idx,
        "status": "pending",
        "prNumber": None,
        "lastActivityBy": None,
        "branchName": None,
        "prUrl": None
    }

    prd['userStories'].append(user_story)

# Output formatted JSON
print(json.dumps(prd, indent=2))
