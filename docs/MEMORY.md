# Memory — so you stop re-explaining your own project

Without memory, every session starts from nothing. You explain the same
architecture, re-litigate the same decision, and watch your assistant
confidently suggest the approach you already rejected last week.

Memory fixes that. It captures what happened in a session — decisions,
rationale, what was tried and rejected — and makes it searchable next time.

There's one backend: **claude-mem**. It runs locally, stores everything in
`~/.claude-mem`, and nothing leaves your machine.

> **Upgrading from an older version?** agentmemory was removed in 3.4.0. Your
> old store is untouched and there's a one-command migration. Your old store is untouched and there is a one-command migration —
[skip to it](#migrating-off-agentmemory).

Two of the optional tools also store session data, and neither is a substitute:

- **context-mode** does *session continuity* — surviving a compaction inside
  one long session. It does not give you recall of a decision made three weeks
  ago, and does not try to. Run it alongside a backend, not instead of one.
- **token-savior** ships a genuine memory engine (SQLite WAL + FTS5 +
  vectors). On a machine running `--memory=none` it can be your backend. On a
  machine already running claude-mem it is a **second store recording the same
  sessions** — leave that half unwired.

`agent-tools doctor` warns when two capturers are **active**, not merely
installed. See [TOOLS.md](TOOLS.md#memory--one-capturer-always).

---

## claude-mem

| | |
|---|---|
| store | `~/.claude-mem/` — SQLite + Chroma vectors, **absolute path** |
| store override | `CLAUDE_MEM_DATA_DIR` (honored) |
| service | worker on :37701; restart with `agent-tools restart memory`; **no launchd/systemd unit** |
| context injection | **automatic**, from your second session in a project |
| ingest past sessions | no bulk importer; ships `/learn-codebase` for a repo |
| export to Markdown | yes (`agent-tools memory export`, reads its SQLite read-only) |
| write API | none — only its own hooks write |
| MCP surface | registers its own |
| multi-agent | claude-code, codex, cursor, copilot, gemini, windsurf, warp, opencode, openclaw, antigravity |

It is not Claude-only — a common misconception. It ships adapters for roughly
the same host list agentmemory did.

**The one thing to know: the worker is not autostarted.** claude-mem's own
installer prints *"Worker autostart skipped — start it manually with `npx
claude-mem start`"* and moves on. No worker means no capture, and nothing in
the session tells you. `agent-tools doctor` checks :37701; [SERVICES.md](SERVICES.md)
has a login-time snippet.

---

## Choosing

```bash
agent-tools install-machine --memory=claude-mem     # default
agent-tools install-machine --memory=none           # graphify only, nothing captures
agent-tools memory status                           # which one is active
```

The choice is stored in `~/.config/agent-tools/config`.

A config file that still says `memory_backend=agentmemory` does not break:
agent-tools falls back to claude-mem, prints one notice, and leaves your store
alone.

---

## Switching

```bash
agent-tools memory switch claude-mem     # start capturing
agent-tools memory switch none           # stop capturing; store kept
```

**Machine-wide, not per-project.** Memory hooks at user scope and keeps one
global store, so a per-project split would fragment your history.

The switch **exports first**, every time. `switch none` stops the worker but
leaves both the store and claude-mem's hooks in place, so switching back costs
nothing.

To remove claude-mem itself:

```bash
agent-tools uninstall claude-mem
```

That runs `npx claude-mem uninstall`, records the backend as `none` so the
default cannot silently reinstate one, and then — separately — asks whether you
also want `~/.claude-mem` deleted. **That store is every session it has ever
captured and cannot be regenerated**, so the default answer is no; `--purge`
deletes it, `--keep-data` keeps it without asking. See
[UPDATING.md](UPDATING.md#removing-things).

---

## Migrating off agentmemory

agentmemory was a supported backend through 3.2.x. It is gone as of 3.3.0.

### Why it was removed

Not a quality judgement — a maintenance one. Three facts, all verified:

- **The store path was relative to the server's working directory**
  (v0.9.28: `./data/state_store.db`). `AGENTMEMORY_DATA_DIR` and `--data-dir`
  were documented and **inert**. Start the server from the wrong place and you
  silently got a new, empty memory.
- **Surviving that required a supervisor.** The launchd plist and systemd unit
  this repo shipped existed almost entirely to pin one working directory — and
  brought `loginctl enable-linger`, a WSL-after-Windows-restart gap, and a
  `--tools core` argument that could not be set any other way (as an env var or
  in `.env` it was ignored, which is the difference between 53 MCP tools
  ≈5,918 tokens of schema per session and 8 ≈995).
- **It had no native-Windows engine installer**, and `agentmemory connect` was
  unsupported there. That single fact pinned this whole project to
  "Windows = graphify only" for three minor versions.

Removing it deleted the plist, the unit, the linger call, the cwd pinning, the
`--tools core` law, and the Windows blocker in one go.

### The migration

**Your data is not deleted.** `~/.agentmemory` is left byte-for-byte intact.

```bash
agent-tools memory migrate-from-agentmemory
```

It runs in three stages and asks before each destructive one:

1. **Export** the store to Markdown at `~/agentmemory-export-<date>` — the exact
   record, before anything is touched. (Needs the server running on :3111; if it
   is stopped, the command tells you how to start it once.)
2. **Import** what it can into claude-mem (see the asymmetry below).
3. **Retire the service**: stop it, disable the launchd job (keeping the plist
   as `.disabled`) or the systemd unit, disable the Claude Code plugin so its
   hooks stop firing, and remove the stale MCP entry.

`agent-tools doctor` detects a legacy install and tells you whether it is still
capturing alongside claude-mem — which is worth fixing, because that means two
hook sets fire on every tool call.

### The asymmetry

|  | possible? | how |
|---|---|---|
| agentmemory → claude-mem | ⚠️ indirectly | claude-mem has **no ingest API** |
| claude-mem → agentmemory | ❌ | the backend no longer exists |

Memories cannot be injected into claude-mem. Instead
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

### Handling the old store by hand

If you would rather not run the migration, two rules from the agentmemory era
still apply to that directory:

- **Stop the server before copying store files**, or the live engine overwrites
  the session index mid-copy. Store files are JSON plus an 8-byte hash/length
  footer; hand-edit them and the engine rejects the file.
- **Never run `memory_heal` on a freshly restored store** — restored
  observations look exactly like the "orphaned" data it deletes.

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

Only one backend ships now, so the common conflict is a **legacy agentmemory
still capturing** alongside claude-mem. `doctor` distinguishes **installed**
from **active**:

- both **active** → error, with the command to fix it
- legacy present but inert → fine, reported as an archive

An inert install costs nothing and remains a searchable archive if you
re-enable it. That is a legitimate setup, and the tool does not nag about it.

The supported fix is `agent-tools memory migrate-from-agentmemory`. To make one
inert by hand instead:

```bash
claude plugin disable agentmemory@agentmemory --scope local   # stop its hooks
launchctl bootout gui/$(id -u)/com.agentmemory.server         # macOS service
systemctl --user disable --now agentmemory                    # Linux/WSL
claude mcp remove agentmemory -s local                        # stale MCP entry
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


---

## Multiple machines — what actually travels

**Investigated 2026-07-29.** Short answer: **memory does not travel.**

The backend *choice* is machine-wide and portable-by-config
(`~/.config/agent-tools/config`, read identically from every project — there is
no per-project backend, deliberately). The memory *itself* is another matter.

| | where it lives | travels? |
|---|---|---|
| claude-mem store | `~/.claude-mem/` (SQLite + Chroma) | **no** |
| legacy agentmemory store | `~/.agentmemory/` | **no** |
| global skills (caveman, pocock) | `~/.agents/skills/` | **no** — but `install-machine` reinstalls them |
| transcripts | `~/.claude/projects/` | **no** — so `claude --resume` history is per-machine |
| graphify semantic cache | `graphify-out/cache/` **if committed** | **yes** |
| git hooks | `.git/hooks/` | **no** — git never clones hooks; re-run `agent-tools init` |

### claude-mem has two runtimes, and only one is local

```
npx claude-mem install --runtime worker    # default: local SQLite + Chroma
npx claude-mem install --runtime server    # Docker postgres + redis + API key
```

The **server** runtime is the real multi-machine answer: several machines point
at one backend instead of each keeping a private SQLite. It generates an API key
and injects the IDE MCP config.

The `sync_*` tables in the local store (`sync_outbox`, `sync_state`,
`sync_entity_heads`, `sync_dead_letter`) are scaffolding for that path. On a
worker-runtime install they are **inert**: observed `sync_state = 0` with 16
rows queued in `sync_outbox` that nothing drains. Do not read a populated
outbox as "sync is working."

### Carrying memory across without a server

1. **`agent-tools memory export <dir>`** — verified 2026-07-29 to copy stored
   text **verbatim** (3/3 sampled fields matched byte-for-byte); it does not
   re-summarize. The summarization loss happened once, upstream, at ingest.
   This is your portable, exact record — commit it or sync it to a vault.
2. **`scripts/adopt-session.sh --into <project>`** — moves an individual session
   so `claude --resume` finds it in another project and claude-mem attributes
   memory there.

## Telemetry

**claude-mem sends anonymous telemetry, and it is ON by default.**

```bash
npx claude-mem telemetry status     # Telemetry: ENABLED / Decided by: default
npx claude-mem telemetry disable
```

It reports a random install UUID (`~/.claude-mem/telemetry.json`), documented at
docs.claude-mem.ai/telemetry. Noted because it is easy to miss during install,
and because caveman — installed alongside — states the opposite policy for
itself. Neither claim was independently verified here; both are the projects'
own statements.
