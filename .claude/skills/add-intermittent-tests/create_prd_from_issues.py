#!/usr/bin/env python3
import json
import sys
import subprocess
import os

# Read GitHub issues from stdin
github_issues = json.loads(sys.stdin.read())

def find_test_location(test_class_name):
    """
    Determine if a test is a Brave test or Chromium test by running git grep.
    Returns 'brave' if found in src/brave, 'chromium' if found in src only, or 'unknown'.
    """
    # Get the directory where this script is located, then navigate to src/brave
    script_dir = os.path.dirname(os.path.abspath(__file__))
    brave_dir = os.path.join(script_dir, '..', '..', '..', '..', 'src', 'brave')
    chromium_dir = os.path.join(script_dir, '..', '..', '..', '..', 'src')

    # Check Brave first
    try:
        result = subprocess.run(
            ['git', 'grep', '-l', test_class_name],
            cwd=brave_dir,
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode == 0 and result.stdout.strip():
            return 'brave'
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    # Check Chromium (but not brave subfolder)
    try:
        result = subprocess.run(
            ['git', 'grep', '-l', test_class_name, '--', '.', ':!brave'],
            cwd=chromium_dir,
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode == 0 and result.stdout.strip():
            return 'chromium'
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    return 'unknown'

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

    # Extract test class name for location detection
    test_class_name = test_name.split('.')[0]

    # Determine test location by running git grep
    test_location = find_test_location(test_class_name)

    # Determine test type and binary based on test name and location
    if "AlternateTestParams" in test_name or "PartitionAlloc" in test_name:
        test_type = "unit_test"
        test_binary = "brave_unit_tests" if test_location == 'brave' else "unit_tests"
    else:
        test_type = "browser_test"
        test_binary = "brave_browser_tests" if test_location == 'brave' else "browser_tests"

    # Build acceptance criteria based on test location
    acceptance_criteria = [
        "Read ./BEST-PRACTICES.md for async testing patterns and common pitfalls",
        f"Fetch issue #{issue_num} details from brave/brave-browser GitHub API",
        "Analyze stack trace and identify root cause",
        "Implement fix for the intermittent failure",
        "Run npm run build from src/brave (must pass)",
        "Run npm run format from src/brave (must pass)",
        "Run npm run presubmit from src/brave (must pass)",
        "Run npm run gn_check from src/brave (must pass)",
        f"Run npm run test -- {test_binary} --gtest_filter={test_name} (must pass - run 5 times to verify consistency)"
    ]

    # Create user story
    user_story = {
        "id": f"US-{idx:03d}",
        "title": f"Fix test: {test_name}",
        "description": f"As a developer, I need to fix the intermittent failure in {test_name} (issue #{issue_num}).",
        "testType": test_type,
        "testLocation": test_location,
        "testFilter": test_name,
        "acceptanceCriteria": acceptance_criteria,
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
