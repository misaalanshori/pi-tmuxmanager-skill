#!/usr/bin/env bash
# worker-wait.sh — blocking supervisor for the pi worker running under tmux.
#
# The manager (me) runs this ONCE per dispatch and sleeps inside it. This
# script is the only poller — it checks the worker's state every 5 s and
# returns the moment something meaningful happens. The manager never polls.
#
# Completion signal (cooperative, zero-poll primary path): the dispatch
# prompt instructs the worker to run
#     tmux -L <socket> wait-for -S <channel>
# when and only when the cycle is genuinely complete. The primary wait is
# `tmux wait-for` (blocks in the tmux server, no polling). The 5 s poller
# below only covers the failure modes.
#
# Exit codes:
#   0  signal received -> cycle complete -> review the result
#   1  pane idle for --idle-secs without a signal -> agent stopped working
#      (stuck, asked a question, or idling) -> check the pane
#   2  --max-secs elapsed -> check in; if all is well, call again
#   3  pi not running in the pane (crashed / exited) -> rescue
#   4  setup error (socket/session/pane missing)
#   5  storage pressure: free space fell below DISK_MIN_GB (default 25 GB).
#      The manager returns immediately to clean/prune rather than sleeping
#      until a worker deadline while the machine fills up (owner request
#      2026-10-20: two worktrees hit 100% and killed both workers).
#
# Every return prints a report: pane tail + disk state (df, target size),
# so disk hygiene is observed at every check-in without a separate tool.
#
# ponytail: 5 s stat loop, worst-case detection latency 5 s. A stat loop
# in a script is free; inotify-tools is not installed and would be a
# dependency for nothing. Upgrade only if latency ever matters.

set -u

usage() {
  cat <<'EOF'
worker-wait.sh — blocking supervisor for a pi worker running under tmux.

Usage: worker-wait.sh --socket SOCK --session NAME --channel CHAN [options]

Required (a flag wins; the env var is the fallback; there are no baked defaults):
  --socket SOCK     tmux socket of the management plane      (TMUX_SOCKET)
  --session NAME    worker session on that socket            (TMUX_SESSION)
  --channel CHAN    completion channel for this cycle        (none: fresh per cycle)

Options:
  --idle-secs N     silence before rc 1                      (default 120)
  --max-secs N      total wait budget before rc 2            (default 3600)
  --quiet           suppress the pane + disk report
  --selftest        run the built-in supervisor tests
  -h, --help        this help

Tunables (env):
  DISK_MIN_GB       free-space floor in GB, measured on DISK_PATH  (default 25)
  DISK_PATH         filesystem to measure                          (default .)

Exit: 0 signal | 1 idle | 2 deadline | 3 worker gone | 4 usage/setup | 5 disk
EOF
}

SOCK="${TMUX_SOCKET:-}"
SESSION="${TMUX_SESSION:-}"
CHANNEL=""
IDLE_SECS=120
MAX_SECS=3600
REPORT=1
DISK_PATH="${DISK_PATH:-.}"   # filesystem to watch; default is "wherever I run"

while [ $# -gt 0 ]; do
  case "$1" in
    --socket)    SOCK=$2; shift 2 ;;
    --session)   SESSION=$2; shift 2 ;;
    --channel)   CHANNEL=$2; shift 2 ;;
    --idle-secs) IDLE_SECS=$2; shift 2 ;;
    --max-secs)  MAX_SECS=$2; shift 2 ;;
    --quiet)     REPORT=0; shift ;;
    --selftest)  SELFTEST=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "worker-wait: unknown arg: $1" >&2; usage >&2; exit 4 ;;
  esac
done

