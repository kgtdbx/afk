---
name: afk
description: Run one Ralph-style autonomous iteration on GitHub issues / plan files inside the current Claude Code session. In-session port of ralph/afk.sh — drops Docker, claude --print, codex exec, auth tokens, and the MAX_ITER outer loop, so there is no per-token API cost. Args mirror the original: --issue N (repeatable), --file FILE (repeatable). When the prompt.md's completion criteria are met, emit `<promise>NO MORE TASKS</promise>` so /loop stops. Use when the user types /afk, says "run afk on issue N", or asks to drive ralph/sandcastle issues from this session.
---

# AFK — autonomous iteration in this session

In-session port of `ralph/afk.sh`. Each `/afk` invocation = ONE iteration. Use `/loop /afk …` to drive multiple iterations (self-paced; stops when you emit the sentinel).

## Arguments (mirror the original)

- `--issue N` (repeatable) — GitHub issue numbers
- `--file FILE` (repeatable) — plan / PRD / spec markdown files
- No args → ingest all open issue titles

## Steps for each iteration

1. **Build the prompt.** Run, exactly:
   ```bash
   "$CLAUDE_PROJECT_DIR/.claude/skills/afk/build-prompt.sh" <user-supplied args>
   ```
   (If `$CLAUDE_PROJECT_DIR` isn't set, fall back to `./.claude/skills/afk/build-prompt.sh` from the repo root.)
   Output's first three lines are `GH_REPO=…`, `REPO_ROOT=…`, `PROMPT_MD=…`. **Export `GH_REPO`** in this session before any `gh` call — every `gh` invocation must use `--repo "$GH_REPO"` (the bundled `prompt.md` enforces this).

2. **Do the work.** Treat everything after that header as your instructions for this iteration. Use Read/Edit/Write/Bash normally. Follow `prompt.md` to the letter — in particular:
   - Pick exactly ONE issue per iteration; do not touch unrelated code.
   - Run `pnpm run test` and `pnpm run typecheck` before committing.
   - **Never** `git commit --no-verify`.
   - Commit message references the issue (`Fixes #N` / `Progress on #N`).
   - Comment on the issue (incomplete) or close it (complete) with `gh issue …`.

3. **Log the iteration.** Append one line to `$REPO_ROOT/afk/logs/$(git rev-parse --abbrev-ref HEAD).log` (create the dir if missing):
   ```
   <ISO-8601 UTC> | <branch> | issue #N | <one-line status>
   ```

4. **Stop signal.** If — and only if — the prompt.md's completion criteria are met (nothing actionable left in scope), end your final reply with the literal token `<promise>NO MORE TASKS</promise>` on its own line. `/loop` watches for this. If there's more to do, do not emit it.

## What's intentionally dropped vs upstream `afk.sh`

- Docker, `ralph-runner` image, `Dockerfile.ralph`, `pnpm install` step inside container
- `CLAUDE_CODE_OAUTH_TOKEN` / `CODEX_AUTH_JSON` auth files
- `--agent codex` branch (Claude session only; add a separate skill if codex parity needed)
- `MAX_ITER` — `/loop` owns iteration count

## What's preserved

- `prompt.md` read verbatim (resolution order: `$AFK_PROMPT_MD` → `<repo>/afk/ralph/prompt.md` → `<repo>/ralph/prompt.md`)
- Last-5-commits header + gh issue/file ingestion
- `<promise>NO MORE TASKS</promise>` sentinel
- Per-branch log at `<repo>/afk/logs/<branch>.log`

## Failure modes

- Not in a git repo, or no `origin` remote → `build-prompt.sh` exits non-zero; surface the error.
- `prompt.md` missing → set `AFK_PROMPT_MD=…` or add `afk/ralph/prompt.md` to the repo.
- `gh` not authed → run `gh auth status`; do not store tokens in files.
