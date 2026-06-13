---
description: Complete feature or bugfix workflow and open a PR against the default branch (or --base <branch>)
hidden: true
effort: medium
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Goal

Complete feature or bugfix workflow by cleaning up, validating, committing, pushing, and opening a pull request against the parent branch.

**Purpose**: Provide a clean, guided completion process for features and bugfixes developed with SpecSwarm workflows.

**Scope**: Handles cleanup → validation → commit → push → PR creation

**Target branch**: Defaults to the detected parent branch (from spec.md or repo default). Pass `--base <branch>` to override.

---

## Pre-Flight Checks

```bash
# Ensure we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "❌ Error: Not in a git repository"
  echo ""
  echo "This command must be run from within a git repository."
  exit 1
fi

# Get repository root
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"
```

---

## Execution Steps

### Step 1: Detect Workflow Context

```bash
echo "🎯 Feature Completion Workflow"
echo "══════════════════════════════════════════"
echo ""

# Detect current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Extract feature/bug number from branch name
# Patterns: NNN-*, feature/NNN-*, bugfix/NNN-*, fix/NNN-*
FEATURE_NUM=$(echo "$CURRENT_BRANCH" | grep -oE '^[0-9]{3}' || \
              echo "$CURRENT_BRANCH" | grep -oE '(feature|bugfix|fix)/([0-9]{3})' | grep -oE '[0-9]{3}' || \
              echo "")

# Extract optional --base branch override from arguments
BASE_BRANCH_OVERRIDE=$(echo "$ARGUMENTS" | grep -oP '(?<=--base\s)\S+' || echo "")

# If no number found, check user arguments
if [ -z "$FEATURE_NUM" ] && [ -n "$ARGUMENTS" ]; then
  # Try to extract number from arguments (skip --base and its value)
  FEATURE_NUM=$(echo "$ARGUMENTS" | sed 's/--base\s\+\S\+//' | grep -oE '\b[0-9]{3}\b' | head -1)
fi

# If still no number, ask user
if [ -z "$FEATURE_NUM" ]; then
  echo "⚠️  Could not detect feature/bug number from branch: $CURRENT_BRANCH"
  echo ""
  read -p "Enter feature or bug number (e.g., 915): " FEATURE_NUM

  if [ -z "$FEATURE_NUM" ]; then
    echo "❌ Error: Feature number required"
    exit 1
  fi

  # Pad to 3 digits
  FEATURE_NUM=$(printf "%03d" $FEATURE_NUM)
fi

# Source features location helper
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
source "$PLUGIN_DIR/lib/features-location.sh"

# Initialize features directory
get_features_dir "$REPO_ROOT"

# Determine workflow type from branch or directory
if echo "$CURRENT_BRANCH" | grep -qE '^(bugfix|bug|fix)/'; then
  WORKFLOW_TYPE="bugfix"
elif echo "$CURRENT_BRANCH" | grep -qE '^(feature|feat)/'; then
  WORKFLOW_TYPE="feature"
else
  # Check if feature directory exists
  if find_feature_dir "$FEATURE_NUM" "$REPO_ROOT" 2>/dev/null; then
    WORKFLOW_TYPE="feature"
  else
    # Ask user
    read -p "Is this a feature or bugfix? (feature/bugfix): " WORKFLOW_TYPE
  fi
fi

# Find feature directory (re-find since condition above may not have set it)
find_feature_dir "$FEATURE_NUM" "$REPO_ROOT" 2>/dev/null

if [ -z "$FEATURE_DIR" ]; then
  echo "⚠️  Warning: Feature directory not found for ${WORKFLOW_TYPE} ${FEATURE_NUM}"
  echo ""
  echo "Continuing without feature artifacts..."
  FEATURE_DIR=""
  STORED_PARENT_BRANCH=""
else
  # Get feature title from spec
  if [ -f "$FEATURE_DIR/spec.md" ]; then
    FEATURE_TITLE=$(grep -m1 '^# Feature' "$FEATURE_DIR/spec.md" | sed 's/^# Feature [0-9]*: //' || echo "Feature $FEATURE_NUM")

    # Extract parent branch from YAML frontmatter (v2.1.1+)
    STORED_PARENT_BRANCH=$(grep -A 10 '^---$' "$FEATURE_DIR/spec.md" 2>/dev/null | grep '^parent_branch:' | sed 's/^parent_branch: *//' | tr -d '\r' || echo "")
  else
    FEATURE_TITLE="Feature $FEATURE_NUM"
    STORED_PARENT_BRANCH=""
  fi
fi

# Display detected context
echo "Detected: $(echo "$WORKFLOW_TYPE" | sed 's/\b\(.\)/\u\1/') $FEATURE_NUM"
if [ -n "$FEATURE_TITLE" ]; then
  echo "Title: $FEATURE_TITLE"
fi
echo "Branch: $CURRENT_BRANCH"
if [ -n "$FEATURE_DIR" ]; then
  echo "Directory: $FEATURE_DIR"
fi
echo ""
```