selftest() {
  local S="${SOCK:-pi}-selftest"
  tmux -L "$S" kill-server 2>/dev/null
  local fail=0 t0 rc
  local NODE_SILENT='node -e "setInterval(()=>{},10000)"'
  local NODE_TICKING='node -e "setInterval(()=>console.log(\"tick\"),500)"'

  say() { printf 'selftest: %s\n' "$*"; }

  # 1. signal path: worker signals after ~2 s -> expect 0, fast
  tmux -L "$S" new-session -d -s t1 "bash --norc"
  tmux -L "$S" send-keys -t t1 "sleep 2; tmux -L $S wait-for -S stdone; sleep 3600" Enter
  t0=$(date +%s)
  "$0" --socket "$S" --session t1 --channel stdone --idle-secs 60 --max-secs 20 --quiet
  rc=$?
  [ "$rc" -eq 0 ] && [ $(( $(date +%s) - t0 )) -lt 15 ] && say "PASS signal (rc=$rc)" || { say "FAIL signal rc=$rc"; fail=1; }

  # 2. idle path: silent worker (node, no output) -> expect 1
  tmux -L "$S" new-session -d -s t2 "$NODE_SILENT"
  t0=$(date +%s)
  "$0" --socket "$S" --session t2 --channel never2 --idle-secs 5 --max-secs 30 --quiet
  rc=$?
  [ "$rc" -eq 1 ] && say "PASS idle (rc=$rc)" || { say "FAIL idle rc=$rc"; fail=1; }

  # 3. deadline path: silent worker, idle window huge -> expect 2
  tmux -L "$S" new-session -d -s t3 "$NODE_SILENT"
  "$0" --socket "$S" --session t3 --channel never3 --idle-secs 3600 --max-secs 8 --quiet
  rc=$?
  [ "$rc" -eq 2 ] && say "PASS deadline (rc=$rc)" || { say "FAIL deadline rc=$rc"; fail=1; }

  # 4. crash path: pane command exits -> pane_dead -> expect 3
  tmux -L "$S" new-session -d -s t4 "sleep 2"
  tmux -L "$S" set-option -t t4 remain-on-exit on
  "$0" --socket "$S" --session t4 --channel never4 --idle-secs 3600 --max-secs 20 --quiet
  rc=$?
  [ "$rc" -eq 3 ] && say "PASS crash (rc=$rc)" || { say "FAIL crash rc=$rc"; fail=1; }

  # 5. regression (first real use): a WORKING pane must never look idle.
  #    Two consecutive waits on one ticking pane; the second must still see
  #    activity, which a stale/starved activity source would not.
  tmux -L "$S" new-session -d -s t5 "$NODE_TICKING"
  "$0" --socket "$S" --session t5 --channel never5 --idle-secs 3600 --max-secs 3 --quiet
  "$0" --socket "$S" --session t5 --channel never5 --idle-secs 5 --max-secs 12 --quiet
  rc=$?
  [ "$rc" -eq 2 ] && say "PASS active-not-idle (rc=$rc)" || { say "FAIL active-not-idle rc=$rc"; fail=1; }

  # 6. orphan hygiene: the design relies on `wait-for -S` waking EVERY waiter
  #    on a channel, so a leftover waiter from an aborted run cannot starve the
  #    live one. Assert that property directly — if it ever changes, a killed
  #    wait starts swallowing the next cycle's completion signal.
  tmux -L "$S" new-session -d -s t6 "$NODE_SILENT"
  tmux -L "$S" wait-for orphan6 & orphan=$!
  sleep 1
  tmux -L "$S" wait-for orphan6 & live=$!
  sleep 1
  tmux -L "$S" wait-for -S orphan6
  sleep 1
  o=alive; l=alive
  kill -0 "$orphan" 2>/dev/null || o=woke
  kill -0 "$live" 2>/dev/null || l=woke
  kill "$orphan" "$live" 2>/dev/null
  [ "$o" = woke ] && [ "$l" = woke ] && say "PASS orphan-no-starvation (orphan=$o live=$l)" \
    || { say "FAIL orphan-no-starvation orphan=$o live=$l"; fail=1; }

  # 7. idle latency: a pane that has been silent since BEFORE the wait began
  #    must return idle at ~idle-secs, not at the deadline.
  tmux -L "$S" new-session -d -s t7 "$NODE_SILENT"
  sleep 3
  t0=$(date +%s)
  "$0" --socket "$S" --session t7 --channel never7 --idle-secs 6 --max-secs 45 --quiet
  rc=$?; el=$(( $(date +%s) - t0 ))
  [ "$rc" -eq 1 ] && [ "$el" -lt 20 ] && say "PASS idle-latency (rc=$rc ${el}s)" || { say "FAIL idle-latency rc=$rc ${el}s"; fail=1; }

  tmux -L "$S" kill-server 2>/dev/null
  [ "$fail" -eq 0 ] && say "ALL PASS" || say "FAILURES PRESENT"
  exit "$fail"
}

[ "${SELFTEST:-0}" = 1 ] && selftest

missing=""
[ -n "$SOCK" ]    || missing="$missing --socket(or TMUX_SOCKET)"
[ -n "$SESSION" ] || missing="$missing --session(or TMUX_SESSION)"
[ -n "$CHANNEL" ] || missing="$missing --channel"
if [ -n "$missing" ]; then
  echo "worker-wait: missing required:$missing" >&2
  usage >&2
  exit 4
fi

