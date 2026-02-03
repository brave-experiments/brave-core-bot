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
LOGS_DIR="$SCRIPT_DIR/logs"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"
RUN_STATE_FILE="$SCRIPT_DIR/run-state.json"

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

# Create logs directory if it doesn't exist
mkdir -p "$LOGS_DIR"

echo "Starting Claude Code agent - Max iterations: $MAX_ITERATIONS"
echo "Logs will be saved to: $LOGS_DIR"

# Reset run state at the start of each run
echo "Resetting run state for fresh start..."
"$SCRIPT_DIR/reset-run-state.sh"

# Track both loop count (for max iterations) and work iterations (actual state changes)
loop_count=0
work_iteration=0

while [ $loop_count -lt $MAX_ITERATIONS ]; do
  ((++loop_count))

  # Check if last iteration had state change (default to true for first iteration)
  HAD_STATE_CHANGE=$(jq -r '.lastIterationHadStateChange // true' "$RUN_STATE_FILE" 2>/dev/null || echo "true")

  # Only increment work iteration counter if there was actual state change
  if [ "$HAD_STATE_CHANGE" = "true" ]; then
    ((++work_iteration))
    echo ""
    echo "==============================================================="
    echo "  Work Iteration $work_iteration (loop $loop_count of $MAX_ITERATIONS)"
    echo "==============================================================="
  else
    echo ""
    echo "==============================================================="
    echo "  Checking next task (work iteration $work_iteration, loop $loop_count of $MAX_ITERATIONS)"
    echo "  Previous check had no state change - continuing without incrementing work iteration"
    echo "==============================================================="
  fi

  # Initialize runId if it's null (start of new run)
  RUN_ID=$(jq -r '.runId // "null"' "$RUN_STATE_FILE" 2>/dev/null || echo "null")
  if [ "$RUN_ID" = "null" ]; then
    # Initialize new run with current timestamp
    RUN_ID=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    TMP_RUN_STATE=$(mktemp)
    jq --arg runId "$RUN_ID" '.runId = $runId | .storiesCheckedThisRun = [] | .lastIterationHadStateChange = true' "$RUN_STATE_FILE" > "$TMP_RUN_STATE" && mv "$TMP_RUN_STATE" "$RUN_STATE_FILE"
  fi

  # Generate log file path for this iteration
  # Create a filename-safe version of runId (replace colons and other special chars)
  RUN_ID_SAFE=$(echo "$RUN_ID" | sed 's/[^a-zA-Z0-9-]/-/g')
  ITERATION_LOG="$LOGS_DIR/iteration-${RUN_ID_SAFE}-loop-${loop_count}.log"

  # Store the current iteration log path in run-state.json
  TMP_RUN_STATE=$(mktemp)
  jq --arg logPath "$ITERATION_LOG" '.currentIterationLogPath = $logPath' "$RUN_STATE_FILE" > "$TMP_RUN_STATE" && mv "$TMP_RUN_STATE" "$RUN_STATE_FILE"

  echo "Logging to: $ITERATION_LOG"

  # Run Claude Code with the agent prompt
  # Use a temp file to capture output while allowing real-time streaming
  TEMP_OUTPUT=$(mktemp)

  # Change to the parent directory (brave-browser) so relative paths in CLAUDE.md work
  BRAVE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  cd "$BRAVE_ROOT"

  # Claude Code: use --dangerously-skip-permissions for autonomous operation, --print for output
  # Always use opus model (which has extended thinking built-in)
  # Use stream-json output format with verbose flag to capture detailed execution logs
  # Capture output to temp file and log file
  claude --dangerously-skip-permissions --print --model opus --verbose --output-format stream-json "Follow the instructions in ./brave-core-bot/CLAUDE.md to execute one iteration of the autonomous agent workflow. The CLAUDE.md file contains the complete workflow and task selection algorithm." 2>&1 | tee -a "$ITERATION_LOG" > "$TEMP_OUTPUT" || true

  # Check for completion signal (only in assistant text responses, not tool results)
  # Use jq to properly filter for assistant messages with text content to avoid false positives from reading CLAUDE.md
  if jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "text") | .text' "$TEMP_OUTPUT" 2>/dev/null | grep -q "<promise>COMPLETE</promise>"; then
    echo ""
    echo "Agent completed all tasks!"
    echo "Completed at work iteration $work_iteration (loop $loop_count of $MAX_ITERATIONS)"
    rm -f "$TEMP_OUTPUT"
    exit 0
  fi

  rm -f "$TEMP_OUTPUT"

  echo "Loop $loop_count complete. Starting fresh context..."
  sleep 2
done

echo ""
echo "Agent reached max loop iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Work iterations completed: $work_iteration"
echo "Check $PROGRESS_FILE for status."
exit 1
