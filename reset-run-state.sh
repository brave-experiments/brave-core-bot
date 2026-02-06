#!/bin/bash
# Reset run state to start a fresh iteration cycle
# This allows all stories to be checked again

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_STATE_FILE="$SCRIPT_DIR/run-state.json"

echo "Resetting run state..."

# Preserve configuration settings (not iteration state)
SKIP_PUSHED=$(jq -r '.skipPushedTasks // false' "$RUN_STATE_FILE" 2>/dev/null || echo "false")
ENABLE_MERGE_BACKOFF=$(jq -r '.enableMergeBackoff // true' "$RUN_STATE_FILE" 2>/dev/null || echo "true")
MERGE_BACKOFF_STORY_IDS=$(jq -c '.mergeBackoffStoryIds // null' "$RUN_STATE_FILE" 2>/dev/null || echo "null")
PRIORITIZE_TASK=$(jq -c '.prioritizeTask // []' "$RUN_STATE_FILE" 2>/dev/null || echo "[]")

cat > "$RUN_STATE_FILE" << EOF
{
  "runId": null,
  "storiesCheckedThisRun": [],
  "skipPushedTasks": $SKIP_PUSHED,
  "enableMergeBackoff": $ENABLE_MERGE_BACKOFF,
  "mergeBackoffStoryIds": $MERGE_BACKOFF_STORY_IDS,
  "prioritizeTask": $PRIORITIZE_TASK,
  "notes": [
    "This file tracks iteration state within a single run",
    "runId: Timestamp when this run started (null = needs initialization)",
    "storiesCheckedThisRun: Story IDs that have been processed in this run",
    "skipPushedTasks: Set to true to skip all 'pushed' status tasks and only work on new development",
    "prioritizeTask: Array of story IDs, PR numbers, or repo refs to prioritize (e.g., ['US-012', '33750', 'brave/brave-browser#31393'])"
  ],
  "lastIterationHadStateChange": false,
  "currentIterationLogPath": null
}
EOF

echo "✓ Run state reset successfully"
echo "  - runId: null (will be initialized on next iteration)"
echo "  - storiesCheckedThisRun: [] (empty)"
echo "  - skipPushedTasks: $SKIP_PUSHED (preserved from previous state)"
echo "  - enableMergeBackoff: $ENABLE_MERGE_BACKOFF (preserved from previous state)"
echo "  - mergeBackoffStoryIds: $MERGE_BACKOFF_STORY_IDS (preserved from previous state)"
echo "  - prioritizeTask: $PRIORITIZE_TASK (preserved from previous state)"
echo ""
echo "Next iteration will start a fresh run and can check all stories again."
