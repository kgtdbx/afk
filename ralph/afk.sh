#!/bin/bash
set -eo pipefail

if [ -z "$1" ]; then
  echo "Usage: $0 <iterations> [options...]"
  echo "  iterations:  max number of iterations to run"
  echo ""
  echo "Options (all repeatable, can be mixed):"
  echo "  --issue N    work on a specific GitHub issue"
  echo "  --file FILE  include a markdown file (plan, PRD, etc.)"
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
ISSUES=()
FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue) ISSUES+=("$2"); shift 2 ;;
    --file) FILES+=("$2"); shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

IMAGE="ralph-runner"
AUTH_FILE="$HOME/.claude_auth.txt"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
GH_REPO=$(git remote get-url origin | sed 's|.*github.com/||;s|\.git$||')

# Validate auth
if [ ! -f "$AUTH_FILE" ]; then
  echo "Error: OAuth token not found at $AUTH_FILE"
  echo "Run: claude setup-token"
  echo "Then: echo \"your-token\" > $AUTH_FILE"
  exit 1
fi

# Check Docker image exists
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Docker image '$IMAGE' not found. Building..."
  docker build -t "$IMAGE" -f "$PROJECT_DIR/Dockerfile.ralph" "$PROJECT_DIR"
fi

# jq filters
stream_filter='select(.type == "assistant").message.content[]? | if .type == "text" then .text // empty | gsub("\n"; "\r\n") | . + "\r\n\n" elif .type == "tool_use" then "\(.name)(\(.input.command // .input.file_path // .input.query // "" | .[0:100]))\r\n" else empty end'
final_result='select(.type == "result").result // empty'

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

for ((i=1; i<=$MAX_ITER; i++)); do
  echo "=== Ralph iteration $i of $MAX_ITER ==="

  tmpfile=$(mktemp)
  trap "rm -f $tmpfile" EXIT

  commits=$(git log -n 5 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No commits found")
  prompt=$(cat "$SCRIPT_DIR/prompt.md")

  RALPH_PROMPT="Previous commits: $commits Inputs: $inputs $prompt"

  docker run --rm \
    -v "$PROJECT_DIR":/workspace \
    -v ralph_node_modules:/workspace/node_modules \
    -e CLAUDE_CODE_OAUTH_TOKEN="$(cat "$AUTH_FILE")" \
    -e GH_TOKEN="$(gh auth token)" \
    -e GH_REPO="$GH_REPO" \
    -e RALPH_PROMPT="$RALPH_PROMPT" \
    "$IMAGE" \
    bash -c 'pnpm install --frozen-lockfile 2>/dev/null; claude \
      --dangerously-skip-permissions \
      --verbose \
      --print \
      --output-format stream-json \
      "$RALPH_PROMPT"' \
  | grep --line-buffered '^{' \
  | tee "$tmpfile" \
  | jq --unbuffered -rj "$stream_filter"

  result=$(jq -r "$final_result" "$tmpfile")

  if [[ "$result" == *"<promise>NO MORE TASKS</promise>"* ]]; then
    echo "Ralph complete after $i iterations."
    exit 0
  fi
done

echo "Ralph reached max iterations ($MAX_ITER)."
