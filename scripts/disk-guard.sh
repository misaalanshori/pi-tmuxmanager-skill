#!/usr/bin/env bash
# disk-guard.sh — storage watchdog for multi-worktree development.
#
# Prevents disk exhaustion from Rust target/ directories during multi-worktree
# or parallel worker builds. Runs as preflight before dispatch/merge and
# on supervisor wait returns.
#
# Worktree roots are REQUIRED: --wt1/--wt2 (or WT1/WT2). There are no baked
# paths, so the script says nothing about any particular layout.
#
# Usage:
#   disk-guard.sh --wt1 <path> --wt2 <path>              report only, exit 0
#   disk-guard.sh --wt1 <path> --wt2 <path> --check      exit 1 under pressure
#                                                        (free < FREE_MIN_GB or
#                                                        combined targets >
#                                                        TARGET_MAX_GB)
#   disk-guard.sh --wt1 <path> --wt2 <path> --clean-idle clean target/ only when
#                                                        no cargo/rustc process
#                                                        runs anywhere
#
# Tunables (env, with defaults — these are numbers, not identity):
#   FREE_MIN_GB   = 25   below this, refuse/heal before building
#   TARGET_MAX_GB = 60   combined target/ above this, prune idle target
set -u
FREE_MIN_GB=${FREE_MIN_GB:-25}
TARGET_MAX_GB=${TARGET_MAX_GB:-60}
DISK_PATH=${DISK_PATH:-.}   # filesystem to watch; default is "wherever I run"
HERE=$(cd "$(dirname "$0")" && pwd)

usage() {
  cat <<'EOF'
disk-guard.sh — storage watchdog for multi-worktree Rust development.

Usage: disk-guard.sh --wt1 PATH --wt2 PATH [--check | --clean-idle]

Required (flag wins; env var is the fallback; no baked defaults):
  --wt1 PATH        first worktree root                  (WT1)
  --wt2 PATH        second worktree root                 (WT2)

Modes:
  (none)            report only, exit 0
  --check           exit 1 when free < FREE_MIN_GB or combined targets > TARGET_MAX_GB
  --clean-idle      cargo clean the larger target/, only if no cargo/rustc runs

Tunables (env):
  FREE_MIN_GB       free-space floor in GB               (default 25)
  TARGET_MAX_GB     combined target/ ceiling in GB       (default 60)
  DISK_PATH         filesystem to measure                (default .)

  -h, --help        this help
EOF
}

WT1="${WT1:-}"
WT2="${WT2:-}"
MODE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --wt1)        WT1=$2; shift 2 ;;
    --wt2)        WT2=$2; shift 2 ;;
    --check|--clean-idle) MODE=$1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "disk-guard: unknown arg: $1" >&2; usage >&2; exit 4 ;;
  esac
done

missing=""
[ -n "$WT1" ] || missing="$missing --wt1(or WT1)"
[ -n "$WT2" ] || missing="$missing --wt2(or WT2)"
if [ -n "$missing" ]; then
  echo "disk-guard: missing required:$missing" >&2
  usage >&2
  exit 4
fi

free_gb=$(df -BG --output=avail "$DISK_PATH" 2>/dev/null | tail -1 | tr -dc '0-9')
[ -n "$free_gb" ] || free_gb=$(df -BG --output=avail . 2>/dev/null | tail -1 | tr -dc '0-9')

size_gb() { # path -> integer GB (0 when absent)
  [ -d "$1" ] || { echo 0; return; }
  du -sBG "$1" 2>/dev/null | awk '{print $1}' | tr -dc '0-9'
}

t1=$(size_gb "$WT1/target"); t2=$(size_gb "$WT2/target")
combined=$((t1 + t2))
builders=$(pgrep -c -x cargo 2>/dev/null || true)
rustcs=$(pgrep -c -x rustc 2>/dev/null || true)
builders=$(( ${builders:-0} + ${rustcs:-0} ))   # both are empty when pgrep is absent

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
    now_free=$(df -BG --output=avail "$DISK_PATH" 2>/dev/null | tail -1 | tr -dc '0-9')
    echo "disk-guard: free now ${now_free}GB (was ${free_gb}GB)"
    exit 0 ;;
  "")
    exit 0 ;;
  *)
    echo "disk-guard: unknowable mode $MODE" >&2; usage >&2; exit 4 ;;
esac
