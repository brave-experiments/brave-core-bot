#!/bin/bash
# Long-running AI agent loop
# Usage: ./run.sh [max_iterations]

set -e

# Parse arguments
MAX_ITERATIONS=10

if [[ $# -gt 0 ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
  MAX_ITERATIONS="$1"
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"

# Function to switch back to master branch on exit
cleanup_and_return_to_master() {
  # Extract git repo directory from prd.json
  if [ -f "$PRD_FILE" ]; then
    GIT_REPO=$(jq -r '.config.workingDirectory // .config.gitRepo // .ralphConfig.workingDirectory // .ralphConfig.gitRepo // empty' "$PRD_FILE" 2>/dev/null || echo "")

    if [ -n "$GIT_REPO" ]; then
      # Handle relative paths - make them absolute from brave-browser root
      if [[ "$GIT_REPO" != /* ]]; then
        # Assume it's relative to brave-browser root (parent of brave-core-bot)
        BRAVE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
        GIT_REPO="$BRAVE_ROOT/$GIT_REPO"
      fi

      if [ -d "$GIT_REPO/.git" ]; then
        echo ""
        echo "Switching back to master branch in $GIT_REPO..."
        cd "$GIT_REPO" && git checkout master 2>/dev/null || git checkout main 2>/dev/null || echo "Could not switch to master/main branch"
      fi
    fi
  fi
}

# Register cleanup function to run on exit
trap cleanup_and_return_to_master EXIT

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")
  
  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$LAST_BRANCH"
    
    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"
    
    # Reset progress file for new run
    echo "# Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

echo "Starting Claude Code agent - Max iterations: $MAX_ITERATIONS"

# Reset run state at the start of each run
echo "Resetting run state for fresh start..."
"$SCRIPT_DIR/reset-run-state.sh"

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "==============================================================="
  echo "  Iteration $i of $MAX_ITERATIONS"
  echo "==============================================================="

  # Run Claude Code with the agent prompt
  # Use a temp file to capture output while allowing real-time streaming
  TEMP_OUTPUT=$(mktemp)

  # Claude Code: use --dangerously-skip-permissions for autonomous operation, --print for output
  # Always use opus model (which has extended thinking built-in)
  claude --dangerously-skip-permissions --print --model opus < "$SCRIPT_DIR/CLAUDE.md" 2>&1 | tee "$TEMP_OUTPUT" || true

  # Check for completion signal
  if grep -q "<promise>COMPLETE</promise>" "$TEMP_OUTPUT"; then
    echo ""
    echo "Agent completed all tasks!"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    rm -f "$TEMP_OUTPUT"
    exit 0
  fi

  rm -f "$TEMP_OUTPUT"
  
  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Agent reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
exit 1
