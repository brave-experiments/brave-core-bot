#!/bin/bash
# Reset run state to start a fresh iteration cycle
# This allows all stories to be checked again

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_STATE_FILE="$SCRIPT_DIR/run-state.json"

echo "Resetting run state..."

cat > "$RUN_STATE_FILE" << 'EOF'
{
  "runId": null,
  "storiesCheckedThisRun": [],
  "skipPushedTasks": false,
  "notes": [
    "This file tracks iteration state within a single run",
    "runId: Timestamp when this run started (null = needs initialization)",
    "storiesCheckedThisRun: Story IDs that have been processed in this run",
    "skipPushedTasks: Set to true to skip all 'pushed' status tasks and only work on new development"
  ]
}
EOF

echo "✓ Run state reset successfully"
echo "  - runId: null (will be initialized on next iteration)"
echo "  - storiesCheckedThisRun: [] (empty)"
echo "  - skipPushedTasks: false"
echo ""
echo "Next iteration will start a fresh run and can check all stories again."
