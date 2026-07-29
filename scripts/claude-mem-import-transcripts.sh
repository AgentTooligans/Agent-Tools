#!/usr/bin/env bash
# ===========================================================================
# Replay historical Claude Code transcripts into claude-mem.
#
# WHY THIS EXISTS
#   claude-mem builds memory from sessions as they happen, via lifecycle hooks.
#   It has no documented bulk importer, so installing it on a machine with
#   months of history gives you an empty store and a cold start.
#
#   But its hooks read the session transcript from a JSON payload on stdin —
#   the field is `transcript_path`, mapped internally to `transcriptPath`. Your
#   past sessions are still on disk as JSONL under ~/.claude/projects/. So a
#   finished session can be replayed by handing the worker the same payload
#   Claude Code would have sent at Stop:
#
#     echo '{"session_id":..,"transcript_path":..,"cwd":..}' \
#       | node bun-runner.js worker-service.cjs hook claude-code summarize
#
# ✅ VERIFIED 2026-07-29 against claude-mem 13.12.4 (macOS): transcripts replay,
#    summaries land in session_summaries, and project attribution is correct.
#    Still run --dry-run first on a new machine — internal field names can
#    change between versions, and this drives an undocumented interface.
#
#    Two behaviors found by testing, both handled below:
#      1. claude-mem reads `cwd` from the TRANSCRIPT RECORDS. Transcripts copied
#         from another machine carry that machine's paths, so we re-home them.
#      2. `project` is stamped only in claude-mem's user-prompt path, so a
#         Stop-only replay lands with project='' -- we backfill it.
#
# ⚠️  COSTS TOKENS. Each replayed session triggers an AI summarization pass.
#     173 transcripts is 173 of them. Start small.
#
# Usage
#   claude-mem-import-transcripts.sh                    # dry run, shows what it would do
#   claude-mem-import-transcripts.sh --limit 1 --go     # try ONE for real
#   claude-mem-import-transcripts.sh --project myrepo --go
#   claude-mem-import-transcripts.sh --all --go         # everything (expensive)
# ===========================================================================
set -uo pipefail

PROJECTS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/projects"
DRY=1
LIMIT=5
FILTER=""
ALL=0
CWD_OVERRIDE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --go)      DRY=0 ;;
        --all)     ALL=1 ;;
        --limit)   LIMIT="${2:-5}"; shift ;;
        --project) FILTER="${2:-}"; shift ;;
        --cwd)     CWD_OVERRIDE="${2:-}"; shift ;;
        -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
        *) echo "unknown option: $1"; exit 2 ;;
    esac
    shift
done

c_ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
c_bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }
c_warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }

# --- locate claude-mem's plugin scripts -----------------------------------
# Mirrors the resolution order in claude-mem's own hook command.
find_plugin() {
    local c="${CLAUDE_CONFIG_DIR:-$HOME/.claude}" p
    for p in \
        "$c/plugins/cache/thedotmack/claude-mem/plugin" \
        "$c/plugins/cache/thedotmack/claude-mem" \
        "$c/plugins/marketplaces/thedotmack/plugin" \
        "$HOME/.claude-mem/plugin"; do
        [ -f "$p/scripts/worker-service.cjs" ] && [ -f "$p/scripts/bun-runner.js" ] && { printf '%s' "$p"; return 0; }
    done
    # Last resort: search, but do not wander the whole disk.
    p="$(find "$c" -name worker-service.cjs -path '*claude-mem*' 2>/dev/null | head -1)"
    [ -n "$p" ] && { printf '%s' "$(dirname "$(dirname "$p")")"; return 0; }
    return 1
}

PLUGIN="$(find_plugin)" || {
    c_bad "claude-mem plugin scripts not found."
    echo "     Install it first:  npx claude-mem install"
    exit 1
}
c_ok "plugin: $PLUGIN"

[ -d "$PROJECTS_DIR" ] || { c_bad "no transcripts at $PROJECTS_DIR"; exit 1; }

