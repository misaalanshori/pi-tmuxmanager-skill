# tmux subagent playbook — how the manager drives a pi worker

**Read this before managing any worker under tmux.**
It records the architecture, traps, and standing rules for driving worker agents. Companion files live beside it:

| File | What |
|---|---|
| `worker-wait.sh` | the supervisor (blocking; polls internally; `--selftest` = 5 cases) |
| `worker-dispatch-prompt.md.tpl` | the per-cycle dispatch text + completion protocol |
| `worker-manager-plan.md` | the manager plan: setup, cycle loop, review checklist, disk policy |

---

## 1. The architecture

```
manager (the pi session you are)                  — writes briefs, dispatches, sleeps, reviews
tmux -L ${TMUX_SOCKET:-roller-mgr} / session worker-1 — the worker: pi interactive agent in the repo
```

- **Dedicated socket for management.** Use `${TMUX_SOCKET:-roller-mgr}` for management. Never the default socket (shared machine, the owner runs their own sessions).
- **Completion detection**: the dispatch prompt's completion protocol —
  the worker runs `tmux -L ${TMUX_SOCKET:-roller-mgr} wait-for -S <channel>` **once, only
  when genuinely done**. `manager` blocks in `worker-wait.sh`, whose
  primary wait is `tmux wait-for` (kernel-blocked, zero polling).
  The script's internal 5s poll loop covers only failure modes.
- **"No polling" means the AGENT doesn't poll.** A script may poll
  internally all it likes; the manager makes ONE blocking tool call and
  sleeps inside it.
- Exit codes: `0` signal (review), `1` idle-without-signal (peek: stuck
  or a question), `2` deadline (check-in after ~1h; peek, then re-wait),
  `3` pi gone from the pane (rescue), `4` setup error, `5` disk pressure.

## 2. The traps (each one cost real time — don't repeat)

1. **`pipe-pane -o` starves across invocations.** `-o` keeps a *previous*
   invocation's pipe, pointing at its deleted log; the new log never
   receives bytes and an actively-working pane looks idle. **Fix**: close
   first (`pipe-pane -t <pane>`), then open.
2. **A silent pane never creates the log** → the idle timer never ages →
   never-idle. **Fix**: pre-create the log (`: > "$log"`) so "no output
   for N s" counts from wait-start.
3. **Channel reuse**: re-waits within one cycle MUST pass the SAME
   `--channel`. Fresh channels per invocation blind the waiter to the
   worker's signal. Fresh channels are for fresh *cycles* (stale-signal hygiene).
4. **pi's Ctrl+C is "clear", Ctrl+D is exit.** Sending Ctrl+C to restart
   pi typed my restart command INTO the composer and submitted it as a
   prompt. Exit with `Ctrl+D`; pi prints `To resume this session: pi
   --session <uuid>` — record the uuid for rescues.
5. **Provider-qualified model ids.** `--model deepseek-v4.1-flash` is
   ambiguous across multiple providers; use qualified names like `opendesign/<model>`. Also:
   the tmux server inherits **your** environment (`PI_PROVIDER`, proxy
   vars, …) — remember the worker sees it too.
6. **API 400s under big contexts** happen under heavy contexts.
   **Rescue ladder**: Switch models (context preserved) → message "continue exactly where you left off, do not restart" → verify orientation on `git status/log` → re-wait. If the state is poisoned, `/compact` or re-prime.
7. **Workers die mid-turn with uncommitted work.** The rescue prompt
   names the uncommitted area explicitly; verify orientation before
   trusting it to continue.
8. **`pane_current_command` semantics**: `pi`/`node` = working (or
   idle-at-composer); `bash` = pi not running = crash state (rc 3).
   `pane_dead` = same.
9. **Stale signals**: a signaled `wait-for` channel can persist server-
   side. Use a unique channel per cycle (`worker-done-1`, `worker-done-1fix`, …).

## 3. Dispatch mechanics

