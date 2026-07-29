#!/usr/bin/env bash
# ===========================================================================
# Adopt a Claude Code session into a DIFFERENT project.
#
# WHY THIS EXISTS
#   Work often spans repos: you sit in project A, but the durable outcome
#   belongs to project B. Claude Code files a session under the directory you
#   launched it from, and that decides two things you may want elsewhere:
#
#     1. `claude --resume` only lists sessions filed under the CURRENT project
#        directory, so you cannot pick the conversation back up from B.
#     2. claude-mem attributes memory by the cwd recorded IN the transcript,
#        so project-scoped recall in B will never surface it.
#
#   This copies the transcript into B's store with `cwd` rewritten, then
#   optionally replays it through claude-mem so the memory lands in B too.
#
# ⚠  RUN IT AFTER THE SESSION ENDS.
#   claude-mem summarizes a still-open session as a mid-session CHECKPOINT --
#   observed 2026-07-29: a session with 12 commits across two repos was
#   summarized as "No work has shipped or changed... Discussion phase only,"
#   because status was still `active`. The transcript is also still being
#   appended, so an early copy is a partial snapshot. Finish the session first.
#
# Usage
#   adopt-session.sh --into ~/Projects/Agent-Tools                  # newest session here
#   adopt-session.sh --into ~/Projects/B --session <uuid>
#   adopt-session.sh --into ~/Projects/B --from ~/Projects/A
#   adopt-session.sh --into ~/Projects/B --no-import                # copy only, no memory
# ===========================================================================
set -uo pipefail

PROJECTS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
INTO=""; FROM="$(pwd)"; SESSION=""; DO_IMPORT=1

while [ $# -gt 0 ]; do
    case "$1" in
        --into)    INTO="${2:-}"; shift ;;
        --from)    FROM="${2:-}"; shift ;;
        --session) SESSION="${2:-}"; shift ;;
        --no-import) DO_IMPORT=0 ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

c_ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
c_bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }
c_warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }

[ -n "$INTO" ] || { c_bad "--into <project-dir> is required"; exit 2; }
[ -d "$INTO" ] || { c_bad "no such directory: $INTO"; exit 1; }
INTO="$(cd "$INTO" && pwd)"
FROM="$(cd "$FROM" 2>/dev/null && pwd)" || { c_bad "no such directory: $FROM"; exit 1; }

# Claude Code encodes a project path by replacing every "/" with "-".
encode() { printf '%s' "$1" | sed 's|/|-|g'; }
SRC_DIR="$PROJECTS_DIR/$(encode "$FROM")"
DST_DIR="$PROJECTS_DIR/$(encode "$INTO")"
[ -d "$SRC_DIR" ] || { c_bad "no transcripts for $FROM"; exit 1; }

if [ -n "$SESSION" ]; then
    SRC="$SRC_DIR/$SESSION.jsonl"
else
    # newest transcript, by mtime
    SRC="$(ls -t "$SRC_DIR"/*.jsonl 2>/dev/null | head -1)"
fi
[ -f "$SRC" ] || { c_bad "transcript not found in $SRC_DIR"; exit 1; }

# A session still being written is a partial snapshot; warn but proceed.
if [ -n "$(find "$SRC" -mmin -2 2>/dev/null)" ]; then
    c_warn "this transcript was modified in the last 2 minutes — the session may"
    c_warn "still be running. claude-mem will summarize it as a CHECKPOINT."
fi

mkdir -p "$DST_DIR"
DST="$DST_DIR/$(basename "$SRC")"

"${PYBIN:-python3}" - "$SRC" "$DST" "$FROM" "$INTO" <<'PYEOF'
import json, sys
src, dst, old, new = sys.argv[1:5]
n = r = 0
with open(src, encoding="utf-8", errors="replace") as fh, \
     open(dst, "w", encoding="utf-8") as out:
    for line in fh:
        line = line.rstrip("\n")
        if not line.strip():
            continue
        n += 1
        try:
            d = json.loads(line)
        except Exception:
            out.write(line + "\n"); continue
        # Rewrite cwd, including paths NESTED under the old root (a session
        # records subdirectories too, e.g. <root>/docs).
        if isinstance(d, dict) and isinstance(d.get("cwd"), str) and d["cwd"].startswith(old):
            d["cwd"] = new + d["cwd"][len(old):]
            r += 1
        out.write(json.dumps(d) + "\n")
print(f"  {n} records copied, {r} cwd values re-homed")
PYEOF

c_ok "transcript -> $DST"
c_ok "'claude --resume' in $(basename "$INTO") will now list this session"

if [ "$DO_IMPORT" = 1 ]; then
    here="$(dirname "$(command -v adopt-session.sh 2>/dev/null || echo "$0")")"
    imp="$here/claude-mem-import-transcripts.sh"
    [ -f "$imp" ] || imp="$(dirname "$0")/claude-mem-import-transcripts.sh"
    if [ -f "$imp" ]; then
        echo
        bash "$imp" --project "$(basename "$INTO")" --limit 1 --go
    else
        c_warn "claude-mem-import-transcripts.sh not found; copied only"
    fi
else
    c_warn "skipped the memory import (--no-import)"
fi
