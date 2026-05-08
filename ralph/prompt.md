# ISSUES

You've been passed a list of open GitHub issue titles and numbers. You've also been passed the last few commits.

To read the full details of an issue, run:

```
gh issue view <number> --repo "$GH_REPO"
```

The `GH_REPO` environment variable is set to the correct repository. ALWAYS use `--repo "$GH_REPO"` with ALL `gh` commands.

If all tasks are complete, output <promise>NO MORE TASKS</promise>.

# TASK SELECTION

Pick ONE issue to work on. Prioritize in this order:

1. Critical bugfixes
2. Development infrastructure

Getting development infrastructure like tests and types and dev scripts ready is an important precursor to building features.

3. Tracer bullets for new features

Tracer bullets are small slices of functionality that go through all layers of the system, allowing you to test and validate your approach early. This helps in identifying potential issues and ensures that the overall architecture is sound before investing significant time in development.

TL;DR - build a tiny, end-to-end slice of the feature first, then expand it out.

4. Polish and quick wins
5. Refactors

Once you pick an issue, fetch its full body with `gh issue view`, then implement it.

# EXPLORATION

Explore the repo to understand existing patterns. Focus on files relevant to your issue.

# IMPLEMENTATION

Implement what the issue describes. Nothing more, nothing less.
Do NOT fix unrelated code, even if it has errors.

# FEEDBACK LOOPS

Before committing, run the feedback loops:

- `pnpm run test` to run the tests
- `pnpm run typecheck` to run the type checker

If they fail on YOUR changes, fix them. If they fail on pre-existing unrelated code, proceed with the commit.

Do NOT skip pre-commit hooks with --no-verify.

# COMMIT

Make a git commit. The commit message must:

1. Reference the issue number (e.g. "Fixes #1" or "Progress on #1")
2. Include key decisions made
3. Include files changed
4. Blockers or notes for next iteration

Do NOT use --no-verify.

# GITHUB

If the task is complete, close the issue:

```
gh issue close <number> --repo "$GH_REPO" --comment "Completed. <brief summary>"
```

If the task is not complete, leave a comment:

```
gh issue comment <number> --repo "$GH_REPO" --body "<what was done and what remains>"
```

# FINAL RULES

ONLY WORK ON A SINGLE TASK.
ONLY implement what the chosen GitHub issue describes.
NEVER fix unrelated code.
NEVER use git commit --no-verify.
ALWAYS use --repo "$GH_REPO" with gh commands.
