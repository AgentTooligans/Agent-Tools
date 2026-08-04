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

`.graphify_python` and `.graphify_root` pin **absolute** machine-specific paths.
They were once committed alongside an otherwise-gitignored `graphify-out/`, so a
stale interpreter path travelled with the repo — which is exactly what broke
graphify in the 2026-07-28 move. **They are now deliberately gitignored** and
each machine writes its own. Verified 2026-07-29: 0 tracked in every repo here.

`.git/hooks/` is **never version controlled**, so the post-commit and
post-checkout hooks must be reinstalled per machine — that is what
`agent-tools init` does.

**Procedure, as opposed to this incident record:** [MIGRATION.md](MIGRATION.md)
lists every out-of-repo path, what to copy, what to reinstall, and how to rotate
keys.

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
2026-07-28 this silently replaced 534 thematic names (*Billing Rules Engine*,
*Payment Retry Tests*) with hub names (*api_client.py*, *SessionCache*)
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
- `wiki` and `obsidian` ARE implemented — as `graphify export <format>`
  subcommands, not top-level flags. (An earlier version of this document said
  `--wiki` did not exist; that was wrong, and came from grepping only the
  top-level help.) Full list: `html`, `callflow-html`, `obsidian`, `wiki`,
  `svg`, `graphml`, `neo4j`, `falkordb`.
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
graphify query "how does session expiry work"
agentmemory status
```

Expected: graph present with node/edge counts, server healthy on :3111 with your
real session and observation counts.


---

## 2026-07-29 — the graph has no sense of time

A real graph was found holding a 190-line snapshot of a ledger that had grown to
3,061 lines and was seven days behind, sitting beside the live one at equal
standing. Nodes carry no date and no ordering (`version` was null on 14,644 of
14,647), so nothing distinguished them.

Hence two defaults: `init` and `doctor` care about instruction-file hygiene and
duplicate sections, and the documented practice is **scope** (`.graphifyignore`)
plus **`STATUS:` banners in prose**, because prose is the only staleness signal
extraction can read. Full failure catalog: [GRAPH-HYGIENE.md](GRAPH-HYGIENE.md).

Also from that day: `GRAPHIFY_API_TIMEOUT` defaults to 1800s for deep runs. A
chunk that exceeds the 600s default is lost, which makes the run partial, which
trips the node-count guard, which wastes the entire run — and a retry loop
without the raised ceiling just hits the same wall on the same chunk.

---

## 2026-08-04 — an installer that succeeds and installs nothing

`rtk init -g` is documented as the way to wire rtk's Claude Code hook. Run
without a terminal — from a script, from CI, from another tool — it prints:

```
Patch existing /Users/<you>/.claude/settings.json? [y/N]
(non-interactive mode, defaulting to N)

  MANUAL STEP: Add this to /Users/<you>/.claude/settings.json:
```

…and **exits 0**. Anything driving it programmatically records a success. The
binary is installed, the hook is not, and the only evidence is text on stdout.
It also has no per-project form, and it appends an `@RTK.md` import to the
**global** `CLAUDE.md` — a machine-wide edit, made even when what you asked for
was one repo.

So `agent-tools` does not call it. It writes the same `PreToolUse`/`Bash` entry
itself, through a JSON edit that:

- refuses to touch a `settings.json` it cannot parse (that file is somebody's
  entire Claude Code configuration);
- is idempotent — a second run reports "already present" rather than stacking
  a duplicate hook;
- appends to an existing `Bash` matcher instead of replacing it, so a repo that
  already has `graphify hook-guard search` ends up with **both**;
- removes cleanly, leaving every unrelated hook in the file untouched.

Verified both directions on a settings file containing graphify's two hook
entries: adding rtk left them intact, removing rtk left them intact.

### The same day: two tools named `rtk`

crates.io ships an unrelated **Rust Type Kit** under the same binary name.
`rtk --version` prints a version for either one, so it is not a test. `rtk gain`
exists only on `rtk-ai/rtk`, which is what `doctor` checks. Homebrew core's
`rtk` formula is the right project (homepage `rtk-ai.app`). On native Windows,
where upstream's `install.sh` does not run, `cargo install --git` names the
repository and therefore cannot resolve to the wrong package.

Related, smaller, same shape as graphify's `[gemini,mcp]`: **token-savior's
extras are not remembered across an upgrade.** Without `[memory-vector]` it
starts, prints *"vector search disabled"* to stderr, and degrades to
keyword-only recall — working, quieter, worse. `agent-tools update` reinstalls
with the extras named rather than running a bare `uv tool upgrade`.

And one path detail with teeth: rtk's macOS config directory is
`~/Library/Application Support/rtk` — **it contains a space**. A `tar` line
that word-splits an unquoted path list turns that into three nonexistent
arguments and silently ships an archive without your savings history.
`migrate export` feeds tar a newline-delimited `-T` file for exactly this
reason.

### And: two Bash rewriters is not twice the saving

`ts init` (token-savior) offers to write **ten** hook entries into the global
`~/.claude/settings.json`. One of them is a `PreToolUse`/`Bash` command
rewriter — the same job rtk's hook does. Stacked, they are not additive: each
rewrites the command the other produced, and a command that returns something
unexpected now has two filters to bisect.

`agent-tools wire token-savior` therefore registers the MCP server and nothing
else; the server does not need that hook. `doctor` flags the pair if it is
already there, because the only way to end up with both is to have run
`ts init` by hand and not connected it to rtk.

(Unlike context-mode, which also hooks `PreToolUse`/`Bash`, this one genuinely
conflicts. context-mode routes the *result*; rtk and token-savior both rewrite
the *command*.)