- Short messages: `send-keys -l 'text'` then `send-keys Enter`.
- **`worker-log.sh -n 20 <session-uuid>` pretty-tails the worker's
  session JSONL** (pi's schema: `message.role` = assistant/toolResult/
  user with toolCall/reasoning content) — the pane is a tiny window, the
  log is the whole story: exact tool calls, thinking, errors. Use it at
  check-ins and whenever the pane is ambiguous. The uuid is recorded at
  session launch (`ls -t ~/.pi/agent/sessions/*/*.jsonl` + the manager's
  own session is in the same dir — filter by the worker's uuid).
- **At EVERY `worker-wait.sh` return: tail the worker's session log
  (`worker-log.sh`), assess alignment against the brief, and steer or
  interrupt if it is derailed.**
  The pane shows where it is; the log shows what it *thinks* it is
  doing — confusion, phantom chasing, and scope drift are visible there
  minutes before the pane shows them.
- Long prompts: `load-buffer` + `paste-buffer` (bracketed paste).
- **Manually poll at the start of every dispatch** (capture-pane ~45s
  after submit) to confirm the worker is really working — and manually
  poll whenever something looks broken. Blocking waits in between.
- On rc 2 (check-in): `capture-pane | tail`, judge, re-wait with the
  same channel. On rc 1: same peek — a quiet worker is either done-then-
  stuck or asking a question.
- The dispatch template's completion protocol tells the worker to signal
  ONLY when genuinely complete and to stay silent when blocked. That
  asymmetry is what makes rc 1 meaningful.

## 4. Session lifecycle

- **Priming** (fresh session): the two prompts in order —
  docs-as-stakeholder, then code-bearings — waiting for idle between.
  A primed session carries across cycles.
- **Continue vs compact**: after a cycle, read the footer's context %;
  < 45% → dispatch immediately; ≥ 45% → `/compact` first. Re-prime
  carefully (new session + the two prompts) when the session is degraded.
- **Model**: Keep `--models` cycling available for fallback.

## 5. The review pass (Strict TDD & Quality Gates)

1. Read the worker's report — then verify independently.
2. Gates **myself** on the final commit: `cargo fmt --check`, `cargo clippy
   --workspace --all-targets -- -D warnings`, `cargo nextest run --workspace`.
3. Strict TDD verification: ensure failing tests were written first before the implementation.
4. Ceilings: max file lines (1,200), panic/unwrap check in production paths.
5. Secret hygiene: verify no API keys or credentials leaked into code, commits, or reports.
6. Docs drift + report accuracy (commit ledgers, model notes).
7. Only then: accept → next cycle, or write the fix brief and re-dispatch.

### Supervisor Scars & Traps

- **Run ALL gates before any direct push — not a subset.** "Commits land green" applies to the manager's own commits exactly as much as the worker's.
- **A test/behavior difference may be a stale binary or target cache.** Always verify cargo actually recompiled and tests ran against latest code.
- **`pkill -f <pattern>` kills your own shell** when the command line contains the pattern. Use `pkill -x <name>`.
- When the worker's repro contradicts yours, verify both trees/branches and build status before briefing a regression.

## 6. Standing rules

- Phases land green; never CI red on push.
- Strict TDD: test first, then minimal implementation.
- No approval needed mid-cycle; deviations documented in the report.
- Disk: `cargo clean` at cycle boundaries ONLY (never while a build may run); the wait script prints `df` + `target` size on every return.

## Dual-worker addendum

Two worker panes share `tmux -L ${TMUX_SOCKET:-roller-mgr}`: `worker-1` (primary worktree) and `worker-2` (secondary worktree). Everything above applies per worker; the deltas:

1. **Channels are worker-scoped**: `worker-done-w1-<cycle>` /
   `worker-done-w2-<cycle>`. `worker-wait-both.sh` is one blocking call over
   both; its rc names the worker and the state (0 signal, 1 idle, 2
   deadline, 3 crash). Re-wait on a still-running worker with the SAME
   channel — the reuse rule is per worker per cycle.
2. **Log tails always carry the uuid** (`worker-log.sh -n N <uuid-w1|w2>`);
   the sessions share one project dir and `ls -t` alone WILL mix them up.
3. **Steering is per worker**: send-keys into the named pane; verify the pane's cwd before sending.
4. **Both starts are verified** after dispatch: pane capture + log tail on
   BOTH uuids within ~60s.