---

### Step 1b: Detect Parent Branch Strategy

```bash
echo "🔍 Analyzing git workflow..."
echo ""

# Detect main branch name
MAIN_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
if [ -z "$MAIN_BRANCH" ]; then
  # Fallback: try common names or use git's default branch
  if git show-ref --verify --quiet refs/heads/main; then
    MAIN_BRANCH="main"
  elif git show-ref --verify --quiet refs/heads/master; then
    MAIN_BRANCH="master"
  else
    MAIN_BRANCH=$(git rev-parse --abbrev-ref HEAD)
    echo "⚠️  Warning: Could not detect main branch, using current branch: $MAIN_BRANCH"
  fi
fi

# Apply explicit --base override first (highest priority)
if [ -n "$BASE_BRANCH_OVERRIDE" ]; then
  PARENT_BRANCH="$BASE_BRANCH_OVERRIDE"
  echo "✓ Using --base override: $PARENT_BRANCH"
  echo ""
  SEQUENTIAL_BRANCH=false
else
  # Detect if we're in a sequential upgrade branch workflow
  SEQUENTIAL_BRANCH=false
  PARENT_BRANCH="$MAIN_BRANCH"

  if [ "$CURRENT_BRANCH" != "$MAIN_BRANCH" ]; then
    FEATURE_DIRS_ON_BRANCH=$(git log "$CURRENT_BRANCH" --not "$MAIN_BRANCH" --name-only --pretty=format: 2>/dev/null | \
                              grep -E '^(features/|\.specswarm/features/)[0-9]\{3\}-' | sed 's#^\.specswarm/##' | cut -d'/' -f2 | sort -u | wc -l || echo "0")

    if [ "$FEATURE_DIRS_ON_BRANCH" -gt 1 ]; then
      SEQUENTIAL_BRANCH=true
      PARENT_BRANCH="$CURRENT_BRANCH"
      echo "Detected: Sequential branch workflow"
      echo "  This branch contains $FEATURE_DIRS_ON_BRANCH features"
      echo "  Features will be marked complete without a PR"
      echo ""
    fi
  fi

  # If not sequential, determine parent branch from spec or fallback
  if [ "$SEQUENTIAL_BRANCH" = "false" ]; then
    echo "Determining PR target branch..."
    echo "  Stored parent branch: ${STORED_PARENT_BRANCH:-<empty>}"

    if [ -n "$STORED_PARENT_BRANCH" ] && [ "$STORED_PARENT_BRANCH" != "unknown" ]; then
      PARENT_BRANCH="$STORED_PARENT_BRANCH"
      echo "✓ Using parent branch from spec.md: $PARENT_BRANCH"
      echo ""
    else
      echo "⚠️  No valid parent branch in spec.md, checking fallback options..."
      PREV_FEATURE_NUM=$(printf "%03d" $((10#$FEATURE_NUM - 1)))
      PREV_FEATURE_BRANCH=$(git branch -a 2>/dev/null | grep -E "^  (remotes/origin/)?${PREV_FEATURE_NUM}-" | head -1 | sed 's/^[* ]*//' | sed 's/remotes\/origin\///' || echo "")

      if [ -n "$PREV_FEATURE_BRANCH" ] && git show-ref --verify --quiet "refs/heads/$PREV_FEATURE_BRANCH" 2>/dev/null; then
        echo "Found previous feature branch: $PREV_FEATURE_BRANCH"
        echo ""
        read -p "Target PR at $PREV_FEATURE_BRANCH instead of $MAIN_BRANCH? (y/n): " target_prev
        if [ "$target_prev" = "y" ]; then
          PARENT_BRANCH="$PREV_FEATURE_BRANCH"
          echo "✓ PR will target: $PARENT_BRANCH"
        else
          echo "✓ PR will target: $MAIN_BRANCH"
        fi
        echo ""
      else
        echo "✓ PR will target: $MAIN_BRANCH (default)"
        echo ""
      fi
    fi
  fi
fi
```

