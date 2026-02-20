#!/usr/bin/env bash
#
# detect_chain.sh - Detect downstream branch tree from a starting branch.
#
# Usage: detect_chain.sh [starting-branch]
#
# Outputs "branch:parent" per line in rebase order (depth-first pre-order).
# Handles trees with sibling branches (forks).
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
  #   "branch: Created from refs/remotes/origin/<parent>"
  #   "branch: Created from <parent>"
  #   "branch: Created from HEAD"
  parent=""
  if [[ "$creation_line" =~ branch:\ Created\ from\ refs/heads/(.+) ]]; then
    parent="${BASH_REMATCH[1]}"
  elif [[ "$creation_line" =~ branch:\ Created\ from\ refs/remotes/origin/(.+) ]]; then
    # Created from a remote tracking branch — use the local name
    candidate="${BASH_REMATCH[1]}"
    if git show-ref --verify --quiet "refs/heads/$candidate" 2>/dev/null; then
      parent="$candidate"
    fi
  elif [[ "$creation_line" =~ branch:\ Created\ from\ (.+) ]]; then
    candidate="${BASH_REMATCH[1]}"
    if [[ "$candidate" == "HEAD" ]]; then
      # Resolve HEAD at creation time: get the SHA from the branch's
      # oldest reflog entry, then find which branch had that SHA.
      creation_sha=$(git reflog show "$branch" --format='%H' \
        2>/dev/null | tail -1) || true
      if [[ -n "$creation_sha" ]]; then
        for other in $all_branches; do
          [[ "$other" == "$branch" ]] && continue
          # Check if the other branch had this exact SHA at its tip
          # (current or historical via reflog)
          if git reflog show "$other" --format='%H' 2>/dev/null \
              | grep -qx "$creation_sha"; then
            parent="$other"
            break
          fi
        done
      fi
    elif git show-ref --verify --quiet "refs/heads/$candidate" 2>/dev/null; then
      parent="$candidate"
    fi
  fi

  if [[ -n "$parent" ]]; then
    set_parent "$branch" "$parent"
  fi
done

# is_ancestor_of: check if $1 (or any historical tip of $1) is an
# ancestor of $2. Handles rebased branches by walking the reflog.
is_ancestor_of() {
  local ref="$1" target="$2"
  if git merge-base --is-ancestor "$ref" "$target" 2>/dev/null; then
    return 0
  fi
  # Fallback: if the local branch was rewritten (e.g., rebased with new
  # hashes), the old commits still exist on origin/<branch>.
  if git show-ref --verify --quiet "refs/remotes/origin/$ref" 2>/dev/null; then
    if git merge-base --is-ancestor "origin/$ref" "$target" 2>/dev/null; then
      return 0
    fi
  fi
  # Fallback: walk the reflog of $ref to find old tips that are still
  # ancestors of $target. This catches cases where both local and origin
  # have been rebased (new commits) but the downstream branch still has
  # the old commits.
  local old_sha
  while IFS= read -r old_sha; do
    [[ -z "$old_sha" ]] && continue
    if git merge-base --is-ancestor "$old_sha" "$target" 2>/dev/null; then
      return 0
    fi
  done < <(git reflog show "$ref" --format='%H' 2>/dev/null \
    | awk '!seen[$0]++' | head -50)
  return 1
}

# Fallback: for branches without reflog parent, use merge-base + ancestor
# checks. Collect all candidates that descend from start_branch, then
# determine the closest parent for each using --is-ancestor.
candidates=()
for branch in $all_branches; do
  [[ "$branch" == "$start_branch" ]] && continue
  has_parent "$branch" && continue

  # Check if start_branch (or origin/start_branch) is an ancestor
  if is_ancestor_of "$start_branch" "$branch"; then
    candidates+=("$branch")
  fi
done

# For each candidate, find its closest parent among start_branch + other
# candidates. The closest parent is the one whose HEAD is an ancestor of
# the candidate AND is not an ancestor of any other ancestor candidate.
for branch in "${candidates[@]+"${candidates[@]}"}"; do
  closest_parent="$start_branch"
  for other in "${candidates[@]+"${candidates[@]}"}"; do
    [[ "$other" == "$branch" ]] && continue
    # If other is an ancestor of branch AND other is a descendant of
    # our current closest_parent, then other is a closer parent.
    if is_ancestor_of "$other" "$branch" && \
       is_ancestor_of "$closest_parent" "$other"; then
      closest_parent="$other"
    fi
  done
  set_parent "$branch" "$closest_parent"
done

# Build children map from parent map
for f in "$parent_dir"/*; do
  [[ -f "$f" ]] || continue
  branch=$(basename "$f" | sed 's|__|/|g')
  parent=$(cat "$f")
  add_child "$parent" "$branch"
done

# Walk the tree starting from start_branch (depth-first pre-order)
walk_tree() {
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

  # Visit each child and recurse (parents always before children)
  for child in "${kid_array[@]}"; do
    echo "$child:$current"
    walk_tree "$child"
  done
}

walk_tree "$start_branch"
