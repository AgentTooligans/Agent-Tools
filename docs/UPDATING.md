# Updating everything

Five things update independently, each with its own footgun. There is one
command that handles all of them:

```bash
agent-tools update            # graphify + memory backend + caveman + self
agent-tools update graphify
agent-tools update memory     # whichever backend is active
agent-tools update caveman
agent-tools update self
```

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
graphify --version
agentmemory --version
npx claude-mem --version
agent-tools caveman status
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
