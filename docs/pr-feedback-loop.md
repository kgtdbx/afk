# PR Feedback Loop (design)

A label-driven feedback loop on top of any AFK runtime (Ralph, Sandcastle, or the Claude Desktop in-session skill). The agent opens a PR, you review it, you tag it with `agent-revise`, the agent addresses your feedback, pushes, retags, and waits for re-review. Loops until you merge.

This is **not implemented yet** — it's a blueprint for what to build. The pieces map cleanly onto the existing AFK tooling (same Docker container, same `build-prompt.sh` shape, same `<promise>NO MORE TASKS</promise>` sentinel) so most of the work is a second `prompt.md` and a `--mode revise` flag.

## ELI5

Imagine you run a restaurant kitchen, but you've hired a robot cook.

- You write order tickets: "Table 5 wants spaghetti carbonara."
  → That's a **GitHub issue**.

- The robot cooks the dish at its own little prep station, not on your main service line.
  → That's a **branch**.

- When the dish is ready, the robot puts it on the pass with a "READY FOR INSPECTION" flag.
  → That's a **pull request**, with the `pending-review` label.

- You walk over and taste it.
  → That's the **review**.

  - If it's good, you send it to the customer.
    → You **merge** the PR.

  - If the salt's off, you tell the robot: "add salt, retry."
    → You add the `agent-revise` label and leave a comment.

- The robot picks up its dish from the pass, fixes it, puts it back with a "READY FOR RE-INSPECTION" flag.
  → That's the **revise pass**, ending in the `awaiting-review` label.

- You re-taste, send it.
  → You merge.

The order ticket exists so anyone can see what's been requested. The pass exists so nothing reaches the customer without you tasting it. The two labels (`agent-revise` and `awaiting-review`) are the kitchen's universal way of saying "needs your attention" vs "needs robot's attention," so neither of you wastes time staring at a dish that's not your move.

That's the entire feedback loop.

### What if you want to cook multiple orders at once?

Now imagine you've got 5 tables waiting and the robot can clone itself. You don't want all the clones cooking at the same prep counter — they'd fight over the same chopping board, the same olive oil, the same station.

So you set up extra prep counters in the kitchen. Each counter has its own chopping board, its own bottle of olive oil, its own pan. They all share the same pantry and walk-in (ingredients and recipes are the same), but each clone gets its own surface to work on.
  → That's a **git worktree** — another working directory backed by the same git repo, but on a different branch. Each clone-robot cooks at its own counter without bumping into the others.

Five orders → five counters → five PRs on the pass to taste, all roughly at the same time. Same kitchen, same pantry, same head chef tasting. Just more counter space.

You only need extra counters when you want to cook in parallel. If you're fine cooking one order at a time on the main counter, skip the extras — they're just setup overhead for parallelism you don't need.

## Background: issues, pull requests, and why both

Skip this if you live on GitHub. Read it if "issue" and "pull request" feel like the same thing to you.

### What is a GitHub issue?

A ticket. A short written description of something that needs to happen — a bug to fix, a feature to add, a question to discuss. It has:

- A title and body (markdown text)
- A number (`#42`) so people can refer to it
- A status (open / closed)
- Labels (e.g. `bug`, `pending-review`)
- A comment thread

An issue does NOT contain code. It describes what needs to happen, not how it was done.

Example issue:

```
#41: Typo: button on /signup says 'Sumbit', should be 'Submit'

The Submit button on the signup form is misspelled.
Visible at /signup. One letter swap fixes it.
```

### What is a pull request (PR)?

A proposal to merge code changes from one branch into another (usually into `main`). It has:

- A title and body
- A number (`#100`) — separate numbering from issues
- A diff (the actual code changes, line by line)
- A status (open / merged / closed)
- Labels
- A comment thread, including inline comments on specific lines
- Linked issues that the PR will close on merge

A PR DOES contain code — it's the code changes themselves, wrapped for review.

Example PR:

```
#100: Fixes #41: Submit typo on signup page

Changed "Sumbit" to "Submit" in app/routes/signup.tsx.

Fixes #41

[diff: +1 line, -1 line]
```

### Why have an issue at all? Can't you just open a PR?

