#!/usr/bin/env bash
# worker-log.sh — pretty-tail a pi session's JSONL.
#
# The tmux pane is a tiny window on the worker; the session log is the
# whole story (every tool call, result, and message). Usage:
#   worker-log.sh [-n N] [-f] [uuid-substring]
# -n lines (default 12); -f follows. With a substring, the newest log
# whose path matches it (the worker's session uuid, recorded at its
# launch — the manager's own session is also live in the same project
# dir, so the bare default is only safe when one session is active).
set -u
LINES=12; FOLLOW=""; MATCH=""

usage() {
  cat <<'EOF'
worker-log.sh — pretty-tail a pi session log (JSONL).

Usage: worker-log.sh [-n N] [-f] <uuid-substring>

  <uuid-substring>  required: matches the worker's session uuid; the newest
                    matching log wins. There is no "newest log overall"
                    fallback, because the manager's own session shares the dir.
  -n N              lines to tail                       (default 12)
  -f                follow
  -h, --help        this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -n) LINES=$2; shift 2 ;;
    -f) FOLLOW="-f"; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "worker-log: unknown flag: $1" >&2; usage >&2; exit 4 ;;
    *) MATCH=$1; shift ;;
  esac
done

if [ -z "$MATCH" ]; then
  echo "worker-log: missing required <uuid-substring>" >&2
  usage >&2
  exit 4
fi

DIR="$HOME/.pi/agent/sessions"
LOG=$(ls -t "$DIR"/*/*.jsonl 2>/dev/null | grep "$MATCH" | head -1)
[ -n "$LOG" ] || { echo "worker-log: no session log matching '$MATCH' under $DIR" >&2; exit 1; }
echo "log: $LOG" >&2
tail $FOLLOW -n "$LINES" "$LOG" | python3 -u -c "
import json, sys
def clip(s, n=160):
    s = str(s).replace(chr(10), ' ')
    return s[:n] + ('…' if len(s) > n else '')
for line in sys.stdin:
    try: e = json.loads(line)
    except Exception: continue
    m = e.get('message') or {}
    role = m.get('role', e.get('t', '?'))
    ts = (e.get('timestamp') or '')[11:19]
    if role == 'assistant':
        for c in m.get('content', []):
            if not isinstance(c, dict): continue
            ty = c.get('type')
            if ty == 'toolCall':
                name = c.get('toolName') or c.get('name') or m.get('toolName') or '?'
                arg = c.get('input', c.get('arguments', ''))
                print(ts, 'TOOL', name + ':', clip(arg))
            elif ty == 'text' and c.get('text', '').strip():
                print(ts, 'SAY :', clip(c.get('text', '')))
            elif ty == 'reasoning':
                print(ts, 'THINK:', clip(c.get('text', '')))
    elif role == 'toolResult':
        ok = 'ERR' if m.get('isError') else 'ok'
        txt = ''.join(x.get('text', '') for x in m.get('content', []) if isinstance(x, dict))
        print(ts, 'RES [' + ok + ']', clip(txt, 120))
    elif role == 'user':
        txt = ''.join(x.get('text', '') for x in m.get('content', []) if isinstance(x, dict))
        if txt.strip(): print(ts, 'USER:', clip(txt, 100))
"
