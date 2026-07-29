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
# ⚠️  UNVERIFIED. This was derived by reading claude-mem's minified bundle, not
#     by running it — claude-mem was never installed on the machine where this
#     was written. Treat it as a starting point: run --dry-run first, then a
#     single transcript, and check `claude-mem status` before doing the rest.
#     Internal field names may change between versions.
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

while [ $# -gt 0 ]; do
    case "$1" in
        --go)      DRY=0 ;;
        --all)     ALL=1 ;;
        --limit)   LIMIT="${2:-5}"; shift ;;
        --project) FILTER="${2:-}"; shift ;;
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
decode_cwd() {
    local dir="$1" guess
    guess="$(printf '%s' "$dir" | sed 's|^-|/|; s|-|/|g')"
    [ -d "$guess" ] && { printf '%s' "$guess"; return; }
    printf '%s' "$HOME"
}

total=0; done_n=0; skipped=0
echo
[ "$DRY" = 1 ] && c_warn "DRY RUN — nothing will be imported. Add --go to execute."

for pdir in "$PROJECTS_DIR"/*/; do
    [ -d "$pdir" ] || continue
    base="$(basename "$pdir")"
    [ -n "$FILTER" ] && case "$base" in *"$FILTER"*) ;; *) continue ;; esac
    cwd="$(decode_cwd "$base")"

    for t in "$pdir"*.jsonl; do
        [ -f "$t" ] || continue
        total=$((total + 1))
        if [ "$ALL" = 0 ] && [ "$done_n" -ge "$LIMIT" ]; then skipped=$((skipped + 1)); continue; fi

        sid="$(basename "$t" .jsonl)"
        payload="$(printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","hook_event_name":"Stop"}' \
                   "$sid" "$t" "$cwd")"

        if [ "$DRY" = 1 ]; then
            printf '  would import: %-38s -> %s\n' "${sid:0:36}" "$cwd"
            done_n=$((done_n + 1))
            continue
        fi

        printf '  importing %s ... ' "${sid:0:12}"
        if printf '%s' "$payload" | node "$PLUGIN/scripts/bun-runner.js" \
             "$PLUGIN/scripts/worker-service.cjs" hook claude-code summarize >/dev/null 2>&1; then
            echo "ok"
        else
            echo "FAILED"
        fi
        done_n=$((done_n + 1))
    done
done

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
