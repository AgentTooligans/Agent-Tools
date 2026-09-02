# Getting good use out of the graph and your memory

These two tools do genuinely different jobs, and most of the skill in using
them is knowing which one you actually want.

The short version: **the graph knows what your code *is*. Memory knows what you
*decided*.** If you're asking "what calls this function?", that's the graph. If
you're asking "why on earth did we do it this way?", that's memory.

This page covers when each one earns its keep, what the graph is genuinely bad

## Which model builds the graph?

The structural pass needs no model at all — it's local AST parsing. Only the
semantic pass (docs, concepts, community naming) calls one, and the backend is
chosen in this order:

1. **`AGENT_TOOLS_BACKEND` or `GRAPHIFY_BACKEND`**, if you set either. An
   explicit choice always wins.
2. **`claude-cli`**, if the `claude` CLI is installed — no API key, billed to
   an existing subscription, so it's free at the margin for people who have it.
   It runs the **Sonnet** model by default (graphify's own default is Opus,
   overkill for structured extraction). Override with
   `GRAPHIFY_CLAUDE_CLI_MODEL=haiku` (or `opus`, or a full model id).
3. **Whatever API key you have.** graphify auto-detects from `GEMINI_API_KEY`,
   `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `DEEPSEEK_API_KEY` and friends.
   No `claude` CLI needed — a Codex-only user with `OPENAI_API_KEY` lands here
   automatically (there is no `codex` backend; the `openai` one is used).
4. **A local ollama** on `:11434`.

If none of those exist, `agent-tools refresh` refuses to start and points you
at `--code-only`, which needs nothing.

**Parallelism.** On an API backend the semantic pass runs 4 chunks at once by
default; raise it with `AGENT_TOOLS_CONCURRENCY=8`. On `claude-cli` graphify
**forces serial execution** (one chunk at a time) — parallel `claude -p`
subprocesses conflict over Claude Code session state — so `AGENT_TOOLS_CONCURRENCY`
is ignored there (refresh prints a notice when you set it on claude-cli). Each
claude-cli chunk is also a full `claude -p` process that reloads the CLI's system
prompt. Net: for a fast, parallel semantic pass, use an API key backend.

> Earlier versions passed `--backend claude-cli` unconditionally. That
> **overrode** graphify's own auto-detection, so a machine with a Gemini key
> and no Claude CLI failed for no good reason. See [WHY.md](WHY.md).
at (there are real gaps — grep is still the right tool sometimes), and how to
get your assistant to actually reach for them.

| | **graphify** | **claude-mem** |
|---|---|---|
| answers | "what *is* this code, and what connects to what" | "what did we *do*, and why" |
| source | your repo, parsed | your past sessions |
| lives | `graphify-out/` in the project | `~/.claude-mem/`, all projects |
| cost | free for code; docs cost tokens once | free |

Two opt-in tools — **code-review-graph** and **token-savior** — answer the same
question as graphify with different trade-offs. Everything on this page about
*when a graph earns its keep* applies to all three; which one to reach for is
[TOOLS.md](TOOLS.md). Wire one per project, not three.

---

## graphify — when it earns its keep

### 1. Orienting in unfamiliar code

```bash
graphify query "how does session expiry work"
```

Returns a **scoped subgraph** within a token budget instead of the fifteen files
you'd otherwise read. On a 7,000-node graph a typical query surfaces ~60 relevant
nodes for roughly 2,000 tokens.

### 2. Blast radius — before you change something

```bash
graphify affected "SessionCache"              # what breaks if I touch this
graphify affected "helpers.py" --depth 1      # direct dependents only
graphify affected "api.py" --relation calls   # only call edges
```

Real output is `symbol [relation] file:line`, so you get the actual call sites,
not a guess.

### 3. What is dangerous to touch at all

```bash
graphify god-nodes --top 10
```

Ranks the most-connected nodes. A node with 146 edges is a change you plan;
a node with 3 is a change you just make.

### 4. Tracing a connection

```bash
graphify path "AuthService" "Database"
graphify explain "RetryPolicy"
```

### 5. The reports

`graphify-out/GRAPH_REPORT.md` includes **God Nodes**, **Surprising
Connections** (inferred cross-file links you didn't know about), and **Import
Cycles**. `GRAPH_TREE.html` is a browsable tree — use it instead of `graph.html`,
which is skipped above 5,000 nodes.

### What graphify is BAD at

It models **symbols and modules**, not text. Ask it about a CSS variable or any
string-level concern and it will confidently return nothing:

```bash
graphify explain "--brand-color"      # -> No node matching found
grep -rl -- "--brand-color" src       # -> the actual 13 files
```

This is not a bug — a CSS custom property inside a template literal is not an
AST symbol. **For token/string questions, grep is correct and graphify is
useless.** Knowing the boundary is the whole trick.

---

## Memory — how to use it well

Both backends capture automatically through session hooks; you rarely call
them directly. See [MEMORY.md](MEMORY.md) for choosing and switching.

**Do:**

- Let it record. The hooks fire on session start, tool use, and stop.
- Save durable decisions explicitly when they matter:
  `memory_save` / "remember that we chose X because Y".
- Use `recall` for *why* questions: "did we ever try Redis for this?"
- Use `recap` / `session-history` to reconstruct where you left off.
- Use `handoff` when starting a session cold.

**Don't:**

- Don't use it for facts that live in the repo — that's graphify's job. Memory
  is for decisions, dead ends, and rationale, not for "what does this function
  do".
- Don't paste secrets into a session. Everything is captured and persisted
  locally, so a pasted key ends up in the store.
- Don't run `memory_heal` on a freshly restored store — restored observations
  look exactly like the "orphaned" data it deletes.

**Know:** sessions record the working directory they ran in. Move a project (or
a machine) and directory-filtered commands like `recap` won't match the old
ones. Search still finds them.

---

## Telling the agent to use them

Agents do **not** automatically know these tools exist or when to prefer them.
Four mechanisms, weakest to strongest:

**1. MCP tools (passive).** After `agent-tools init` the agent *can* call
graphify's 10 graph tools, plus whatever your memory backend registers. It will
sometimes choose to. This alone is not reliable.

**2. graphify's hook-guard (active).** Installed by `init`. Before any
Bash/Read/Glob it injects:

> *MANDATORY: graphify-out/graph.json exists. You MUST run `graphify query` before grepping raw files.*

This is the single most effective nudge, because it fires at the moment the
agent is about to grep.

**3. Skills teach judgment, MCP tools only grant capability.** Wiring a memory
or graph MCP server makes tools *available*; it does not teach an agent *when*
to reach for them. That is what a skill is for. `agent-tools` installs two
packs globally (`caveman`, `pocock`) — see [SKILLS.md](SKILLS.md) — and
`/grill-me` in particular is the one to reach for before implementation, when
the cheapest thing you can do is pin the plan down.

**4. Project instructions (strongest).** Put it in the file your agent already
reads — `AGENTS.md`, or `CLAUDE.md` for Claude Code. `agent-tools init` offers
to add a section for you, **generated from what's wired here** (graphify always;
`code-review-graph` and `token-savior` lines only when wired — `wire`/`unwire`
add and remove them, and re-running `init` resyncs). Since Claude Code reads
`CLAUDE.md`, not `AGENTS.md`, it also drops a one-line `CLAUDE.md` that
`@`-imports `AGENTS.md` so Claude sees the same block with nothing duplicated.
`agent-tools doctor` checks that import is present. Something like:

```markdown
## Codebase knowledge
Before grepping or reading files broadly, run `graphify query "<question>"`.
Use `graphify affected "<symbol>"` before refactoring to see the blast radius.
Note: graphify does NOT index string/CSS-level details — use grep for those.

