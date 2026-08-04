# Updating everything

Everything here updates independently, each with its own footgun. There is one
command that handles all of them:

```bash
agent-tools update              # everything INSTALLED: graphify + memory
                                # + every optional tool + agent-tools itself
agent-tools update tools        # only the optional tools
agent-tools update graphify
agent-tools update memory       # whichever backend is active
agent-tools update rtk
agent-tools update caveman
agent-tools update superpowers
agent-tools update context-mode
agent-tools update crg          # code-review-graph (alias)
agent-tools update ts           # token-savior (alias)
agent-tools update self
```

**`update` never installs something you don't have.** Anything missing is
reported and skipped — an update command that quietly adds tools is not an
update command. To add one, `agent-tools install <name>`.

It finishes with a reminder to run `agent-tools doctor`, which is the real test
that nothing came loose. The rest of this page is what each step does by hand,
and why it is not just "install latest".

---

## The quick table

| component | update | must restart after? |
|---|---|---|
| graphify | `uv tool install "graphifyy[gemini,mcp]" --with "mcp<2" --force` | no |
| claude-mem | `npx -y claude-mem@latest install` | **yes** — the worker |
| agentmemory | `npm install -g @agentmemory/agentmemory@latest` | **yes** — the service |
| caveman | `npx -y github:JuliusBrussee/caveman --force` | **yes** — your agent session |
| rtk | `brew upgrade rtk` / re-run its `install.sh` / `cargo install --git … --force` | **yes** — hooks load at session start |
| superpowers | `claude plugin update superpowers@claude-plugins-official` | **yes** |
| context-mode | `claude plugin update context-mode@context-mode` | **yes** |
| code-review-graph | `uv tool upgrade code-review-graph` | no — but rebuild the graph |
| token-savior | `uv tool install "token-savior-recall[mcp,memory-vector]" --force` | no |
| agent-tools | `git pull && ./install.sh` | no |

---

## graphify

```bash
uv tool install "graphifyy[gemini,mcp]" --with "mcp<2" --force
```

**Always this exact line, never a bare `uv tool upgrade`.** Two reasons:

- `[gemini,mcp]` must be re-specified or you lose the extras. Without `gemini`
  the gemini/openai/kimi/ollama backends die with *"the 'openai' package is
  required"*; without `mcp` the MCP server is gone.
- `mcp<2` is mandatory. graphify 0.9.29 imports `AnyUrl` from `mcp.types`, which
  `mcp` 2.0.0 removed, and then reports *"mcp not installed"* when it plainly is.

### The cost of upgrading

**An upgrade can invalidate your semantic cache.** Cache entries are stamped
with the extraction prompt that produced them, so a release that changes that
prompt turns every entry into a miss — and you pay for the doc extraction pass
again (hours, on a large corpus).

So don't upgrade reflexively. Upgrade when you have a reason — a bug you're
hitting, a feature you want — and when you can absorb a re-extraction window.
Afterwards:

```bash
agent-tools doctor        # confirm nothing came loose
agent-tools refresh       # rebuild; re-extracts only what the cache missed
```

---

## claude-mem

```bash
npx -y claude-mem@latest install     # upgrade in place
npx claude-mem start                 # restart the worker afterwards
```

Its store (`~/.claude-mem/claude-mem.db` + Chroma index) is untouched by an
upgrade. Check afterwards with `agent-tools doctor`, which verifies the worker
is answering on :37701.

Close all Claude Code sessions before **uninstalling** — its own installer
warns that active hooks will recreate `~/.claude-mem` underneath you.

## agentmemory

```bash
npm install -g @agentmemory/agentmemory@latest
```

Then restart the service so the new binary is actually running:

```bash
# macOS
launchctl bootout gui/$(id -u)/com.agentmemory.server
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.agentmemory.server.plist

# Linux / WSL
systemctl --user restart agentmemory
```

**Check the Node floor first.** agentmemory requires **Node >= 20** and npm only
*warns* if you're below it — it installs and then crash-loops on startup. Verify:

```bash
node -v                   # must be v20+
agent-tools doctor        # flags an old Node explicitly
```

Your memory data is not touched by an upgrade. It lives in the store directory,
which is decided by the service's working directory — see [WHY.md](WHY.md).

---

## caveman

```bash
agent-tools caveman update
```

By hand, both halves:

```bash
cd /tmp                                     # NOT inside a repo -- see below
npx -y github:JuliusBrussee/caveman --non-interactive --force
npx -y skills update caveman -g -y
```

Three things to know:

