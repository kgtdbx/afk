# Walkthrough: Gamification feature, three workflows

A concrete walkthrough using the **Student Gamification (XP, Levels & Streaks)** feature shipped to `kgtdbx/cohort-003-project-kgt`. Same set of GitHub issues, three different ways to drive them to merged. The point is to make the tradeoffs visceral — what each workflow looks like in practice, not just in theory.

The three workflows:

- **Scenario A — PR workflow only** (one working dir, sequential, every change behind a PR)
- **Scenario B — Worktree workflow only** (parallel agents, direct merges to main, no PRs)
- **Scenario C — Combined PR + worktree** (parallel agents, every change behind a PR)

Companion to:
- [pr-feedback-loop.md](pr-feedback-loop.md) — the design doc for the PR workflow itself
- [AIHERO-HIGH_LEVEL_WORKFLOWS.md](AIHERO-HIGH_LEVEL_WORKFLOWS.md) — the full workflow catalog

---

## The setup

The gamification feature was broken into 7 GitHub issues by `/prd-to-issues`:

```
#1  Parent PRD (Student Gamification)

#2  Slice 1: XP foundation
    └─ schema, leveling utility, sidebar badge

#3  Slice 2: First-quiz-pass XP            ← needs #2
#4  Slice 3: Sidebar level progress bar    ← needs #2
#5  Slice 4: Streaks                       ← needs #2
#7  Slice 6: Module completion toast       ← needs #2

#6  Slice 5: Dashboard summary card        ← needs #2 AND #5
#8  Slice 7: Manual QA pass (HITL)         ← needs all of the above
```

Dependency graph:

```
                  #2 (foundation)
                ┌──┬──┬──┬──┐
                │  │  │  │  │
                ▼  ▼  ▼  ▼  ▼
               #3 #4 #5 #7
                       │
                       ▼
                      #6 (dashboard)
                       │
                       ▼
                      #8 (HITL QA)
```

Key facts:
- **#2 is the gate.** Nothing else can start until #2 lands (it adds the `xp_events` table + leveling utility + `getUserStats` API that everyone else consumes).
- **Once #2 is merged, four issues fan out in parallel** (#3, #4, #5, #7). They touch different files mostly — the only shared surface is `sidebar.tsx`, where #4 and #5 both add UI.
- **#6 is gated on #5** (it reuses the streak block).
- **#8 is HITL** — a human, not an agent, runs through the manual QA checklist.

For sizing, assume each AFK build pass takes ~1 hour and each human PR review takes ~30 minutes. (Real numbers vary; these are for the timelines below.)

---

## Scenario A — PR workflow only

**One working directory, one agent at a time, every change behind a PR.** The agent works through issues serially. After each issue, it pushes a branch and opens a PR. You review, optionally request changes via the `agent-revise` label, then merge. Then the agent moves to the next issue.

### Visual

```
Working dir: ~/dev/cohort-003-project-kgt2/   (single checkout)

   main ──────────────┬──────────┬──────────┬──────────┬──────────┬──────────┐
                      │          │          │          │          │          │
                      │ merge    │ merge    │ merge    │ merge    │ merge    │
                      │ PR #100  │ PR #101  │ PR #102  │ PR #103  │ PR #104  │
                      │          │          │          │          │          │
   PR #100 (#2) ──────┘          │          │          │          │          │
   PR #101 (#3) ─────────────────┘          │          │          │          │
   PR #102 (#4) ────────────────────────────┘          │          │          │
   PR #103 (#5) ───────────────────────────────────────┘          │          │
   PR #104 (#7) ──────────────────────────────────────────────────┘          │
   PR #105 (#6) ─────────────────────────────────────────────────────────────┘
```

### Timeline

```
       Hour: 1    2    3    4    5    6    7    8    9    10
              │    │    │    │    │    │    │    │    │    │
#2 found:  [B]→PR  R    M
#3 quiz:                [B]→PR  R    M
#4 bar:                            [B]→PR  R    M
#5 streaks:                                     [B]→PR  R    M
#7 toast:                                                   [B]→PR  R    M
#6 dash:                                                              [B]→PR  R   M
#8 HITL:                                                                          [QA]

   Legend:  [B]=AFK build pass    PR=opens PR    R=human review    M=merge
```

