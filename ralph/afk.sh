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
  echo "  $0 5                                                    # all open issues (claude)"
  echo "  $0 5 --agent codex                                      # use Codex instead"
  echo "  $0 3 --agent codex --issue 1 --issue 2                  # Codex + specific issues"
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

# ---- Agent configuration ----
case "$AGENT" in
  claude)
    AUTH_VAR="CLAUDE_CODE_OAUTH_TOKEN"
    AUTH_FILE="$HOME/.claude_auth.txt"
    AUTH_SETUP="Run: claude setup-token && echo \"your-token\" > $HOME/.claude_auth.txt"
    ;;
  codex)
    AUTH_VAR="CODEX_AUTH_JSON"
    AUTH_FILE="$HOME/.codex/auth.json"
    AUTH_SETUP="Run: codex login"
    ;;
  *)
    echo "Unknown agent: $AGENT"
    echo "Supported: claude, codex"
    exit 1
    ;;
esac

IMAGE="ralph-runner"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
GH_REPO=$(git remote get-url origin | sed 's|.*github.com/||;s|\.git$||')

# ---- Logging (tee all output to log file) ----
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
LOG_DIR="$PROJECT_DIR/ralph/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/${BRANCH}.log"
echo "--- Run started: $(date -u +%Y-%m-%dT%H:%M:%SZ) ---" >> "$LOG_FILE"
echo "Agent: $AGENT | Branch: $BRANCH | Max iterations: $MAX_ITER" >> "$LOG_FILE"
echo "Logging to: $LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# Validate auth
if [ ! -f "$AUTH_FILE" ]; then
  echo "Error: Auth token not found at $AUTH_FILE"
  echo "$AUTH_SETUP"
  exit 1
fi

# Check Docker image exists
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Docker image '$IMAGE' not found. Building..."
  docker build -t "$IMAGE" -f "$SCRIPT_DIR/Dockerfile.ralph" "$PROJECT_DIR"
fi

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

# ---- Agent-specific run + parse functions ----

run_claude() {
  local prompt="$1"
  local tmpfile="$2"

  local stream_filter='select(.type == "assistant").message.content[]? | if .type == "text" then .text // empty | gsub("\n"; "\r\n") | . + "\r\n\n" elif .type == "tool_use" then "\(.name)(\(.input.command // .input.file_path // .input.query // "" | .[0:100]))\r\n" else empty end'
  local final_result='select(.type == "result").result // empty'

  docker run --rm \
    -v "$PROJECT_DIR":/workspace \
    -v ralph_node_modules:/workspace/node_modules \
    -e CLAUDE_CODE_OAUTH_TOKEN="$(cat "$AUTH_FILE")" \
    -e GH_TOKEN="$(gh auth token)" \
    -e GH_REPO="$GH_REPO" \
    -e AFK_PROMPT="$prompt" \
    "$IMAGE" \
    bash -c 'pnpm install --frozen-lockfile 2>/dev/null; claude \
      --dangerously-skip-permissions \
      --verbose \
      --print \
      --model claude-opus-4-6 \
      --output-format stream-json \
      "$AFK_PROMPT"' \
  | grep --line-buffered '^{' \
  | tee "$tmpfile" \
  | jq --unbuffered -rj "$stream_filter"

  local result
  result=$(jq -r "$final_result" "$tmpfile")
  [[ "$result" == *"<promise>NO MORE TASKS</promise>"* ]]
}

run_codex() {
  local prompt="$1"
  local tmpfile="$2"

  docker run --rm \
    -v "$PROJECT_DIR":/workspace \
    -v ralph_node_modules:/workspace/node_modules \
    -v "$HOME/.codex":/home/ralph/.codex \
    -e GH_TOKEN="$(gh auth token)" \
    -e GH_REPO="$GH_REPO" \
    -e AFK_PROMPT="$prompt" \
    "$IMAGE" \
    bash -c 'pnpm install --frozen-lockfile 2>/dev/null; codex exec \
      -s danger-full-access \
      -o /tmp/result.txt \
      "$AFK_PROMPT"; cat /tmp/result.txt' \
  | tee "$tmpfile"

  grep -q "<promise>NO MORE TASKS</promise>" "$tmpfile"
}

# ---- Main loop ----

for ((i=1; i<=$MAX_ITER; i++)); do
  echo "=== $AGENT iteration $i of $MAX_ITER ==="

  tmpfile=$(mktemp)
  trap "rm -f $tmpfile" EXIT

  commits=$(git log -n 5 --format="%H%n%ad%n%B---" --date=short 2>/dev/null || echo "No commits found")
  prompt=$(cat "$SCRIPT_DIR/prompt.md")

  AFK_PROMPT="Previous commits: $commits Inputs: $inputs $prompt"

  if "run_$AGENT" "$AFK_PROMPT" "$tmpfile"; then
    echo "$AGENT complete after $i iterations."
    exit 0
  fi
done

echo "$AGENT reached max iterations ($MAX_ITER)."
