#!/usr/bin/env bash
# worker-wait-both.sh — one blocking wait over BOTH worker channels.
#
# Companion to worker-wait.sh (dual-worker topology, 2026-10-20). Runs one
# worker-wait.sh per worker in parallel and returns the moment EITHER exits
# (signal rc0 / idle rc1 / deadline rc2 / crash rc3 / setup rc4). The other
# worker keeps working; re-wait on it with the SAME channel.
#
# Usage:
#   worker-wait-both.sh --ch1 <chan> --ch2 <chan> [--idle-secs N] [--max-secs N]
#
# Output: the exiting worker's full worker-wait.sh report, prefixed with
# `RESULT worker<N>=<rc>`, plus a one-line state of the other. Exit code is
# the exiting worker-wait.sh's rc. Storage pressure short-circuits both:
# free space below DISK_MIN_GB (default 25 GB) prints the guard's report and
# exits 5, so the manager can clean before a full disk kills the workers
# (owner request 2026-10-20, after two worktrees hit 100%).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
CH1=""; CH2=""
IDLE=120; MAX=5400
while [ $# -gt 0 ]; do
  case "$1" in
    --ch1) CH1=$2; shift 2 ;;
    --ch2) CH2=$2; shift 2 ;;
    --idle-secs) IDLE=$2; shift 2 ;;
    --max-secs) MAX=$2; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 4 ;;
  esac
done
[ -n "$CH1" ] && [ -n "$CH2" ] || { echo "usage: $0 --ch1 <chan> --ch2 <chan> [--idle-secs N] [--max-secs N]" >&2; exit 4; }

O1=$(mktemp /tmp/w1.wait.XXXX); O2=$(mktemp /tmp/w2.wait.XXXX)
"$HERE/worker-wait.sh" --socket lca-mgr --session lca-worker   --channel "$CH1" --idle-secs "$IDLE" --max-secs "$MAX" > "$O1" 2>&1 &
P1=$!
"$HERE/worker-wait.sh" --socket lca-mgr --session lca-worker-2 --channel "$CH2" --idle-secs "$IDLE" --max-secs "$MAX" > "$O2" 2>&1 &
P2=$!

# The moment either exits, report it and stop waiting on the other (its
# worker keeps working; a killed waiter consumes no wait-for signal).
# The loop ALSO watches free space itself: both inner waits exit with rc 5 on
# storage pressure, but this wrapper can be the thing that notices first when
# the disk is draining fast between their 5 s samples.
while kill -0 "$P1" 2>/dev/null && kill -0 "$P2" 2>/dev/null; do
  free_gb=$(df -BG --output=avail /home/debian 2>/dev/null | tail -1 | tr -dc '0-9')
  if [ -n "$free_gb" ] && [ "$free_gb" -lt "${DISK_MIN_GB:-25}" ]; then
    echo "DISK PRESSURE: free=${free_gb}GB (< ${DISK_MIN_GB:-25}GB) — returning to clean up"
    kill "$P1" "$P2" 2>/dev/null; wait "$P1" "$P2" 2>/dev/null
    "$HERE/disk-guard.sh" 2>/dev/null || true
    echo "RESULT storage=5 channel=both"
    rm -f "$O1" "$O2"
    exit 5
  fi
  sleep 5
done
if ! kill -0 "$P1" 2>/dev/null; then
  wait "$P1"; RC=$?
  kill "$P2" 2>/dev/null; wait "$P2" 2>/dev/null
  echo "RESULT worker1=$RC channel=$CH1"
  cat "$O1"
  echo "-- worker2 ($CH2): still running (re-wait with the same channel) --"
else
  wait "$P2"; RC=$?
  kill "$P1" 2>/dev/null; wait "$P1" 2>/dev/null
  echo "RESULT worker2=$RC channel=$CH2"
  cat "$O2"
  echo "-- worker1 ($CH1): still running (re-wait with the same channel) --"
fi
rm -f "$O1" "$O2"
# Storage is part of every return (2026-10-20: two worktrees filled the disk
# to 100% and killed both workers mid-cycle). Report always; heal only when
# no builder is running anywhere.
if [ -x "$HERE/disk-guard.sh" ]; then
  echo "-- disk --"
  "$HERE/disk-guard.sh" --clean-idle
fi
exit "$RC"
