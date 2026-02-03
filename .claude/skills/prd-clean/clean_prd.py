#!/usr/bin/env python3
import json
import sys
import os
import copy

# Read PRD path from command line
if len(sys.argv) < 2:
    print("Usage: python3 clean_prd.py path/to/prd.json", file=sys.stderr)
    sys.exit(1)

prd_path = sys.argv[1]
prd_dir = os.path.dirname(prd_path)
old_prd_path = os.path.join(prd_dir, "prd.archived.json")

# Read existing PRD
try:
    with open(prd_path, 'r') as f:
        prd = json.load(f)
except FileNotFoundError:
    print(f"ERROR: PRD file not found at {prd_path}", file=sys.stderr)
    sys.exit(1)
except json.JSONDecodeError as e:
    print(f"ERROR: Invalid JSON in {prd_path}: {e}", file=sys.stderr)
    sys.exit(1)

# Read existing old PRD if it exists
old_stories = []
if os.path.exists(old_prd_path):
    try:
        with open(old_prd_path, 'r') as f:
            old_prd = json.load(f)
            old_stories = old_prd.get('userStories', [])
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"WARNING: Could not read existing {old_prd_path}: {e}", file=sys.stderr)
        print("Starting with empty old PRD", file=sys.stderr)

# Split stories into active and archived
active_stories = []
archived_stories = []

for story in prd['userStories']:
    status = story.get('status', '')
    if status in ['merged', 'invalid']:
        archived_stories.append(story)
    else:
        active_stories.append(story)

# Merge with existing archived stories
# Create a map of existing old stories by ID to avoid duplicates
existing_old_story_ids = {story['id']: story for story in old_stories}

# Add newly archived stories, avoiding duplicates
for story in archived_stories:
    story_id = story['id']
    if story_id in existing_old_story_ids:
        # Update existing story with latest data
        existing_old_story_ids[story_id] = story
    else:
        # Add new archived story
        existing_old_story_ids[story_id] = story

# Convert back to list and sort by ID
all_old_stories = list(existing_old_story_ids.values())
all_old_stories.sort(key=lambda s: s['id'])

# Create new PRD with only active stories
new_prd = copy.deepcopy(prd)
new_prd['userStories'] = active_stories

# Create old PRD structure
old_prd_data = {
    "projectName": prd.get('projectName', 'Unknown'),
    "config": prd.get('config', {}),
    "userStories": all_old_stories
}

# Write old PRD to file
try:
    with open(old_prd_path, 'w') as f:
        json.dump(old_prd_data, f, indent=2)
except IOError as e:
    print(f"ERROR: Could not write to {old_prd_path}: {e}", file=sys.stderr)
    sys.exit(1)

# Output updated PRD to stdout
print(json.dumps(new_prd, indent=2))

# Print summary to stderr
print(f"\n=== PRD Cleaning Summary ===", file=sys.stderr)
print(f"Archived stories moved to {old_prd_path}:", file=sys.stderr)
print(f"  - Merged: {sum(1 for s in archived_stories if s.get('status') == 'merged')}", file=sys.stderr)
print(f"  - Invalid: {sum(1 for s in archived_stories if s.get('status') == 'invalid')}", file=sys.stderr)
print(f"Total archived stories: {len(all_old_stories)}", file=sys.stderr)
print(f"Active stories remaining: {len(active_stories)}", file=sys.stderr)
print(f"\nArchived stories:", file=sys.stderr)
for story in archived_stories:
    print(f"  {story['id']}: {story.get('title', 'No title')} [{story.get('status')}]", file=sys.stderr)
