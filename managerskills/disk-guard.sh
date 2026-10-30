#!/usr/bin/env bash
# disk-guard.sh — storage watchdog for LLMRoller development.
#
# Prevents disk exhaustion from Rust target/ directories during multi-worktree
# or parallel worker builds. Runs as preflight before dispatch/merge and
# on supervisor wait returns.
#
# Usage:
#   disk-guard.sh                report only, exit 0 (informational)
#   disk-guard.sh --check        exit 1 when under pressure (free < FREE_MIN_GB
#                                or combined targets > TARGET_MAX_GB)
#   disk-guard.sh --clean-idle   clean target/ only when no cargo/rustc
#                                process runs anywhere
#
# Thresholds:
#   FREE_MIN_GB   = 25 (or 40)   below this, refuse/heal before building
#   TARGET_MAX_GB = 60           combined target/ above this, prune idle target
set -u
FREE_MIN_GB=${FREE_MIN_GB:-25}
TARGET_MAX_GB=${TARGET_MAX_GB:-60}
HERE=$(cd "$(dirname "$0")" && pwd)

WT1=${WT1:-"$HERE/LLMRoller"}
WT2=${WT2:-"$HERE/../LLMRoller-wt2"}
[ -d "$WT2" ] || WT2="$HERE/LLMRoller-wt2"
MODE=${1:-}

free_gb=$(df -BG --output=avail /home/debian 2>/dev/null | tail -1 | tr -dc '0-9')
[ -n "$free_gb" ] || free_gb=$(df -BG --output=avail . 2>/dev/null | tail -1 | tr -dc '0-9')

size_gb() { # path -> integer GB (0 when absent)
  [ -d "$1" ] || { echo 0; return; }
  du -sBG "$1" 2>/dev/null | awk '{print $1}' | tr -dc '0-9'
}

t1=$(size_gb "$WT1/target"); t2=$(size_gb "$WT2/target")
combined=$((t1 + t2))
builders=$(pgrep -c -x cargo 2>/dev/null || true)
builders=$(( ${builders:-0} + $(pgrep -c -x rustc 2>/dev/null || true) ))

printf 'disk-guard: free=%sGB targets: wt1=%sGB wt2=%sGB combined=%sGB builders=%s\n' \
  "$free_gb" "$t1" "$t2" "$combined" "$builders"

pressure=0
[ -n "$free_gb" ] && [ "$free_gb" -lt "$FREE_MIN_GB" ] && { echo "disk-guard: PRESSURE low free space (<${FREE_MIN_GB}GB)"; pressure=1; }
[ "$combined" -gt "$TARGET_MAX_GB" ] && { echo "disk-guard: PRESSURE targets too large (>${TARGET_MAX_GB}GB)"; pressure=1; }

case "$MODE" in
  --check)
    exit "$pressure" ;;
  --clean-idle)
    if [ "$builders" -gt 0 ]; then
      echo "disk-guard: NOT cleaning — $builders cargo/rustc process(es) running"
      exit "$pressure"
    fi
    if [ "$pressure" -eq 0 ]; then
      echo "disk-guard: no pressure, nothing to clean"
      exit 0
    fi
    # Prune the larger worktree's target first; never both at once mid-cycle.
    if [ "$t1" -ge "$t2" ] && [ -d "$WT1/target" ]; then victim=$WT1; else victim=$WT2; fi
    echo "disk-guard: cleaning $victim/target (idle: no builders)"
    ( cd "$victim" && cargo clean >/dev/null 2>&1 ) && echo "disk-guard: cleaned $victim"
    now_free=$(df -BG --output=avail /home/debian 2>/dev/null | tail -1 | tr -dc '0-9')
    echo "disk-guard: free now ${now_free}GB (was ${free_gb}GB)"
    exit 0 ;;
  "")
    exit 0 ;;
  *)
    echo "usage: $0 [--check|--clean-idle]" >&2; exit 4 ;;
esac
