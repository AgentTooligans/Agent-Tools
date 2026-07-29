# Memory backends: choosing, switching, converting

Two tools do this job well. **Only one should be capturing at a time** — each
hooks the session lifecycle, so two active backends means every tool call fires
two hook sets into two stores.

---

## The comparison

| | **claude-mem** (default) | **agentmemory** |
|---|---|---|
| stars / npm | 88.9k · 73.6k per month | 25.9k |
| store | `~/.claude-mem/` — SQLite + Chroma vectors | `./data/` **relative to the server's working directory** |
| store override | `CLAUDE_MEM_DATA_DIR` (honored) | `AGENTMEMORY_DATA_DIR` (**documented but inert**) |
| service | worker on :37701, `npx claude-mem start`; no launchd/systemd unit | supervised server on :3111 (launchd/systemd) |
| context injection | **automatic**, from your second session in a project | opt-in (`AGENTMEMORY_INJECT_CONTEXT`, off — costs tokens) |
| ingest past sessions | no bulk importer; ships `/learn-codebase` for a repo | `import-jsonl` over `~/.claude/projects` |
| export to Markdown | yes (`agent-tools memory export`, reads its SQLite read-only) | yes |
| write API | none — only its own hooks write | `POST /agentmemory/remember` |
| MCP surface | registers its own | 53 tools by default; **8 with `--tools core`** |
| multi-agent | claude-code, codex, cursor, copilot, gemini, windsurf, warp, opencode, openclaw, antigravity | similar list via `agentmemory connect` |

Neither is Claude-only — that is a common misconception. Both ship adapters for
roughly the same set of hosts.

### Which to pick

**claude-mem** if you want it to just work: no supervised service, no working-
directory trap, and context appears automatically at session start.

**agentmemory** if you want a supervised server with a documented write API
(`POST /agentmemory/remember`) that anything can post to, and you do not mind
that its working directory decides where the data lands.

Neither export nor history-rebuilding separates them any more: `agent-tools`
ships a Markdown exporter and a transcript importer for both. What still differs
is the *write path* — agentmemory takes writes from any client, while claude-mem
only writes through its own hooks.

---

## Choosing

```bash
agent-tools install-machine --memory=claude-mem     # default
agent-tools install-machine --memory=agentmemory
agent-tools install-machine --memory=none           # graphify only
agent-tools memory status                           # which one is active
```

The choice is stored in `~/.config/agent-tools/config`.

---

## Switching

```bash
agent-tools memory switch claude-mem
agent-tools memory switch agentmemory
```

**Machine-wide, not per-project.** Both backends hook at user scope and keep one
global store, so a per-project split would fragment your history and require
both to stay hooked — exactly the conflict this avoids.

The switch always: **exports first**, then converts what can be converted, then
**stops and disables** the outgoing backend (service *and* plugin hooks). The
outgoing store is **never deleted**, so switching back is possible.

### The asymmetry

|  | possible? | how |
|---|---|---|
| claude-mem → agentmemory | ✅ | memories POSTed to `/agentmemory/remember` |
| agentmemory → claude-mem | ⚠️ indirectly | claude-mem has **no ingest API** |

Going *to* claude-mem, memories cannot be injected. Instead
`scripts/agentmemory-to-claude-mem.py` synthesises a Claude Code transcript
containing them and feeds claude-mem's own Stop hook, so claude-mem summarises
and embeds them **natively** — the only way they end up semantically
searchable. Writing rows into its SQLite directly would produce memories that
keyword search finds and vector search cannot, because nothing would generate
their embeddings.

**Verified 2026-07-29:** 28 memories → 3 synthetic sessions → 3 stored
summaries, retaining the substance (architecture decisions, defect registers,
design laws).

**The trade-off, stated plainly:** claude-mem **summarises on ingest**, so the
converted copies are its compression of your memories, not verbatim. It also
correctly notes *"no primary session activity observed"* on them, because they
were not real work sessions. **Keep the Markdown export as the exact record.**

```bash
agent-tools memory export ~/my-memory-notes    # one note per memory + INDEX
```

---

## Rebuilding history in claude-mem

Two options, neither automatic:

**1. `/learn-codebase`** — claude-mem's own command, run inside Claude Code.
Ingests the current repo (~5 min). Best for *codebase* knowledge.

**2. Transcript replay** — `scripts/claude-mem-import-transcripts.sh` replays
past sessions from `~/.claude/projects` through the Stop hook. Best for
*session* history.

**Verified 2026-07-29** against claude-mem 13.12.4: transcripts replay, summaries
land, and sessions carry the right project. It stays dry-run by default and caps
at 5 transcripts, because **each replayed session costs an LLM summarization
pass** — 173 transcripts is 173 of them. Start with `--limit 1 --go`.

Two quirks the script works around, both found by running it:

- **`cwd` comes from the transcript records**, not the hook payload. Transcripts
  copied from another machine carry that machine's paths, so the script rewrites
  them into a temp copy before feeding it. Claude Code's project directory names
  are lossy (`/` becomes `-`, so `a home-automation project` is ambiguous), so it
  resolves the real path by merging segments back until one exists on disk.
- **`project` is only stamped in claude-mem's user-prompt path.** A Stop-only
  replay leaves it empty, which makes project-scoped recall miss the session, so
  the script backfills it using claude-mem's own rule —
  `basename(git rev-parse --show-toplevel)`. That column carries no embedding,
  so writing it directly is safe; content never is.

---

## Not competing

`doctor` distinguishes **installed** from **active**:

- both **active** → error, with the command to stop one
- one active, one installed-but-inert → fine, reported as an archive

An inert backend costs nothing and remains a searchable archive if you
re-enable it. That is a legitimate setup, and the tool no longer nags about it.

To make one inert by hand:

```bash
claude plugin disable agentmemory@agentmemory --scope local   # stop its hooks
launchctl bootout gui/$(id -u)/com.agentmemory.server         # macOS service
systemctl --user disable --now agentmemory                    # Linux/WSL
npx claude-mem stop                                           # claude-mem worker
```

**Gotcha:** `claude plugin uninstall` **fails** when a plugin is enabled at
*project* scope (listed in a repo's `.claude/settings.json`). Use
`disable --scope local` to stop the hooks immediately, then remove the entry
from that file so the repo stops advertising a backend you no longer use.

---

## Keeping memory out of CLAUDE.md

The reason a memory backend exists is so narrative does **not** live in your
instruction file. `init` writes a rule saying so, and `doctor` warns when
`CLAUDE.md` exceeds ~200 lines / 10 KB or contains a line over 2,000 characters
(a good sign of a pasted log). It never edits the file — see
[USAGE.md](USAGE.md).