## Memory
Use `recall` before re-deriving a past decision. Save durable decisions with
`memory_save`.
```

---

## What happens when the graph is stale

**graphify notices, and degrades honestly.** Its hook-guard checks freshness
*per file*: when the graph is stale for the file being read, it softens from
MANDATORY to a non-binding nudge, so the agent reads the real file instead of
trusting an outdated map (graphify `cli.py`: *"a graph that is stale for the
target file softens to a non-mandatory nudge instead of blocking or
demanding"*).

So a stale graph degrades toward normal file reading rather than lying — but
only for files it knows changed. **Structure it has never seen (a brand-new
module) simply isn't there**, and a query will quietly return nothing about it.
That is the failure mode to watch for.

Check and refresh:

```bash
agent-tools doctor    # what state is this project in?
agent-tools refresh   # structure -> labels -> viz -> verify
```

Rule of thumb: refresh **before you lean on the graph**, not on a schedule.

### Choosing a tier

```bash
agent-tools refresh --code-only   # structure only, free, ~1 min
agent-tools refresh               # + docs/images + community naming
agent-tools refresh --deep        # + aggressive inferred edges
```

`refresh` also updates the other graphs you've wired into the repo — it runs
`code-review-graph build` when code-review-graph is wired, and warms the
token-savior daemon when that is wired. A repo with only code-review-graph and
no graphify graph refreshes just code-review-graph: refresh touches only what
you've actually wired, and nothing else.

`--deep` is worth it when you want the graph to connect *concepts* across prose
and code rather than just structure. It is the most expensive thing here: its
cache namespace is separate, so the first deep run re-reads every document.
Above roughly a hundred docs, prefer `scripts/graphify-full-run.sh`, which runs
detached with retry-on-rate-limit and cleans up after itself.

An unrecognised flag is rejected outright — a typo must never start an
hours-long LLM job by falling through to the default.
