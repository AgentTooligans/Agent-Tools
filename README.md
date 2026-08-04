# agent-tools

Set up a **coding agent's whole context stack** — a codebase knowledge graph,
persistent memory, and output compression — on any project, correctly, on any
platform.

One command sets up a computer. One sets up a project. One keeps it fresh.

```bash
./install.sh                              # put agent-tools on your PATH

agent-tools install-machine               # once per computer
cd ~/code/anything && agent-tools init    # once per project
agent-tools refresh                       # after a batch of work
agent-tools tools                         # every tool: installed? wired? overlapping?
agent-tools update all                    # upgrade everything you have
agent-tools doctor                        # what's wrong (safe — changes nothing)
agent-tools help                          # the reasoning behind every default
```

`agent-tools` is a **single self-contained bash script**. No dependencies beyond
bash, python, and the tools it installs. Copy it anywhere and it works.
PowerShell users get the same commands via `agent-tools.ps1`.

### Find what you need

| I want to… | go to |
|---|---|
| set up a **new computer** | [Install consent](#install-consent) → `agent-tools install-machine` |
| add this to **projects I already have** | [Adding it to existing projects](#adding-it-to-existing-projects) |
| **install / remove one tool** | [Managing the tools](#managing-the-tools) |
| confine a tool to **one repo** | [Machine-wide, or one project](#machine-wide-or-one-project) |
| **upgrade** anything | [Updating](#updating) |
| know **which tool to use** when two overlap | [docs/TOOLS.md](docs/TOOLS.md) |
| **move to another computer** | [Moving to another computer](#moving-to-another-computer) |
| understand **why a default is what it is** | [docs/WHY.md](docs/WHY.md) |

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
`--user` on Linux/WSL), and four tools that each cut a different part of the
bill:

| tool | cuts | skip with |
|---|---|---|
| **graphify** | what the agent must **read** to find things | — |
| **memory** | what it must **re-derive** from past sessions | `--memory=none` |
| **caveman** | what it **says back** | `--no-caveman` |
| **rtk** | what shell commands **return** (`git status`, test runs) | `--no-rtk` |
| **context-mode** | re-reading everything **after a compaction** | `--no-context-mode` |
| **superpowers** | doing the work the long way round | `--no-superpowers` |

They stack because they cut different text — that is the whole point, and
[docs/TOOLS.md](docs/TOOLS.md) is the map of which tool owns which row.

Two more are **installed only if you ask**, because they duplicate graphify and
each other:

```bash
agent-tools install code-review-graph    # second code graph, 30 MCP tools
agent-tools install token-savior         # third code graph + its own memory
```

An MCP server's tool schema is re-sent **every session whether or not you call
it**. Three code graphs wired at once spends, every session, exactly the budget
a graph is supposed to save — so `doctor` counts them and complains.

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
| `agent-tools migrate export` / `import` | move memory, keys and `~/.claude` to another computer | no | seconds |
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

## Adding it to existing projects

Most of the stack is **machine-wide** and reaches every repo you already have
the moment it is installed. Only the graph is per-project.

| tool | scope | what an existing project needs |
|---|---|---|
| rtk | machine (a hook in `~/.claude/settings.json`) | **nothing** |
| caveman | machine (skills) | **nothing** |
| superpowers | machine (plugin, user scope) | **nothing** |
| context-mode | machine (plugin, user scope) | **nothing** |
| memory backend | machine (one store, all projects) | **nothing** |
| **graphify** | **per project** | `agent-tools init` |
| code-review-graph / token-savior | binary machine-wide, index per project | `agent-tools wire <name>` |

So, for a repo you already work in:

```bash
agent-tools install-machine        # once. Idempotent — adds only what's missing.

cd ~/code/existing-project
agent-tools init                   # .gitignore, git hooks, MCP, first graph (~1 min, no LLM)
agent-tools doctor                 # confirm, and see what this repo is missing
```

`init` is **safe to re-run**. It reports "already configured" for anything it
finds in place and only adds what is absent — which is also how you pick up new
git hooks or instruction-block changes after `agent-tools update self`.

For a lot of repos at once:

```bash
for d in ~/code/*/; do
  ( cd "$d" && git rev-parse --git-dir >/dev/null 2>&1 && agent-tools init )
done
```

**Optional, per repo** — only where you want them (read
[docs/TOOLS.md](docs/TOOLS.md) first, they overlap graphify):

```bash
agent-tools install code-review-graph     # once per machine
cd ~/code/big-monorepo
agent-tools wire code-review-graph        # this repo only; also builds its graph
agent-tools unwire code-review-graph      # take it back out
```

**Opting one repo *out* of a machine-wide tool is not possible**, and it is
worth being blunt about why: Claude Code **merges** user and project settings
additively. A project file can add a hook; it cannot cancel one your
`~/.claude/settings.json` already declares. There is no negation.

So if you want rtk (or a plugin) in *some* repos only, decide that at install
time and never install it machine-wide:

```bash
agent-tools install-machine --no-rtk      # keep it out of ~/.claude/settings.json
cd ~/code/repo-that-wants-it
agent-tools install rtk --project         # hook lands in THIS repo's settings
```

`agent-tools uninstall rtk --project` removes the project entry and leaves the
binary — useful for undoing the line above, but it will **not** override a
machine-wide hook, and `agent-tools` says so if you try it.

Nothing you add per project is committed unless you choose to: `init` writes
`.gitignore` rules and `.claude/settings.json`, and the graph output is ignored
apart from the expensive LLM cache.

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

## Managing the tools

```bash
agent-tools tools                      # what you have, what is wired, what overlaps
agent-tools install <name>             # rtk | superpowers | context-mode | caveman
                                       # | code-review-graph | token-savior
                                       # | defaults | all
agent-tools uninstall <name>
agent-tools wire <name>                # add a graph's MCP to THIS repo
agent-tools unwire <name>              # take it back out
```

Aliases work where you'd expect them to: `crg`, `ts`, `ctx`, `superpower`.

### Machine-wide, or one project

```bash
agent-tools install rtk                # hook in ~/.claude/settings.json
agent-tools install rtk --project      # hook in <repo>/.claude/settings.json only
agent-tools install all --project      # everything, this repo only
```

**The binaries are still shared** — brew, uv and npm have no per-project form.
`--project` changes where the *activation* lands: the hook, the plugin scope,
the MCP entry. So `agent-tools uninstall rtk --project` opts one repo out and
leaves every other repo alone.

### Updating

```bash
agent-tools update all         # graphify + memory + every installed tool + self
agent-tools update tools       # only the optional tools
agent-tools update graphify    # just one — same for rtk, caveman, crg, ts, ...
```

`update` never installs something you don't already have. Each component has
its own footgun (graphify loses its extras, token-savior loses vector recall,
the memory service keeps running the old binary until restarted) — that is why
there is one command instead of a list of incantations you must remember.
Details: [docs/UPDATING.md](docs/UPDATING.md).

### About rtk specifically

Two sharp edges, both handled:

- **There are two different `rtk`s.** crates.io ships an unrelated "Rust Type
  Kit" under the same binary name. `rtk --version` succeeds for both, so it is
  not a test; `rtk gain` only exists on the right one, and that is what
  `doctor` checks.
- **`rtk init -g` prompts, and answers "no" for you when it can't see a
  terminal** — it prints a manual step and exits 0. Driven from a script it
  reports success and installs nothing. `agent-tools` writes the hook entry
  itself, idempotently, and can remove it again without touching the rest of
  your settings.

---

## Platforms

| platform | support | verified |
|---|---|---|
| macOS | full (launchd) | ✅ |
| Linux | full (systemd --user) | ✅ Ubuntu 24.04 |
| WSL2 | full (systemd --user) | ✅ Win 11 + Ubuntu 26.04 & 24.04 |
| Windows native | everything **except agentmemory**; rtk needs cargo or a release zip | ✅ Win 11 + Git Bash |

Native Windows is limited by **agentmemory upstream**, not by this tool: it
ships no PowerShell/scoop/winget installer for its engine, and
`agentmemory connect` is unsupported there. Upstream's advice is WSL2, and so is
ours. rtk is the only other gap: its `install.sh` doesn't cover native Windows,
so `agent-tools` builds it with `cargo install --git` when Rust is present — a
route that also sidesteps the crates.io name collision — and otherwise points
you at the release zip. Everything else (graphify, code-review-graph,
token-savior via uv; superpowers and context-mode via the Claude plugin system)
is platform-agnostic. Details and the WSL interop trap:
[docs/PLATFORMS.md](docs/PLATFORMS.md).

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

## Moving to another computer

```bash
agent-tools migrate export ~/move.tgz     # old machine
agent-tools migrate import ~/move.tgz     # new machine
agent-tools install-machine               # binaries + plugins back
agent-tools tools                         # confirm
```

`export` carries the things that **cannot be reinstalled**: your memory store,
every session transcript, `~/.claude/CLAUDE.md` *and every file it `@`-imports*,
context-mode's sessions, token-savior's store, rtk's savings history, and your
saved plans. It skips ~800 MB of caches, venvs and plugin binaries, which
`install-machine` rebuilds correctly.

It stops the memory worker at both ends first — copying a live SQLite store
gets you a torn one — and `import` **keeps** existing files unless you pass
`--force`, so a fresh install's empty store is never silently replaced.

Per-repo state is not in the archive; run `agent-tools init` in each project on
the new machine. Full path-by-path breakdown, including key rotation:
[docs/MIGRATION.md](docs/MIGRATION.md).

---

## Keeping CLAUDE.md lean

`init` writes a rule telling the agent that `CLAUDE.md` / `AGENTS.md` is for
build, test and lint commands and hard constraints — not session logs, status
updates or narrative history, which belong in memory or `docs/`.

`doctor` measures the file and warns past ~200 lines / 10 KB, and flags any line
over 2,000 characters as a likely pasted log. **It never edits your file.**

## Documentation

| doc | what's in it |
|---|---|
| [docs/TOOLS.md](docs/TOOLS.md) | **every tool, what each is best at, and which one to keep when two overlap** |
| [docs/MEMORY.md](docs/MEMORY.md) | choosing, switching and converting between memory backends |
| [docs/USAGE.md](docs/USAGE.md) | when each tool earns its keep, what graphify is **bad** at, telling agents to use them, stale-graph behavior |
| [docs/SERVICES.md](docs/SERVICES.md) | startup, restarts, reboots — including the WSL-after-Windows-restart gap |
| [docs/UPDATING.md](docs/UPDATING.md) | `agent-tools update`, per-component upgrade steps, and why upgrading graphify can cost hours |
| [docs/CAVEMAN.md](docs/CAVEMAN.md) | the output-compression skill: why it is default, its levels, and the nuance it costs |
| [docs/AGENTS.md](docs/AGENTS.md) | Codex, Cursor, Gemini CLI, Copilot and friends |
| [docs/MIGRATION.md](docs/MIGRATION.md) | moving to another computer: every out-of-repo path, what to copy vs reinstall, and rotating API keys |
| [docs/PLATFORMS.md](docs/PLATFORMS.md) | support matrix, verification status, WSL traps |
| [docs/GRAPH-HYGIENE.md](docs/GRAPH-HYGIENE.md) | keeping a graph honest: the graph is flat in time, so scope + status banners are the only levers; duplicate/oversize/stale failure modes |
| [docs/WHY.md](docs/WHY.md) | the incident record behind every default |
| [docs/session-notes/](docs/session-notes/) | working records of each build session — what was decided and why |

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