Total wall time ≈ 9–10 hours. Adds ~30 min per round of `agent-revise` feedback if a PR needs changes.

### How each issue closes

**#2 (XP foundation)**
1. AFK picks #2 (highest priority — it's the only unblocked one).
2. Branches `git checkout -b 2-xp-foundation` from `main`.
3. Implements: `xp_events` table + migration, `app/lib/leveling.ts`, `getUserStats`, sidebar wiring.
4. `pnpm test && pnpm typecheck` — green.
5. `git push -u origin 2-xp-foundation`.
6. `gh pr create --label pending-review --title "Fixes #2: XP foundation" --body "<details>"`.
7. `gh issue close 2 --comment "Implemented in PR #100"`.
8. **AFK stops** until #100 is merged. (Otherwise #3's branch wouldn't have the schema it needs.)
9. You review #100, optionally apply `agent-revise`, eventually merge.

**#3, #4, #5, #7 (parallel-eligible but driven serially here)**
Same loop, one at a time. Each branches off the now-updated `main`, implements, opens a PR, you review and merge before the next one starts.

**#6 (dashboard summary)**
Needs #5 merged first (consumes the streak block). The serial nature of this scenario makes that automatic — by the time AFK gets to #6, #5 has already merged.

**#8 (HITL QA)**
You manually walk the checklist from issue #8. Verify all 17 user stories. Close #8 when done.

### Pros / cons

**Pros**
- Every change is reviewed before it touches `main`. Maximum safety net.
- Easy to revert any single slice — just close the PR or `git revert` the merge commit.
- Linear history; nothing weird happening in parallel.
- Works with current AFK as soon as you swap in the increment-1 PR-opening prompt from `pr-feedback-loop.md`.

**Cons**
- **Slowest of the three** (~10h vs ~3h for B and ~5h for C).
- Human review is the main bottleneck. Agent often idle waiting for you.
- Doesn't exploit the parallelism the dependency graph allows.

### When to pick

- You're new to AFK and want to keep tight control.
- Each slice is risky enough that you want to review it before the next one builds on it.
- You're solo and don't want to deal with multiple worktrees.

---

## Scenario B — Worktree workflow only

**Parallel agents in separate worktrees, no PRs, direct merges to `main`.** Foundation lands first (sequential). Then four agents fan out into four worktrees and work concurrently. Each merges its branch to `main` directly when tests are green. No human review gate.

This is what you'd reach for if you trust the agent's output and the dependency graph supports parallelism.

### Visual

```
Filesystem layout:

   ~/dev/cohort-003-project-kgt2/         ← main checkout (on `main`)
   │
   ~/dev/cohort-003-worktrees/
   ├── 2-xp-foundation/                   ← agent #1 (Phase 1)
   ├── 3-quiz-xp/                         ── agent #1 (Phase 2)
   ├── 4-progress-bar/                    ── agent #2 (Phase 2)
   ├── 5-streaks/                         ── agent #3 (Phase 2)
   ├── 7-module-toast/                    ── agent #4 (Phase 2)
   └── 6-dashboard/                       ── agent #1 (Phase 3)

Branch state on the canonical .git/:

   main ───┬──────────┬───────────┬───────────────┐
           │          │           │               │
           │ merge    │ merge     │ merge         │ merge
           │ #2       │ #3,#4,    │ #6            │ (final)
           │          │ #5,#7     │               │
           │          │ (4 in     │               │
           │          │  rapid    │               │
           │          │  succession)│            │
           ▼          ▼           ▼               ▼
        Phase 1    Phase 2     Phase 3        HITL #8
```

### Timeline

```
       Hour: 1    2    3    4
              │    │    │    │

PHASE 1 (foundation, single worktree):
W2:        [B]─merge to main
                  │
       ┌────┬─────┴─────┬────┐
       │    │           │    │
PHASE 2 (4 worktrees in parallel):
W3 (#3):        [B]─merge
W4 (#4):        [B]─merge
W5 (#5):        [B]─merge
W7 (#7):        [B]─merge
                              │
PHASE 3 (single worktree, gated on #5):
W6 (#6):                     [B]─merge
                                    │
HITL:                              [QA]

   Legend:  [B]=AFK build pass    merge=git merge to main (no PR)
```