You can. For a one-line typo you spotted yourself, sure. But for most work, the issue exists for reasons the PR can't cover:

1. **Intent before code.** The issue captures WHAT needs to happen BEFORE anyone writes code. PRs assume the code already exists.
2. **Triage and prioritization.** You can have 50 open issues and zero open PRs. Issues are the queue; PRs are work-in-progress.
3. **Discussion separated from review.** Issue comments discuss whether/what/when. PR comments discuss whether the code is correct. Different conversations.
4. **One issue can have multiple PRs.** A big feature might be 7 slices, each its own PR. Each PR says "this is one slice of the work toward issue #N."
5. **Non-engineers can participate in issues.** A product manager files an issue. A designer comments. An engineer eventually opens the PR. The PR is engineering-internal; the issue is the team-wide artifact.

### The classic flow

```
1. Someone files an issue   →   "we need to fix the typo"
                                (no code yet)

2. Engineer picks it up     →   git checkout -b 41-fix-typo
                                writes code on a branch

3. Engineer pushes branch   →   git push -u origin 41-fix-typo

4. Engineer opens PR        →   "this branch fixes issue #41,
   linking the issue            please review my code"

5. Reviewers comment        →   "looks good" / "fix X first"

6. Engineer addresses       →   more commits on same branch
   feedback (loops 5-6
   until approved)

7. PR is merged             →   main now contains the fix.
                                Issue #41 auto-closes (because
                                the PR body said "Fixes #41")
```

The PR feedback loop in this doc replaces "Engineer" in steps 2-6 with "AFK agent." The rest of the flow stays the same.

### What is a git worktree?

By default, a git repo gives you one working directory — one folder on disk with one branch checked out at a time. To switch branches you `git checkout other-branch`, and the files in that folder change to match.

A worktree is an *additional* working directory backed by the same repo. You can have `main` checked out in one folder and `fix-typo` checked out in a sibling folder at the same time. Both share the same `.git/` underneath (object database, refs, history) but have independent file checkouts.

Why bother?

1. **Run two things at once without git checkout fighting.** Build pass on one branch in worktree A while you test a PR locally in worktree B. Without worktrees, one would have to wait.
2. **Multiple AI agents on different branches simultaneously.** Each agent gets its own worktree and never collides on `git checkout`.
3. **Cheaper than cloning the repo a second time.** Worktrees share the underlying git object database — no re-fetching, no duplicated git internals.

You only need worktrees when you want concurrency. If you build one PR at a time, review, merge, build the next — skip worktrees. A single working dir is fine.

