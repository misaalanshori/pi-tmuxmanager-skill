> **Optional mode — OFF by default.**
> The default topology is one worker in one checkout, committing straight to the
> main branch: no second worktree, no merge step, no `worker-wait-both.sh`, no
> partitioned batches. Run this procedure only when the operator explicitly asks
> for two workers — see "Operating modes" in `SKILL.md`. Step 5 (recording the
> protocol in the notes) is already done in these bundled documents, so record
> only what this particular project changes.

Alright, a single sequential worker is not using our token and rate limits efficiently, so we are upgrading our topology to **two parallel worker agents** operating in separate Git worktrees. Your job is now to set up, prime, dispatch, supervise, review, and merge both workers concurrently while keeping merge conflicts to a minimum by partitioning their tasks across orthogonal parts of the codebase.

Execute the following steps immediately and record this new dual-worker protocol in our out-of-tree notes (`references/manager-cycle-playbook.md`, `references/worker-manager-plan.md`, and `references/tmux-subagent-playbook.md`) for future reference:

#### 1. Provision the Second Worktree & Tmux Worker Session (`worker-2`)

* **Worktree Setup**: Keep the primary worker (`worker-1`) in the primary checkout, and create a second Git worktree out-of-tree (e.g., `git worktree add ../repo-wt2 -b worker-2/batch-1`).


* **Tmux Session Creation**: On our dedicated management socket (`tmux -L $TMUX_SOCKET`), create a second worker session named `worker-2` starting in the second worktree:
`tmux -L $TMUX_SOCKET new-session -d -s worker-2 -c /path/to/worktree 'bash --norc'`


* **Model Launch**: Launch `pi` in `worker-2` using the exact same primary and fallback model configuration as `worker-1`:
`pi --model <provider>/<model> --models "<provider>/<model>,<provider>/<fallback>"`
Verify the footer in the pane to confirm the model loaded properly.


* **Mandatory Two-Step Priming**: Prime `worker-2` with the exact two priming prompts in order, waiting for `worker-2` to go idle between them:

1. `"Read the README and the ./docs, no need to read the code yet. just explain to me as if im a minimally-technical stakeholder"`
2. `"okay now read and analyze the actual code, just to get your bearings"`


* **Session UUID Registration**: Once `worker-2` completes its first turn and writes its session file, run `ls -t ~/.pi/agent/sessions/*/*.jsonl` to grab and record `worker-2`'s unique session UUID alongside `worker-1`'s UUID so you never mix up Worker 1, Worker 2, or your own Manager session when tailing logs with `scripts/worker-log.sh`.



#### 2. Orthogonal Issue Batching & Conflict-Free Briefing

* **Partition by Crate/Subsystem**: When pulling open issues (`gh issue list` / `gh issue view <n> --comments` with `.author.login == "$OWNER_LOGIN"` verified), select two batches that touch **completely disjoint areas** of the workspace:
* *Example Partition*: Assign Worker 1 (`worker-1`) issues in frontend/surface crates (e.g. `crates/proxy`, `crates/admin`, `crates/server`), and assign Worker 2 (`worker-2`) issues in core/data crates (e.g. `crates/core`, `crates/proto`, `crates/store`).


* **Explicit Scope & Strict TDD Guardrails in Briefs**:
* Write separate out-of-tree briefs for each worker (`../PROMPT-W1-<ID>-<date>.md` and `../PROMPT-W2-<ID>-<date>.md`) following the full RCA-and-design standard.
* Emphasize Test-Driven Development (TDD): require writing failing unit/integration tests first before touching implementation code.
* In each brief, explicitly state which crates/files the worker is permitted to touch and forbid touching files outside that boundary.
* Instruct each worker **not** to `git push origin main` directly if both branches are in flight; instead, have each worker commit cleanly to its local branch (`worker-1/...` and `worker-2/...`) and push its feature branch (or let you merge into `main` and push after review).



#### 3. Parallel Dispatch & Dual-Worker Supervision

* **Distinct Completion Channels**: When rendering `assets/worker-dispatch-prompt.md.tpl` for each worker, assign worker-specific completion channels (`worker-done-w1-<cycle>` for `worker-1` and `worker-done-w2-<cycle>` for `worker-2`). Tell `worker-2` to run `tmux -L $TMUX_SOCKET wait-for -S worker-done-w2-<cycle>` upon completion.