Total wall time ≈ 3–4 hours. Phase 2 saves ~3 hours by running 4 agents in parallel.

### How each issue closes

**#2 (foundation, Phase 1)**
1. `git worktree add ../worktrees/2-xp-foundation -b 2-xp-foundation`.
2. `cd ../worktrees/2-xp-foundation && pnpm install` (worktrees don't share `node_modules`).
3. Run AFK in there: `./afk/sandcastle/afk.sh 1 --issue 2` (or `/afk --issue 2` in a Claude Desktop session pointed at this worktree).
4. Agent implements, tests green.
5. `git checkout main` in the canonical checkout.
6. `git merge 2-xp-foundation` (fast-forward).
7. `git push origin main`.
8. `gh issue close 2 --comment "Merged"`.
9. `git worktree remove ../worktrees/2-xp-foundation`.

**#3, #4, #5, #7 (Phase 2, parallel)**
1. Spawn 4 worktrees, one per issue: `git worktree add ../worktrees/3-quiz-xp -b 3-quiz-xp`, etc.
2. `pnpm install` in each. (Yes, four times. Or symlink `node_modules` if you trust `package.json` is identical across worktrees, which it is here.)
3. Spawn 4 AFK runners — one per worktree. Each on the same model:
   - **Sandcastle/Ralph**: 4 Docker containers, each bind-mounting a different worktree as `/workspace`.
   - **Claude Desktop AFK**: 4 desktop sessions, each `cd`'d into a different worktree, each invoking `/afk --issue N`.
4. Each agent commits to its own branch. When tests green, push.
5. **Merge order matters even though work was parallel**: merge them one at a time into `main`, resolve any `sidebar.tsx` conflicts as they come up.
   - Likely conflict zone: `app/components/sidebar.tsx` between #4 (progress bar) and #5 (streak section). Both add UI to the same file.
   - Strategy: merge #5 first, then `git rebase main` in #4's worktree, fix the conflict, merge #4.
6. `gh issue close N` for each as it merges.
7. `git worktree remove` each as you go.

**#6 (Phase 3, dashboard)**
Same as #2 — single worktree, gated on #5 already being on `main`.

**#8 (HITL QA)**
Manual walk-through. Same as in Scenario A.

### Pros / cons

**Pros**
- **Fastest** (~3–4h). Phase 2 runs 4 issues in the time of one.
- No PR overhead, no review queue.
- Works today with current AFK — no PR-opening capability needed.

**Cons**
- **No human review.** If the agent ships a bad API for slice #1, the four parallel slices in Phase 2 will all build on it before you notice.
- **Merge conflicts on shared files** (`sidebar.tsx` here) require manual resolution. Not awful for 4 PRs; gets ugly at 10+.
- `node_modules` × 4 worktrees costs disk space (~600MB each here).
- `data.db` is per-worktree (gitignored), so each agent has its own DB. Fine for build, but you can't `npm run dev` in one worktree to test changes in another — they have isolated state.
- Spawning and supervising 4 concurrent AFK runners is non-trivial. Each one needs its own terminal / Docker container / desktop session.

### When to pick

- The slices are well-spec'd and the agent has high credibility for this codebase (you've already shipped a few like this).
- Time matters more than review rigor.
- The dependency graph genuinely allows wide parallelism (this gamification example is a good fit; pure-sequential refactors are not).
- You can tolerate hand-resolving 1–2 merge conflicts.

---

## Scenario C — Combined PR + worktree

**Parallel agents in worktrees, but every branch goes through a PR before merge.** Foundation #2 ships as a PR. Once merged, four worktrees fan out in parallel — each opens its own PR. You review them in a batch (much higher throughput than one-at-a-time). Optionally use the `agent-revise` label to round-trip feedback. Final slice #6 goes through one more PR.

This is the maximum-throughput-with-review pattern.

### Visual

