#!/bin/bash
# ---------------------------------------------------------------------------
# graphify full LLM pass for a home-automation project — detached launchd job.
#
# Phase 1  semantic extraction (--mode deep) over docs + images, AST over code,
#          wrapped in a retry loop so a plan rate-limit is a pause, not a death.
#          graphify caches completed files, so each pass only retries what's
#          left; the deep cache namespace is cold on the first pass by design.
# Phase 2  re-cluster + LLM community naming (~6 calls).
# Phase 3  GRAPH_TREE.html — the node-capped graph.html can't render 7k nodes.
# Phase 4  smoke-test queries so the log proves the graph still answers.
#
# Terminates itself: on completion it boots itself out of launchd and deletes
# its own plist, so it never re-runs at next login. Written 2026-07-28.
# ---------------------------------------------------------------------------
set -u

REPO="/Users/you/Projects/a home-automation project"
LOGDIR="$HOME/graphify-backups"
LOG="$LOGDIR/graphify-full-run.log"
PASSLOG="$LOGDIR/.pass-current.log"
STATUS="$LOGDIR/graphify-full-run.status"
LABEL="com.graphify.fullrun"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
MAX_PASSES=8
BACKOFF=300   # seconds between retry passes (rate-limit cool-off)

# Deep chunks are big, and the claude-cli backend answers slowly on them.
# graphify's default API timeout is 600s; a chunk that exceeds it is lost and
# the whole run lands PARTIAL, which the node-count guard then (correctly)
# refuses to write. Observed 2026-07-29: chunk 23/26 timed out, the run produced
# 3341 nodes against an existing 14647, and graphify refused to overwrite.
# Raise the ceiling, but never override a value the user set deliberately.
export GRAPHIFY_API_TIMEOUT="${GRAPHIFY_API_TIMEOUT:-1800}"


export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "$LOGDIR"
say() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }
setstatus() { echo "$1" > "$STATUS"; }

say "================ graphify full LLM run: START ================"
say "repo=$REPO  backend=claude-cli  mode=deep  max_passes=$MAX_PASSES"
setstatus "RUNNING phase1"

cd "$REPO" || { say "FATAL: cannot cd to $REPO"; setstatus "FAILED cd"; exit 1; }

# ---- Phase 1: semantic extraction with retry ------------------------------
pass=1
extract_ok=0
while [ "$pass" -le "$MAX_PASSES" ]; do
  say "--- phase1 pass $pass/$MAX_PASSES: graphify extract . --backend claude-cli --mode deep"
  : > "$PASSLOG"
  graphify extract . --backend claude-cli --mode deep >> "$PASSLOG" 2>&1
  rc=$?
  cat "$PASSLOG" >> "$LOG"
  say "pass $pass exit=$rc"

  # Completion signal: graphify warns when chunks fail or files yield no nodes,
  # and leaves them unstamped for the next pass. No warnings + rc 0 == done.
  if [ "$rc" -eq 0 ] && ! grep -qE "WARNING|failed|error:" "$PASSLOG"; then
    say "phase1 CLEAN on pass $pass"
    extract_ok=1
    break
  fi

  # Failure-aware backoff. Sleeping only helps when the cause is a quota that
  # refills with wall-clock time. A parse/envelope failure (e.g. the claude-cli
  # session drifting agentic and returning truncated JSON, #2076) fails or
  # succeeds identically now or in an hour — waiting there is pure latency, and
  # the retry usually clears it because the remaining files get re-batched into
  # a different chunk shape.
  if grep -qiE "rate limit|429|quota|RESOURCE_EXHAUSTED|usage limit|overloaded" "$PASSLOG"; then
      say "phase1 incomplete: QUOTA/RATE-LIMIT signature — sleeping ${BACKOFF}s"
      sleep "$BACKOFF"
  else
      say "phase1 incomplete: non-quota failure (parse/envelope/partial) — retrying immediately"
      sleep 5
  fi
  pass=$((pass + 1))
done

if [ "$extract_ok" -ne 1 ]; then
  say "WARNING: phase1 still had warnings after $MAX_PASSES passes — continuing"
  say "         (cached files persist; re-running this script resumes cheaply)"
fi

# ---- Phase 2: LLM community naming ----------------------------------------
# MUST be `label`, not `cluster-only`. On 2026-07-28 this used cluster-only and
# silently destroyed the thematic names: semantic extraction had shifted the
# clustering (534 communities -> 280), so the saved labels no longer matched and
# cluster-only fell back to renaming every community after its hub node,
# printing "Run `graphify label` to refresh names with the LLM". `label` does
# the clustering AND spends the ~6 LLM calls to name it properly.
setstatus "RUNNING phase2"
say "--- phase2: graphify label . --backend claude-cli"
graphify label . --backend claude-cli >> "$LOG" 2>&1
say "phase2 exit=$?"
if grep -q "Run \`graphify label\`" "$LOG" 2>/dev/null; then
    say "WARNING: graphify still reports hub-renamed communities — names may not be thematic"
fi

# ---- Phase 3: tree visualization (no node cap) ----------------------------
setstatus "RUNNING phase3"
say "--- phase3: graphify tree"
graphify tree >> "$LOG" 2>&1
say "phase3 exit=$?"

# ---- Phase 4: smoke tests --------------------------------------------------
setstatus "RUNNING phase4"
say "--- phase4: smoke queries"
{
  echo "### query: heatmap outlier attribution"
  graphify query "heatmap outlier attribution dead run dump" 2>&1 | head -12
  echo "### query: resolution law"
  graphify query "resolution law v2 max per day" 2>&1 | head -12
} >> "$LOG" 2>&1

if [ -f graphify-out/graph.json ]; then
  N=$(python3 -c "import json;d=json.load(open('graphify-out/graph.json'));print(len(d['nodes']),len(d['links']))" 2>/dev/null)
  say "final graph: $N (nodes edges)"
fi

say "================ graphify full LLM run: DONE ================"
setstatus "DONE $(date '+%Y-%m-%d %H:%M:%S')"

# ---- Self-termination ------------------------------------------------------
# Remove the plist first so a crash between the two steps can't leave a job
# that re-runs this whole thing at next login.
rm -f "$PLIST"
say "plist removed; booting out of launchd (this ends the job)"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
exit 0
