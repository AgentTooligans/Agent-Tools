# Other AI agents (including Codex)

Both tools are agent-agnostic. `agent-tools` wires Claude Code by default
because that is what it was built against, but nothing is Claude-specific.

---

## claude-mem

Also multi-agent, despite the name. Its package ships adapters for
`claude-code`, `codex`, `cursor`, `copilot`, `gemini`, `windsurf`, `warp`,
`opencode`, `openclaw` and `antigravity`, and includes a `.codex-plugin`. Its
own tagline is *"Persistent Context Across Sessions for Every Agent"*.

`npx claude-mem install` detects installed agents and wires them itself, so
there is usually nothing to do per agent.

## agentmemory

It speaks **MCP** and has a `connect` command with adapters for a long list of
hosts:

```bash
agentmemory connect codex          # OpenAI Codex CLI
agentmemory connect cursor
agentmemory connect copilot-cli
agentmemory connect gemini-cli
agentmemory connect antigravity    # replaces Gemini CLI (sunset 2026-06-18)
agentmemory connect opencode
agentmemory connect zed
agentmemory connect continue
agentmemory connect cline
agentmemory connect kiro
agentmemory connect warp
agentmemory connect hermes
agentmemory connect droid
agentmemory connect qwen
agentmemory connect openclaw
agentmemory connect --all          # every detected agent
agentmemory connect --dry-run      # show what would change
```

`connect` merges the memory server into that host's MCP config and preserves
any servers already there.

Two caveats:

- **Codex:** hooks ship via the Codex plugin. On Codex Desktop also pass
  `--with-hooks` to install the global `hooks.json` workaround.
- **Native Windows:** `connect` is unsupported except for `copilot-cli`, which
  is Windows-safe. Everything else needs WSL2.

`connect` makes the *tools* available. The *skills* — which teach an agent when
to recall and when to save — install separately:

```bash
npx skills add rohitg00/agentmemory -y
```

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
# memory
agentmemory connect codex

# graph — MCP
#   add graphify-mcp to Codex's MCP config, or:
graphify install --platform codex        # gives Codex the CLI skill
```

Then confirm the host lists the tools. For agentmemory, seeing only 7–8 tools
when you expected more usually means the MCP shim could not reach the server —
check `curl localhost:3111/agentmemory/health`. (Seeing exactly 8 is expected if
the server runs with `--tools core`, which is the default `agent-tools` sets.)

---

## What `agent-tools init` does and doesn't do

It wires **Claude Code** (`claude mcp add ... -s local`) because that is what it
can verify. For any other host, run the `connect` / `install` commands above —
they are one-liners, and both tools are already installed and running.

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
