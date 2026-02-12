#!/usr/bin/env bash
#
# detect_chain.sh - Detect downstream branch chain from a starting branch.
#
# Usage: detect_chain.sh [starting-branch]
#
# Outputs one branch per line in rebase order (direct child first).
# Warnings about forks (multiple children) go to stderr.
#
# Compatible with bash 3+ (no associative arrays).

set -euo pipefail

start_branch="${1:-$(git branch --show-current)}"

if [[ -z "$start_branch" ]]; then
  echo "Error: No branch specified and not on a branch." >&2
  exit 1
fi

# Use temp files to store parent and children maps (bash 3 compat)
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

parent_dir="$tmpdir/parents"
children_dir="$tmpdir/children"
mkdir -p "$parent_dir" "$children_dir"

# Sanitize branch name for use as filename (replace / with __)
sanitize() {
  echo "$1" | sed 's|/|__|g'
}

set_parent() {
  local branch="$1" parent="$2"
  echo "$parent" > "$parent_dir/$(sanitize "$branch")"
}

get_parent() {
  local f="$parent_dir/$(sanitize "$1")"
  [[ -f "$f" ]] && cat "$f" || true
}

has_parent() {
  [[ -f "$parent_dir/$(sanitize "$1")" ]]
}

add_child() {
  local parent="$1" child="$2"
  echo "$child" >> "$children_dir/$(sanitize "$parent")"
}

get_children() {
  local f="$children_dir/$(sanitize "$1")"
  [[ -f "$f" ]] && cat "$f" || true
}

# Build parent map by parsing reflog creation entries
all_branches=$(git for-each-ref --format='%(refname:short)' refs/heads/)

for branch in $all_branches; do
  [[ "$branch" == "$start_branch" ]] && continue

  # Look for the creation entry in the reflog
  creation_line=$(git reflog show "$branch" --format='%gs' 2>/dev/null \
    | tail -1) || true

  if [[ -z "$creation_line" ]]; then
    continue
  fi

  # Match patterns like:
  #   "branch: Created from refs/heads/<parent>"
  #   "branch: Created from <parent>"
  parent=""
  if [[ "$creation_line" =~ branch:\ Created\ from\ refs/heads/(.+) ]]; then
    parent="${BASH_REMATCH[1]}"
  elif [[ "$creation_line" =~ branch:\ Created\ from\ (.+) ]]; then
    candidate="${BASH_REMATCH[1]}"
    # Only use if it matches a known branch name (not a SHA)
    if git show-ref --verify --quiet "refs/heads/$candidate" 2>/dev/null; then
      parent="$candidate"
    fi
  fi

  if [[ -n "$parent" ]]; then
    set_parent "$branch" "$parent"
  fi
done

# Fallback: for branches without reflog creation entries, use merge-base
# heuristic. If merge-base(start, candidate) == HEAD of start, the candidate
# likely branched from start (or a descendant).
for branch in $all_branches; do
  [[ "$branch" == "$start_branch" ]] && continue
  has_parent "$branch" && continue

  mb=$(git merge-base "$start_branch" "$branch" 2>/dev/null) || continue
  start_head=$(git rev-parse "$start_branch" 2>/dev/null) || continue

  if [[ "$mb" == "$start_head" ]]; then
    set_parent "$branch" "$start_branch"
  fi
done

# Build children map from parent map
for f in "$parent_dir"/*; do
  [[ -f "$f" ]] || continue
  branch=$(basename "$f" | sed 's|__|/|g')
  parent=$(cat "$f")
  add_child "$parent" "$branch"
done

# Walk the chain starting from start_branch
walk_chain() {
  local current="$1"
  local kids
  kids=$(get_children "$current")

  if [[ -z "$kids" ]]; then
    return
  fi

  # Read children into an array
  local kid_array=()
  while IFS= read -r k; do
    [[ -n "$k" ]] && kid_array+=("$k")
  done <<< "$kids"

  if [[ ${#kid_array[@]} -gt 1 ]]; then
    echo "WARNING: Branch '$current' has multiple children:" \
      "${kid_array[*]}" >&2
    echo "WARNING: Following first child '${kid_array[0]}' only." \
      "Other branches: ${kid_array[*]:1}" >&2
  fi

  # Follow the first child (or only child)
  local next="${kid_array[0]}"
  echo "$next"
  walk_chain "$next"
}

walk_chain "$start_branch"