```
Filesystem layout (Phase 2):

   ~/dev/cohort-003-project-kgt2/         ← main checkout
   │
   ~/dev/cohort-003-worktrees/
   ├── 3-quiz-xp/        ──→ PR #101 ──→ pending-review ──┐
   ├── 4-progress-bar/   ──→ PR #102 ──→ pending-review ──┤
   ├── 5-streaks/        ──→ PR #103 ──→ pending-review ──┤
   └── 7-module-toast/   ──→ PR #104 ──→ pending-review ──┤
                                                            │
                                                  ┌─────────┘
                                                  ▼
                                       ┌──────────────────┐
                                       │ HUMAN REVIEW     │
                                       │ - merge #101     │
                                       │ - merge #103     │
                                       │ - agent-revise   │
                                       │   #102, #104     │
                                       └──────────────────┘
                                                  │
                                                  ▼
                                       Revise pass picks up
                                       #102 and #104 in their
                                       same worktrees, addresses
                                       feedback, relabels to
                                       awaiting-review.
                                                  │
                                                  ▼
                                       You merge them.
```

### Timeline

```
       Hour: 1    2    3    4    5    6    7
              │    │    │    │    │    │    │

PHASE 1 (foundation):
W2 (#2):  [B]→PR  R    M
                       │
       ┌────┬─────────┴─────────┬────┐
PHASE 2 (4 worktrees, 4 PRs in parallel):
W3 (#3):              [B]→PR  R    M
W4 (#4):              [B]→PR  R[+revise]  M
W5 (#5):              [B]→PR  R    M
W7 (#7):              [B]→PR  R[+revise]  M
                                              │
PHASE 3 (single worktree, gated on #5):
W6 (#6):                                     [B]→PR  R    M
                                                              │
HITL:                                                        [QA]

   Legend: [B]=build  PR=open PR  R=human review  M=merge
           [+revise]=at least one agent-revise round-trip
```

Total wall time ≈ 5–6 hours. Phase 2 batch-review (4 PRs at once) is the speedup over Scenario A.

### How each issue closes

**#2 (foundation, Phase 1)**
Identical to Scenario A's #2 — single worktree, opens PR, you review and merge. AFK stops until #2 is merged because everything downstream depends on its schema.

**#3, #4, #5, #7 (Phase 2, parallel through PRs)**
1. Spawn 4 worktrees just like Scenario B.
2. Each AFK runner implements, tests green, **opens a PR with label `pending-review`** (instead of merging directly).
3. Each agent stops after opening the PR — no waiting around.
4. You sit down to review all 4 PRs at once. This is much faster than 4 separate review sessions because:
   - You're already in the gamification headspace.
   - Many comments will be the same ("test name should describe behavior, not implementation") — copy-paste applies.
   - You can batch-test by checking out each PR in turn (or in 4 more review-only worktrees if you want them all running at once).
5. For each PR:
   - **Approve** → merge.
   - **Need fixes** → comment, apply `agent-revise` label.
6. Revise pass (a single AFK runner with `--mode revise`) polls PRs labeled `agent-revise`, picks them up one at a time, addresses feedback, relabels `awaiting-review`. The revise pass uses `gh pr checkout N` — if you're worried about it conflicting with other in-flight worktrees, give it its own dedicated revise worktree.
7. You re-review the revised PRs, merge.
8. **Merge order**: same as Scenario B — merge #5 first if there's a `sidebar.tsx` conflict with #4.
9. `gh issue close N` happens automatically via the `Fixes #N` line in each PR.

**#6 (Phase 3)**
After #5 has merged, single worktree → PR → review → merge.

**#8 (HITL QA)**
Same as the others. Manual walk-through.

### Pros / cons

**Pros**
- **Best balance** of speed and safety: Phase 2 parallelism + every change reviewed.
- Human review batched (4 PRs in one sitting) is cheaper per-PR than serialized.
- `agent-revise` round-trips feedback without you typing follow-up issues.
- Still has the "decline a bad PR with zero side effects" property.

**Cons**
- **Most moving parts** of the three scenarios. You're juggling worktrees, PRs, labels, and a revise pass.
- Requires the PR-opening capability built into AFK (increment 1 from `pr-feedback-loop.md`).
- Requires the revise loop built (increment 2 from `pr-feedback-loop.md`) — or you skip it and re-tag the agent manually with a follow-up issue.
- Same `node_modules` × N worktrees disk cost as Scenario B.
- `sidebar.tsx` merge conflicts still possible — the PR mechanism doesn't make them go away, but you'll hit them at merge time, not at agent time.

### When to pick

