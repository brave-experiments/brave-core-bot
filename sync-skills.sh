#!/bin/bash
# Sync skills from brave-core-bot to src/brave via symlinks
# Each skill is prompted individually so you can choose which ones to share

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$SCRIPT_DIR/.claude/skills"
SKILLS_DEST="$SCRIPT_DIR/../src/brave/.claude/skills"

# Skills to skip (project-specific, not for general use)
SKIP_SKILLS=(
  learnable-pattern-search
  update-best-practices
  add-backlog-to-prd
  prd
  prd-clean
  prd-json
)

if [ ! -d "$SKILLS_SRC" ]; then
  echo "No skills found in $SKILLS_SRC"
  exit 1
fi

# Create destination directory if needed
mkdir -p "$SKILLS_DEST"

for skill_dir in "$SKILLS_SRC"/*/; do
  skill_name=$(basename "$skill_dir")
  dest="$SKILLS_DEST/$skill_name"

  # Check if skill is in the skip list
  skip=false
  for s in "${SKIP_SKILLS[@]}"; do
    if [ "$skill_name" = "$s" ]; then
      skip=true
      break
    fi
  done
  if $skip; then
    continue
  fi

  if [ -L "$dest" ]; then
    echo "✓ $skill_name (already symlinked)"
    continue
  fi

  if [ -d "$dest" ]; then
    echo "⚠ $skill_name (exists as regular directory, skipping)"
    continue
  fi

  read -p "Symlink $skill_name? (y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    ln -s "../../../brave-core-bot/.claude/skills/$skill_name" "$dest"
    echo "  ✓ Linked"
  else
    echo "  ✗ Skipped"
  fi
done

echo ""
echo "Done. Current symlinks in $SKILLS_DEST:"
ls -la "$SKILLS_DEST" | grep "^l" || echo "  (none)"
