# Why every default exists — the incident record

This is the evidence behind `agent-tools`. Every rule it enforces is here with
the failure that produced it, so nobody has to rediscover them.

It was written during a Linux → macOS migration of one project on 2026-07-28,
then extended by real Linux and WSL2 testing on 2026-07-29. Project-specific
paths appear in places; the lessons are general.

**Start with [../README.md](../README.md).** Read this when something breaks, or
when you want to know why a rule is a rule.

---

## 1. What does not survive a machine move

| What | Symptom | Fix |
|---|---|---|
| **node / uv** | nothing runs at all | `brew install node uv` |
| **graphify CLI** | `graphify: command not found` | `uv tool install "graphifyy[gemini]"` |
| **Hook paths in `.claude/settings.json`** | hooks silently never fire | hooks must call bare **`graphify`**, never an absolute path |
| **`graphify-out/.graphify_python`** | every graphify run fails | repoint to this machine's uv interpreter |
| **agentmemory CLI** | `agentmemory: command not found` | `npm i -g @agentmemory/agentmemory` |
| **`~/.agentmemory/bin/iii`** | engine won't start | a copied binary is the **wrong architecture** — delete it, it re-downloads |
| **`iii.pid` / `worker.pid` / `engine-state.json`** | `stop --force` may signal an unrelated process | delete; regenerated on start |
| **MCP servers + plugins** | tools missing in Claude Code | `claude mcp add` / `claude plugin install` |
| **Memory data** | 0 sessions, 0 observations | manual copy — see §3 |
| **API keys** | LLM backends unavailable | manual — see §4 |

`.graphify_python` is **checked into the repo** while `graphify-out/` is otherwise
gitignored, so a stale absolute path travels with the repo to every new machine.

`.git/hooks/` is **never version controlled**, so the post-commit hook must be
reinstalled per machine — that is what `setup-dev-machine.sh` is for.

---

## 2. graphify

### What it is

Parses the repo with tree-sitter into a queryable graph, clusters it into
communities, and answers questions by traversing structure instead of grepping.
As of 2026-07-28: **7,001 nodes / 13,023 edges / ~534 communities** —
code (3,479), documents (2,741), rationale (764), concepts (17).

Outputs in `graphify-out/`: `graph.json`, `GRAPH_REPORT.md`, `GRAPH_TREE.html`.

### The rule that governs cost: code never uses an LLM

This was verified empirically, not assumed. In `cli.py`:

```python
semantic_files = doc_files + paper_files + image_files   # code excluded
```

and the `--mode deep` branch builds its set from `("document", "paper", "image")`
only. Extraction runs with Opus, Sonnet, Haiku, and `--mode deep` all produced
**byte-identical** code graphs (156 nodes / 290 edges on the same input).

| you changed | command | LLM? | cost |
|---|---|---|---|
| **code** | `graphify update .` | never | ~1 min, free |
| **docs / images** | `graphify extract . --backend claude-cli` | yes, only changed files | minutes |
| **community names** | `graphify label .` | yes, ~6 calls | minutes |