* **Verify Both Starts**: After pasting each dispatch via `tmux -L $TMUX_SOCKET load-buffer` + `paste-buffer -p` + `Enter`, check both panes after ~45–60 seconds and run `scripts/worker-log.sh -n 25 <uuid-w1>` and `scripts/worker-log.sh -n 25 <uuid-w2>` to confirm both workers are `● Working` and aligned.


* **Dual-Worker Blocking Wait**: Run `scripts/worker-wait-both.sh --socket "$TMUX_SOCKET" --s1 worker-1 --s2 worker-2 --ch1 worker-done-w1-<cycle> --ch2 worker-done-w2-<cycle> --wt1 "$WT1" --wt2 "$WT2"` so that a single blocking invocation watches **both** `worker-1` (`--ch1 worker-done-w1-<cycle>`) and `worker-2` (`--ch2 worker-done-w2-<cycle>`) on `tmux -L $TMUX_SOCKET` and returns as soon as **either** worker signals completion (`rc 0`), goes idle for 120s (`rc 1`), crashes (`rc 3`), or hits the deadline (`rc 2`). Remember to reuse the exact same channel name whenever re-waiting on a still-running worker within the same cycle.


* **Verification & Log Tailing**:
* At every wait return, tail **both** session logs (`scripts/worker-log.sh -n 40 <uuid-w1>` and `scripts/worker-log.sh -n 40 <uuid-w2>`). If either worker is stuck or drifting, diagnose the code yourself and send a mechanism-level steering prompt to that specific worker.
* Run verification via cargo gates and integration tests independently to confirm ongoing test pass rates without relying on manual terminal drives.



#### 4. Review, Merging, Conflict Resolution & Disk Hygiene

* **Independent Review First**: Whenever a worker signals completion, run the review checklist inside that worker's worktree (`git show` on every commit hunk, test sanction check, functional/test gap audit, Rust anti-pattern scan, TDD adherence, and cargo test/nextest runs). If it fails review, dispatch a fix-up brief to that worker on a fresh `worker-done-w<1|2>-<cycle>fix` channel while the other worker keeps running.


* **Merge & Conflict Resolution**:
* Once a worker's branch passes review, rebase or merge it onto `main`.
* If both workers touched shared files (such as `Cargo.lock`, `./CHANGELOG.md`, or `./docs/*`), resolve the merge conflicts yourself, regenerate/verify `Cargo.lock`, and run the full gate suite (`cargo check --workspace --all-targets`, `cargo fmt --check`, `cargo clippy --workspace --all-targets -- -D warnings`, cross-target Windows clippy if `cfg` code was touched, and `cargo nextest run`) on the merged `main` before pushing and verifying CI.
* When the other worker reaches its cycle boundary, fast-forward/rebase its worktree onto the updated `main` before dispatching its next batch so it never works off a stale base.


* **Two-Worktree Context & Disk Hygiene**:
* At each worker's cycle boundary, check its footer context % independently (`< 45%` $\rightarrow$ dispatch next batch immediately; $\ge 45\%$ $\rightarrow$ run `/compact` and verify the drop before dispatching).
* Because two worktrees will double `target/` disk consumption, check `df -h` and target folder sizes at cycle boundaries, and run `cargo clean` in either worktree (only when that worker is idle at a boundary, never mid-build!) whenever combined `target/` size exceeds 25–30 GB or free disk space drops below 25 GB.



#### 5. Save to Out-of-Tree Notes Immediately

* Before starting the first dual dispatch, update `references/manager-cycle-playbook.md`, `references/worker-manager-plan.md`, and `references/tmux-subagent-playbook.md` with:
1. The dual-worker topology (`worker-1` in primary checkout and `worker-2` in the secondary worktree on `tmux -L $TMUX_SOCKET`).
2. Both workers' active session UUIDs and completion channel naming scheme.
3. The orthogonal crate-partitioning rule and merge/rebase conflict-resolution protocol.
4. Dual-worktree `target/` disk hygiene rules.
