# Manager cycle playbook (out of tree — how one dispatch runs end to end)

The companion to `manager-review-checklist.md` (which covers WHAT to
check): this covers HOW a cycle moves. Written 2026-10-06 from ~40
cycles of scar tissue.

## Contents

- **Topology (fixed)**
- **The cycle (every dispatch, in order)**
- **Standing mechanics**
  - Before any wait: confirm the worker is actually working (owner, 2026-10-22)
  - Re-dispatch is part of the merge, not after it (owner correction, 2026-10-21)
  - Every hang-prone command gets a timeout (owner, 2026-10-23)
  - Verify every path in a brief against the tree before dispatching (manager, 2026-10-24)
  - Three tells a worker is wedged, and the one I ignored (owner, 2026-10-23)
- **Prioritization law (owner, restated 2026-10-21 — read this before any dispatch)**
- **Dual-worker topology — OPTIONAL, off by default (owner directive, 2026-10-20)**
  - Storage monitoring (owner escalation, 2026-10-20 — two worktrees crashed the machine)
  - Manager gate runs must not overlap a worker build (2026-10-20, dual-worker)
  - Root cause of the disk crisis, fixed in the profiles (2026-10-20)
  - Pricing-window scheduling — off by default (owner, 2026-10-21)
  - A byte-comparison gate is not a portable gate (2026-10-21, #427)
  - Provider failure: retry first, switch only if it stays down (owner, 2026-10-21)
  - Worker session recycling, with a helper that lied (2026-10-21)
  - Three-worktree topology + "manager owns main" (two-worker mode, 2026-10-21)
  - Sending a slash command while a worker is mid-turn (2026-10-21)

## Topology (fixed)

- **Worker count defaults to one.** A second worker is an opt-in mode (see
  "Operating modes" in `SKILL.md`); read every section below as single-worker
  unless it says otherwise.
- Manager: a pi session. Worker: pi in `tmux -L $TMUX_SOCKET`, session
  `worker-1`, cwd = the repo. Separate socket so the management plane never
  collides with other sessions. NEVER the default socket (shared machine).
- Worker model + thinking are owner-set; record both at setup. A model
  switch = clean exit (`C-d`, record the resume uuid) + relaunch with
  `--model <provider-qualified-id> --models '<same>' --session <uuid>`
  + a "continue exactly where you left off" nudge. Verify the footer.
- Worker session uuid: the pi session file created AFTER launch (grab
  it late, not at launch — the file may not exist in the first
  seconds; grabbing early once mis-attributed the manager's own log).
  `worker-log.sh -n N <uuid-substring>` pretty-tails it.

## The cycle (every dispatch, in order)

1. **Read the issue live** (`gh issue view <n> --comments`): body +
   FULL thread + author check (`$OWNER_LOGIN` only). Never brief from a
   stale copy.
2. **RCA yourself first.** Read the code the issue names; verify the
   mechanism; make the design calls (scope, divergences, what is
   explicitly out). The brief carries mechanism-level diagnosis, not
   symptoms. If the worker will need pi ground truth, name the exact
   files.
3. **Write the brief** (`PROMPT-<X>-<date>.md`):
   goal → verified mechanism → decided design (with alternatives
   killed and why) → acceptance criteria → test policy (sanctioned
   changes named; strict TDD required) → verification triad (local gates,
   nextest test suites, CI) → docs updates → constraints → completion
   protocol with a FRESH `done_channel` per cycle.
4. **Post a progress comment** on the issue (design + scope notes).
5. **Dispatch**: short message referencing the brief + `load-buffer` +
   `paste-buffer -p` for long text (`-p` = real bracketed paste) +
   Enter. Confirm `● Working` within a minute.
6. **Supervise** with `worker-wait.sh --socket "$TMUX_SOCKET" --session "$TMUX_SESSION" --channel <chan>`: ONE blocking
   call per wait (the agent never polls; the script may). Exit codes:
   0 = signal (review), 1 = idle without signal (peek: stuck or a
   question), 2 = deadline (~1h — peek, judge, re-wait SAME channel),
   3 = pi gone (rescue with `--continue`), 4 = setup error. At EVERY
   return, tail the worker log DEEP (`-n 40+`) for alignment — confusion
   and phantom-chasing show in the log minutes before the pane does.
7. **Steer with answers, not nudges.** When it struggles, diagnose
   first (read the code yourself), then send the mechanism + the fix
   shape. Mid-turn messages queue as steers (join at the next
   boundary) — good for steering, terrible for urgent stops; for a
   real stop, wait for idle. Never let it spin more than ~30 min on
   one wall.
8. **Review** (the checklist file — every hunk, sanctions, smells,
   evidence run yourself, secrets grep). Fix-ups get their own brief +
   FRESH channel (`worker-done-<x>fix`), never the same channel
   (stale-signal hygiene cuts both ways: same channel for re-waits,
   fresh channel for new work).
9. **Comment + close** with evidence (commits, guards, receipts, CI
   run ids, deviations). Check for late owner comments FIRST.
10. **Loop immediately to Step 1.** NEVER return the turn to the user or
    ask for confirmation. As long as open issues authored by `$OWNER_LOGIN`
    exist, loop continuously and autonomously. Only stop when the issue list
    is completely cleared.

## Standing mechanics

- **Autonomous loop mandate**: The manager never yields the turn back to the
  human operator between issues. Complete one issue $\rightarrow$ close it
  $\rightarrow$ immediately pick and brief the next.
- **Zero polling**: The manager does not poll the worker. Call `worker-wait.sh`
  once and sleep inside it. Polling burns tokens and turns for zero gain.
- **Worker compaction discipline ($\ge 45\%$)**: Never let a worker carry
  $\ge 45\%$ context into a new cycle. Check the footer at every cycle boundary;
  if $\ge 45\%$, send `/compact` and verify the drop before dispatching.
- **Zero context window anxiety**: The manager session has plenty of context
  tokens (1M+ limit). Do not cut corners, skip diff lines, or rush reviews
  because of imagined context budget pressure. Thoroughness beats token thrift.
- **Disk**: `cargo clean` at boundaries only (never mid-build), when
  target/ > 25 GB or free < 25 GB.
- **Manager's own commits** (docs, notes, releases): only on a clean
  tree while the worker is parked in a wait (CI-watch, gates) — never
  with uncommitted worker work in flight; push immediately so nothing
  lingers to be swept into the worker's next commit.
- **Release flow**: worker preps (changelog + bump + all 11 gates),
  manager reviews + drives the manual gate + cuts the tag (never
  moved) + publishes + verifies (assets, checksums, attestation, real
  one-liner install). Versioning: no ABI break → no ABI bump.
- **Flakes**: one green rerun of the same commit after reading the
  failure log = documented flake (record it); a second occurrence =
  quarantine per testing-plan §13. Never retry blind.
- **Cross-target clippy** (`--target x86_64-pc-windows-gnu`) joins the
  pre-push gates whenever cfg'd code is touched.
- Worker session uuids: `01a10b25` (retired 2026-10-10 at 86%,
  compaction stopped dropping) → **`01a1277f`** (fresh + primed,
  2026-10-10). Always `ls -t` to confirm before tailing; the
  manager session (`01a0ff4c`) lives in the same dir.
- A steer that lands as "Queued message for after compaction" (or any
  queued steering) may sit un-flushed while the worker idles: send
  `Escape` then `Enter` to force it into the turn (owner tip,
  2026-10-11). Verify with `● Working` + moving context %.
- 2026-10-13: a completion signal can fire before the waiter
  starts listening (worker signaled, manager idle-polled the report
  instead). Fix: after any idle return whose pane tail already
  claims completion, verify + treat as done; do not demand a
  second signal (exactly-once cuts both ways).
- 2026-10-14 session close: backlog 30 open (stabilization rest:
  quarantines #190/#195, #53 prompts, 0.7 designs #135/#149/
  #123/#170/#171, ideas #1/#4/#5/#6/#13, owner-calls #48/#53).
  New-rule hygiene: `cargo check` pre-push (2 broken-HEAD pushes),
  SRDD dep-table row with every new dep (arboard/html2md/similar),
  lockfile commit check before signaling (2 misses), turn-level
  guards for permission behavior (authorize-level tests miss the
  path), headless-turn proof for per-turn I/O. Manager live
  drives filed #253/#254/#255/#256/#259/#261 (all fixed+closed
  except #261 UX nit).
- Worker session `01a13001` (fresh, post-OOM), Lun 2026-10-14.
  If resuming: verify tree + brief from issues (ground truth).
- 2026-10-17 (owner): the manager NEVER returns its turn while work remains —
  the autonomous loop runs continuously inside one turn; a turn ends only when
  the queue is drained (or a genuine hard blocker stands). "Continue by
  default" is the standing instruction; no checkpoint turn ends for approval.
- 2026-10-19 (scope tension, resolved): the standing dispatch template mandates
  side-by-side pi parity fixing ("compare them side by side... and then fix
  it"), while briefs carry a strict scope line. Rule from here: briefs state
  explicitly whether the parity-drive clause is OPEN (small parity gaps found
  by live driving may land, flagged in the report) or SHUT (strict scope,
  findings go to the report only). A parity fix landing under an ambiguous
  brief gets flagged in the closing comment, never silently accepted.
- 2026-10-20 (owner): **prioritize by value and development time**, not by
  recency. A newly filed or freshly updated issue is not thereby a priority.
  Step 2 weighs (user/owner value of the fix) against (estimated cycle cost:
  scope, risk, review weight) — high-value/low-cost first, epics phased so
  each phase pays back value early. Newest-first is explicitly wrong.

### Before any wait: confirm the worker is actually working (owner, 2026-10-22)

Written when two workers were running; in the default single-worker mode the same
rule reduces to step 1: capture the pane, and if its tail already claims
completion, review instead of waiting.

The race this prevents: a worker finishes and signals **while the manager is
still composing the wait**. `worker-wait.sh` then attaches after the fact,
misses the signal, and returns `rc=1 (idle)` on a worker that already finished —
which reads as "stuck", costs a diagnosis round-trip, and in one case had the
manager re-dispatching work that was already done.

Happened repeatedly this session (W1 three times, W2 twice). The symptom is a
wait return whose pane tail already claims completion and whose report file
already exists.

**The rule, in order:**

1. Capture the pane(s) (`capture-pane -p -t worker-1`, and `-t worker-2` in
two-worker mode).
2. Confirm each footer shows the working state and the expected branch. If
   either is idle — or its pane tail says it finished — **do not wait on it**:
   go straight to review/merge for that worker, dispatch its next batch, then
   wait on the other.
3. Only when both are genuinely working, call `worker-wait-both.sh` (single-worker
   mode: `worker-wait.sh`).

This is cheap (two captures, ~1 s) and it makes the wait trustworthy: a `rc=1`
return then really does mean "it went quiet", not "I was late".

Corollary, so nothing is lost when a signal *does* arrive pre-attach: a wait
return whose pane tail shows the completion command having run, and a report at
the path the brief named, is **done** — verify and proceed rather than demanding
a second signal (the exactly-once rule from 2026-10-13, now with a check that
makes it rare in the first place).

### Re-dispatch is part of the merge, not after it (owner correction, 2026-10-21)

**An idle worker is a defect, and closing an issue is not the end of a cycle —
re-dispatching the idle worker is.** The failure mode: merge the branch, post the
closing comment, close the issue, and *then* look at the other worker's CI. That
leaves the worker whose batch was just merged sitting idle for however long the
next investigation takes. It happened once this session for ~20 minutes and the
owner caught it.

The corrected order for one completion, with no step skippable:

1. Review + gates + merge + push.
2. Comment + close.
3. **Immediately dispatch that worker's next batch** (branch off the just-pushed
   `main`, write or reuse the brief, paste, verify `● Working`).
4. *Then* handle the other worker's CI trace, an incident, or the backlog scan.

Steps 3 and 4 are the common inversion: the other worker's problem feels urgent
because it is red, but a red CI has a runner watching it while an idle worker
burns nothing but time. Dispatch first.

Two mechanical checks that make it hard to forget:

- after every `git push origin main`, the next command is the other worker's
  dispatch or a wait, never an investigation;
- before any `gh issue view` / `gh run view` that is not part of a dispatch, look
  at both footers — if either says idle, dispatch first.

### Every hang-prone command gets a timeout (owner, 2026-10-23)

A worker was wedged for **3.5 hours** on a single command — `cargo run` of a
busy-spin probe with no bound, fired at 02:33 and dead until an interrupt at 06:02.
The irony is exact: the command was probing a busy-spin, and it busy-waited the
cycle away.

The rule, which goes in **every brief** from now on: a command that can hang gets a
bound —

    timeout 300 cargo nextest run ...
    timeout 120 ./scripts/thing.sh
    timeout 60 gh run view <id> --json status

The ceiling is chosen per command, not copied: a suite that legitimately takes
10 minutes gets 1200; a probe gets 60. What is never acceptable is an unbounded
call, because an unbounded call is a cycle that can silently disappear.

**A spin probe is the case that most needs the bound, not the least.** The thing
being measured may genuinely not terminate — that is the finding — so the bound is
the *instrument*, and hitting it is a measurement rather than a failure. Say so
explicitly in any brief that asks for one.

**Detection, since a wedged worker looks exactly like a busy one** (`● Working` in
the footer either way): check the session log's last timestamp against the clock.
`worker-log.sh -n 3 <uuid>` shows it; if the newest entry is more than ~15 minutes
old while the pane claims to be working, the worker is stuck in a command, not
thinking. The wait script's 5 s pane-output poller cannot catch this because the
pane genuinely is not producing output either — which is why the log timestamp is
the reliable tells.

Recovery: `send-keys Escape` (aborts the command, keeps the session and the
context), then a rescue prompt naming what it was doing. Everything already
committed or edited is intact; the model resumes mid-thought.

### Verify every path in a brief against the tree before dispatching (manager, 2026-10-24)

Two briefs in one session named files that do not exist (`widgets/separator.rs` when the
separator lives in `ui/src/separator.rs`; a `chat_hub.rs` line range from an issue
filed against an older tree). Both came from **quoting the issue body instead of reading
the tree**. The cost is small but pure waste: the worker spends its first tools discovering
the brief is wrong, and one of them burned a turn on it.

The rule: a brief may quote an issue's paths as *claims to verify*, but the **File boundary
section must be written from the tree** — `rg -l <the symbol>` first, then paste the real
path. It costs one command and saves the worker's first five. Where an issue's line numbers
matter, say "verify against today's tree" in the brief (already standing) *and* check the
file exists while writing.

### Three tells a worker is wedged, and the one I ignored (owner, 2026-10-23)

I watched a worker sit dead for 3.5 hours and checked on it repeatedly without
noticing. The signals were all present, and one of them I *wrote down twice*:

1. **A frozen context percentage.** The footer's `N%` advances only when a turn
   completes. Across four separate wait cycles I recorded W2 at **exactly 10.0%**
   and called it "fresh" each time. A percentage that does not move between
   check-ins is not freshness — it is a worker that has not finished a turn since
   the last time I looked. **This is the cheapest and most reliable tell, and it is
   the one I had in hand.**
2. **A stale session-log timestamp.** `worker-log.sh -n 3 <uuid>` shows the newest
   entry's time; more than ~15 min behind the clock while the pane says `● Working`
   means stuck in a command, not thinking. The wait script cannot catch this — the
   pane is genuinely silent, so its output poller sees the same thing a healthy
   quiet worker looks like.
3. **A command with no bound.** The one that did it: `cargo run ... spin_probe`,
   unbounded, at 02:33. Which is doubly wrong because the thing being probed was
   *a busy-spin* — a probe that may legitimately never terminate is the case that
   most needs a `timeout`.

**The rule this produced, which is now a check rather than a lesson:** every
manager check-in compares two numbers — the footer's context `%` and the log's
newest timestamp — against the previous check-in. Either one unchanged after
~15–20 minutes is an interrupt (`send-keys Escape`), not another wait. Waiting is
only correct when the worker is demonstrably producing turns.

Cost of getting this wrong: 3.5 hours of a P2 worker, on a cycle whose measurement
took **30 seconds** once it was resumed (614,104 spin-calls/s before the fix,
137.9/s after).

## Prioritization law (owner, restated 2026-10-21 — read this before any dispatch)

**Prioritize by VALUE x DEVELOPMENT TIME. Never by recency.** A newly
filed or freshly updated issue is not thereby a priority — the issue
list's default `updatedAt` ordering is a trap, and taking the top row
because it is on top is exactly the mistake this rule exists to stop.

How a batch is actually chosen:

1. **Value** — what does the user get? Rank: a defect that breaks a real
   journey (a pull that fails after auth, a prompt duplicated on every
   request, a login no non-github.com account can complete) > a shipped
   defect's missing guard > a documented-but-absent behavior > polish and
   ergonomics > backlog ideas and p3 labels.
2. **Development time** — the honest cycle cost: files touched, review
   weight, gate cost, and how likely the worker is to wander. A one-file
   fix with a clear mechanism is cheap; an epic phase is expensive.
3. **The product is value x time**, so a p3 issue nobody feels loses to a
   p2 issue that makes every request more expensive, and a cheap p2 beats
   an expensive p1 whose blast radius is small.
4. **Epics get phased**, and each phase must pay back value on its own —
   never "eight phases then a payoff".
5. **Recency is only ever a tiebreak** inside the same value and cost
   class, and even then the older issue usually wins, because it has had
   longer to prove nobody is reaching for it.

Applied examples from this session: #280 (a System message duplicated into
`contents` — every request, every user, cheap fix) outranked a newer p3;
#308 (an authenticated ghcr pull failing outright) outranked #427's fixture
staleness; #282 (enterprise logins cannot complete at all) outranked
cosmetic TUI rows. The most recently touched issue in the queue (#439, a
docs/CI publishing task) is correctly sitting below all of them.

## Dual-worker topology — OPTIONAL, off by default (owner directive, 2026-10-20)

Applies only in the opt-in two-worker mode. It was the operating mode for a stretch
of the reference project, which is why the scars below read as if it were always on.
The default remains one worker in one checkout.

Two workers run concurrently on `tmux -L $TMUX_SOCKET`, in separate Git worktrees:

| role | tmux session | worktree | branch |
|---|---|---|---|
| Worker 1 | `worker-1` | primary worktree wt1 | `worker-1/<batch>` |
| Worker 2 | `worker-2` | secondary worktree wt2 | `worker-2/<batch>` |

Session UUIDs (keep exact — three sessions live in one project dir):
W1 and W2 session UUIDs are recorded at launch; Manager sessions are the remaining
`*.jsonl` in the same dir. NEVER tail without the uuid.

**Model law.** Both workers run the configured model.

**Orthogonal batching (conflict minimization).** Each cycle assigns two
disjoint batches by crate *role*: W1 = the surface/HTTP layer (in one project
`proxy`, `admin`, `server`, plus integration tests); W2 = core/data (`core`,
`proto`, `store`). Name the real crates in the brief — the roles are what keep
the batches orthogonal; the crate names are just today's example. Shared files (`Cargo.lock`, `CHANGELOG.md`,
`docs/*`) are the only expected conflict surface: both briefs say
"touch only your section of CHANGELOG; never reformat", and the manager
resolves any conflict at merge. Prioritization:
1. P0/P1 defects (safety, data corruption, panic holes) take precedence.
2. Orthogonal crate batches keep worktrees disjoint.

**Branch & merge protocol.** While both branches are in flight, NO worker
pushes `main`. Each worker commits to its own branch (`worker-1/<batch>`,
`worker-2/<batch>`) and pushes the branch; the manager reviews in the
worker's own worktree, then merges/rebases onto `main`, resolves shared-file
conflicts, regenerates `Cargo.lock` if needed, runs the FULL gate suite on
merged `main`, pushes, verifies CI. At the next cycle boundary the other
worker's worktree is rebased/fast-forwarded onto updated `main` before its
next dispatch (never work off a stale base).

**Supervision.** Worker-specific completion channels:
`worker-done-w1-<cycle>` / `worker-done-w2-<cycle>` (fix-ups get a fresh
`...fix` channel). `scripts/worker-wait-both.sh` is the single blocking wait over
both channels (returns when EITHER worker signals/idsles/crashes/deadlines;
rc carries which one). Re-waits reuse the same channel per still-running
worker. At every return, `worker-log.sh -n 40` BOTH uuids.

**Disk hygiene (two worktrees).** At every cycle boundary check
`df -h "$DISK_PATH"` + `du -sh` of target directories. `cargo clean` the idle
worktree's `target/` when the combined size exceeds ~25-30 GB or free drops
below 25 GB — ONLY when that worker is idle at a boundary, never mid-build.

### Storage monitoring (owner escalation, 2026-10-20 — two worktrees crashed the machine)

Two workers × 50-70 GB `target/` + a gate run filled the 394 GB disk to 100%
mid-cycle; suites died without summaries and every downstream thing fell
apart. Monitoring at wait-returns alone was not enough. The binding rules:

1. **`scripts/disk-guard.sh` is a PREFLIGHT, not a report.** Before every dispatch,
   every merge/rebase, and every gate run:
   `scripts/disk-guard.sh --wt1 "$WT1" --wt2 "$WT2" --check || { scripts/disk-guard.sh --wt1 "$WT1" --wt2 "$WT2" --clean-idle; ... }`.
   It exits 1 on pressure (free < 40 GB, or combined `target/` > 60 GB).
2. **`worker-wait-both.sh` runs it on every return** (`--clean-idle`): it
   prints free space + both `target/` sizes, and prunes the larger idle
   worktree's `target/` when under pressure — never while any `cargo`/`rustc`
   process is alive anywhere.
3. **Briefs carry the knob.** Every brief tells its worker: shared
   `CARGO_TARGET_DIR` stays off (per-worktree targets are the isolation);
   `debug = 0` / no `[profile.dev]` bloat, `cargo clean` at phase boundaries
   only, and never a `--workspace --all-features` build inside the e2e branch
   if a scoped build answers the question.
4. **Banked space, not banked luck**: keep ≥ 40 GB free as the operating
   floor. A worker that reports "DISK FULL" is telling the truth — clean
   first, steer second.

**Storage pressure returns the wait itself (owner request, 2026-10-20).**
`worker-wait.sh` gained a fifth exit code — `5` — and a `disk(<free>GB)`
reason: its 5 s poller also reads free space on `$DISK_PATH`, and below
`DISK_MIN_GB` (default **25 GB**) it returns immediately instead of sleeping
to a worker deadline. `worker-wait-both.sh` races the same check at wrapper
level and additionally prints `disk-guard.sh`'s numbers on the way out.
Rationale: the manager sleeps inside the wait; a full disk kills both workers
mid-cycle far from the next check-in, so the wait must be the thing that
notices. Free-space only — a `du -sG` over a 60 GB target every 5 s would
itself cost.

### Manager gate runs must not overlap a worker build (2026-10-20, dual-worker)

Root-caused, not ledgered-again: a full `cargo nextest run --workspace` inside
the manager worktree, run WHILE Worker 2 was building (5 live `rustc`), failed
due to system load and timeouts, whereas every test passed solo. Two workers ×
full builds + a parallel suite on 4 cores is oversubscription.

**Rule.** In the dual-worker topology the manager runs, on merged `main`:
1. the FAST gates locally always (fmt, clippy, ceiling, traceability,
   docs-consistency, `disk-guard.sh --wt1 "$WT1" --wt2 "$WT2" --check`);
2. the heavy suite locally ONLY when no worker is building
   (`pgrep -x cargo/rustc` empty) — otherwise push and let the isolated CI
   matrix be the full-suite judge (it is the receipt of record anyway);
3. never treat a load-shaped local failure as a product failure without a
   solo rerun on the identical tree.

### Root cause of the disk crisis, fixed in the profiles (2026-10-20)

Monitoring was the wrong fix on its own. The cause was debug builds carrying
full DWARF plus incremental artifacts: `target/debug/deps` was **37 GB** and
`target/debug/incremental` **8.1 GB** per worktree, so two worktrees plus a
gate run could not fit in 394 GB.

`Cargo.toml` now sets, for **dev and test** profiles:
`debug = 0` (no DWARF) and `incremental = false`.

Measured cold on this tree:

| command | before | after |
|---|---|---|
| `cargo check --workspace --all-targets` | ~45 GB | **577 MB** |
| `cargo nextest run --workspace --no-run` | ~45 GB | **5.6 GB** |
| `target/debug/incremental` | 8.1 GB | **4 KB** |

Accepted cost: backtraces lose line numbers (panics still name file:line via
the panic-location string; test failures read the assertion). Incremental is
off — free here because every phase boundary runs `cargo clean` and CI is
always cold — and `CARGO_INCREMENTAL=1` re-enables it for a long local loop.
The release profile is untouched (NFR-1 sizes against it).

With this in place the operating floor is generous: two cold worktrees ≈
11 GB combined, so `disk-guard.sh`'s 40 GB free / 60 GB combined thresholds
now only fire on genuinely anomalous growth (a runaway build, leftover
archives, a third worktree).

### Pricing-window scheduling — off by default (owner, 2026-10-21)

**Default state: off**, so no dispatch is gated by the hour. The gate itself lives in
`references/manager-deepseek-offpeak-prompt.md`; turn it on only on request, and only
for the worker it names.

Earlier sessions scheduled dispatches and heavy gate runs inside DeepSeek's
off-peak pricing window. **The default is that this rule is off:** workers run
continuously, and an idle worker is treated as a defect (something to dispatch,
not something to wait out). Retained here so a future session does not
rediscover scheduling as "the way we do things"; it becomes active only when the
off-peak gate is explicitly enabled, and then only for the worker that document
names.

### A byte-comparison gate is not a portable gate (2026-10-21, #427)

`wasm-check.sh` gained a fixture guard and the first version compared **bytes**:
the committed component against the one the same run built. Locally it was
stable across cold clones, warm caches and `CARGO_INCREMENTAL=0` — all
`747dc1ad…`. A hosted runner built the same source into a component of
**identical interface, identical size, different bytes** (`b023b5a8…`), and
CI went red on `main` (run 39631810706).

The profile is `lto = "fat"` with `codegen-units = 1`; any toolchain or linker
detail below that can move bytes that mean the same thing. **A gate that
reddens on codegen noise teaches people to ignore it, which is worse than no
gate.** Compare the *interface* (`wasm-tools component wit`), which is what a
link failure is actually about.

Two lessons, both general:
1. **A local green is not evidence of portability.** If a gate compares
   build output rather than behavior, prove it on the runner before trusting
   it — or compare something semantic.
2. **`command -v` is not the same as "installed".** `cargo install` writes to
   `$CARGO_HOME/bin`, which is absent from PATH under `bash --norc` and in CI
   steps that never sourced a profile. The guard silently took its
   "tool unavailable" branch on a machine that had the tool. Fall back to the
   known install paths.

Also: the fix-forward took under twenty minutes because the worker had already
diagnosed it on its own branch and written the correction while I was merging
the broken version. Reading a worker's in-flight branch before declaring an
issue closed is cheaper than rediscovering it.

### Provider failure: retry first, switch only if it stays down (owner, 2026-10-21)

A provider error is not a model-down verdict. The 503s that hit both workers
twice each were `workspace_billing_scope_unavailable` — a **billing-service
timeout**, transient by nature, not a model outage. The correct response, in
order:

1. **Retry the turn.** Send the worker a resume nudge ("continue exactly
   where you left off"), or let the harness retry, and try again. A transient
   503 clears in minutes.
2. **Retry a few more times over a bounded window** (a few attempts, not one).
   Only a failure that survives that window counts as "down".
3. **Only then switch the provider**, and switch **cheap first**: the
   `--models` cycle order decides the cost, so know what each entry bills as.
   A subscription-billed model is **not** a cheap model however fast its name
   sounds; put the genuinely cheap fallback last-but-one and keep the healthy
   default first, so a retry never lands on the expensive option.
4. **Switch back as soon as the default is healthy** — a worker left on the
   fallback silently spends the wrong budget.

The failure mode this rule prevents: treating one 503 as "the default model is down
forever", flipping both workers to gemini (the expensive option), and leaving
them there. That happened this cycle; the owner's instruction is that retrying
is the first move and a switch is the last resort, cheap-model-only.

### Worker session recycling, with a helper that lied (2026-10-21)

`/compact` on Worker 1 failed with "Summarization failed: generation hit the
token cap" and left context at 74% — the documented silent-failure mode. The
cycle was clean (tree committed, branch merged), so the session was recycled:
`C-d`, relaunch with the same `--model/--models`, the two priming prompts,
and a **new** session uuid recorded from `ls -t` + the session header's `id`.
Retired: `01a143e1` → fresh `01a15cf7`.

**Trap:** `worker-log.sh <old-uuid>` keeps resolving the RETIRED file, so its
tail looks frozen and can be mistaken for a stalled worker. After recycling,
re-derive the uuid from the session header (`head -1 | jq -r .id`) filtered by
cwd, and never keep tailing the old one.

### Three-worktree topology + "manager owns main" (two-worker mode, 2026-10-21)

Supersedes the dual-worker section's worktree split. Primary checkout
is the **manager's** checkout and the only place `main` is checked out; W1 lives
in `wt1`, W2 in `wt2`, each on its own `worker-N/<batch>` branch.

**Why:** sharing the primary checkout cost an afternoon — a manager `checkout
main` silently moved W1's HEAD (its work ended up on the wrong branch), a
`git branch -f main` repair was needed to un-wedge it, and a merge aborted
because W1 had 20 uncommitted files in the tree the manager was merging into.
Shared mutable state, not discipline, was the defect.

**Rules:** only the manager checks out `main`; workers never touch it, never
pull it, never push anything but their branch. The manager merges, resolves
shared-file conflicts, gates, pushes, and verifies CI. Rebases of a worker's
tree happen only while that worker is parked.

**Merge etiquette (learned the hard way):** pass the merge message with
`-F <file>`, never `-m "…"` with backticks/quotes in it — a shell-mangled
message made git read words as a *path* (`merge: far - not something we can
merge`).

### Sending a slash command while a worker is mid-turn (2026-10-21)

Two traps in one minute, both worth knowing:

1. **A `/command` typed while the worker is `● Working` steers into the run as
   literal text.** It does not execute — the turn sees `/thinking high` as a
   user message. Only send slash commands at an idle composer.
2. **`send-keys … Enter` may not submit the first time.** The key lands while
   the composer is re-rendering (or a queued steer is being flushed), and the
   line sits in the editor looking sent. Symptom: the footer still shows the
   old value and the pane shows the typed line. Fix: send `Enter` again and
   re-capture; verify by the *state* (footer shows `• high`, or the pane prints
   `Thinking level: high`), never by having sent the key.

**Verification rule:** after any settings command, confirm the new value in the
footer or a confirmation line. A sent key is not a changed setting.
