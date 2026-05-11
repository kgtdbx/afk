# Line-by-Line Walkthrough: `ralph/afk.sh`

## The Full Script (with annotations)

```bash
#!/bin/bash                          # 1. Use bash to run this script
set -eo pipefail                     # 2. Exit on ANY error. Pipe failures count too.
```

`set -e` = if any command fails, stop the whole script.
`set -o pipefail` = if any command in a pipe (`cmd1 | cmd2`) fails, the whole pipe fails.

```bash
if [ -z "$1" ]; then                 # 3. If no arguments given...
  echo "Usage: $0 <iterations> ..."  # 4-17. Print help text and exit
  exit 1
fi
```

Guards against running `./afk.sh` with no arguments.

```bash
MAX_ITER="$1"                        # 20. Save first arg as max iterations
shift                                # 21. Remove it from the arg list
```

After `shift`, `$1` now points to whatever came after the number.

```bash
ISSUES=()                            # 24. Empty array for issue numbers
FILES=()                             # 25. Empty array for file paths
while [[ $# -gt 0 ]]; do            # 26. While there are still args...
  case "$1" in
    --issue) ISSUES+=("$2"); shift 2 ;;   # 28. Add issue num, skip 2 args
    --file) FILES+=("$2"); shift 2 ;;     # 29. Add file path, skip 2 args
    *) echo "Unknown option: $1"; exit 1 ;; # 30. Anything else = error
  esac
done
```

This parses `--issue 3 --file plan.md --issue 7` into:
```
ISSUES = (3, 7)
FILES  = (plan.md)
```

```bash
IMAGE="ralph-runner"                 # 34. Docker image name
AUTH_FILE="$HOME/.claude_auth.txt"   # 35. Where the Claude OAuth token lives
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"  # 36. Absolute path to this script's folder
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)" # 37. Two levels up = project root
GH_REPO=$(git remote get-url origin | sed 's|.*github.com/||;s|\.git$||')  # 38. Extract "owner/repo"
```

Line 38 example:
```
git remote get-url origin
  --> https://github.com/kgtdbx/cohort-003-project-kgt.git

sed removes "https://github.com/" prefix and ".git" suffix
  --> kgtdbx/cohort-003-project-kgt
```

```bash
if [ ! -f "$AUTH_FILE" ]; then       # 41. If auth file doesn't exist...
  echo "Error: OAuth token not found..."  # 42-45. Print instructions
  exit 1                             # 46. Abort
fi
```

Claude Code needs an OAuth token to authenticate. This checks for it.

```bash
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then  # 49. If Docker image doesn't exist...
  echo "Docker image '$IMAGE' not found. Building..."      # 50.
  docker build -t "$IMAGE" -f "$PROJECT_DIR/Dockerfile.ralph" "$PROJECT_DIR"  # 51. Build it
fi
```

Auto-builds the Docker image on first run.

```bash
stream_filter='select(.type == "assistant")...'   # 55. jq filter for streaming output
final_result='select(.type == "result")...'       # 56. jq filter for final result
```

These are **jq** filters (JSON query language). Claude outputs JSON when using
`--output-format stream-json`. These filters extract:
- `stream_filter`: The assistant's text and tool calls (for live display)
- `final_result`: The final result string (to check for NO MORE TASKS)

```bash
inputs=""                            # 58. Start with empty inputs string

for num in "${ISSUES[@]}"; do        # 60. For each --issue number...
  issue_data=$(gh issue view "$num" --repo "$GH_REPO" \
    --json number,title,body \
    --jq '"#\(.number): \(.title)\n\(.body)"')  # 61. Fetch full issue from GitHub
  inputs+="$issue_data"$'\n\n'       # 62. Append to inputs string
  echo "Added issue #$num..."        # 63.
done
```

If you said `--issue 3`, this fetches issue #3's title and body from GitHub
and adds it to the prompt.

```bash
for file in "${FILES[@]}"; do        # 66. For each --file path...
  if [ ! -f "$file" ]; then          # 67. If file doesn't exist...
    echo "Error: file not found: $file"
    exit 1
  fi
  inputs+="$(cat "$file")"$'\n\n'    # 71. Read file contents into inputs
  echo "Added file: $file"           # 72.
done
```

If you said `--file plans/plan.md`, this reads the file and appends its
contents to the prompt.

```bash
if [ ${#ISSUES[@]} -eq 0 ] && [ ${#FILES[@]} -eq 0 ]; then  # 76. No --issue or --file given?
  inputs=$(gh issue list --state open --repo "$GH_REPO" \
    --json number,title \
    --jq '.[] | "#\(.number): \(.title)"')  # 77. Fetch ALL open issue titles
  echo "Open issues on $GH_REPO:"    # 78.
  echo "$inputs"                     # 79.
fi
```

Default behavior: list all open issues (titles only, not full bodies).

