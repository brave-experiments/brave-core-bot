#!/bin/bash
# Setup script for brave-core-bot
# This script installs the pre-commit hook and helps configure git

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK_SOURCE="$SCRIPT_DIR/hooks/pre-commit"

echo "==================================="
echo "  Brave Core Bot Setup"
echo "==================================="
echo ""

# Validate directory structure
EXPECTED_REPO_PATH="$(dirname "$SCRIPT_DIR")/src/brave"
if [ ! -d "$EXPECTED_REPO_PATH" ]; then
  echo "⚠️  Warning: Expected directory structure not found"
  echo ""
  echo "This script expects to be run from:"
  echo "  brave-browser/brave-core-bot/"
  echo ""
  echo "Where brave-browser contains:"
  echo "  - src/brave/ (target git repository)"
  echo "  - brave-core-bot/ (this directory)"
  echo ""
  echo "Expected path not found: $EXPECTED_REPO_PATH"
  echo ""
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 1
  fi
  echo ""
fi

# Check if prd.json exists
if [ ! -f "$SCRIPT_DIR/prd.json" ]; then
  echo "❌ Error: prd.json not found in $SCRIPT_DIR"
  echo "   Please create a prd.json file before running setup."
  exit 1
fi

# Extract git repo from prd.json
GIT_REPO=$(jq -r '.config.workingDirectory // .config.gitRepo // .ralphConfig.workingDirectory // .ralphConfig.gitRepo // empty' "$SCRIPT_DIR/prd.json" 2>/dev/null || echo "")

if [ -z "$GIT_REPO" ]; then
  echo "❌ Error: Could not find git repository in prd.json"
  echo "   Please set config.workingDirectory or config.gitRepo"
  exit 1
fi

# Handle relative paths
if [[ "$GIT_REPO" != /* ]]; then
  BRAVE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
  GIT_REPO="$BRAVE_ROOT/$GIT_REPO"
fi

echo "Target git repository: $GIT_REPO"
echo ""

# Verify git repo exists
if [ ! -d "$GIT_REPO/.git" ]; then
  echo "❌ Error: $GIT_REPO is not a git repository"
  exit 1
fi

# Install pre-commit hook
HOOK_DEST="$GIT_REPO/.git/hooks/pre-commit"

echo "Installing pre-commit hook..."
cp "$HOOK_SOURCE" "$HOOK_DEST"
chmod +x "$HOOK_DEST"
echo "✓ Pre-commit hook installed to $HOOK_DEST"
echo ""

# Install Claude Code skills
echo "Installing Claude Code skills..."
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"

if [ ! -d "$CLAUDE_SKILLS_DIR" ]; then
  echo "Creating Claude skills directory: $CLAUDE_SKILLS_DIR"
  mkdir -p "$CLAUDE_SKILLS_DIR"
fi

# Install brave_core_prd skill
if [ -f "$SCRIPT_DIR/skills/brave_core_prd.md" ]; then
  echo "  Installing /brave_core_prd skill..."
  cp "$SCRIPT_DIR/skills/brave_core_prd.md" "$CLAUDE_SKILLS_DIR/"
  echo "  ✓ /brave_core_prd skill installed"
fi

# Install brave_core_prd_json (PRD converter) skill
if [ -f "$SCRIPT_DIR/skills/brave_core_prd_json.md" ]; then
  echo "  Installing /brave_core_prd_json skill..."
  cp "$SCRIPT_DIR/skills/brave_core_prd_json.md" "$CLAUDE_SKILLS_DIR/"
  echo "  ✓ /brave_core_prd_json skill installed"
fi

echo ""

# Check git config
echo "Checking git configuration..."
cd "$GIT_REPO"

GIT_USER=$(git config user.name || echo "")
GIT_EMAIL=$(git config user.email || echo "")

if [ -z "$GIT_USER" ] || [ -z "$GIT_EMAIL" ]; then
  echo ""
  echo "⚠️  Git user configuration not found!"
  echo ""
  echo "Please configure git for this repository:"
  echo ""
  echo "  cd $GIT_REPO"
  echo "  git config user.name \"Your Bot Name\""
  echo "  git config user.email \"your-bot@example.com\""
  echo ""
  echo "For the netzenbot account (with dependency restrictions):"
  echo "  git config user.name \"netzenbot\""
  echo "  git config user.email \"netzenbot@brave.com\""
  echo ""
else
  echo "✓ Git user: $GIT_USER"
  echo "✓ Git email: $GIT_EMAIL"
  echo ""
fi

echo "==================================="
echo "  Setup Complete!"
echo "==================================="
echo ""
echo "Next steps:"
echo "1. Configure git user/email if not already set (see above)"
echo "2. Review prd.json and update configuration as needed"
echo "3. Run the bot: cd $SCRIPT_DIR && ./run.sh"
echo ""
