#!/bin/bash
# Assemble the AFK iteration prompt: last-5 commits + issue/file inputs + prompt.md.
# Prints to stdout. Pure data gathering — no agent dispatch, no docker, no auth file.
#
# Usage: build-prompt.sh [--issue N]... [--file FILE]...
#   No args -> list all open issue titles.
#
# prompt.md resolution: $AFK_PROMPT_MD, else <repo>/afk/ralph/prompt.md, else <repo>/ralph/prompt.md.

set -eo pipefail

ISSUES=()
FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --issue) ISSUES+=("$2"); shift 2 ;;
    --file)  FILES+=("$2");  shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel)"
GH_REPO="$(git remote get-url origin | sed 's|.*github\.com[:/]||;s|\.git$||')"

PROMPT_MD="${AFK_PROMPT_MD:-}"
if [[ -z "$PROMPT_MD" ]]; then
  if   [[ -f "$REPO_ROOT/afk/ralph/prompt.md" ]]; then PROMPT_MD="$REPO_ROOT/afk/ralph/prompt.md"
  elif [[ -f "$REPO_ROOT/ralph/prompt.md"     ]]; then PROMPT_MD="$REPO_ROOT/ralph/prompt.md"
  else echo "prompt.md not found (set AFK_PROMPT_MD)" >&2; exit 1
  fi
fi

inputs=""
for num in "${ISSUES[@]}"; do
  inputs+="$(gh issue view "$num" --repo "$GH_REPO" --json number,title,body --jq '"#\(.number): \(.title)\n\(.body)"')"
  inputs+=$'\n\n'
done
for file in "${FILES[@]}"; do
  [[ -f "$file" ]] || { echo "missing file: $file" >&2; exit 1; }
  inputs+="$(cat "$file")"
  inputs+=$'\n\n'
done
if [ ${#ISSUES[@]} -eq 0 ] && [ ${#FILES[@]} -eq 0 ]; then
  inputs="$(gh issue list --state open --repo "$GH_REPO" --json number,title --jq '.[] | "#\(.number): \(.title)"')"
fi

commits="$(git log -n 5 --format='%H%n%ad%n%B---' --date=short 2>/dev/null || echo 'No commits')"

cat <<EOF
GH_REPO=$GH_REPO
REPO_ROOT=$REPO_ROOT
PROMPT_MD=$PROMPT_MD

# Previous commits

$commits

# Inputs

$inputs

# Prompt (from $PROMPT_MD)

$(cat "$PROMPT_MD")
EOF