**Use `label`, never `cluster-only`, to name communities.** `cluster-only`
re-clusters and, when the community set has shifted, renames every community
after its **hub node** rather than calling the LLM — it prints *"Run `graphify
label` to refresh names with the LLM"* and exits 0, so it looks successful. On
2026-07-28 this silently replaced 534 thematic names (*Event Rule Engine*,
*InfluxDB Dialect Parsing Tests*) with hub names (*api_live.py*, *EnergyCache*)
because semantic extraction had shifted the clustering 534 -> 280.

Corollary: **any run that changes the graph invalidates the labels.** Labels are
keyed to a clustering, so re-extract then re-label, in that order.

So: **code changes never need an LLM.** Doc changes do, but incrementally — the
per-file manifest plus a content+prompt-keyed cache mean editing one session note
dispatches one file, not the whole corpus.

### Backends

- `claude-cli` — uses the **Claude Code subscription**, no API key. Concurrency is
  **forced to 1**, so it is slow but free. Defaults to whatever model the CLI
  defaults to; override with `GRAPHIFY_CLAUDE_CLI_MODEL`.
- `gemini` — needs `GEMINI_API_KEY` (an AI Studio key; a Gemini *subscription*
  does not provide one). Runs 4-way parallel. Requires the `[gemini]` extra or it
  fails with *"the 'openai' package is required for this backend"*.
- There is **no** backend for a ChatGPT subscription or for Antigravity/`agy`.

**Install line (both extras + the version pin):**

```bash
uv tool install "graphifyy[gemini,mcp]" --with "mcp<2" --force
```

`mcp<2` is mandatory. graphify 0.9.29 does `from mcp.types import AnyUrl`, which
`mcp` 2.0.0 removed — and it catches that and reports *"mcp not installed. Run:
pip install graphifyy[mcp]"* when the package **is** installed. Without the pin
`graphify-mcp` never starts and the error message sends you the wrong way.

Measured on 3 docs (72 KB), same input:

| backend | nodes / edges | time | notes |
|---|---|---|---|
| claude-cli (Opus) | **111 / 134** | 6.5 min | created edges to files outside the input set |
| gemini flash | 12 / 11 | 13 sec | dropped 1 of 3 files entirely |
| gemini pro | — | — | free tier is `limit: 0` — flash-class only |

Claude is far richer for prose; Gemini flash is ~30× faster and sparse. Note that
work is **chunked** (~17 files per chunk), so cost scales with chunks, not files.

### Auto-update on commit

`.git/hooks/post-commit` runs `graphify update .` (code only, no LLM). Three
safety layers:

1. **opt-in gate** — `.git/graphify-auto-update-ENABLED` **absent → skip** (default)
2. **concurrency** — any graphify process running → skip
3. **detached** — `git commit` never waits

```bash
touch .git/graphify-auto-update-ENABLED   # enable
rm    .git/graphify-auto-update-ENABLED   # disable (also the default)
tail  .git/graphify-auto-update.log       # what it did
```

**Why opt-in rather than a kill switch.** This started as an opt-OUT sentinel
(`.git/no-graphify-auto-update`). On 2026-07-28 that file vanished for reasons
never established, the hook silently re-enabled itself, and it re-clustered the
graph immediately after a commit. A guard whose *absence* means "run" turns
itself on through any accident. Inverted, a missing file means disabled — the
safe state. Do not flip this back.

The gate and log live under `.git/` deliberately: graphify owns
`graphify-out/`, so a sentinel stored there can be cleared by a rebuild.

### Keeping the graph current (use the script)

```bash
./scripts/graphify-refresh.sh              # full refresh, incremental
./scripts/graphify-refresh.sh --code-only  # AST only, zero LLM, ~1 min
./scripts/graphify-refresh.sh --check      # staleness report, changes nothing
./scripts/graphify-refresh.sh --no-label   # structure only, keep existing names
```

The script exists to enforce **one law**:

> **structure → labels → viz → verify.** Never label first.

It also refuses to run while another graphify process is active, and finishes
with a real query to prove the graph still answers.

**Why the order is not negotiable.** Labels are keyed to a *clustering*. Any run
that changes the graph re-clusters it, and communities that no longer match a
saved label get renamed after their hub node. Measured erosion from single runs:

| saved labels | communities after | hub-renamed |
|---|---|---|
| 536 | 535 | **501 (94%)** |
| 534 | 280 | **280 (100%)** |
| 280 | 271 | **137 (49%)** |

That is why `graphify update .` on its own quietly turns *Event Rules Engine*
back into *api_live.py*. The damage is cosmetic — nodes, edges and query results
are unaffected — and `graphify label .` repairs it in ~53 seconds.

**When to run it:** before you rely on the graph, not on a schedule. The failure
mode is not "slightly behind", it is a stale graph confidently answering with
code that no longer exists. Run it after a batch of work rather than after every
edit. A no-op refresh is free: graphify serves unchanged files from the
content-keyed cache (verified — *"535 files cached/unchanged, 0 re-extracted"*
with zero LLM calls), so you only pay for docs you actually edited.

`graphify check-update .` is the staleness probe. It is silent and exits 0 when
nothing is pending, which makes it safe for cron or a shell prompt.

### Upgrading graphify itself

```bash
uv tool install "graphifyy[gemini]" --force
./scripts/setup-dev-machine.sh --check      # confirm nothing came loose
```

**Not** plain `uv tool upgrade` — the `[gemini]` extra must be re-specified or
the gemini backend breaks again with *"the 'openai' package is required for this
backend"*.

**Upgrading can invalidate the committed semantic cache.** Entries are stamped
with the extraction prompt that produced them (upstream #1939), so a release
that changes that prompt turns all 1.6 MB into cache misses and costs a ~2-hour
re-extraction. Do not upgrade reflexively — upgrade when you have a reason (a
bug you are hitting, a feature you want) and can absorb a re-extraction window.

### Gotchas

- `graph.html` is skipped above **5,000 nodes**. Use `graphify tree` →
  `GRAPH_TREE.html`, which has no cap.
- `--wiki` appears in the skill's usage text but is **not implemented** in the
  0.9.29 CLI.
- The `hook-guard` PreToolUse hook is **advisory only** — it prints a nudge and
  exits. It never rebuilds anything, so it cannot conflict with a running job.

---

## 3. agentmemory

### The store-location law (most important thing here)

In v0.9.28 the iii engine resolves its state path as **`./data/state_store.db`
relative to the working directory**. `AGENTMEMORY_DATA_DIR` and `--data-dir` are
documented but **not honored** — both were tested on 2026-07-28 and ignored.

Consequences:

- Launch it from a project folder and you silently get a **new, empty** memory
  store, plus a stray `data/` directory inside that repo.
- The LaunchAgent's `WorkingDirectory` (`~/.agentmemory`) is the *only* thing
  keeping one shared store. **Do not change it.**
- On another machine, the old store is wherever the server was launched from —
  **not** `~/.agentmemory`. Find it with:
  ```bash
  find / -type d -name state_store.db 2>/dev/null
  ```

### Migrating the store

**Stop the server first.** A running engine rewrites the session index while you
copy — that is how the 2026-07-28 migration lost its session list (observations
and memories survived; `mem:sessions.bin` was overwritten and had to be restored
from the source copy).

```bash
launchctl bootout gui/$(id -u)/com.agentmemory.server
cp -R /path/to/old/data/* ~/.agentmemory/data/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.agentmemory.server.plist
agentmemory status      # expect your real session/observation counts
```

The store files are JSON plus an **8-byte footer**: a 4-byte hash and a 4-byte
negative payload length. **Do not hand-edit them.** Rewriting session paths with
a corrected length but the original hash made the engine reject the file —
sessions and observations both read as 0 until the backup was restored.

### Old sessions keep the old machine's paths

Sessions record the `cwd` they ran in, and there is no supported update endpoint.
So after a move:

- `recall`, `session-history` — unaffected (no path filter)
- `/handoff` — filters by directory, but accepts a path override
- `/recap` — filters by directory, **no override**; will not see old sessions

### Scope

- **MCP server**: scoped to this project (`-s local`). A user-scope entry makes
  every `claude -p` subprocess boot a memory shim (~300 ms each) — pure waste for
  scripted fan-out like graphify's LLM backend.
- **Plugin hooks**: installed at user scope, so they fire in *every* project.
  Measured overhead: PostToolUse ~50–80 ms on every tool call, PreToolUse ~50 ms
  on Edit/Write/Read/Glob.
- **`--tools core` must be a server ARGUMENT.** The default `all` publishes 53
  MCP tools — **~5,918 tokens of schema in every session**. `core` is 8 tools,
  **~995 tokens**. Setting `AGENTMEMORY_TOOLS=core` in `~/.agentmemory/.env` had
  **no effect**, and neither did setting it in the MCP shim's environment; both
  were measured. It works only as `agentmemory --tools core`, i.e. in the
  LaunchAgent's `ProgramArguments`.

Measured MCP schema cost — this is carried in *every* session, so tool count
matters more than it looks:

| server | tools | per-session |
|---|---|---|
| agentmemory (`all`, default) | 53 | ~5,918 tokens |
| agentmemory (`--tools core`) | 8 | ~995 tokens |
| graphify-mcp | 10 | ~1,522 tokens |

graphify's MCP surface includes `get_pr_impact`, `list_prs` and `triage_prs` —
PR blast-radius analysis, which is normally cited as the reason to add a
*second* graph tool alongside it.

### Do not run `memory_heal` on a freshly restored store

Its job is to "clean up orphaned data." If the session index is missing or
mismatched, restored observations are exactly what it would classify as orphaned.

---

## 4. Secrets

Nothing migrates keys. graphify's gemini backend reads `GEMINI_API_KEY` from the
environment; keep it in `~/.config/graphify/env` (`chmod 600`) and source it.

Free-tier AI Studio keys are **flash-class only** — pro models return HTTP 429
with `limit: 0` for both request and token quotas.

---

## 5. Verification

```bash
./scripts/setup-dev-machine.sh --check
graphify query "how does heatmap outlier attribution work"
agentmemory status
```

Expected: graph present with node/edge counts, server healthy on :3111 with your
real session and observation counts.
