# Using graphify and agentmemory well

Two tools, two different jobs. Knowing which answers a given question is most of
the skill.

| | **graphify** | **agentmemory** |
|---|---|---|
| answers | "what *is* this code, and what connects to what" | "what did we *do*, and why" |
| source | your repo, parsed | your past sessions |
| lives | `graphify-out/` in the project | one server, all projects |
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

**3. agentmemory's skills.** `npx skills add rohitg00/agentmemory` installs
skills that teach an agent *when* to recall and save. `connect` makes the tools
available; skills teach the judgment.

**4. Project instructions (strongest).** Put it in the file your agent already
reads — `AGENTS.md`, or `CLAUDE.md` for Claude Code. `agent-tools init` offers
to add a short section for you. Something like:

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

`--deep` is worth it when you want the graph to connect *concepts* across prose
and code rather than just structure. It is the most expensive thing here: its
cache namespace is separate, so the first deep run re-reads every document.
Above roughly a hundred docs, prefer `scripts/graphify-full-run.sh`, which runs
detached with retry-on-rate-limit and cleans up after itself.

An unrecognised flag is rejected outright — a typo must never start an
hours-long LLM job by falling through to the default.
