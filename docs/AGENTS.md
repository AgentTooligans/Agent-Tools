# Using this with other assistants

Agent Tools isn't only for Claude Code. Codex, Antigravity, Cursor, Gemini and
anything else that can run a shell command can use the same graph, the same
memory and the same skills.

The one thing that *is* Claude-Code-specific is MCP, and it turns out you don't
need it. This page explains why, and how each assistant gets at the tools.

> **You do not need MCP for any of this.** Every graph tool here ships a CLI,
> and the CLI is the cheaper interface: an MCP server re-sends its whole tool
> schema **every session whether you call it or not** (graphify ~1.5k tokens,
> code-review-graph 30 tools), while a CLI costs **zero** until the agent runs
> it. Any agent that can run a shell command can use these tools.
>
> ```bash
> agent-tools agents          # which agents are here, and how each gets the tools
> agent-tools init            # DEFAULT: no server wired at all
> agent-tools init --add-mcp  # opt THIS repo in to graphify's server
> agent-tools unwire graphify # take the server back out of a repo
> ```

## Two different questions: which assistant, and which model

These get confused constantly, so plainly:

* **Your assistant** (Claude Code, Codex, Antigravity, Cursor…) *uses* the
  graph. Any of them can, via the CLI or a skill.
* **A model** *builds* the graph's semantic layer. That is a separate thing,
  and your assistant's subscription usually can't drive it.

**Does graphify work with Codex?** Yes for using it — `graphify install
--platform codex` gives Codex the skill, and the CLI works there like anywhere
else. **No** for building it: there is no `codex` backend. graphify's list is
`claude, claude-cli, gemini, openai, deepseek, kimi, ollama, azure, bedrock`.
A ChatGPT subscription cannot drive it, and neither can Antigravity.

In practice this rarely bites, because a Codex user usually has an
`OPENAI_API_KEY`, which the `openai` backend uses directly.

### What happens if you have no usable model

`agent-tools refresh` checks before it starts, and stops with instructions:

```
✗ no LLM backend available for the semantic pass

  The graph's STRUCTURE needs no model at all. This works right now:
        agent-tools refresh --code-only
```

`--code-only` is a full structural graph — every function, class, import and
call — built by local AST parsing. No model, no key, no cost. Only doc
understanding and readable community names need the semantic pass.

### The four failure modes, and what each looks like

All of these were reproduced against a real graphify, not guessed:

| situation | what happens |
|---|---|
| no CLI, no key, no ollama | refuses before starting, names your options, exits 1 |
| `AGENT_TOOLS_BACKEND=openai` but no `OPENAI_API_KEY` | refuses before starting: *"backend 'openai' was requested, but OPENAI_API_KEY is not set"* |
| a key that is set but **invalid** | graphify tries, gets a 401, and **refuses to write a partial graph**. Your existing graph is untouched. We then point you at `--code-only` |
| no docs in the repo at all | nothing to do semantically — the pass is a no-op and the run succeeds |

That third row is the important one. A half-written graph is worse than no
graph, because it looks fine and answers wrongly. graphify gets this right on
its own; we just explain it.

## MCP vs CLI: what is actually different

The most common confusion, so plainly:

**Installing a tool installs BOTH interfaces.** They are not separate products.

```
uv tool install "graphifyy[gemini,mcp]"
   ├── graphify        <- the CLI
   └── graphify-mcp    <- the MCP server
```

One package, two entry points, **the same code reading the same
`graphify-out/graph.json`**. `code-review-graph mcp` is that same binary's `mcp`
subcommand. `token-savior` in server mode is the same binary as `ts`.

So there is no "install the MCP version" step. It is already on disk. Wiring
only tells Claude Code to *launch* it:

```bash
agent-tools init               # DEFAULT since 3.4.0: no server at all
agent-tools init --add-mcp     # opt this repo in
agent-tools wire graphify      # or add one later
agent-tools unwire graphify    # stop; the CLI is unaffected
```

**Re-running `init` never removes a server you added.** It is an idempotent
maintenance command, run routinely to pick up new hooks, so it reports an
existing server and leaves it:

