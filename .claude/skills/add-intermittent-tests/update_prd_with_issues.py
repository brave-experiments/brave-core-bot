#!/usr/bin/env python3
import json
import sys
import re
import copy

# Read GitHub issues and existing PRD
if len(sys.argv) < 2:
    print("Usage: cat github_issues.json | python3 update_prd_with_issues.py path/to/prd.json", file=sys.stderr)
    sys.exit(1)

prd_path = sys.argv[1]

# Read GitHub issues from stdin
github_issues = json.loads(sys.stdin.read())

# Read existing PRD
with open(prd_path, 'r') as f:
    prd = json.load(f)

# Create a deep copy of existing stories for verification
original_stories = copy.deepcopy(prd['userStories'])
existing_story_count = len(prd['userStories'])

# Extract existing issue numbers from PRD
existing_issues = set()
for story in prd['userStories']:
    desc = story['description']
    # Match patterns like "issue #12345" or "(issue #12345)"
    matches = re.findall(r'issue #(\d+)', desc)
    for match in matches:
        existing_issues.add(int(match))

# Find the highest existing ID number and priority
max_id = 0
max_priority = 0
for story in prd['userStories']:
    id_num = int(story['id'].split('-')[1])
    if id_num > max_id:
        max_id = id_num
    if story['priority'] > max_priority:
        max_priority = story['priority']

# Process each GitHub issue and add if missing
new_stories = []
for issue in github_issues:
    issue_num = issue['number']

    # Skip if already in PRD
    if issue_num in existing_issues:
        continue

    title = issue['title']
    max_id += 1
    max_priority += 1

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
        "id": f"US-{max_id:03d}",
        "title": f"Fix test: {test_name}",
        "description": f"As a developer, I need to fix the intermittent failure in {test_name} (issue #{issue_num}).",
        "testType": test_type,
        "testFilter": test_name,
        "acceptanceCriteria": [
            "Read ./BEST-PRACTICES.md for async testing patterns and common pitfalls",
            f"Fetch issue #{issue_num} details from brave/brave-browser GitHub API",
            f"Determine test location: Run git grep {test_name.split('.')[0]} in ../src and ../src/brave to find where the test is defined",
            "Analyze stack trace and identify root cause",
            "Implement fix for the intermittent failure",
            "Run npm run build from src/brave (must pass)",
            "Run npm run format from src/brave (must pass)",
            "Run npm run presubmit from src/brave (must pass)",
            "Run npm run gn_check from src/brave (must pass)",
            f"[For Brave tests only] Run npm run test -- {test_binary} --gtest_filter={test_name} (must pass - run 5 times to verify consistency)"
        ],
        "priority": max_priority,
        "status": "pending",
        "prNumber": None,
        "lastActivityBy": None,
        "branchName": None,
        "prUrl": None
    }

    new_stories.append(user_story)

# SAFETY CHECK: Verify existing stories were not modified
for i in range(existing_story_count):
    if prd['userStories'][i] != original_stories[i]:
        print(f"ERROR: Existing story {prd['userStories'][i]['id']} was modified!", file=sys.stderr)
        print("This is a bug - existing stories should never be changed.", file=sys.stderr)
        sys.exit(1)

# Add new stories to PRD (appends to end, doesn't modify existing)
prd['userStories'].extend(new_stories)

# Output updated PRD
print(json.dumps(prd, indent=2))

# Print summary to stderr
print(f"\nAdded {len(new_stories)} new issues to PRD", file=sys.stderr)
for story in new_stories:
    issue_match = re.search(r'issue #(\d+)', story['description'])
    issue_num = issue_match.group(1) if issue_match else "unknown"
    print(f"  {story['id']}: {story['testFilter']} (#{issue_num})", file=sys.stderr)