pane=$(tmux -L "$SOCK" list-panes -t "$SESSION" -F '#{pane_id}' 2>/dev/null | head -1)
[ -n "${pane:-}" ] || { echo "worker-wait: no session '$SESSION' on socket '$SOCK'" >&2; exit 4; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# Pane activity is read from tmux itself (`window_activity`, a unix-seconds
# stamp tmux advances on every byte it paints). This replaced a pipe-pane ->
# log-file -> stat-mtime chain that had three failure modes of its own:
# `pipe-pane -o` starving across invocations, a silent pane never creating
# the log, and an orphaned `cat >>` holding the pipe after an aborted run.
# A tmux counter has none of them, needs no cleanup, and cannot go stale
# because an earlier wait died.
baseline=$(tmux -L "$SOCK" display-message -p -t "$pane" '#{window_activity}' 2>/dev/null)
case "$baseline" in ''|*[!0-9]*) baseline=$(date +%s) ;; esac

# Idle counts from wait-start even if the pane went silent before we
# attached: the first poll compares against this baseline.
activity=$baseline

deadline=$(( $(date +%s) + MAX_SECS ))

# Primary: cooperative completion signal — kernel-blocked, zero polling.
( tmux -L "$SOCK" wait-for "$CHANNEL"; echo signal > "$tmp/reason" ) &
j1=$!

# Poller: failure modes (idle / crash / deadline).
(
  while :; do
    sleep 5
    [ -f "$tmp/reason" ] && exit 0
    now=$(date +%s)
    dead=$(tmux -L "$SOCK" display-message -p -t "$pane" '#{pane_dead}' 2>/dev/null)
    cmd=$(tmux -L "$SOCK" display-message -p -t "$pane" '#{pane_current_command}' 2>/dev/null)
    [ "$dead" = 1 ] && { echo pane-dead > "$tmp/reason"; exit 0; }
    case "$cmd" in
      pi|node) ;;
      *) echo "worker-gone($cmd)" > "$tmp/reason"; exit 0 ;;
    esac
    act=$(tmux -L "$SOCK" display-message -p -t "$pane" '#{window_activity}' 2>/dev/null)
    case "$act" in ''|*[!0-9]*) act=$activity ;; esac
    [ "$act" -gt "$activity" ] && activity=$act
    [ $(( now - activity )) -ge "$IDLE_SECS" ] && { echo idle > "$tmp/reason"; exit 0; }
    # Storage pressure unblocks the manager immediately (2026-10-20 owner
    # request: two worktrees filled the disk to 100% and killed every worker
    # mid-cycle while the manager slept in a 90-minute wait). Free-space only,
    # deliberately: `du -sG` on a 60 GB target every 5 s would itself cost.
    free_gb=$(df -BG --output=avail "$DISK_PATH" 2>/dev/null | tail -1 | tr -dc '0-9')
    [ -n "$free_gb" ] && [ "$free_gb" -lt "${DISK_MIN_GB:-25}" ] && \
      { echo "disk(${free_gb}GB)" > "$tmp/reason"; exit 0; }
    [ "$now" -ge "$deadline" ] && { echo deadline > "$tmp/reason"; exit 0; }
  done
) &
j2=$!

# Sleep here until either watcher fires. This is the manager's block.
#
# `wait -n` with NO arguments, deliberately. `wait -n "$j1" "$j2"` is a trap:
# it returns when any of the *listed* jobs finishes *or* when `wait` is
# interrupted, and it discards the exit status of already-finished jobs. The
# bare form waits for the next job to change state regardless of which, which
# is what "either watcher fired" means. Both forms are correct here only
# because a watcher writes $tmp/reason before exiting; the bare form is
# immune to a job having finished before the wait was reached.
wait -n
kill "$j1" "$j2" 2>/dev/null
kill "$j1" "$j2" 2>/dev/null
wait "$j1" "$j2" 2>/dev/null

reason=$(cat "$tmp/reason" 2>/dev/null || echo unknown)

if [ "$REPORT" = 1 ]; then
  echo "== worker-wait: $reason @ $(date -Is) (channel=$CHANNEL)"
  echo "-- pane tail --"
  tmux -L "$SOCK" capture-pane -p -t "$pane" 2>/dev/null | grep -v '^$' | tail -n 12
  echo "-- disk --"
  df -h "$DISK_PATH" | tail -1
  for t in target */target ../*/target; do
    [ -d "$t" ] && du -sh "$t" 2>/dev/null
  done
fi

case "$reason" in
  signal) exit 0 ;;
  idle) exit 1 ;;
  deadline) exit 2 ;;
  disk*) exit 5 ;;
  *) exit 3 ;;
esac
