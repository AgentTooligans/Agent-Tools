# Moving to another computer, and managing keys

A checklist. The *why* behind each item is in [WHY.md](WHY.md) §1; this page is
what to actually do.

---

## Part 1 — What travels, what doesn't

**Travels automatically (it's in git):**

| | |
|---|---|
| the Agent-Tools repo | `agent-tools`, `install.sh`, `docs/`, `scripts/` |
| per-project config | `.graphifyignore`, `.gitignore`, the `agent-tools:managed` block in `CLAUDE.md`/`AGENTS.md`, `.claude/settings.json` |
| **the expensive LLM work** | `graphify-out/cache/semantic/` + `cache/semantic-deep/` + `.graphify_labels.json` — **only if committed** |

That last row is the whole payoff: a fresh clone rebuilds its graph at **zero LLM
cost** from the committed cache. Verify before you wipe the old machine:

```bash
git ls-files graphify-out/cache | wc -l      # expect > 0
```

## Everything outside the repo — the actual paths

Nothing below is in any git repo. Sizes are from a real macOS install
(2026-07-29) to show what is worth copying over a network and what is not.

### 🔴 Irreplaceable — copy these or the data is gone

| path | size | what it is |
|---|---|---|
| `~/.claude-mem/` | 11 M | **claude-mem memory store** — SQLite + Chroma vectors. Every summary and observation. |
| `~/.agentmemory/` | 68 M | agentmemory store (if you use that backend). Exclude `bin/iii` — see below. |
| `~/.claude/projects/` | 192 M | **every session transcript.** This is `claude --resume` history *and* the only source a bulk memory re-import could read. |
| `~/.config/graphify/env` | small | API keys. **Prefer rotating over copying** — see Part 4. |

Stop the worker before copying a live store, or you may copy a torn database:

```bash
npx claude-mem stop        # then copy ~/.claude-mem/
```

### 🟡 Small settings — copy them, or let `init` recreate them

| path | what breaks without it |
|---|---|
| `~/.claude.json` (44 K) | **MCP wiring** — graphify tools missing in Claude Code. `agent-tools init` re-adds them. |
| `~/.config/agent-tools/config` | which memory backend is active; reverts to the default. `init` rewrites it. |
| `~/.claude/settings.json` | global Claude Code hooks/settings. |
| `~/.claude/.caveman-active` | caveman level; a fresh install starts at `full`. |
| `~/Library/LaunchAgents/com.agentmemory.server.plist` (macOS)<br>`~/.config/systemd/user/agentmemory.service` (Linux/WSL) | no supervised memory server. `install-machine` recreates it. |

### 🟢 Do NOT copy — reinstall instead

These are large, machine-specific, and rebuilt correctly by `install-machine`:

| path | size | why not |
|---|---|---|
| `~/.local/share/uv/tools/graphifyy/` | 170 M | a venv with absolute paths and a platform-specific interpreter |
| `~/.claude/plugins/` | 580 M | plugin caches; `caveman`/claude-mem reinstall themselves |
| `~/.local/bin/` | — | `install.sh` puts `agent-tools` and the helper scripts back |
| `~/.agents/skills/` | 120 K | recreated by `agent-tools caveman install` |
| `~/.claude/skills/` | — | symlinks into `~/.agents/skills` |
| `~/.agentmemory/bin/iii` | — | a copied engine binary is the **wrong architecture** — delete it and it re-downloads |
| `~/.cache/graphify-rebuild.log`, `*.pid`, `engine-state.json` | — | logs and stale PIDs; stale PIDs can make `stop --force` signal an unrelated process |

**Inside a repo but never cloned:** `.git/hooks/*` — git does not version hooks,
so post-commit/post-checkout must be reinstalled per machine by
`agent-tools init`.

### The one-line version

Copy `~/.claude-mem/`, `~/.claude/projects/`, and `~/.claude.json`. Reinstall
everything else. Rotate the keys rather than copying them.

### The same paths on every platform

`~` above means the user's home directory. Most of these tools resolve it the
same way everywhere (Node's `os.homedir()`, Python's `Path.home()`), so the
layout is identical on macOS, Linux and WSL. Only three things genuinely differ:

| | macOS | Linux / WSL2 | Windows (native) |
|---|---|---|---|
| home | `/Users/<you>` | `/home/<you>` | `C:\Users\<you>` — write paths as `%USERPROFILE%\.claude` |
| service manager | launchd:<br>`~/Library/LaunchAgents/com.agentmemory.server.plist` | systemd user unit:<br>`~/.config/systemd/user/agentmemory.service` | none — Task Scheduler; **agentmemory is unsupported natively, use WSL2** |
| uv tool install | `~/.local/share/uv/tools/` | `~/.local/share/uv/tools/` | `%APPDATA%\uv\tools\` |

Everything else — `~/.claude/`, `~/.claude.json`, `~/.claude-mem/`,
`~/.agentmemory/`, `~/.agents/skills/`, `~/.config/agent-tools/`,
`~/.config/graphify/` — sits in the same place relative to home on all of them.

**WSL2 is its own machine.** Its home is inside the distro
(`\\wsl$\<distro>\home\<you>`), *not* your Windows profile. Moving between
Windows and WSL is a machine move, not a copy — and keep repos on the Linux
filesystem, never `/mnt/c/...`, or you inherit the interop traps described in
[PLATFORMS.md](PLATFORMS.md).

**Three environment variables relocate these paths**, so check them before
concluding a directory is missing:

| variable | moves |
|---|---|
| `CLAUDE_CONFIG_DIR` | `~/.claude` (transcripts, plugins, settings) — `agent-tools` honors it throughout |
| `CLAUDE_MEM_DATA_DIR` | `~/.claude-mem` (the memory store) |
| `XDG_CONFIG_HOME` | `~/.config` on Linux, hence `agent-tools` and `graphify` config |

agentmemory is the exception with a trap of its own: its store location is
decided by the **server's working directory**, not by `AGENTMEMORY_DATA_DIR`
(documented but inert). See [WHY.md](WHY.md) §3.

### Sizes are indicative, not fixed

The figures above came from one real install. Check your own before copying:

```bash
du -sh ~/.claude-mem ~/.claude/projects ~/.agentmemory 2>/dev/null
```

```powershell
# Windows
Get-ChildItem "$env:USERPROFILE\.claude-mem","$env:USERPROFILE\.claude" -Recurse |
  Measure-Object Length -Sum
```

**Must NOT be copied — copying these *causes* breakage:**

| | why |
|---|---|
| `graphify-out/.graphify_python`, `.graphify_root` | they pin **absolute** interpreter/repo paths. Carrying them to a new machine is what broke graphify in the 2026-07-28 migration. Keep them gitignored; let each machine write its own. |
| `~/.agentmemory/bin/iii` | a copied engine binary is the **wrong architecture** — delete it and it re-downloads |
| `iii.pid`, `worker.pid`, `engine-state.json` | stale PIDs can make `stop --force` signal an unrelated process |
| `graphify-out/graph.json` and other derived output | rebuilt for free from the committed cache |

---

## Part 2 — New machine, in order

```bash
# 1. the tool itself
git clone <your-agent-tools-remote> ~/Projects/Agent-Tools
cd ~/Projects/Agent-Tools && ./install.sh

# 2. everything it manages: node, uv, graphify (with extras + the mcp<2 pin),
#    the memory backend and its service, caveman
agent-tools install-machine

# 3. per project — this is what recreates the git hooks and MCP wiring
cd ~/Projects/<project> && agent-tools init

# 4. rebuild the graph from the committed cache (no LLM, no cost)
agent-tools refresh --code-only

# 5. confirm
agent-tools doctor
```

`init` is idempotent — it reports "already configured" for anything already in
place, so re-running it is always safe.

**Then carry over what git could not.** Memory is the one that surprises people:

```bash
# on the OLD machine
agent-tools memory export ~/memory-notes    # verbatim Markdown, exact
# copy ~/memory-notes across (or commit it somewhere private)
```

Copying `~/.claude-mem/` wholesale also works and preserves vector search, but it
is a moving SQLite + Chroma store — **stop the worker first** (`npx claude-mem
stop`) or you may copy a torn database.

---

## Part 3 — Two machines at once

Different problem from migration. Nothing syncs by default:

- **graphify** is fine — the graph and its cache live in the repo, so git *is*
  the sync.
- **memory does not sync.** claude-mem's default `worker` runtime is a local
  SQLite; its `sync_*` tables are inert scaffolding. The real answer is
  `npx claude-mem install --runtime server` (Docker postgres + redis), where
  several machines point at one backend. See [MEMORY.md](MEMORY.md).
- **transcripts do not sync**, so `claude --resume` history is per-machine.

---

## Part 4 — Keys: rotating, changing, and what actually reads them

### The short version

**`agent-tools` needs no API key at all.** Every graphify call it makes passes
`--backend claude-cli`, which drives your Claude subscription. Keys are only for
running graphify's *other* backends by hand.

### Where a key has to end up

graphify reads **environment variables** — `GEMINI_API_KEY`, `ANTHROPIC_API_KEY`,
`OPENAI_API_KEY`, and so on. It does **not** read any config file of its own.

The convention here is to keep the secret in a `600` file and source it, so it
stays out of your shell history and out of rc files:

```bash
# ~/.config/graphify/env   (chmod 600)
GEMINI_API_KEY=...
```

**Storing it is not enough — nothing sources that file automatically.** A machine
was found with the file correctly in place and the key never reaching a single
process, because this step was missing:

```bash
set -a; . ~/.config/graphify/env; set +a     # add to ~/.zshrc to make it stick
```

### Rotating or changing a key

```bash
# 1. rotate at the provider   (Gemini: https://aistudio.google.com/apikey)
# 2. write the new value WITHOUT putting it in your shell history or a chat:
read -rs -p "new GEMINI_API_KEY: " K && \
  printf 'GEMINI_API_KEY=%s\n' "$K" > ~/.config/graphify/env && \
  chmod 600 ~/.config/graphify/env && unset K
# 3. reload it in any shell that needs it
set -a; . ~/.config/graphify/env; set +a
# 4. verify
graphify extract . --backend gemini --dry-run 2>&1 | head -3
```

Rotating at the provider **does not** update the file. Doing only step 1 leaves a
dead key on disk, which is worse than none — see below.

### Removing a key you no longer want

Comment it out rather than deleting the file, so the variable name and format
survive for next time:

```bash
#GEMINI_API_KEY=PASTE_NEW_KEY_HERE
```

Nothing breaks: graphify's auto-detect deliberately **excludes `claude-cli`**
(auto-selecting it would silently spend your Claude subscription), so with no key
a bare `graphify extract .` says *"no LLM API key found"* and you pass
`--backend claude-cli` explicitly. `agent-tools` already does.

**A dead key is worse than no key** *if it reaches the environment*: auto-detect
picks that backend because the variable exists, then fails. If you have revoked a
key, redact it from the file too.

### If a key leaks

Order matters:

1. **Revoke at the provider first.** Everything else is cleanup.
2. Write the new key using the no-echo command above.
3. Assume the old value is still recoverable: pasting a secret into an agent
   session puts it in the session transcript under `~/.claude/projects/`, and
   possibly in memory summaries and shell history. Revocation is what protects
   you; scrubbing is best-effort.
4. Never paste a key into a chat to have an agent write it for you. Have the
   agent give you the command, and run it yourself.

### Other credentials worth knowing about

| | where | notes |
|---|---|---|
| claude-mem server API key | created by `claude-mem server api-key create` | only exists on the `--runtime server` path |
| claude-mem telemetry ID | `~/.claude-mem/telemetry.json` | random UUID; telemetry is **on by default** — `npx claude-mem telemetry disable` |
| agentmemory | none | local server, no key |
| caveman | none | skills only, no service |
