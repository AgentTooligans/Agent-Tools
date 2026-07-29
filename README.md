# agent-tools

Set up **graphify** (codebase knowledge graph) and **agentmemory** (persistent
memory for coding agents) on any project, correctly, on any platform.

One command sets up a computer. One sets up a project. One keeps it fresh.

```bash
./install.sh                              # put agent-tools on your PATH

agent-tools install-machine               # once per computer
cd ~/code/anything && agent-tools init    # once per project
agent-tools refresh                       # after a batch of work
agent-tools doctor                        # what's wrong (safe — changes nothing)
agent-tools help                          # the reasoning behind every default
```

`agent-tools` is a **single self-contained bash script**. No dependencies beyond
bash, python, and the tools it installs. Copy it anywhere and it works.
PowerShell users get the same commands via `agent-tools.ps1`.

---

## Why this exists

graphify and agentmemory are both excellent and both have sharp edges that are
invisible until they cost you something. This tool encodes the edges.

A few of the defaults it enforces, each learned the hard way:

- **graphify never sends code to an LLM** — only docs and images. So code updates
  are free, and only doc passes cost tokens.
- **Community labels must be regenerated LAST**, and only via `graphify label`.
  `cluster-only` silently renames every community after its hub node and exits 0.
- **agentmemory's store path is relative to the working directory.** Start the
  server from the wrong place and you silently get a new, empty memory.
- **agentmemory's `--tools core` only works as a server argument** — the
  environment variable and `.env` are both ignored. It's the difference between
  53 MCP tools (~5,918 tokens of schema per session) and 8 (~995).
- **graphify's MCP server needs `mcp<2` pinned**, or it fails with a message
  saying the package isn't installed when it is.

Full incident record with the evidence: [docs/WHY.md](docs/WHY.md).

---

## What it configures

**Per computer** (`install-machine`): node, uv, graphify (with the right extras
and pins), your memory backend and its service (launchd on macOS, systemd
`--user` on Linux/WSL), and **caveman** — a skill that cuts output tokens by
telling the agent to drop filler. Skip it with `--no-caveman`.

The three cover different halves of the same bill: graphify cuts what the agent
must *read*, memory cuts what it must *re-derive*, caveman cuts what it *says
back*. See [docs/CAVEMAN.md](docs/CAVEMAN.md) for what it costs you in nuance.

`init` also offers to add a short section to your `AGENTS.md` / `CLAUDE.md`
telling the agent to query the graph before grepping — MCP tools alone are
passive, and the instruction file is what an agent actually reads every session.

**Per project** (`init`):

| | |
|---|---|
| `.gitignore` rules | ignore the generated graph, **keep** the expensive LLM cache |
| `.claude/settings.json` | hook-guard nudging the agent to query the graph before grepping |
| `.git/hooks/post-commit` | auto-refresh the code graph — **installed disabled** |
| MCP servers (project scope) | graphify (10 tools, ~1.5k tokens); the memory backend wires its own |
| initial code graph | AST only — no LLM, no cost |

Docs are deliberately **not** indexed by `init`, because that pass costs tokens.
`init` gets you a working graph in a minute; the semantic read is a deliberate
second step.

### The three tiers

| command | scans | LLM? | time |
|---|---|---|---|
| `agent-tools init` | code only (AST) | no | ~1 min |
| `agent-tools refresh` | code + **docs + images**, then names the communities | yes | minutes → hours |
| `agent-tools refresh --deep` | same, plus aggressive inferred edges | yes | hours on a big corpus |

**Do not run a standard refresh "first" before `--deep`.** `--deep` already does
everything `refresh` does, and it uses a **separate cache namespace** — so a
standard pass beforehand doesn't warm it, and you pay for the doc extraction
twice. If you want deep, go straight to deep. For a corpus large enough
to run for hours, use `scripts/graphify-full-run.sh` instead — it detaches,
retries on rate limits, and terminates itself.

Only docs and images ever cost tokens; code is always AST. And it is
incremental — after the first pass you pay only for docs you actually edited.

---

## Install consent

Nothing is installed without your say-so:

```bash
agent-tools install-machine              # asks before each install
agent-tools install-machine --yes        # unattended (CI)
agent-tools install-machine --no-install # report only
```

When run non-interactively without `--yes` it **skips and tells you** rather
than hanging on a prompt nobody can answer.

---

## Platforms

| platform | support | verified |
|---|---|---|
| macOS | full (launchd) | ✅ |
| Linux | full (systemd --user) | ✅ Ubuntu 24.04 |
| WSL2 | full (systemd --user) | ✅ Win 11 + Ubuntu 26.04 & 24.04 |
| Windows native | **graphify only** | ✅ Win 11 + Git Bash |

Native Windows is limited by **agentmemory upstream**, not by this tool: it
ships no PowerShell/scoop/winget installer for its engine, and
`agentmemory connect` is unsupported there. Upstream's advice is WSL2, and so is
ours. Details and the WSL interop trap: [docs/PLATFORMS.md](docs/PLATFORMS.md).

---

## Day to day

```bash
agent-tools refresh              # code + docs + names, incremental
agent-tools refresh --code-only  # AST only, zero LLM, ~1 min
```

Run it **before you lean on the graph**, not on a schedule. The failure mode
isn't "slightly behind" — it's a stale graph confidently answering with code
that no longer exists.

A refresh is **free when nothing changed**: unchanged files come from a
content-keyed cache. You only pay for docs you actually edited.

### Long runs