For the gotchas (per-worktree `node_modules`, branch claiming, the setup commands) and a parallel-AFK walkthrough, see ["Parallelism with git worktrees"](#parallelism-with-git-worktrees) later in this doc.

## Branches, PRs, and skipping both — Q&A

### Q1: Is a branch or worktree a prereq for creating a PR?

**Branch — YES, required.** A pull request is by definition "merge branch X into branch Y." You can't open a PR without two branches. Usually the source is a feature branch and the target is `main`.

**Worktree — NO, optional.** A worktree is just a way to have multiple branches checked out *at the same time*, on disk. You can create branches and PRs all day from a single working directory without ever touching worktrees. Worktrees only matter when you want concurrency.

So the relationship is:

```
                REQUIRED for PR     OPTIONAL
                ───────────────     ─────────
  Branch              ✓
  Worktree                              ✓
                  (it's about         (it's about doing
                   git history)        multiple things at once)
```

A worktree without a separate branch buys you nothing. A separate branch without a worktree is the normal everyday workflow for most engineers.

### Q2: What if you don't create a branch or worktree, and don't create a PR?

You commit directly to whatever branch you're on. The change goes live immediately — no review, no diff to inspect, no opportunity to revert before it lands.

```
   Normal flow:        main ──────────────────────────►
                              │
                              └─ feature-branch ──┐
                                                  │
                                                  PR ─► review ─► merge

   "Just commit"       main ──[commit]──[commit]──[commit]──►
   flow:               (no branch, no PR, no review)
```

This is exactly what AFK does today before adding the PR-opening capability — the agent commits straight to the working branch and closes the issue via the commit message. Concrete example: the gamification feature in `kgtdbx/cohort-003-project-kgt2` shipped as 7 commits on a single branch:

```
2b345b7 Progress on #8: Slice 7 QA pass
3d8949d Fixes #7:  Slice 6 — module completion toast
1793d06 Fixes #6:  Slice 5 — dashboard summary
525f13f Fixes #5:  Slice 4 — streaks
76354ab Fixes #4:  Slice 3 — sidebar progress bar
f9b4af7 Fixes #3:  Slice 2 — first-quiz-pass XP
a473bca Fixes #2:  XP foundation
```

`gh pr list` returned empty — zero PRs were ever opened. Each issue was closed by a commit message containing `Fixes #N`, which auto-closes the issue when pushed. No human review, no PR merge, no revise loop — just direct commits. This matches the "Naive AI world" column in [Old world vs new world](#old-world-vs-new-world) below.

### Q3: Is that bad practice?

Honest answer: it depends on context.

| Context | Verdict | Why |
|---|---|---|
| Solo dev, learning / experimenting | **Fine** | No team to coordinate with. Fast feedback loop. Easy to `git revert` if needed. |
| Solo dev, real production code shipped to users | **Risky** | No second pair of eyes. A bad commit ships to users with no opportunity to catch it. |
| Small team, internal tool | **Acceptable if everyone agrees** | Some teams genuinely prefer trunk-based-no-PR workflows for speed, but it's a deliberate choice with social agreement. |
| Any team, customer-facing product | **Bad practice** | No review trail, no rollback granularity, no record of *why* the change was made beyond the commit message. Makes incident postmortems much harder. |
| AFK with autoaccept | **Especially risky in production** | The agent ships code → trunk with no human in the loop AT ALL. Magnifies all the above risks because there's not even a human author to catch their own mistakes. |

The general rule professionals follow:

> **Commit to main directly when the cost of a bad commit is low.**
> **Use PRs when the cost of a bad commit is high enough to be worth a human reading the diff first.**

There's no universal answer. The reason the PR ritual exists is that, on most production systems, the cost of "bad commit slips through" is high enough that the 30 minutes of review time is worth it. On a sandbox you're learning in, that math flips.

## A walkthrough: one-line typo fix

The simplest possible example. One issue, one round of feedback, merged.

```
─── Day 1, 10:00am ─────────────────────────────────────────
   👤 You file issue #41:
      "Typo: button on /signup says 'Sumbit', should be 'Submit'"
                            │
                            ▼
   🤖 AFK build pass picks it up
      ─ Reads issue, finds the line in app/routes/signup.tsx
      ─ Changes "Sumbit" to "Submit"
      ─ Runs pnpm test + typecheck → green
      ─ git push → branch 41-fix-submit-typo
                            │
                            ▼
   📦 PR #42 opened
      ─ 1 file changed, 1 line
      ─ label: pending-review
      ─ closes #41

─── Day 1, 11:00am ─────────────────────────────────────────
   👤 You review PR #42:
      Comment: "Looks right, but check the cancel modal too —
                I think the same typo is in CancelDialog.tsx"
                            │
                            ▼
   👤 You add label: `agent-revise`

─── Day 1, 11:05am ─────────────────────────────────────────
   🤖 AFK revise pass picks up PR #42 from the label queue:
      ─ gh pr checkout 42
      ─ Reads your comment
      ─ greps for 'Sumbit' across the repo
      ─ Finds one more in CancelDialog.tsx line 88, fixes it
      ─ pnpm test + typecheck → green
      ─ git push → adds 2nd commit to the same branch
                            │
                            ▼
   💬 Agent comments on the PR:
      "Addressed: also fixed in CancelDialog.tsx:88.
       Grepped — no other occurrences in the repo."
                            │
                            ▼
   📦 PR #42 updated
      ─ label: agent-revise REMOVED
      ─ label: awaiting-review ADDED

─── Day 1, 11:30am ─────────────────────────────────────────
   👤 You re-review:
      ─ Diff is now 2 lines, both correct
      ─ Click "Merge" → ✅ DONE
```

## Why this loop exists

Three reasons, in order of importance:

1. **Reviewability without slowing down the build.** The build pass might churn out 10 PRs in an hour. Humans review at human speed. PRs let the agent keep moving while you take your time.
2. **Feedback is concrete and addressable.** "Make the gamification feature better" is useless. "Also fix this typo in CancelDialog.tsx" is precise — the agent can act on it directly because it's anchored to a line.
3. **Reversibility.** A bad PR is closed and forgotten — zero side effects. A bad commit to `main` requires git surgery.

## End-to-end flow (generalized)

```
   ┌──────────────┐
   │ HUMAN        │
   │ Open issue   │
   └──────┬───────┘
          │
          ▼
┌────────────────────────────────┐
│ AFK BUILD PASS                 │
│ ./afk/sandcastle/afk.sh        │
│   (or /afk in Claude Desktop)  │
│                                │
│ 1. Pick an open issue          │
│ 2. Implement on feature branch │
│ 3. pnpm test + typecheck       │
│ 4. git push                    │
│ 5. gh pr create                │
│    label: pending-review       │
│ 6. gh issue close              │
└────────────────┬───────────────┘
                 │
                 ▼
       ┌──────────────────┐
       │ PR OPEN          │
       │ pending-review   │
       └────────┬─────────┘
                │
                ▼
┌────────────────────────────────┐
│ HUMAN REVIEW                   │
│                                │
│ Read diff, leave comments      │
│                                │
│ Approve?    ─► merge ─► DONE   │
│                                │
│ Need fixes? ─► add label       │
│                `agent-revise'  │
└────────────────┬───────────────┘
                 │
                 ▼
┌────────────────────────────────┐
│ AFK REVISE PASS                │
│ ./afk/sandcastle/afk.sh        │
│   --mode revise                │
│                                │
│ 1. Find PR with agent-revise   │
│ 2. gh pr checkout              │
│ 3. Fetch comments + reviews    │
│    (filter bots + own author)  │
│ 4. Address each point          │
│ 5. pnpm test + typecheck       │
│ 6. git push                    │
│ 7. gh pr comment summary       │
│ 8. relabel: agent-revise →     │
│             awaiting-review    │
└────────────────┬───────────────┘
                 │
                 ▼
       ┌──────────────────┐
       │ PR OPEN          │
       │ awaiting-review  │
       └────────┬─────────┘
                │
                └─► back to HUMAN REVIEW
                    (loops until merge)
```

## Label state machine

The label IS the queue. Three labels, four transitions:

```
                            ┌─────────────────┐
                            │   (no label)    │ ← pre-PR
                            └────────┬────────┘
                                     │ AFK build pass opens PR
                                     ▼
                            ┌─────────────────┐
              ┌──────────── │ pending-review  │ ◄────────┐
              │             └────────┬────────┘          │
              │                      │                    │
       human merges          human applies                │
              │              `agent-revise`               │
              ▼                      │                    │
       ┌────────────┐                ▼                    │
       │   MERGED   │       ┌─────────────────┐           │
       └────────────┘       │  agent-revise   │           │
                            └────────┬────────┘           │
                                     │ revise pass picks  │
                                     │ up + addresses     │
                                     ▼                    │
                            ┌─────────────────┐           │
                            │ awaiting-review │ ──────────┘
                            └─────────────────┘  (human treats
                                                  this like
                                                  pending-review)
```

Only humans transition `pending-review` ↔ `agent-revise`. Only the agent transitions `agent-revise` → `awaiting-review`. Never let the agent self-apply `agent-revise` — that creates an infinite loop.

## What needs to be built

Three increments, each independently useful. Don't build all of it at once.

### Increment 1: Build pass opens PRs (no revise loop yet)

Today's `prompt.md` says "commit on the current branch, then `gh issue close`." Change it to:

- Create a feature branch named `<issue-number>-<short-slug>`.
- Commit there.
- `gh push -u origin <branch>`.
- `gh pr create --label pending-review --title "Fixes #N: …" --body "…"`.
- Then `gh issue close N --comment "PR #M opened"`.

This alone is a useful change. You get human-reviewable diffs and the option to revert any single slice without losing the others.

**Files to touch (in your target repo):**
- `afk/ralph/prompt.md` — replace the close-issue section with create-PR-then-close-issue.
- (Optional) `.github/labels.yml` or a one-time `gh label create` for `pending-review`.

### Increment 2: Revise pass (HITL trigger)

Add a second prompt and a second selector. Reuse the same Docker container and `afk.sh` wrapper.

**New files:**
- `afk/ralph/revise-prompt.md` — the revise instructions (see "Revise prompt skeleton" below).
- (Optional) modify `afk/ralph/build-prompt.sh` to accept `--mode revise`, which queries `gh pr list --label agent-revise` instead of `gh issue list`.

**Trigger:** manual. You add `agent-revise` to a PR, then run `./afk/sandcastle/afk.sh 1 --mode revise`. One pass, watch what it does, iterate on the prompt.

### Increment 3: Automate the trigger (optional)

Once the revise prompt is reliable:

- Cron job that runs `./afk/sandcastle/afk.sh 5 --mode revise` every N minutes.
- OR a GitHub Action that fires on `pull_request.labeled` with `agent-revise` and pings a webhook on a self-hosted runner.

Cron is simpler and good enough for a personal workflow. Webhooks matter when latency does (team setting, multiple agents).

## Revise prompt skeleton

What `revise-prompt.md` needs to contain (don't copy verbatim — adapt):

```
# REVISE A PR

You've been passed a list of open PRs labeled `agent-revise`. Pick ONE.

# FETCH FEEDBACK

For the chosen PR number N:

  gh pr view N --repo "$GH_REPO" --json title,body,headRefName,reviews,comments
  gh api repos/$GH_REPO/pulls/N/comments  # inline review comments

Filter the resulting comments:
  - Drop anything where author.login == "$AGENT_GH_LOGIN" (avoid feedback loops).
  - Drop anything where author.type == "Bot" (Vercel previews, Codecov, etc.).
  - Drop comments on resolved threads (is_resolved == true).

# CHECK OUT THE BRANCH

  gh pr checkout N --repo "$GH_REPO"

# ADDRESS EACH FEEDBACK POINT

For every remaining comment:
  - Understand what's being asked. If it's ambiguous, post a clarifying
    comment back and SKIP this PR for this iteration — do not guess.
  - Make the smallest change that addresses the comment.
  - Do not refactor unrelated code. Do not add features. Do not "improve"
    things the reviewer didn't mention.

# FEEDBACK LOOPS

  pnpm run test
  pnpm run typecheck

If they fail on YOUR changes, fix them. If they fail on pre-existing
unrelated code, mention it in your PR comment and proceed.

# COMMIT AND PUSH

  - One or more commits referencing the PR.
  - git push (no --force unless you actually rebased).

# COMMENT ON THE PR

  gh pr comment N --repo "$GH_REPO" --body "<summary>"

The summary should list each feedback point and what you did about it
(or "still unclear, awaiting clarification" for ones you skipped).

# RELABEL

  gh pr edit N --repo "$GH_REPO" --remove-label agent-revise --add-label awaiting-review

# RULES

NEVER apply the `agent-revise` label yourself.
NEVER force-push someone else's branch.
NEVER address feedback you don't understand — ask instead.
```

## Gotchas to fence for upfront

- **Infinite loop**: agent's own comment somehow re-triggers the label. Always filter by `author.login != "$AGENT_GH_LOGIN"`. The relabel-to-`awaiting-review` step is the agent's commitment that it's done — only a human re-applies `agent-revise`.
- **Two kinds of comments on every PR**: top-level conversation comments AND inline review comments. They live in different `gh` endpoints. The agent must fetch both.
- **CI noise**: filter on `author.type == "Bot"` so Vercel/Renovate/Codecov chatter doesn't get treated as feedback.
- **Resolved threads**: prefer to skip threads marked resolved (`is_resolved`). Re-addressing already-resolved feedback is at best wasted work, at worst confusing.
- **Baseline test failures**: a PR that's already red on `main` will look like the agent broke things. Capture the baseline before changes; fail the iteration only on *new* failures.
- **Force pushes**: agent should `git push` (no `--force`) unless it explicitly rebased onto a moved base. Force-pushing a branch someone is reviewing live silently wipes their in-progress comments-in-the-margin.
- **Multiple PRs labeled at once**: pick the oldest one per iteration. Same `<promise>NO MORE TASKS</promise>` sentinel applies once the queue is drained.
- **PRs the agent didn't open**: in principle the revise loop will happily try to fix any PR with the label. Decide whether you want that scope or whether to gate on `gh pr view N --json author --jq '.author.login == $AGENT_GH_LOGIN'`.

## When things go wrong — how to revert

Two universal moves apply to any PR-based scenario:

**Before code lands on `main` →** prevent it. Close the PR or delete the worktree. Zero history pollution.

**After code lands on `main` →** invert it. `git revert <sha>` creates a NEW commit that undoes the bad commit's changes. The original commit stays in history (so you have an audit trail). Never `git reset --hard` on a branch others have pulled — it rewrites history and breaks everyone downstream.

### Before merge: just close it

If the bad code is sitting in an open PR, it never reached `main`. You don't need to revert anything — just close the PR:

```bash
gh pr close 103 --comment "Reverting — bug found during review"
git push origin --delete <branch-name>   # optional, cleans up
```

Done. The bad code never touched `main`.

### After merge: GitHub's revert button (or `git revert`)

```
   Before:
   main ──[PR #100 ✓]──[PR #101 ✓]──[PR #103 BAD]──[PR #104 ✓]──►
                                          │
                                          │ Click "Revert" button on PR #103
                                          │ on github.com (or:
                                          │   git revert -m 1 <merge-sha>
                                          │   git push)
                                          ▼
   After:
   main ──[#100]──[#101]──[#103]──[#104]──[Revert #103 ✓]──►
```

GitHub auto-creates a "Revert PR #103" pull request. Review it, merge it. The bad code is undone in `main` AND you have a clean PR-history record of WHY.

### What about #104? — `git revert` is surgical

Common confusion: "if I revert #103, does #104 get rolled back too?"

**Short answer: PR #104 stays intact.** `git revert` only undoes the specific commit you point it at.

```
   Before revert:
   main ──[#100]──[#101]──[#103 BAD]──[#104]──►
                              │
                              │ added 50 lines in 3 files
                              │
                              ▼

   After git revert <#103 merge sha>:

   main ──[#100]──[#101]──[#103]──[#104]──[REVERT #103]──►
                                              │
                                              │ removes the SAME 50 lines
                                              │ in the SAME 3 files
                                              │ that #103 added.
                                              │ Doesn't touch anything else.
                                              ▼
```

The revert is a NEW commit on top of `main`, NOT a deletion of #103 from history. It just adds the inverse of #103's diff. #104's changes are completely untouched — they exist in their own commit which the revert doesn't address.

### But: two cases — does #104 *depend* on #103's code?

**Case A: #104 is INDEPENDENT of #103 → clean revert, #104 keeps working.**

If #104 doesn't import anything from #103, doesn't reference any database column #103 created, doesn't call any function #103 added — then removing #103's lines leaves #104 entirely happy.

```
   ──[#103 streaks BAD]──[#104 toast]──[REVERT #103]──►

   Result:
   - Things #103 added (streak table, sidebar streak block): gone
   - Things #104 added (toast): still there
   - app boots, tests pass
```

**Case B: #104 DEPENDS on #103 → reverting #103 breaks #104.**

If #104 imported a function from #103, or referenced a database column #103 created, then removing #103 leaves #104 referencing ghost code. The app breaks.

```
   ──[#103 streaks]──[#104 dashboard uses streak block]──[REVERT #103]──►

   Result:
   - getStreakStats() function: gone
   - Dashboard component: still calls getStreakStats()  ← BROKEN
   - app crashes on dashboard route
```

In Case B, you have to choose:

1. **Revert the cascade**: also revert #104 (and anything else downstream) — produces multiple revert commits.
2. **Fix forward**: instead of reverting, write a new commit that removes #104's dependency on #103 (e.g. delete the dashboard streak section), then revert #103.

### How to know which case you're in

Before reverting, run:

```bash
git revert --no-commit <#103 sha>
git status        # shows what files would change
pnpm test         # are #104's tests still passing?
pnpm typecheck    # any references to ghost code?
```

If everything's green → Case A, just `git commit` the revert and push.

If tests/typecheck fail → Case B. `git revert --abort` to back out, then think about whether to revert the cascade or fix forward.

### The deeper truth: review windows prevent cascades

The cascade problem exists in any workflow when slices stack — but the diff is in *what you can do early*:

- **PRs (any scenario):** PR open but not merged → close it → never hits `main` → no downstream slices were built on it → no cascade.
- **No PRs (commit-direct):** Every commit IS a "merge" to your working branch. By the time you notice the bad slice, downstream slices may already exist on top of it.

This is the structural reason the PR loop exists: not the review itself, but **the gap between "agent done" and "code live" where you can intervene**. The deeper a slice sits in the dependency graph, the cheaper a revert is. The closer it is to the foundation, the more expensive. **This is one reason vertical slices are designed thin and independent** — to limit the blast radius of any single revert.

For a per-scenario walkthrough using the actual gamification slices, see [walkthrough-gamification.md → Reverting in each scenario](walkthrough-gamification.md#reverting-in-each-scenario).

## Parallelism with git worktrees

The workflow above assumes one build pass and one revise pass running serially in the same checkout. If you ever want to run them concurrently — or scale to N parallel build agents on independent issues — **git worktrees are the cleanest way**.

A worktree is a second working directory backed by the same `.git/` repo. You can have `main` checked out in one directory and `feature-branch` checked out in another, simultaneously, both reading from the same object database.

```
                     ┌─────────────────────┐
                     │  Shared .git/       │
                     │  (object DB, refs)  │
                     └──────────┬──────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        │                       │                       │
        ▼                       ▼                       ▼
┌────────────────┐    ┌────────────────┐    ┌────────────────┐
│ Worktree A     │    │ Worktree B     │    │ Worktree C     │
│ branch:        │    │ branch:        │    │ branch:        │
│ 50-streaks     │    │ 41-fix-typo    │    │ 42-revise      │
│                │    │                │    │                │
│ (own data.db,  │    │ (own data.db,  │    │ (own data.db,  │
│  node_modules) │    │  node_modules) │    │  node_modules) │
└────────┬───────┘    └────────┬───────┘    └────────┬───────┘
         │                     │                     │
         ▼                     ▼                     ▼
┌────────────────┐    ┌────────────────┐    ┌────────────────┐
│ AFK build pass │    │ You testing    │    │ AFK revise     │
│ on issue #50   │    │ PR locally     │    │ pass on PR #42 │
│                │    │ (npm run dev)  │    │                │
└────────────────┘    └────────────────┘    └────────────────┘

   All three run concurrently. Each has its own HEAD, working
   tree, data.db, and node_modules. They share only the git
   object database.
```

### Where worktrees help

1. **Build pass + revise pass running concurrently.** Without worktrees, the revise pass needs `gh pr checkout 42`, which switches the current dir's branch. If the build pass is mid-iteration on `50-streaks`, they collide. With worktrees, each pass owns a separate physical directory.
2. **Multiple parallel build agents on independent issues.** Spawn N agents, each on its own issue. Without worktrees they'd fight over `git checkout` state. With worktrees each agent is fully isolated.
3. **You testing a PR locally while AFK is mid-loop.** `git worktree add ../worktrees/review-42 42-fix-typo`, run `npm run dev` there, delete the worktree when done. Doesn't disturb the agent.
4. **Per-agent isolation for spawned subagents.** Some agent frameworks (including Claude Code's own `Agent` tool) support `isolation: "worktree"` — each subagent runs in a temporary worktree that's auto-cleaned if it makes no changes.

### Where worktrees DON'T help

- **In-session Claude Desktop AFK with shared context.** Runs serially through one conversation, on one branch at a time. Worktrees buy you nothing.
- **Single-runner Sandcastle/Ralph loops.** If you're only running one Docker container at a time, the single working dir is fine.

### Real gotchas

- **`.gitignore`d files are NOT shared between worktrees, and they're not auto-isolated either** — each worktree has its own `node_modules/`, `data.db`, `.env`. A new worktree starts with none of these. You have to `pnpm install` per worktree (or symlink, which is risky if branches differ in `package.json`).
- **`data.db` collisions if you DO share it.** Two worktrees running `pnpm run db:migrate` against the same shared SQLite file will corrupt it. Either accept per-worktree DBs (default) or point each at a different file via env var.
- **Docker bind mounts work** with worktrees, but you must mount the worktree path AND the canonical `.git` location, because the worktree's `.git` is a pointer file referencing the parent repo. Mount the wrong thing and `git status` breaks inside the container.
- **Branches are "claimed" by a worktree.** Same branch can't be checked out in two worktrees at once — git refuses. So `41-fix-typo` either lives in the main checkout OR in a worktree, not both.

### Practical setup for parallel AFK

```bash
# From the main project root
mkdir -p ../worktrees

# For each issue you want to work in parallel
# (example: branch 50-streaks)
git worktree add ../worktrees/50-streaks -b 50-streaks

# Then point the AFK runner at that worktree dir:
#   Sandcastle/Ralph: bind-mount ../worktrees/50-streaks as the project dir
#   In-session skill: cd ../worktrees/50-streaks before invoking /afk

# When done
git worktree remove ../worktrees/50-streaks
```

For the PR feedback loop specifically: if you only ever run one build pass and one revise pass sequentially, skip worktrees — let the same dir check out different branches as needed. If you want build + revise concurrent, or multiple build agents at once, worktrees are the cleanest way.

## Old world vs new world

| | **Old world** (humans only) | **Naive AI world** | **This workflow** |
|---|---|---|---|
| Who writes code | Human | AI agent | AI agent |
| Where commits land first | Feature branch → PR | Often direct to `main` (autoaccept) | Feature branch → PR |
| Who reviews | Other humans on the team | Often nobody — you trust autoaccept | You |
| How feedback gets back to the author | PR comments → author pushes follow-up | "Try again, do better" in a chat prompt | PR comments → `agent-revise` label → AFK re-runs |
| If it's wrong | Decline the PR, no harm | `git revert` + cleanup | Close the PR, no harm |
| Speed | Slow — reviewer availability bottleneck | Fast but blind | Slower than naive, faster than old (because build keeps running while you review) |

**The big insight: the PR feedback loop is just the old-world PR ritual brought back, with an AI playing the role of the author.** It's not a new invention; it's the most conservative way to put guardrails on a fast agent.

## What dev shops actually do

There's no industry consensus. The field is fragmented. Roughly:

- **Solo devs / small teams** → often skip PRs entirely. Agent commits to `main` with autoaccept. Maximum speed, accepts the risk. This is what `afk.sh` does today, what `/afk` in Claude Desktop does, and what Cursor's "Yolo mode" is.
- **Most established companies** → keep the traditional PR ritual, agent is just another contributor. Slower than autoaccept but the existing review processes survive intact. **This is where the workflow in this doc sits.**
- **Multi-agent shops** (still rare) → agent A writes the PR, agent B reviews it, human only sees the synthesis. Anthropic's `/ultrareview` is moving in this direction.
- **Spec-driven shops** → human writes/reviews the spec, agent writes the code AND tests, human almost never reads the diff. Bet that the spec is the right level of human attention.
- **Trunk-based + feature flags** → no PRs at all. Agents push to `main` behind disabled flags; humans flip the flag when the feature is ready. Skips review entirely; relies on flags as the safety mechanism.

Most teams are bouncing between these. There's no playbook yet — there's only "what tradeoff are you willing to make this week." The PR feedback loop here is the **most conservative** pattern. It's the right starting point if you're not sure, because it preserves the review safety net you already trust.

## When this is worth building

- You're already running AFK build passes regularly and the friction is "I have feedback I don't want to type into a follow-up issue."
- Your reviews tend to be small, mechanical asks ("rename X", "extract Y", "add a test for Z"). Those round-trip cleanly through an agent.
- You're willing to babysit the first 5–10 revisions. PR feedback is much higher-bandwidth than issue text — small misreads of a review comment can cause big wrong refactors. Watch carefully before letting it loop unattended.

If your reviews are mostly "this whole approach is wrong, let's redesign" — skip this. The revise loop is for incremental polish, not direction changes.
