---
name: pi-tmuxmanager-skill
description: Run one agent as a manager that dispatches, supervises and reviews another agent working in a tmux pane (a "worker"). Use whenever the user wants an agent to drive another agent through development cycles — write a cycle brief, paste it into a worker pane, block on a completion signal instead of polling, review every diff hunk before closing an issue, keep a worker's context and the machine's disk under control, or drain a GitHub issue queue autonomously. Trigger on phrases like manager agent, worker pane, dispatch the next issue, supervise the worker, tmux wait-for channel, worker-wait, review the worker's cycle, dual worker, or "let the manager work through the backlog" — even when the user never says "skill".
compatibility: Requires an Agent Skills host (pi, Claude) plus bash, tmux, gh, python3 and a Unix-like shell. The scripts rely on tmux `window_activity` and `wait-for` channels and on GNU `df`/`du`; they do not run natively on Windows.
---

# Manager and worker agents under tmux

One agent plans and reviews; a second agent, running `pi` inside a tmux pane, does
the work. The manager writes a brief, dispatches it, sleeps on one blocking wait,
then audits every hunk before the issue closes. The split exists so that a long
cycle costs the manager nothing while it runs, and so review is done by a session
that did not write the code.

```
manager (a pi session, cwd = the project repo)   writes briefs, dispatches, sleeps, reviews, merges
tmux -L $TMUX_SOCKET / session $TMUX_SESSION     the worker: pi interactive agent in the repo
```

Everything here is mechanism. Project-specific policy (which model, which crates,
which gates) belongs in the brief you write for that cycle.

## Before the first dispatch

Nothing is baked in: every script takes its values as flags or env and exits `4`
with usage if one is missing. Decide these once and keep them stable for the session.

| Value | What it is | Why it must be explicit |
|---|---|---|
| `TMUX_SOCKET` | dedicated tmux socket for the management plane | a shared machine has other tmux sessions; the management plane must never collide with them, and never use the default socket |
| worker session name (`TMUX_SESSION`, or `--s1`/`--s2`) | the pane running the worker | one socket can host several workers; naming them keeps channels, logs and steers from crossing |
| completion channel | `worker-done-<cycle>` | a fresh name per cycle prevents a stale signal firing the next dispatch early; the same name must be reused for re-waits *within* one cycle |
| worktree roots (`WT1`, `WT2`) | checkouts whose `target/` the disk guard watches | disk pressure is per-worktree; guessing the path silently disables the guard |
| worker model | a provider-qualified id, plus fallbacks | unqualified ids are ambiguous across providers; the footer is the ground truth that the intended model loaded |

Also record the worker's **session uuid** after its first turn (not at launch —
the file may not exist yet, and sampling early once captured the manager's own
session). `scripts/worker-log.sh` needs it: several sessions share one project
directory, so "the newest log" is not a safe guess.

## The cycle

The playbook has the full version and the scar tissue behind each step
(`references/manager-cycle-playbook.md`). The shape:

1. Read the issue live, with its whole comment thread. Bodies go stale; comments
   carry the corrections.
2. Do the root-cause analysis yourself first. The brief must carry a mechanism,
   not a symptom — and a brief written from an issue body alone usually quotes
   paths that no longer exist.
3. Write the brief out-of-tree: goal, verified mechanism, decided design with the
   rejected alternatives, acceptance criteria, test policy, gates, completion
   signal.
4. Post a short design note on the issue so the reasoning is visible where the
   work is tracked.
5. Dispatch: `load-buffer` + `paste-buffer -p` for anything long, because typed
   text gets mangled; then `Enter`. Confirm the worker actually started.
6. Supervise with **one** blocking call to `scripts/worker-wait.sh`, then act on
   its exit code. Never poll: the script is the poller, and the manager sleeps.
7. Tail the session log at every return. The pane shows where the worker is; the
   log shows what it thinks it is doing, and drift is visible there first.
8. Steer with a diagnosis and a fix shape, not a nudge. If a worker has not
   completed a turn in ~15–20 minutes while looking busy, it is stuck in a
   command, not thinking.
9. Review the whole diff, run the gates yourself, and drive the user journey
   once. A green worker claim is a claim.
10. Comment with evidence, close, re-dispatch the now-idle worker, then pick the
    next issue. An idle worker is a defect, not a reward.

## What the manager never does

Each of these cost a real cycle; the reasoning is in the playbooks.

- **Poll.** One blocking wait per dispatch. Repeated `capture-pane` burns turns
  and tells you less than the log.