- **Run it from a neutral directory.** The upstream installer writes
  `$PWD/.agents/skills` for non-Claude agents, so running it inside a project
  litters that project.
- **It is unpinned.** Installing from `github:` takes whatever `main` holds
  right now; there is no version to pin to and no changelog to read first.
- **Restart your agent.** Hooks are read at session start, so a running session
  keeps the old behavior.

Full detail: [CAVEMAN.md](CAVEMAN.md).

---

## rtk

```bash
agent-tools update rtk
```

By hand, whichever route installed it:

```bash
brew upgrade rtk                                          # macOS
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
cargo install --git https://github.com/rtk-ai/rtk --force  # Windows / from source
```

**Restart your agent afterwards** — the `PreToolUse` hook is read at session
start, so a running session keeps calling the old binary path.

The hook itself does not need reinstalling; it is a settings entry, not a
generated file. If `rtk gain` stops working after an update, the `rtk` on your
PATH is the crates.io "Rust Type Kit", not this one — see
[TOOLS.md](TOOLS.md#rtk).

---

## superpowers and context-mode

```bash
agent-tools update superpowers
agent-tools update context-mode
```

Both are Claude Code plugins, so both go through the same two steps — refresh
the marketplace, then update the plugin:

```bash
claude plugin marketplace update
claude plugin update superpowers@claude-plugins-official
claude plugin update context-mode@context-mode
```

**Restart Claude Code.** Plugin manifests — and, for context-mode, six hooks —
are read at session start.

context-mode's data in `~/.claude/context-mode/` survives an update. If it
starts failing after a Node upgrade *downwards*, check `node -v`: it needs
**>= 22.5**, and below that its hooks fail at runtime rather than refusing to
install.

---

## code-review-graph

```bash
agent-tools update crg
```

By hand:

```bash
uv tool upgrade code-review-graph
```

**Rebuild the graph in every repo where it is wired.** The SQLite index is
keyed to the parser version, so a version bump can leave a graph the new binary
disagrees with. It is free to redo — no LLM anywhere in the pipeline:

```bash
cd <repo> && code-review-graph build
```

---

## token-savior

```bash
agent-tools update ts
```

By hand — and **note this is not `uv tool upgrade`**:

```bash
uv tool install "token-savior-recall[mcp,memory-vector]" --force
```

Extras are not remembered across an upgrade. Drop `[memory-vector]` and it
still starts, prints *"vector search disabled"* to stderr, and silently falls
back to keyword-only recall. Same class of bug as graphify's `[gemini,mcp]`,
same fix: always name the extras.

Its store in `~/.local/share/token-savior/` is untouched by an update.

---

## agent-tools itself

```bash
agent-tools update self
```

or by hand:

```bash
cd /path/to/Agent-Tools
git pull
./install.sh
```

`install.sh` overwrites the copy on your PATH and strips CRLF on the way in.
It does not touch any project you've already `init`-ed.

If a new version changes what `init` writes, re-run it in each project — `init`
is idempotent and reports "already configured" for anything it finds in place.
That is how you pick up new git hooks or instruction-block changes.

---

## The MCP servers and skills

These are wired once and rarely need touching, but for completeness:

```bash
claude mcp list                                   # what is wired
claude mcp remove graphify -s local               # then re-run: agent-tools init
npx skills list -g                                # global skills, all agents
npx skills update -g                              # update every global skill
```

`agent-tools init` re-wires the MCP entries idempotently, so re-running it after
an update is safe and is the easiest fix if a server stops loading.

---

## Checking versions

```bash
agent-tools version
agent-tools doctor        # every component, plus what's wrong
agent-tools tools         # the optional tools, and what overlaps
graphify --version
agentmemory --version
npx claude-mem --version
agent-tools caveman status
rtk --version && rtk gain          # gain is the test that it's the RIGHT rtk
code-review-graph --version
claude plugin list                 # superpowers, context-mode, caveman
```

---

## When something breaks after an update

1. `agent-tools doctor` — it names the specific fix for each known failure.
2. If graphify's MCP server stops loading, you almost certainly got `mcp` 2.x —
   re-run the install line above with the pin.
3. If community names turn into file names (`api_client.py` instead of
   *Billing Rules Engine*), something re-clustered after labeling. Run
   `agent-tools refresh`, which enforces structure → labels ordering.
4. If the memory server is "active" but never answers, check `node -v`.
5. If replies suddenly turn terse and cryptic, caveman activated — that is
   working as designed. `/caveman off`, or `agent-tools caveman status` to see
   the level.
6. If an agent lost its skills, `npx skills list -g` will show whether the
   global install survived; re-run `agent-tools caveman install` if not.
