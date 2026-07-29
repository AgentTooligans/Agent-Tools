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
and pins), agentmemory, and a supervised memory server — launchd on macOS,
systemd `--user` on Linux/WSL.

**Per project** (`init`):

| | |
|---|---|
| `.gitignore` rules | ignore the generated graph, **keep** the expensive LLM cache |
| `.claude/settings.json` | hook-guard nudging the agent to query the graph before grepping |
| `.git/hooks/post-commit` | auto-refresh the code graph — **installed disabled** |
| MCP servers (project scope) | 18 tools: 10 graph, 8 memory |
| initial code graph | AST only — no LLM, no cost |

Docs are deliberately **not** indexed by `init`, because that pass costs tokens.
Run `agent-tools refresh` when you want them.

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
| WSL2 | full (systemd --user) | ✅ Win 11 + Ubuntu 26.04 |
| Windows native | **graphify only** | ⚠️ not yet verified |

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

To auto-refresh the code graph on every commit:

```bash
touch .git/graphify-auto-update-ENABLED    # enable
rm    .git/graphify-auto-update-ENABLED    # disable (the default)
```

---

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
