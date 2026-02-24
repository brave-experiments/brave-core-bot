#!/bin/bash
# Sync best practices from brave-core-bot to src/brave/.claude/rules via symlinks

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BP_SRC="$SCRIPT_DIR/docs/best-practices"
BP_DEST="$SCRIPT_DIR/../src/brave/.claude/rules/best-practices"

if [ ! -d "$BP_SRC" ]; then
  echo "No best practices found in $BP_SRC"
  exit 1
fi

# Create destination directory if needed
mkdir -p "$BP_DEST"

for bp_file in "$BP_SRC"/*.md; do
  file_name=$(basename "$bp_file")
  dest="$BP_DEST/$file_name"

  if [ -L "$dest" ]; then
    if [ -e "$dest" ]; then
      echo "✓ $file_name (already symlinked)"
      continue
    else
      echo "⚠ $file_name (broken symlink, recreating)"
      rm "$dest"
    fi
  fi

  if [ -f "$dest" ]; then
    echo "⚠ $file_name (exists as regular file, skipping)"
    continue
  fi

  ln -s "../../../../../brave-core-bot/docs/best-practices/$file_name" "$dest"
  echo "✓ $file_name (linked)"
done

echo ""
echo "Done. Current symlinks in $BP_DEST:"
ls -la "$BP_DEST" | grep "^l" || echo "  (none)"