---

### Step 2: Cleanup Diagnostic Files

```bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 1: Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Patterns for diagnostic files
DIAGNOSTIC_PATTERNS=(
  "check-*.ts"
  "check-*.js"
  "check_*.ts"
  "check_*.js"
  "diagnose-*.ts"
  "diagnose-*.js"
  "debug-*.ts"
  "debug-*.js"
  "temp-*.ts"
  "temp-*.js"
)

# Find matching files
DIAGNOSTIC_FILES=()
for pattern in "${DIAGNOSTIC_PATTERNS[@]}"; do
  while IFS= read -r file; do
    if [ -f "$file" ]; then
      DIAGNOSTIC_FILES+=("$file")
    fi
  done < <(find "$REPO_ROOT" -maxdepth 1 -name "$pattern" 2>/dev/null)
done

if [ ${#DIAGNOSTIC_FILES[@]} -eq 0 ]; then
  echo "✓ No diagnostic files to clean up"
else
  echo "📂 Diagnostic Files Found:"
  for file in "${DIAGNOSTIC_FILES[@]}"; do
    basename_file=$(basename "$file")
    size=$(du -h "$file" 2>/dev/null | cut -f1 || echo "?")
    echo "  - $basename_file ($size)"
  done
  echo ""

  echo "What should I do with these files?"
  echo "  1. Delete all (recommended)"
  echo "  2. Move to .claude/debug/ (keep for review)"
  echo "  3. Keep as-is (will be committed if staged)"
  echo "  4. Manual selection"
  echo ""
  read -p "Choice (1-4): " cleanup_choice

  case $cleanup_choice in
    1)
      for file in "${DIAGNOSTIC_FILES[@]}"; do
        rm -f "$file"
      done
      echo "✓ Deleted ${#DIAGNOSTIC_FILES[@]} diagnostic files"
      ;;
    2)
      mkdir -p "$REPO_ROOT/.claude/debug"
      for file in "${DIAGNOSTIC_FILES[@]}"; do
        mv "$file" "$REPO_ROOT/.claude/debug/"
      done
      echo "✓ Moved ${#DIAGNOSTIC_FILES[@]} files to .claude/debug/"
      ;;
    3)
      echo "✓ Keeping diagnostic files"
      ;;
    4)
      for file in "${DIAGNOSTIC_FILES[@]}"; do
        read -p "Delete $(basename "$file")? (y/n): " delete_choice
        if [ "$delete_choice" = "y" ]; then
          rm -f "$file"
          echo "  ✓ Deleted"
        else
          echo "  ✓ Kept"
        fi
      done
      ;;
    *)
      echo "✓ Skipping cleanup"
      ;;
  esac
fi

echo ""
```

---

### Step 3: Pre-Merge Validation

```bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 2: Pre-Merge Validation"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Running validation checks..."
echo ""

VALIDATION_PASSED=true

# Check if package.json exists (indicates Node.js project)
if [ -f "package.json" ]; then
  # Run tests if test script exists
  if grep -q '"test"' package.json; then
    echo "  Running tests..."
    if npm test --silent 2>&1 | grep -qE "(passing|All tests passed)"; then
      TEST_OUTPUT=$(npm test --silent 2>&1 | grep -oE '[0-9]+ passing' | head -1)
      echo "  ✓ Tests passing ($TEST_OUTPUT)"
    else
      echo "  ⚠️  Some tests may have failed (check manually)"
    fi
  fi

  # TypeScript check if tsconfig.json exists
  if [ -f "tsconfig.json" ]; then
    echo "  Checking TypeScript..."
    if npx tsc --noEmit 2>&1 | grep -qE "error TS[0-9]+"; then
      echo "  ❌ TypeScript errors found"
      VALIDATION_PASSED=false
    else
      echo "  ✓ No TypeScript errors"
    fi
  fi

  # Build check if build script exists
  if grep -q '"build"' package.json; then
    echo "  Checking build..."
    if npm run build --silent 2>&1 | grep -qEi "(error|failed)"; then
      echo "  ⚠️  Build may have issues (check manually)"
    else
      echo "  ✓ Build successful"
    fi
  fi
fi

# Feature completion check
if [ -n "$FEATURE_DIR" ] && [ -f "$FEATURE_DIR/tasks.md" ]; then
  TOTAL_TASKS=$(grep -cE '^### T[0-9]{3}:' "$FEATURE_DIR/tasks.md" 2>/dev/null || echo "0")
  COMPLETED_TASKS=$(grep -cE '^### T[0-9]{3}:.*\[x\]' "$FEATURE_DIR/tasks.md" 2>/dev/null || echo "0")
  if [ "$TOTAL_TASKS" -gt "0" ]; then
    echo "  ✓ Feature progress ($COMPLETED_TASKS/$TOTAL_TASKS tasks)"
  fi
fi

# Bug resolution check
if [ -n "$FEATURE_DIR" ] && [ -f "$FEATURE_DIR/bugfix.md" ]; then
  BUG_COUNT=$(grep -cE '^## Bug [0-9]{3}:' "$FEATURE_DIR/bugfix.md" 2>/dev/null || echo "0")
  if [ "$BUG_COUNT" -gt "0" ]; then
    echo "  ✓ Bugs addressed ($BUG_COUNT bugs)"
  fi
fi

echo ""

if [ "$VALIDATION_PASSED" = "false" ]; then
  echo "⚠️  Validation issues detected"
  echo ""
  read -p "Continue anyway? (y/n): " continue_choice
  if [ "$continue_choice" != "y" ]; then
    echo "❌ Completion cancelled"
    echo ""
    echo "Fix the issues above and run /ss:complete again"
    exit 1
  fi
  echo ""
fi

echo "Ready to commit and merge!"
echo ""
```

---

### Step 4: Commit Changes

```bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 3: Commit Changes"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if there are changes to commit
if git diff --quiet && git diff --cached --quiet; then
  echo "✓ No changes to commit (working tree clean)"
  echo ""
  SKIP_COMMIT=true
else
  SKIP_COMMIT=false

  # Show files to be committed
  echo "Files to commit:"
  git status --short | head -20
  echo ""

  # Determine commit type
  if [ "$WORKFLOW_TYPE" = "bugfix" ]; then
    COMMIT_TYPE="fix"
  else
    COMMIT_TYPE="feat"
  fi

  # Generate commit message
  COMMIT_MSG="${COMMIT_TYPE}: ${FEATURE_TITLE}

"

  # Add description from spec if available
  if [ -n "$FEATURE_DIR" ] && [ -f "$FEATURE_DIR/spec.md" ]; then
    DESCRIPTION=$(grep -A 5 '^## Summary' "$FEATURE_DIR/spec.md" 2>/dev/null | tail -n +2 | head -3 | sed '/^$/d' || echo "")
    if [ -n "$DESCRIPTION" ]; then
      COMMIT_MSG+="${DESCRIPTION}

"
    fi
  fi

  # Add bug fixes if any
  if [ -n "$FEATURE_DIR" ] && [ -f "$FEATURE_DIR/bugfix.md" ]; then
    BUG_NUMBERS=$(grep -oE 'Bug [0-9]{3}' "$FEATURE_DIR/bugfix.md" 2>/dev/null | grep -oE '[0-9]{3}' | sort -u || echo "")
    if [ -n "$BUG_NUMBERS" ]; then
      COMMIT_MSG+="Fixes:
"
      while IFS= read -r bug; do
        COMMIT_MSG+="- Bug $bug
"
      done <<< "$BUG_NUMBERS"
      COMMIT_MSG+="
"
    fi
  fi

  # Add generated footer
  COMMIT_MSG+="🤖 Generated with SpecSwarm

Co-Authored-By: Claude <noreply@anthropic.com>"

  # Show commit message
  echo "Suggested commit message:"
  echo "┌────────────────────────────────────────────┐"
  echo "$COMMIT_MSG" | sed 's/^/│ /'
  echo "└────────────────────────────────────────────┘"
  echo ""

  read -p "Edit commit message? (y/n): " edit_choice

  if [ "$edit_choice" = "y" ]; then
    # Create temp file for editing
    TEMP_MSG_FILE=$(mktemp)
    echo "$COMMIT_MSG" > "$TEMP_MSG_FILE"
    ${EDITOR:-nano} "$TEMP_MSG_FILE"
    COMMIT_MSG=$(cat "$TEMP_MSG_FILE")
    rm -f "$TEMP_MSG_FILE"
  fi

  # Stage all changes
  git add -A

  # Commit
  echo "$COMMIT_MSG" | git commit -F -
  echo "✓ Changes committed to feature branch"
  echo ""
fi

# Always push feature branch to remote so a PR can be opened
echo "Pushing branch to remote..."
if git push -u origin "$CURRENT_BRANCH" 2>&1; then
  echo "✓ Pushed $CURRENT_BRANCH to origin"
else
  echo "❌ Push failed — fix the issue above and re-run /ss:complete"
  exit 1
fi
echo ""
```

---

### Step 5: Open Pull Request

```bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 4: Open Pull Request"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

PR_URL=""

# Skip PR for sequential branches — features are completed in-branch
if [ "$SEQUENTIAL_BRANCH" = "true" ]; then
  echo "✓ Sequential branch workflow — skipping PR"
  echo ""
  echo "This feature is part of a sequential upgrade branch."
  echo "All features will be submitted together via a single PR once the sequence completes."
  echo ""

  TAG_NAME="feature-${FEATURE_NUM}-complete"
  if ! git tag -l | grep -q "^${TAG_NAME}$"; then
    git tag "$TAG_NAME"
    echo "✓ Created completion tag: $TAG_NAME"
  fi
  echo ""
  SKIP_PR=true
elif [ "$CURRENT_BRANCH" = "$PARENT_BRANCH" ]; then
  echo "✓ Already on $PARENT_BRANCH — no PR needed"
  echo ""
  SKIP_PR=true
else
  SKIP_PR=false

  # Build PR body from spec artifacts
  PR_BODY="## Summary

$([ -n "$FEATURE_TITLE" ] && echo "**$(echo "$WORKFLOW_TYPE" | sed 's/\b\(.\)/\u\1/') $FEATURE_NUM:** $FEATURE_TITLE" || echo "$(echo "$WORKFLOW_TYPE" | sed 's/\b\(.\)/\u\1/') $FEATURE_NUM")
"

  if [ -n "$FEATURE_DIR" ] && [ -f "$FEATURE_DIR/spec.md" ]; then
    SPEC_SUMMARY=$(grep -A 5 '^## Summary' "$FEATURE_DIR/spec.md" 2>/dev/null | tail -n +2 | head -3 | sed '/^$/d' || echo "")
    if [ -n "$SPEC_SUMMARY" ]; then
      PR_BODY+="
${SPEC_SUMMARY}
"
    fi
  fi

  if [ -n "$FEATURE_DIR" ] && [ -f "$FEATURE_DIR/bugfix.md" ]; then
    BUG_NUMBERS=$(grep -oE 'Bug [0-9]{3}' "$FEATURE_DIR/bugfix.md" 2>/dev/null | sort -u || echo "")
    if [ -n "$BUG_NUMBERS" ]; then
      PR_BODY+="
## Fixes
"
      while IFS= read -r bug; do
        PR_BODY+="- $bug
"
      done <<< "$BUG_NUMBERS"
    fi
  fi

  if [ -n "$FEATURE_DIR" ] && [ -f "$FEATURE_DIR/tasks.md" ]; then
    TOTAL_TASKS=$(grep -cE '^### T[0-9]{3}:' "$FEATURE_DIR/tasks.md" 2>/dev/null || echo "0")
    COMPLETED_TASKS=$(grep -cE '^### T[0-9]{3}:.*\[x\]' "$FEATURE_DIR/tasks.md" 2>/dev/null || echo "0")
    if [ "$TOTAL_TASKS" -gt 0 ]; then
      PR_BODY+="
## Progress

$COMPLETED_TASKS / $TOTAL_TASKS tasks completed
"
    fi
  fi

  PR_BODY+="
---
🤖 Generated with SpecSwarm"

  PR_TITLE="$(echo "$WORKFLOW_TYPE" | sed 's/\b\(.\)/\u\1/'): ${FEATURE_TITLE:-Feature $FEATURE_NUM}"

  echo "PR Plan"
  echo "  Head branch : $CURRENT_BRANCH"
  echo "  Base branch : $PARENT_BRANCH"
  echo "  Title       : $PR_TITLE"
  if [ -n "$BASE_BRANCH_OVERRIDE" ]; then
    echo "  Base source : --base override"
  elif [ -n "$STORED_PARENT_BRANCH" ]; then
    echo "  Base source : spec.md parent_branch"
  else
    echo "  Base source : default branch"
  fi
  if [ "$PARENT_BRANCH" != "$MAIN_BRANCH" ]; then
    echo ""
    echo "ℹ️  Note: PR targets '$PARENT_BRANCH' (not $MAIN_BRANCH)"
    echo "   This is an intermediate PR in a feature branch hierarchy."
  fi
  echo ""

  read -p "Open PR? (y/n): " pr_choice

  if [ "$pr_choice" != "y" ]; then
    echo ""
    echo "❌ PR creation cancelled"
    echo ""
    echo "You're still on branch: $CURRENT_BRANCH (already pushed)"
    echo ""
    echo "When ready, open the PR manually:"
    echo "  gh pr create --base $PARENT_BRANCH --head $CURRENT_BRANCH"
    echo ""
    echo "Or re-run: /ss:complete"
    exit 0
  fi

  echo ""
  echo "Creating PR..."
  PR_URL=$(gh pr create \
    --base "$PARENT_BRANCH" \
    --head "$CURRENT_BRANCH" \
    --title "$PR_TITLE" \
    --body "$PR_BODY" 2>&1)

  if echo "$PR_URL" | grep -qE '^https?://'; then
    echo "✓ Pull request opened: $PR_URL"
  else
    echo "❌ gh pr create failed:"
    echo "$PR_URL"
    echo ""
    echo "Ensure 'gh' is installed and authenticated, then open the PR manually:"
    echo "  gh pr create --base $PARENT_BRANCH --head $CURRENT_BRANCH"
    exit 1
  fi

  echo ""
fi
```

---

### Step 6: Finalize

```bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 5: Finalize"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Mark feature status as In Review (PR open) or Complete (sequential)
if [ -n "$FEATURE_DIR" ] && [ -f "$FEATURE_DIR/spec.md" ]; then
  if [ "$SEQUENTIAL_BRANCH" = "true" ]; then
    sed -i 's/^Status:.*/Status: Complete/' "$FEATURE_DIR/spec.md" 2>/dev/null || true
    echo "✓ Updated feature status: Complete"
  else
    sed -i 's/^Status:.*/Status: In Review/' "$FEATURE_DIR/spec.md" 2>/dev/null || true
    echo "✓ Updated feature status: In Review"
  fi
fi

# Branch stays open until the PR is merged — no deletion here.
echo "✓ Feature branch '$CURRENT_BRANCH' kept open (will be deleted when PR merges)"

echo ""
```

---

## Final Output

```bash
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 $(echo "$WORKFLOW_TYPE" | sed 's/\b\(.\)/\u\1/') Submitted!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "$(echo "$WORKFLOW_TYPE" | sed 's/\b\(.\)/\u\1/') $FEATURE_NUM: ${FEATURE_TITLE:-<no title>}"
echo ""

if [ "${SKIP_COMMIT:-false}" = "false" ]; then
  echo "✓ Changes committed and pushed"
fi

if [ "$SEQUENTIAL_BRANCH" = "true" ]; then
  echo "✓ Feature marked complete (sequential workflow)"
  echo "✓ Tag created: feature-${FEATURE_NUM}-complete"
  echo ""
  echo "ℹ️  This is part of a sequential upgrade branch."
  echo "   Continue with remaining features, then open a PR for the entire branch."
elif [ "$SKIP_PR" = "false" ]; then
  echo "✓ Pull request opened against: $PARENT_BRANCH"
  if [ -n "$PR_URL" ]; then
    echo "  $PR_URL"
  fi
  if [ "$PARENT_BRANCH" != "$MAIN_BRANCH" ]; then
    echo "ℹ️  Note: This is an intermediate PR. Once merged, complete $PARENT_BRANCH next."
  fi
fi

if [ -n "$FEATURE_DIR" ]; then
  echo ""
  echo "📂 Feature artifacts: $FEATURE_DIR"
fi

echo ""
echo "🚀 Next Steps:"
if [ "$SEQUENTIAL_BRANCH" = "true" ]; then
  echo "  - Continue with next feature in sequence"
  echo "  - After all features complete, open a PR for the entire branch"
  echo "  - Test the complete upgrade sequence"
elif [ "$SKIP_PR" = "false" ]; then
  echo "  - Review and address any PR feedback"
  echo "  - Once the PR merges, the branch will be cleaned up by GitHub"
  if [ "$PARENT_BRANCH" != "$MAIN_BRANCH" ]; then
    echo "  - Complete the parent branch next: /ss:complete"
  fi
else
  echo "  - Branch is already up to date on $PARENT_BRANCH"
fi
echo ""
```

---

## Error Handling

**If not in git repository:**
- Exit with clear error message

**If validation fails:**
- Show issues
- Offer to continue anyway or cancel

**If push fails:**
- Exit with error; user must resolve (auth, diverged history) before retrying

**If `gh pr create` fails:**
- Show the error output and print the manual `gh pr create` command to run

---

## Operating Principles

1. **User Guidance**: Clear, step-by-step process with explanations
2. **Safety First**: Confirm before destructive operations (merge, delete)
3. **Flexibility**: Allow skipping steps or customizing behavior
4. **Cleanup**: Remove temporary files, update documentation
5. **Validation**: Check tests, build, TypeScript before merging
6. **Transparency**: Show what's being done at each step

---

## Success Criteria

✅ Diagnostic files cleaned up
✅ Pre-merge validation passed (or user acknowledged issues)
✅ Changes committed with proper message
✅ Feature branch pushed to remote
✅ Pull request opened against parent branch (or `--base` override)
✅ Feature status updated to In Review

---

**Workflow Coverage**: Completes ~100% of feature/bugfix lifecycle through PR submission
**User Experience**: Guided, safe, transparent completion process
