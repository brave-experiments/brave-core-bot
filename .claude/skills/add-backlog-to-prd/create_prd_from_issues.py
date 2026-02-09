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
    script_dir = os.path.dirname(os.path.abspath(__file__))
    brave_dir = os.path.join(script_dir, '..', '..', '..', '..', 'src', 'brave')
    chromium_dir = os.path.join(script_dir, '..', '..', '..', '..', 'src')

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

def is_test_issue(issue):
    """Check if an issue is a test failure based on title or labels."""
    if issue['title'].startswith('Test failure: '):
        return True
    labels = issue.get('labels', [])
    for label in labels:
        name = label.get('name', '') if isinstance(label, dict) else str(label)
        if name == 'bot/type/test':
            return True
    return False

def build_test_story(idx, issue):
    """Build a user story for a test failure issue."""
    issue_num = issue['number']
    title = issue['title']

    # Extract test name from title (remove common prefixes)
    test_name = title
    for prefix in ["Test failure: ", "Intermittent upstream unittest failure: ", "Intermittent upstream unittest failure:  ", "Intermittent test failure: "]:
        test_name = test_name.replace(prefix, "")
    test_name = test_name.strip()

    # Extract test class name for location detection
    test_class_name = test_name.split('.')[0]
    test_location = find_test_location(test_class_name)

    if "AlternateTestParams" in test_name or "PartitionAlloc" in test_name:
        test_type = "unit_test"
        test_binary = "brave_unit_tests" if test_location == 'brave' else "unit_tests"
    else:
        test_type = "browser_test"
        test_binary = "brave_browser_tests" if test_location == 'brave' else "browser_tests"

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

    return {
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

def build_generic_story(idx, issue):
    """Build a user story for a non-test issue."""
    issue_num = issue['number']
    title = issue['title']

    acceptance_criteria = [
        f"Fetch issue #{issue_num} details from brave/brave-browser GitHub API",
        "Analyze the issue and identify what needs to change",
        "Implement the fix or feature",
        "Run npm run build from src/brave (must pass)",
        "Run npm run format from src/brave (must pass)",
        "Run npm run presubmit from src/brave (must pass)",
        "Run npm run gn_check from src/brave (must pass)",
        "Find and run relevant tests to verify the change (must pass)",
    ]

    return {
        "id": f"US-{idx:03d}",
        "title": title,
        "description": f"Resolve issue #{issue_num}: {title}",
        "acceptanceCriteria": acceptance_criteria,
        "priority": idx,
        "status": "pending",
        "prNumber": None,
        "lastActivityBy": None,
        "branchName": None,
        "prUrl": None
    }

# Initialize PRD structure
prd = {
    "projectName": "Brave Core Bot Backlog",
    "description": "Issues from brave/brave-browser repository to be resolved",
    "config": {
        "workingDirectory": "../src/brave"
    },
    "userStories": []
}

# Process each issue
for idx, issue in enumerate(github_issues, start=1):
    if is_test_issue(issue):
        story = build_test_story(idx, issue)
    else:
        story = build_generic_story(idx, issue)
    prd['userStories'].append(story)

# Output formatted JSON
print(json.dumps(prd, indent=2))