```bash
agent-tools refresh --deep --detach   # survives closing the terminal
agent-tools status                    # running? how far along?
agent-tools stop                      # stop THIS repo's run (others untouched)
```

When a detached run finishes it **exits by itself** — no daemon, nothing to
kill. Its log stays at `.git/graphify-refresh.log`.

Detach uses the best mechanism available: a `systemd-run --user` transient unit
on Linux/WSL (self-cleaning), `caffeinate` + `nohup` on macOS so idle sleep
can't pause a long run, and plain `nohup` elsewhere.

**How long does a refresh take?** It depends entirely on **uncached docs**, not
repo size — code is always free. Roughly 17 docs per LLM chunk and ~5 minutes
per chunk on the serial `claude-cli` backend, so ~400 cold documents is ~2
hours. A repo whose docs are already cached finishes in seconds. `status` shows
chunk progress while it runs.

To auto-refresh the code graph on every commit:

```bash
touch .git/graphify-auto-update-ENABLED    # enable
rm    .git/graphify-auto-update-ENABLED    # disable (the default)
```

---

## Memory backend — you choose

Two tools do this job well, and they must not both be active: each hooks the
session lifecycle, so running both means double capture and double per-tool-call
overhead.

| | **claude-mem** (default) | **agentmemory** |
|---|---|---|
| adoption | ~88.9k stars | ~25.9k stars |
| service | worker on :37701 — start with `npx claude-mem start` (no launchd/systemd unit) | supervised server (launchd/systemd) |
| store | `~/.claude-mem/` (SQLite + Chroma) | follows the server's **working directory** |
| context injection | **automatic at session start** | opt-in (costs tokens) |
| bulk import of past sessions | none — starts from install day | `import-jsonl` |
| export to Markdown | yes (`agent-tools memory export`) | yes (`agent-tools memory export`) |

```bash
agent-tools install-machine --memory=claude-mem    # default
agent-tools install-machine --memory=agentmemory
agent-tools install-machine --memory=none          # graphify only
```

Your choice is remembered in `~/.config/agent-tools/config`.

### Switching backends

```bash
agent-tools memory status                 # which one, what is installed
agent-tools memory export ~/notes         # memories -> portable Markdown
agent-tools memory switch claude-mem      # machine-wide change
```

**Switching is machine-wide, not per-project** — both backends hook at user
scope and keep one global store, so a per-project split would fragment your
history and require both to stay hooked.

**The switch is asymmetric**, and the tool says so rather than pretending:

- **claude-mem → agentmemory**: memories can be POSTed to `/agentmemory/remember`.
- **agentmemory → claude-mem**: claude-mem has *no ingest API*. The switch
  exports your memories to Markdown (the exact record), then converts them by
  synthesising a transcript and feeding claude-mem's own Stop hook, so it
  summarises and embeds them natively. **claude-mem compresses on ingest**, so
  the converted copies are summaries — keep the Markdown as ground truth.

Switching away from agentmemory stops **and disables** its launchd/systemd
service and removes its plugin so the hooks stop firing. **The store is never
deleted**, so you can switch back.

## Obsidian

```bash
agent-tools obsidian ~/Documents/MyVault/agent-tools
agent-tools obsidian ~/vault --graph-only
```

Exports the codebase graph as wiki-linked notes (Obsidian's graph view then
renders your architecture) and your memories as notes with tags and front
matter, plus an index. On demand only — nothing writes to your vault unless you
ask. It is a **snapshot for humans**: agents keep querying `graph.json` and the
live memory store, not the vault.

## Keeping CLAUDE.md lean

`init` writes a rule telling the agent that `CLAUDE.md` / `AGENTS.md` is for
build, test and lint commands and hard constraints — not session logs, status
updates or narrative history, which belong in memory or `docs/`.

`doctor` measures the file and warns past ~200 lines / 10 KB, and flags any line
over 2,000 characters as a likely pasted log. **It never edits your file.**

## Documentation

| doc | what's in it |
|---|---|
| [docs/MEMORY.md](docs/MEMORY.md) | choosing, switching and converting between memory backends |
| [docs/USAGE.md](docs/USAGE.md) | when each tool earns its keep, what graphify is **bad** at, telling agents to use them, stale-graph behavior |
| [docs/SERVICES.md](docs/SERVICES.md) | startup, restarts, reboots — including the WSL-after-Windows-restart gap |
| [docs/UPDATING.md](docs/UPDATING.md) | `agent-tools update`, per-component upgrade steps, and why upgrading graphify can cost hours |
| [docs/CAVEMAN.md](docs/CAVEMAN.md) | the output-compression skill: why it is default, its levels, and the nuance it costs |
| [docs/AGENTS.md](docs/AGENTS.md) | Codex, Cursor, Gemini CLI, Copilot and friends |
| [docs/PLATFORMS.md](docs/PLATFORMS.md) | support matrix, verification status, WSL traps |
| [docs/WHY.md](docs/WHY.md) | the incident record behind every default |

## Extras

`scripts/graphify-full-run.sh` — a detached, resumable full semantic pass for
large doc corpora (launchd/caffeinate on macOS), with retry-on-rate-limit and
self-termination. `scripts/graphify-run-status` reports its progress.

---

## Status

Written 2026-07-28/29. Not an established tool — read
[docs/WHY.md](docs/WHY.md) before trusting it with a machine you care about.
`doctor` and `refresh` only read state or run commands you'd run yourself;
`install-machine` and `init` write files.