# --- Claude Code encodes the project path into the directory name, replacing
# --- separators with dashes. That is lossy, so we can only approximate the
# --- original cwd. Prefer a real path when one exists.
# Claude Code encodes the project path by replacing "/" with "-", which is
# LOSSY: a project literally named "Foo-Bar" is indistinguishable from
# "Foo/Bar". Naive replacement produced /Users/me/Projects/a home-automation project/HomeAssistant
# for a home-automation project, which does not exist, so it fell back to $HOME and
# every imported session landed with project=(none). Verified 2026-07-29.
#
# Greedy fix: start with every dash as "/", and while that path does not exist,
# merge the last two segments back with a dash and retry. Project names with
# dashes are almost always the trailing segment, so this converges fast.
decode_cwd() {
    local dir="$1" guess
    guess="$(printf '%s' "$dir" | sed 's|^-|/|; s|-|/|g')"
    local try="$guess"
    local i=0
    while [ "$i" -lt 8 ]; do
        [ -d "$try" ] && { printf '%s' "$try"; return; }
        case "$try" in
            */*/*) try="$(printf '%s' "$try" | sed 's|/\([^/]*\)$|-\1|')" ;;
            *) break ;;
        esac
        i=$((i + 1))
    done
    # Nothing on disk matches. Prefer the repo the user is standing in over
    # $HOME — an unrelated home directory guarantees a useless project label.
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
        git rev-parse --show-toplevel
    else
        printf '%s' "$HOME"
    fi
}

# claude-mem stamps `project` only in its user-prompt path (the INSERT that
# carries a real project name runs when a prompt arrives). A Stop-only replay
# never goes through it, so imported rows land with project='' and
# project-scoped recall misses them. Verified against worker-service.cjs
# 13.12.4 on 2026-07-29: project = basename(git rev-parse --show-toplevel).
#
# `project` is plain text with no embedding attached, so backfilling it is
# safe -- unlike content, which must be written through the hook to be
# vectorized. We reproduce claude-mem's own derivation exactly.
CM_DB="${CLAUDE_MEM_DATA_DIR:-$HOME/.claude-mem}/claude-mem.db"

backfill_project() {
    local sid="$1" cwd="$2" name
    [ -f "$CM_DB" ] || return 0
    name="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || name=""
    [ -n "$name" ] || name="$cwd"
    name="$(basename "$name")"
    [ -n "$name" ] && [ "$name" != "/" ] || return 0
    "${PYBIN:-python3}" - "$CM_DB" "$sid" "$name" <<'PYEOF'
import sqlite3, sys
db, sid, name = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    c = sqlite3.connect(db)
    c.execute("UPDATE sdk_sessions SET project=? "
              "WHERE content_session_id=? AND (project='' OR project IS NULL)",
              (name, sid))
    # summaries join through memory_session_id
    c.execute("UPDATE session_summaries SET project=? WHERE memory_session_id IN "
              "(SELECT memory_session_id FROM sdk_sessions WHERE content_session_id=?) "
              "AND (project='' OR project IS NULL)", (name, sid))
    c.commit(); c.close()
except Exception:
    pass          # never fail an import over a cosmetic label
PYEOF
}

total=0; done_n=0; skipped=0; TMPFEEDS=""
echo
[ "$DRY" = 1 ] && c_warn "DRY RUN — nothing will be imported. Add --go to execute."

for pdir in "$PROJECTS_DIR"/*/; do
    [ -d "$pdir" ] || continue
    base="$(basename "$pdir")"
    [ -n "$FILTER" ] && case "$base" in *"$FILTER"*) ;; *) continue ;; esac
    cwd="${CWD_OVERRIDE:-$(decode_cwd "$base")}"

    for t in "$pdir"*.jsonl; do
        [ -f "$t" ] || continue
        total=$((total + 1))
        if [ "$ALL" = 0 ] && [ "$done_n" -ge "$LIMIT" ]; then skipped=$((skipped + 1)); continue; fi

        sid="$(basename "$t" .jsonl)"

        # claude-mem reads `cwd` from the TRANSCRIPT RECORDS, not from the hook
        # payload. Transcripts written on another machine carry that machine's
        # paths (e.g. /home/you/git/proj), which do not exist here, so the
        # session lands with project=(none) and project-scoped recall misses it.
        # Verified 2026-07-29. So rewrite cwd into a temp copy and feed that.
        feed="$t"
        if [ -n "$cwd" ] && ! grep -q "\"cwd\":\"$cwd\"" "$t" 2>/dev/null; then
            feed="$(mktemp -t cmimport).jsonl"
            "${PYBIN:-python3}" - "$t" "$feed" "$cwd" <<'PYEOF'
import json, sys
src, dst, cwd = sys.argv[1], sys.argv[2], sys.argv[3]
with open(src, encoding="utf-8", errors="replace") as fh,      open(dst, "w", encoding="utf-8") as out:
    for line in fh:
        line = line.strip()
        if not line:
            continue
        try:
            d = json.loads(line)
        except Exception:
            out.write(line + "\n"); continue
        if "cwd" in d:
            d["cwd"] = cwd          # re-home to this machine
        out.write(json.dumps(d) + "\n")
PYEOF
            TMPFEEDS="$TMPFEEDS $feed"
        fi

        payload="$(printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' \
                   "$sid" "$feed" "$cwd")"

        if [ "$DRY" = 1 ]; then
            printf '  would import: %-38s -> %s\n' "${sid:0:36}" "$cwd"
            done_n=$((done_n + 1))
            continue
        fi

        printf '  importing %s ... ' "${sid:0:12}"
        if printf '%s' "$payload" | node "$PLUGIN/scripts/bun-runner.js" \
             "$PLUGIN/scripts/worker-service.cjs" hook claude-code summarize >/dev/null 2>&1; then
            backfill_project "$sid" "$cwd"
            echo "ok"
        else
            echo "FAILED"
        fi
        done_n=$((done_n + 1))
    done
done

# Clean up any re-homed temp copies.
for f in $TMPFEEDS; do rm -f "$f" 2>/dev/null; done

echo
echo "  transcripts found : $total"
echo "  processed         : $done_n"
[ "$skipped" -gt 0 ] && echo "  skipped (limit)   : $skipped  — use --all to do everything"
if [ "$DRY" = 1 ]; then
    echo
    c_warn "Nothing was written. To try ONE for real:"
    echo "      $0 --limit 1 --go   &&   claude-mem status"
else
    echo
    c_warn "Verify before doing more:  claude-mem status"
fi