```
  ✓ graphify MCP already wired here — left as-is
        remove it with:  agent-tools unwire graphify
```

Both directions work at any time, on any repo, including one set up with
`init` (which wires nothing by default). Nothing is reinstalled either way.

### So what DOES differ?

Not capability. Not the answers. **Discoverability.**

| | MCP server | CLI |
|---|---|---|
| does the agent know it exists? | yes — its schema is in context automatically | only if something tells it |
| cost per session | the full schema, whether called or not | **zero** until the agent runs it |
| works in Codex / Antigravity / Cursor | no | yes |
| same graph, same answers | yes | yes |
| needs the graph built first | yes | yes |

An MCP server advertises itself. A CLI has to be taught — and the instruction
block `agent-tools init` writes into `AGENTS.md` is exactly that teaching, at
roughly **40 tokens instead of ~1,500**.

### Which to choose

* **Wire it** when you query that tool constantly and want the agent reaching
  for it unprompted.
* **Leave it CLI** for everything else — especially a second or third code
  graph, where you are paying a full schema every session for a tool you query
  occasionally.
* **Always CLI** for Codex, Antigravity and every other host, which cannot read
  Claude Code's MCP config at all.

This is why `doctor` complains when three code-graph servers are wired in one
repo: three schemas, every session, to answer questions you ask one of them.

Mixing is normal and per repo:

```bash
agent-tools wire graphify              # this one earns its schema
agent-tools unwire code-review-graph   # this one does not; CLI still works
agent-tools unwire token-savior
```

## The four delivery mechanisms

Nothing here is Claude-Code-specific except the optional MCP wiring.

| mechanism | reaches | cost per session |
|---|---|---|
| **skills** (`~/.agents/skills`) | every agent — symlinked into each one's skills dir | one description line each |
| **CLI** (`graphify`, `ts`, `code-review-graph`, `rtk`) | every agent that can run a shell | **zero** until called |
| **hooks** | whichever hosts support them | zero |
| **MCP** *(optional)* | Claude Code only | the full schema, every session |

### The CLI surface

These are the commands to put in an agent's instruction file. `agent-tools
init` already writes exactly this block into `AGENTS.md` — the cross-agent
standard file, which Codex and the others read:

```bash
graphify query "<question>"        # scoped subgraph instead of grepping
graphify affected "<symbol>"       # blast radius before a refactor
graphify god-nodes                 # what is risky to touch
graphify path "<A>" "<B>"          # how two things connect
graphify explain "<concept>"

