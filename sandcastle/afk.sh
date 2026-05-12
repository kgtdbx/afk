#!/bin/bash
set -eo pipefail

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations> [options...]"
  echo "  iterations:  max number of iterations to run"
  echo ""
  echo "Options (all repeatable, can be mixed):"
  echo "  --agent NAME  agent to use: claude (default), codex"
  echo "  --issue N     work on a specific GitHub issue"
  echo "  --file FILE   include a markdown file (plan, PRD, etc.)"
  echo ""
  echo "Examples:"
  echo "  $0 5                                                    # all open issues"
  echo "  $0 3 --issue 1 --issue 2                                # two specific issues"
  echo "  $0 3 --file plans/plan.md --file plans/prd.md           # plan + PRD"
  echo "  $0 5 --issue 1 --file plans/prd.md --issue 12 --file plans/prd2.md"
  exit 1
fi

MAX_ITER="$1"
shift

# Parse optional flags (all repeatable, any order)
AGENT="claude"
ISSUES=()
FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2 ;;
    --issue) ISSUES+=("$2"); shift 2 ;;
    --file) FILES+=("$2"); shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

GH_REPO=$(git remote get-url origin | sed 's|.*github.com/||;s|\.git$||')

# Build input based on what was passed
inputs=""

for num in "${ISSUES[@]}"; do
  issue_data=$(gh issue view "$num" --repo "$GH_REPO" --json number,title,body --jq '"#\(.number): \(.title)\n\(.body)"')
  inputs+="$issue_data"$'\n\n'
  echo "Added issue #$num from $GH_REPO"
done

for file in "${FILES[@]}"; do
  if [ ! -f "$file" ]; then
    echo "Error: file not found: $file"
    exit 1
  fi
  inputs+="$(cat "$file")"$'\n\n'
  echo "Added file: $file"
done

# Default: fetch all open issue titles
if [ ${#ISSUES[@]} -eq 0 ] && [ ${#FILES[@]} -eq 0 ]; then
  inputs=$(gh issue list --state open --repo "$GH_REPO" --json number,title --jq '.[] | "#\(.number): \(.title)"')
  echo "Open issues on $GH_REPO:"
  echo "$inputs"
fi

# Sandcastle expects to run from the project root
PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_DIR"

# Copy prompt.md so sandcastle-prompt.md can find it at ralph/prompt.md
cp "$(dirname "$0")/prompt.md" ralph/prompt.md 2>/dev/null || true

npx tsx ./.sandcastle/main.ts "$inputs" "$MAX_ITER" "$AGENT" 2>&1 | grep -v "chown.*Permission denied"