- This is the **default for serious production work** once you've used AFK enough to trust the agent for ~80% of slices and want review on the remaining 20%.
- The team or you wants every change behind a PR for compliance / audit / habit reasons.
- The dependency graph has genuine parallelism worth exploiting (true here).

---

## Comparison

| | **A: PRs only** | **B: Worktrees only** | **C: Combined** |
|---|---|---|---|
| Wall time (this gamification) | ~10h | ~3h | ~5–6h |
| Human review per change | ✓ | ✗ | ✓ |
| Parallel agents | ✗ | ✓ (Phase 2) | ✓ (Phase 2) |
| `sidebar.tsx` merge conflicts | None | 1 likely | 1 likely |
| Disk cost | 1× node_modules | 4–5× node_modules | 4–5× node_modules |
| Operational complexity | Lowest | Medium | Highest |
| Reversibility of a bad slice | Decline PR | `git revert` + cleanup | Decline PR |
| Required AFK changes | Increment 1 (open PRs) | None — works today | Increments 1 + 2 |

## Reverting in each scenario

For the general revert mechanics (close-before-merge, `git revert` after, Case A vs Case B), see [pr-feedback-loop.md → When things go wrong](pr-feedback-loop.md#when-things-go-wrong--how-to-revert). Here's what reverts look like for the actual gamification slices in each of the three scenarios above (plus the no-PR baseline you actually used).

The dependency graph determines blast radius:

```
         #2 ◄── everything depends on this
       ┌──┬──┬──┬──┐
       │  │  │  │  │
       ▼  ▼  ▼  ▼  ▼
      #3 #4 #5 #7   ← all independent of each other
                │
                ▼
               #6  ← depends on #5
                │
                ▼
               #8  ← depends on all
```

- Reverting **#3 / #4 / #7** → independent siblings. Clean reverts (Case A).
- Reverting **#5** → cascade. #6 (dashboard) and #8 (QA pass) reference streak code (Case B).
- Reverting **#2** → catastrophic. Everything depends on it. You'd be reverting all 7 slices.

### Scenario A — PRs only

**Bad slice caught DURING review (before merge):**
```bash
gh pr close 103 --comment "Bug found, redo"
```
Done. The next AFK build pass will pick up the issue again from the top.

**Bad slice caught AFTER merge:**
```bash
# On github.com: click "Revert" button on PR #103.
# GitHub creates a revert PR; review and merge it.
# OR locally:
git revert -m 1 <pr-103-merge-sha>
git push
```

Cascade if needed (e.g. PR for #6 dashboard already merged on top of bad #5):
```bash
git revert -m 1 <pr-for-#6-merge-sha>   # revert #6 first
git revert -m 1 <pr-for-#5-merge-sha>   # then #5
git push
```

### Scenario B — Worktrees only

**Bad slice caught BEFORE merge** (still in its worktree, never merged to main):
```bash
git worktree remove ../worktrees/5-streaks
git branch -D 5-streaks
```
Cheapest revert in any scenario — no commits ever existed in the canonical history.

**Bad slice caught AFTER merge:** same as Scenario A's after-merge — `git revert <merge-sha>` and push. But there's no PR mechanism, so no auto-generated revert PR. You commit the revert directly.

### Scenario C — Combined PRs + worktrees

**Bad slice caught BEFORE merge:**
- Close the PR: `gh pr close 103`.
- Optionally inspect the bad worktree first: `cd ../worktrees/5-streaks && git log` — it's still there for you.
- When done debugging: `git worktree remove ../worktrees/5-streaks`.

**Bad slice caught AFTER merge:** same as Scenario A — GitHub's revert button.

### What we actually did (no PRs, direct commits to `04.01.01`)

This is the no-PR baseline — every commit went straight to the working branch. To revert slice #5 (streaks, `525f13f`):

```bash
git revert 525f13f
git push
```

But because the dependency graph stacks, slice #5 has consumers downstream:

```
   ┌── 525f13f #5 streaks (BAD)
   │   ┌── 1793d06 #6 dashboard summary  ◄── uses streak block
   │   │   ┌── 2b345b7 #8 QA pass          ◄── verified #5's behavior
   ▼   ▼   ▼
   ────────►  04.01.01
```

Reverting only `525f13f` leaves #6 referencing ghost code → app breaks. So you'd revert in reverse order:

```bash
git revert 2b345b7   # undo QA pass
git revert 1793d06   # undo dashboard (it depended on streaks)
git revert 525f13f   # undo streaks itself
git push
```

Three commits to roll back one bad slice. Plus you'd manually reopen issues #5, #6, #8 on GitHub because nothing auto-reopens them.

### Comparison

| Scenario | Bad slice caught BEFORE merge | Bad slice caught AFTER merge |
|---|---|---|
| A (PRs only) | Close PR — zero cost | GitHub revert button → revert PR → merge |
| B (Worktrees only) | Delete worktree — zero cost | `git revert` directly |
| C (Combined) | Close PR (worktree available for debugging) — zero cost | GitHub revert button |
| What we did (no PRs) | N/A — every commit IS a "merge" | `git revert` (cascade if downstream slices exist) |

The PR-based scenarios all have a "before merge" escape hatch that costs nothing. The no-PR baseline doesn't — every iteration is final the moment it commits.

## Recommendation for this gamification feature

**Scenario C** if you have the appetite to build the PR-opening + revise capability into AFK first. The four-issue Phase 2 fan-out alone saves ~3 hours of wall time over Scenario A while preserving review.

**Scenario B** if you don't want to build any AFK changes and you're confident in the agent. This is the closest match to what you actually did with Claude Desktop AFK in our session — except you used a single shared context instead of parallel worktrees, which left ~3 hours of parallelism on the table.

**Scenario A** if you're new to AFK or this is your first PR-driven workflow. Get comfortable with the build-pass-opens-PR + you-review pattern before adding worktrees on top.

Whichever you pick: #8 (HITL QA) is always you, manually, at the end.

## Using this walkthrough as a learning experiment

If you've already shipped the gamification feature once (with any of the three workflows above, or with the no-PR baseline), you can use the same set of issues as a controlled experiment to feel the difference between workflows. Same feature, same dependency graph, same expected output — only the workflow changes.

This is the cleanest way to learn what the workflows actually feel like. Reading this doc isn't the same as running them.

### Pre-flight checklist

Before resetting the repo to the pre-gamification state:

**1. Preserve the current implementation as a baseline.** Don't just reset — tag or branch the current state first so the working version isn't lost:

```bash
git tag gamification-direct-commits
# OR if you'd prefer a branch you can check out later:
git branch gamification-v1
```

Now you can compare each new workflow run against the original as a reference.

**2. Reopen the closed issues.** AFK won't pick them up otherwise:

```bash
gh issue reopen 2 3 4 5 6 7 8 --repo <owner>/<repo>
```

**3. Reset to the right commit.** The commit immediately before the gamification work began (in this repo's history, that was `9b7276b` — find your equivalent):

```bash
git reset --hard <pre-gamification-sha>
# If you've pushed the working branch and want the remote to match:
git push --force-with-lease origin <branch-name>
```

> **Reset > revert here.** Revert would create N inverse commits, leaving an ugly history of "implemented gamification, then undid it all." Reset rewinds cleanly to a pre-gamification state. The tag preserves what you'd otherwise lose.

### Suggested order

**Run 1: PR feedback loop** (Scenario A above).

Bigger conceptual shift, you'll feel the most difference. The only prerequisite is a small `prompt.md` change to make AFK open PRs instead of merging directly:

```
[in afk/ralph/prompt.md, replace the "commit + close issue" steps with:]

6. git push -u origin <branch-name>
7. gh pr create --label pending-review \
     --title "Fixes #N: ..." \
     --body "<details>"
8. gh issue close N --comment "Implemented in PR #M"
```

~10 lines of prompt change. Then run AFK and observe what the PR-per-slice flow feels like.

**Run 2: Worktree workflow** (Scenario B above) or **combined** (Scenario C above).

After the PR run, reset again and try worktrees — either alone (parallel direct merges) or combined with PRs (parallel PRs). Combined is the "best of both" pattern from this doc.

### Time budget

A single end-to-end run of gamification is ~5–6 hours of agent + supervision in one Claude Desktop session. Re-running for each workflow is ~same. Both workflows ≈ 2x the original.

If you're up for the full experiment: you'll have hands-on experience with all three patterns. If you're pressed for time: do one — the PR loop is the higher-information run because it's the bigger conceptual shift from direct commits.