code-review-graph query|impact|search|architecture|flows
ts get|search|ctx|structure        # token-savior
rtk <any command>                  # filtered output
```

The block `init` writes contains **no `mcp__` tool names** by design — it is
host-neutral, so the same file works in Claude Code, Codex and Antigravity
without editing.

**The block is generated from what's wired in the repo.** graphify's section is
always there; a `code-review-graph` section and a `token-savior` section appear
only when each is wired here. `agent-tools wire code-review-graph` adds its
lines, `unwire` removes them, and `agent-tools init` rewrites the block to match
the current wiring — so an agent is told to use exactly the tools that are
actually available, and never a tool you removed.

Claude Code is the one host that reads `CLAUDE.md` rather than `AGENTS.md`, so
`init` also writes a one-line `CLAUDE.md` containing `@AGENTS.md` — a native
import. `AGENTS.md` stays the single source of truth; Claude picks it up through
that import with nothing duplicated. `agent-tools doctor` verifies the import is
present (and warns if a repo has the block in `AGENTS.md` but no `CLAUDE.md`
importing it, which would leave Claude Code unaware of it).

### Giving an agent the graphify skill

`graphify install --platform <name>` copies its skill into that host's config
directory. No server, no schema cost. Supported platforms as of 0.9.48:

```
claude  codex  opencode  aider  amp  agents  cursor  antigravity  gemini
kiro  pi  devin  droid  trae  claw  codebuddy  hermes  windows
```

```bash
graphify install --platform codex
graphify install --platform antigravity
```

`agent-tools agents` detects which of these are installed and prints the exact
command for each. `graphify uninstall` removes it from every detected platform
at once.

### Antigravity (`agy`) specifically

Antigravity replaces the Gemini **CLI**, not the Gemini **API**. Two
consequences that matter here:

* graphify's `gemini` LLM backend still works — it calls
  `generativelanguage.googleapis.com`, which Antigravity does not touch.
* There is **no `codex` or `antigravity` LLM backend** in graphify. Its backend
  list is `claude, claude-cli, gemini, openai, kimi, ollama`. So those hosts
  *consume* the graph; they do not *build* it. Build it once with any backend
  (or `--code-only`, which needs no LLM at all), and every agent reads the
  same `graphify-out/`.


Every tool here is agent-agnostic. `agent-tools` wires Claude Code by default
because that is what it was built against, but nothing is Claude-specific.

| tool | other agents it supports natively |
|---|---|
| graphify | MCP — any MCP host |
| claude-mem | its own adapters (below) |
| caveman | `npx skills add … -g` installs to `~/.agents/skills`, symlinked into every agent |
| **pocock** | same mechanism as caveman — global `~/.agents/skills`, all agents |
| **rtk** | `rtk init --agent cursor\|windsurf\|cline\|kilocode\|antigravity\|kimi\|pi\|hermes\|droid`, plus `--gemini` and `--opencode` |
| **context-mode** | Gemini CLI, VS Code / JetBrains Copilot, Copilot CLI, Cursor, OpenCode, KiloCode, Codex, Antigravity, Kimi, Qwen, Zed, Kiro, OMP — via `npm install -g context-mode` |
| **code-review-graph** | `code-review-graph install --platform <cursor\|windsurf\|gemini-cli\|zed\|…>` |
| **token-savior** | any MCP client |

`agent-tools` wires the Claude Code side of each. For a second agent, run that
tool's own command from the table — they are all idempotent, and none of them
conflicts with what `agent-tools` wrote.

---

## claude-mem

Also multi-agent, despite the name. Its package ships adapters for
`claude-code`, `codex`, `cursor`, `copilot`, `gemini`, `windsurf`, `warp`,
`opencode`, `openclaw` and `antigravity`, and includes a `.codex-plugin`. Its
own tagline is *"Persistent Context Across Sessions for Every Agent"*.

`npx claude-mem install` detects installed agents and wires them itself, so
there is usually nothing to do per agent.

## The skill packs (caveman, pocock)

These install **globally**, into `~/.agents/skills`, and the `skills` CLI
symlinks them into every agent's own skills directory it can find — Codex,
Copilot, Cline, Cursor, Zed and dozens more. There is nothing per-agent to run.

```bash
agent-tools install caveman
agent-tools install pocock
npx skills list -g                 # confirm what landed
```

Two agents reject global scope by design (Eve, PromptScript). That is their
limitation, not a failure worth chasing.

`pocock` gives every agent `/grill-me`, `/handoff` and `/wait-what` — see
[SKILLS.md](SKILLS.md). `/handoff` is worth calling out here specifically: it
writes a handoff document to your OS temp directory, which is the practical way
to move work **between** two different agents rather than between two sessions
of the same one.

## agentmemory (removed in 3.3.0)

`agent-tools` no longer installs or wires agentmemory. If you still run one, its
own `agentmemory connect <agent>` command continues to work — that is upstream's
tool, unaffected by anything here.

To retire it and move the data into claude-mem:

```bash
agent-tools memory migrate-from-agentmemory
```

That removes the Claude Code plugin and MCP entry. **Adapters `connect` wrote
into other hosts' MCP configs are not touched** — agent-tools did not write
them and will not guess at them. Remove those yourself, or leave them pointing
at a stopped server. See [MEMORY.md](MEMORY.md).

---

## graphify

Two independent routes.

**1. MCP server** — works with any MCP client:

```bash
graphify-mcp                      # stdio (what agent-tools wires)
graphify-mcp --transport http --port 8080   # HTTP, for remote/shared use
```

Ten tools: `query_graph`, `get_node`, `get_neighbors`, `get_community`,
`god_nodes`, `graph_stats`, `shortest_path`, `list_prs`, `get_pr_impact`,
`triage_prs`. About 1,522 tokens of schema per session.

**2. Skill install** — copies graphify's own skill into a platform's config
directory so the agent knows the commands:

```bash
graphify install --platform codex
graphify install --platform cursor
graphify install --platform gemini
graphify install --platform antigravity
graphify install --platform aider
graphify install --platform opencode
graphify install --platform amp
graphify install --platform droid
graphify install --platform kiro
graphify install --platform trae
graphify install --platform devin
graphify install --platform claude       # the default
```

`graphify uninstall` removes it from every detected platform at once.

---

## Wiring Codex specifically

```bash
# memory — claude-mem ships a .codex-plugin and wires Codex itself
npx claude-mem install

