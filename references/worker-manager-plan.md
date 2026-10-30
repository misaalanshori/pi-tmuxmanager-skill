# Worker-Manager Plan — Supervisor and Pi Workers under Tmux

This plan describes how the Manager Agent dispatches and supervises pi worker agent(s) under tmux. The manager does setup, priming, dispatch, supervision, review, and disk hygiene.

## 1. Topology

| Role | Where | Notes |
|---|---|---|
| manager (me) | this session | writes briefs, dispatches, sleeps in `worker-wait.sh`, reviews, merges |
| Worker 1 | `tmux -L $TMUX_SOCKET`, session `worker-1`, cwd = primary or wt1 | pi interactive TUI |
| Worker 2 | `tmux -L $TMUX_SOCKET`, session `worker-2`, cwd = wt2 | pi interactive TUI — **only in dual-worker mode, off by default** |

A dedicated, isolated socket (`$TMUX_SOCKET`) is used for the management plane so that worker sessions never collide with any other tmux sessions on the machine.

## 2. Setup protocol

1. `tmux -L $TMUX_SOCKET new-session -d -s worker-1 -c /path/to/repo 'bash --norc'`
2. Start pi with the designated model:
   `pi --model antigravity/gemini-3.8-flash --models "antigravity/gemini-3.8-flash,opencode-go/mimo-v2.6-flash"`
   Verify the footer in the pane.
3. Prime (the exact two prompts in order, waiting for each to finish before the next):
   a. "Read the README and the ./docs, no need to read the code yet. just explain to me as if im a minimally-technical stakeholder"
   b. "okay now read and analyze the actual code, just to get your bearings"
4. The agent is primed and stays primed across cycles.

## 3. Cycle protocol

1. **Brief**: Write the cycle's prompt file (e.g. `PROMPT-<ID>-<date>.md`) with full RCA, exact design, TDD requirements, and acceptance criteria.
2. **Dispatch**: Substitute `${prompt_path}` and a fresh `${done_channel}` (e.g. `worker-done-1`) into `worker-dispatch-prompt.md.tpl`, and deliver it into the pane via `tmux load-buffer` + `paste-buffer -p`.
3. **Supervise**: `./worker-wait.sh --socket "$TMUX_SOCKET" --session "$TMUX_SESSION" --channel worker-done-1 --max-secs 3600`
   — one blocking call; the manager sleeps inside it. **Re-waits within the same cycle MUST reuse the same channel**.
   Exit codes:
   | rc | meaning | manager action |
   |---|---|---|
   | 0 | cycle complete | review (§4), then continue/compact decision |
   | 1 | idle without signal | capture-pane; stuck or a question — answer or nudge |
   | 2 | max time elapsed | capture-pane; still working → call worker-wait again with same channel |
   | 3 | pi crashed | rescue: restart pi, `--continue` the session, re-dispatch |
   | 4 | setup error | missing session or socket |
   | 5 | disk pressure | free space fell below minimum threshold; clean target dirs |
4. **Continue vs compact**: After each cycle, read the context % from the pane footer. **< 45% → dispatch the next cycle immediately. ≥ 45% → `/compact` first** (wait for completion and verify context dropped; if degraded, start a fresh primed session per §2). Never allow a worker to carry $\ge 45\%$ into a new cycle.
5. **Continuous autonomous loop**: Never return the turn to the human operator between cycles or issues. The manager immediately loops to §3.1 for the next open issue until all issues are completed. Do not poll the worker during execution; sleep inside `worker-wait.sh`. The manager has plenty of context tokens and must not suffer from context anxiety.

## 4. Review on completion (Strict TDD & Quality Audit)

- **Test-Driven Development (TDD)**: Verify failing tests were written first and committed/demonstrated before implementation.
- **Verification Gates**: Run `cargo check`, `cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D warnings`, and `cargo nextest run --workspace`.
- **Rust Quality**: No unwrap/expect in production code paths, clean error propagation, no needless cloning, no held locks across async await points.
- **Acceptance Criteria**: Check that every requirement in the brief has evidence of completion.
- **Docs & Change Log**: Updated documentation, Architecture Decision Records (if any), and CHANGELOG entries.

## 5. Disk hygiene

- `worker-wait.sh` prints `df` and target sizes on every return.
- **Prune only at cycle boundaries** (never while a build is in progress): before each dispatch, if `target/` > 25 GB or free disk < 25 GB, run `cargo clean`.

## 6. Dual-Worker Topology (optional — off by default)

The default is the single-worker topology in §1. When the operator asks for two
concurrent workers:
- **Topology**: Worker 1 (`worker-1`) in worktree 1; Worker 2 (`worker-2`) in worktree 2, both on `tmux -L $TMUX_SOCKET`.
- **Priming**: Worker 2 gets the two mandatory priming prompts in order, exactly like Worker 1.
- **Channels**: `worker-done-w1-<cycle>` / `worker-done-w2-<cycle>`; fix-ups `...fix`. `worker-wait-both.sh` blocks on both.
- **Batch partition**: Orthogonal batches by crate / subsystem to minimize merge friction.
- **Branches**: Neither worker pushes to `main` directly. Workers commit to `worker-1/<batch>` and `worker-2/<batch>`. The manager merges into `main`, resolves shared-file conflicts (`Cargo.lock`, `CHANGELOG.md`), runs all gates, pushes, and rebases worktrees at cycle boundaries.

## 7. Worktree Rules (two-worker mode)

In the default single-worker mode there are no branches at all: the worker commits
and pushes to `main` directly. These rules apply once two workers share a repo.

1. **Only the manager touches `main`.** Workers commit strictly to their own branch.
2. Each worker operates strictly within its own worktree directory.
3. The manager merges worker branches into `main`, runs full workspace test suites, and pushes.
4. Rebases onto `main` happen only at cycle boundaries while the worker is parked.