```bash
for ((i=1; i<=$MAX_ITER; i++)); do   # 83. === THE MAIN LOOP ===
  echo "=== Ralph iteration $i of $MAX_ITER ==="  # 84.

  tmpfile=$(mktemp)                  # 86. Create temp file for output
  trap "rm -f $tmpfile" EXIT         # 87. Delete temp file when script exits

  commits=$(git log -n 5 --format="%H%n%ad%n%B---" --date=short 2>/dev/null \
    || echo "No commits found")      # 89. Get last 5 commits
  prompt=$(cat "$SCRIPT_DIR/prompt.md")  # 90. Read the prompt template

  RALPH_PROMPT="Previous commits: $commits Inputs: $inputs $prompt"  # 92. Assemble full prompt
```

Every iteration re-reads the last 5 commits (which change as Ralph commits).
The prompt is assembled from three parts:

```
+-------------------------------------------+
|  RALPH_PROMPT =                           |
|                                           |
|  "Previous commits: abc123 ..."           |
|  +                                        |
|  "Inputs: #1: Add XP system ..."          |
|  +                                        |
|  "Pick ONE issue. Implement it. ..."      |
+-------------------------------------------+
```

```bash
  docker run --rm \                  # 94. Start container, destroy when done
    -v "$PROJECT_DIR":/workspace \   # 95. Mount project files into container
    -v ralph_node_modules:/workspace/node_modules \  # 96. Persistent node_modules volume
    -e CLAUDE_CODE_OAUTH_TOKEN="$(cat "$AUTH_FILE")" \  # 97. Pass auth token
    -e GH_TOKEN="$(gh auth token)" \  # 98. Pass GitHub token
    -e GH_REPO="$GH_REPO" \         # 99. Pass repo name
    -e RALPH_PROMPT="$RALPH_PROMPT" \ # 100. Pass the assembled prompt
    "$IMAGE" \                       # 101. Use the ralph-runner image
    bash -c 'pnpm install --frozen-lockfile 2>/dev/null; claude \
      --dangerously-skip-permissions \  # Allows Claude to run tools without asking
      --verbose \                       # Extra output for debugging
      --print \                         # One-shot mode: respond once, then exit
      --output-format stream-json \     # Output as JSON stream
      "$RALPH_PROMPT"' \             # The prompt to send to Claude
  | grep --line-buffered '^{' \      # 108. Keep only JSON lines (filter noise)
  | tee "$tmpfile" \                 # 109. Save to temp file AND...
  | jq --unbuffered -rj "$stream_filter"  # 110. ...stream formatted output to terminal
```

This is the big one. Let's break down the docker flags:

```
  -v "$PROJECT_DIR":/workspace
  =============================
  "Bind mount" = your Mac's project folder appears inside the container
  at /workspace. Changes Claude makes inside /workspace are INSTANTLY
  visible on your Mac (and vice versa). It's the SAME files, not a copy.

  -v ralph_node_modules:/workspace/node_modules
  ================================================
  "Named volume" = a separate Docker-managed folder for node_modules.
  This prevents Linux binaries from overwriting your Mac's node_modules.

  --rm
  ====
  Destroy the container after the command finishes.
  Next iteration will create a brand new container.
```

```bash
  result=$(jq -r "$final_result" "$tmpfile")  # 112. Extract final result from saved JSON

  if [[ "$result" == *"<promise>NO MORE TASKS</promise>"* ]]; then  # 114.
    echo "Ralph complete after $i iterations."  # 115.
    exit 0                           # 116. Stop the loop entirely
  fi
done                                 # 118. End of for loop

echo "Ralph reached max iterations ($MAX_ITER)."  # 120. Ran out of iterations
```

After Claude finishes, check if it said "NO MORE TASKS". If so, stop.
Otherwise, loop back for another iteration.

---

## Visual: The Prompt Assembly Pipeline

```
  +------------------+     +------------------+     +-----------------+
  |  git log -n 5    |     |  gh issue list   |     |   prompt.md     |
  |                  |     |  OR               |     |                 |
  |  Last 5 commits  |     |  --issue bodies   |     |  Instructions:  |
  |  (hashes, dates, |     |  --file contents  |     |  "Pick ONE..."  |
  |   messages)      |     |                  |     |  "Implement..."  |
  +--------+---------+     +--------+---------+     +--------+--------+
           |                        |                         |
           v                        v                         v
      +----+------------------------+-------------------------+----+
      |                    RALPH_PROMPT                             |
      |                                                            |
      |  "Previous commits: abc123 2026-05-09 Fixed XP..."        |
      |  "Inputs: #1: Add XP system  #2: Streaks ..."            |
      |  "Pick ONE issue to work on. Prioritize: 1. Bugfixes..." |
      +----------------------------+-------------------------------+
                                   |
                                   v
                          claude --print "$RALPH_PROMPT"
```