# skills — global, so Codex picks them up with no per-agent step
agent-tools install pocock
agent-tools install caveman

# graph — MCP
#   add graphify-mcp to Codex's MCP config, or:
graphify install --platform codex        # gives Codex the CLI skill
```

Then confirm the host lists the tools and the skills. `npx skills list -g`
shows what is installed globally; if Codex does not see them, check that
`~/.codex/skills` (or its equivalent) contains the symlinks the CLI created.

---

## What `agent-tools init` does and doesn't do

It wires **Claude Code** (`claude mcp add ... -s local`) because that is what it
can verify. For any other host, run the `connect` / `install` commands above —
they are one-liners, and both tools are already installed and running.

It writes the instruction block into `AGENTS.md` (or into `CLAUDE.md` if that
already exists), and when the block lands in `AGENTS.md` it also creates a
one-line `CLAUDE.md` that `@`-imports it — otherwise Claude Code, which reads
`CLAUDE.md` and not `AGENTS.md`, would never see the block. Re-running `init` is
idempotent: it adds the import if missing and leaves it alone otherwise.

### Why it does not call `graphify claude install` or `graphify hook install`

Both commands exist and both do something real. `init` deliberately writes its
own equivalents instead, for reasons worth knowing before you "simplify" this:

**`graphify claude install`** — writes a `## graphify` section to CLAUDE.md plus
the PreToolUse hook-guard. `init` writes the same hook (identical
`graphify hook-guard` commands, in the portable bare form) inside a managed block
that *also* covers memory and the keep-this-file-lean rule. Running both leaves
CLAUDE.md saying the same thing twice — in the very file we ask to keep lean.
`doctor` now flags that; the fix is `graphify claude uninstall`, which drops its
section while `init` restores the hook.

**`graphify hook install`** — installs post-commit and post-checkout git hooks
that rebuild the code graph (AST only, no LLM) in a detached process. Genuinely
useful, and `init` now installs both. It is not delegated because that command
also **writes `.gitattributes`** — a *committed* file — registering
`graphify-out/graph.json merge=graphify`, where the driver itself is defined only
in the local `.git/config` by absolute path. Commit that and every teammate
inherits an attribute pointing at a merge driver they do not have.

Two other differences in our copies:

- **Opt-in, fail-closed.** Both hooks exit unless
  `.git/graphify-auto-update-ENABLED` exists. graphify's fire unconditionally.
  This started as opt-out, the sentinel vanished, and the hook silently
  re-enabled itself — hence the inversion.
- **The concurrency skip is logged.** Both hooks skip when another graphify run
  is in flight. That guard is global, not repo-scoped (reading another process's
  cwd needs `/proc` or `lsof`), so a long run in one repo suppresses rebuilds
  everywhere. It writes "skipped: another graphify run is in flight" to
  `.git/graphify-auto-update.log` rather than doing nothing quietly.

To use graphify's versions instead, run `graphify hook install` and then decide
what to do about the `.gitattributes` line it leaves in your working tree.

The graph itself is host-neutral: `graphify-out/` is just files. Any number of
agents can read the same graph, and the memory server serves all of them from
one place on port 3111.