- **Dispatch to a worker whose context is ≥45%.** Compact first and verify the
  footer actually dropped; a failed compaction must not be mistaken for a fresh
  worker. A context percentage that never moves between check-ins is a worker
  that has not finished a turn, not a fresh one.
- **Trust a brief's own path claims.** Verify file paths, symbols and requirement
  ids against the tree and the spec before writing them. Line-number RCA is a
  hypothesis generator, not a finding.
- **Accept a green suite as proof.** Mutation-check a new guard: if you cannot
  watch it fail for the reason it exists, it is decoration.
- **Spend a cycle testing someone else's runtime.** Test our logic, our state
  transitions, our routing; isolate providers, OS primitives and third-party
  behaviour behind mocks.
- **Let a command hang.** Bound anything that can block (`timeout 300 cargo
  nextest run …`). For a probe, the bound *is* the measurement.
- **Put a secret through the pane.** Keys travel by file reference and are read
  with `export KEY=$(cat path)`; never inline in a brief, a command line or a
  scrollback.
- **Yield the turn mid-queue.** If work remains and nothing is genuinely blocked,
  keep looping.

## Scripts

All four print `--help`; a missing required value exits `4`.

| Script | Use |
|---|---|
| `scripts/worker-wait.sh --socket … --session … --channel …` | the single blocking wait. `0` signal → review, `1` idle without signal → peek, `2` deadline → peek then re-wait with the *same* channel, `3` worker gone → rescue with `--continue`, `4` usage/setup, `5` disk pressure |
| `scripts/worker-wait-both.sh --s1 … --s2 … --ch1 … --ch2 … --wt1 … --wt2 …` | one blocking wait over two workers; returns on the first to change state |
| `scripts/worker-log.sh -n 50 <uuid-substring>` | pretty-tail the worker's session JSONL (tool calls, reasoning, errors) |
| `scripts/disk-guard.sh --wt1 … --wt2 … [--check\|--clean-idle]` | `--check` exits `1` under pressure; `--clean-idle` prunes the larger `target/` only when no `cargo`/`rustc` is running anywhere |

`worker-wait.sh --selftest` runs the supervisor's own 7 cases against throwaway
tmux sessions. Run it on the target host before trusting the wait.

## References

| Read this | When |
|---|---|
| `references/manager-cycle-playbook.md` | moving a cycle end to end: topology, rc handling, merge/rebase etiquette, dual-worker and worktree rules, storage monitoring |
| `references/manager-review-checklist.md` | the review pass: every hunk, test sanctions, smell scan, the flaky-test ledger |
| `references/tmux-subagent-playbook.md` | driving the pane: piping output, `Ctrl+C` vs `Ctrl+D`, rescue ladder, model switching, channel hygiene |
| `references/worker-manager-plan.md` | setup and lifecycle: provisioning, priming, context decisions, disk policy, dual-worker partitions |
| `references/dev-cycle-prompt.md` | the phased TDD loop to append to a brief; placeholder slots are marked |
| `assets/worker-dispatch-prompt.md.tpl` | the text you paste per cycle; substitute the brief path, the socket and a fresh channel |
| `references/manager-prompt.md` | stand-alone loop prompt for a manager session that has none of this in context |
| `references/manager-init-prompt.md` | bootstrap prompt: orient, verify the worker plane, enter the loop |
| `references/manager-dual-worker-prompt.md` | converting a single worker setup into two workers in two worktrees |
| `references/manager-deepseek-offpeak-prompt.md` | gating dispatches to one worker on provider price windows |
| `references/manager-session-notes.md` | worked history (~50 cycles, dated sections): what actually failed and what fixed it. Read the newest sections; jump with `grep -n '^## '`. History, not instructions |

Paths inside the bundled docs are relative to this skill directory (the one
holding `SKILL.md`). Briefs and cycle reports are not bundled: they belong in the
workspace beside the target repo, so a worker never commits them.

## Known contradictions in the source material

These predate this reorganization and were left as written rather than silently
"fixed"; resolve them explicitly per project.

1. `manager-deepseek-offpeak-prompt.md` mandates a peak/off-peak dispatch gate,
   while the playbook records off-peak scheduling as **ignored** by owner
   directive (both workers run continuously).
2. Topology: the playbook's last topology section says three worktrees with the
   manager owning `main`; the newest session notes say single worker, no
   worktrees, worker pushes `main` directly.
3. File ceiling: the review bar says 1,100–1,200 lines per file; the enforced gate
   in the notes' project is 1,600.
4. Disk floor: the playbook says the guard trips below 40 GB free; `disk-guard.sh`
   defaults to 25 (`FREE_MIN_GB`).
