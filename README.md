# Agent Tools

**Agent Tools helps you write better code with an AI assistant - While using fewer tokens!**

If you use Claude Code, Codex, (or others), you'll know how dumb agents can be,
and how much can be useful - and also suck.  They forget things, burn tokens,
and rush to code without stopping and asking the right questions.

Thankfully, some smarter people than I have created tools to help solve this problem. I
compiled the tools I found most useful into one application.  These tools will/can change,
so you may need to update often.  The whole AI space is very fluid.  It also installs
the tools in CLI mode by default to reduce your token usage.  It updates your AGENTS.md file
so you only burn tokens when you use a tool.  If you want the MCP installed, you can do that
too!

Agent Tools installs the useful tools for you and encodes every trap we hit along the
way, so you don't have to hit them too.

```bash
git clone https://github.com/AgentTooligans/agent-tools
cd agent-tools
./install.sh

agent-tools install-machine     # once per computer
cd ~/code/your-project
agent-tools init                # once per project
```

That's it. Your assistant now has a graph of the project, memory that persists
between sessions, and compressed output — and you can check what it cost you
with `agent-tools status`.

---

## Installing

You need **bash** and **python3**. Everything else is installed for you, and
you're asked before anything lands on your machine.

### 1. Get the code

```bash
git clone https://github.com/AgentTooligans/agent-tools
cd agent-tools
```

No git? Download the ZIP from the repo page and unzip it. Everything works the
same, except `agent-tools update self` will offer to clone a proper copy for
you the first time you run it.

### 2. Put it on your PATH

```bash
./install.sh                  # installs to ~/.local/bin
./install.sh /usr/local/bin   # or somewhere else
```

This copies the script, drops in a few helper scripts next to it, adds
`~/.local/bin` to your PATH if it isn't there, and prints the version it just
installed. It doesn't touch any project.

Check it worked:

```bash
agent-tools version
```

### 3. Set up the computer

```bash
agent-tools install-machine
```

This is the only step that installs other software, and it asks first — every
tool, one prompt each, and you can say no to any of them. Skip ones you don't
want up front with `--no-rtk`, `--no-caveman`, and so on, or take everything
without prompts using `--yes`.

Nothing here runs a background service or phones home.

### 4. Set up a project

```bash
cd ~/code/your-project
agent-tools init
```

Run this inside any git repository. It builds the knowledge graph, adds a few
`.gitignore` rules, installs two optional git hooks (disabled by default), and
writes a short block into your `AGENTS.md` telling the assistant how to use the
graph.

`init` is safe to run again any time. It reports what's already in place and
only adds what's missing.

### You don't need Claude Code

Agent Tools works without it. Only one thing needs a language model — the
**semantic pass** that reads your docs and names the parts of your graph — and
you have four ways to provide one:

| you have | what happens |
|---|---|
| the `claude` CLI | used automatically, no API key, billed to your existing subscription. Runs the **Haiku** model by default — fast and cheap. (graphify's own default is Opus, which is overkill for structured extraction; Agent Tools overrides it to Haiku.) |
| any API key (`GEMINI_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `DEEPSEEK_API_KEY`, `MOONSHOT_API_KEY`) | detected automatically |
| ollama on `:11434` | used automatically, fully local, no account |
| none of the above | `agent-tools refresh --code-only` — pure local parsing, no model, no cost |

**Only have Codex (or Cursor, Gemini CLI, …) and no `claude`?** Still works.
The `claude` CLI is never required — it's just one of the four options above.
Codex itself is not a graphify backend, so set the API key you already use
(Codex users usually have `OPENAI_API_KEY`) and it's detected automatically, or
run `--code-only` and skip the model entirely.

If you start a semantic pass with no model available, it stops immediately and
tells you these options rather than failing halfway through.

Tune the model, force a backend, or parallelize harder:

```bash
AGENT_TOOLS_BACKEND=gemini agent-tools refresh          # force a specific backend
GRAPHIFY_CLAUDE_CLI_MODEL=sonnet agent-tools refresh    # override the Haiku default (haiku|sonnet|opus|full model id)
AGENT_TOOLS_CONCURRENCY=8 agent-tools refresh           # run 8 chunks at once (default 4)
```

**`--code-only` is a real option, not a consolation prize.** It gives you the
full structural graph — every function, class, import and call — which is what
most questions actually need. The semantic pass adds doc understanding and
readable community names on top.

### Windows

Use `agent-tools.ps1`, which passes commands through to WSL if you have it and
Git Bash if you don't:

```powershell
.\agent-tools.ps1 doctor
```

Everything works under both. See [docs/PLATFORMS.md](docs/PLATFORMS.md) for
what differs.

### If something looks wrong

```bash
agent-tools doctor
```

`doctor` only reads — it never changes anything. It tells you what's broken and
the exact command that fixes it.

---

## Why we built this

We didn't set out to write a tool. We set out to use several good ones
together, and kept losing hours to problems that had nothing to do with our
actual work.

The pattern was always the same: **a tool would fail in a way that looked like
success.** Not a crash, not an error — a clean exit code and a helpful message,
while doing nothing at all.

A few of the ones that cost us the most:

- We ran the graph builder's clustering command to regenerate a report. It
  renamed every community in the graph after whichever node happened to be most
  connected, exited 0, and said nothing. The labels were gone and there was no
  way to tell from the output.
- We installed four skills with `--skill 'a,b,c'`. The CLI printed the full
  catalogue of available skills and exited successfully. It had installed
  nothing — a comma-separated list matches no skill name, and there's no
  error for that.
- We set up the memory backend and worked for a week before noticing it had
  captured nothing. Its installer mentions that the worker isn't started
  automatically, once, in passing, and then moves on.
- We had three code-graph tools wired at the same time without realising it.
  Each was sending its full tool schema every single session — thousands of
  tokens, every message, to answer questions we were only ever asking one of
  them.

None of these were bugs in those tools exactly. They were sharp edges that are
invisible until they cost you something. So every time one cut us, we wrote the
fix into a script and wrote down what happened.

That script is Agent Tools, and the written-down part is
[docs/WHY.md](docs/WHY.md) — an incident log where every default in here has a
paragraph explaining what went wrong and why the default is what it is. If you
ever wonder why something works the way it does, that's where the answer is.

The other thing we care about is **tokens**. Context is the real budget when
you work with an assistant all day. So the guiding rule is that nothing should
cost you tokens in sessions where it does nothing for you. That's why MCP
servers are opt-in rather than default, why the assistant is pointed at CLIs it
can call on demand, and why `doctor` complains when you have overlapping tools
loaded.

---

## What you get

| | what it does for you |
|---|---|
| **A knowledge graph** | Your assistant asks the graph *"what calls this function?"* instead of grepping and reading files. Faster answers, far fewer tokens. |
| **Persistent memory** | Decisions and context survive between sessions, so you stop re-explaining your own project. |
| **Output compression** | Long command output is filtered before it reaches the assistant. Roughly 75% fewer tokens on shell-heavy work. |
| **Reply compression** | An optional style that makes the assistant answer tersely without losing technical accuracy. |
| **Skills** | Small prompts you invoke by name — `/grill-me` interrogates a plan, `/handoff` writes a summary for the next session. |
| **One health check** | `agent-tools doctor` tells you what's broken across all of it, and never changes anything itself. |

Everything is optional and everything is removable. `agent-tools uninstall
<name>` takes one back out; `agent-tools uninstall all` removes the lot, and
tells you exactly what data would be lost before it deletes anything.

### Find what you need

| I want to… | go to |
|---|---|
| **install this** on a new computer | [Installing](#installing) |
| add this to **projects I already have** | [Adding it to existing projects](#adding-it-to-existing-projects) |
| **install / remove one tool** | [Managing the tools](#managing-the-tools) |
| confine a tool to **one repo** | [Machine-wide, or one project](#machine-wide-or-one-project) |
| **upgrade** anything, all at once or one at a time | [Updating](#updating) |
| know what **/grill-me, /handoff, /wait-what** are | [The skill packs](#the-skill-packs) |
| know **which tool to use** when two overlap | [docs/TOOLS.md](docs/TOOLS.md) |
| see **what I have installed** and every version | `agent-tools status` |
| use these tools in **Codex / Antigravity / Cursor** | [Every agent, no MCP required](#every-agent-no-mcp-required) |
| **remove** a tool without losing data by accident | [Removing things](#removing-things) |
| **move to another computer** | [Moving to another computer](#moving-to-another-computer) |
| understand **why a default is what it is** | [docs/WHY.md](docs/WHY.md) |

---

## What it configures

**Per computer** (`install-machine`): node, uv, graphify (with the right extras
and pins), your memory backend, and five tools that each cut a different part
of the bill. Nothing here installs a launchd or systemd unit — see
[docs/SERVICES.md](docs/SERVICES.md):

| tool | cuts | skip with |
|---|---|---|
| **graphify** | what the agent must **read** to find things | — |
| **memory** | what it must **re-derive** from past sessions | `--memory=none` |
| **caveman** | what it **says back** | `--no-caveman` |
| **rtk** | what shell commands **return** (`git status`, test runs) | `--no-rtk` |
| **context-mode** | re-reading everything **after a compaction** | `--no-context-mode` |
| **superpowers** | doing the work the long way round | `--no-superpowers` |
| **pocock** | the round trips a vague plan costs you | `--no-pocock` |

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
| pocock skills | machine (`~/.agents/skills`, all agents) | **nothing** |
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

`init` installs **no skills and no binaries** — not pocock, not caveman, not
superpowers. Those live in `~/.agents/skills` and `~/.claude`, one copy for
every repo, so they are `install-machine`'s job. If `agent-tools doctor` in a
fresh repo says the pocock skills are missing, the fix is machine scope, not
project scope:

```bash
agent-tools install pocock         # or: agent-tools pocock install
```

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
                                       # | pocock
                                       # | code-review-graph | token-savior
                                       # | defaults | all
agent-tools uninstall <name>
agent-tools wire <name>                # add a graph's MCP to THIS repo
agent-tools unwire <name>              # take it back out
```

Aliases work where you'd expect them to: `crg`, `ts`, `ctx`, `superpower`. For
the skill packs you can also use the skill's own name — `agent-tools install
grill-me` installs the whole `pocock` pack, because installing one of those
four alone is usually a mistake (see below).

Two of them have their own subcommand, since a skill pack has states a binary
does not:

```bash
agent-tools caveman status|install|update|uninstall
agent-tools pocock  status|install|update|uninstall
```

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

**Everything at once:**

```bash
agent-tools update all         # graphify + claude-mem + every installed tool + self
```

**A group:**

```bash
agent-tools update tools       # only the optional tools — skips graphify, memory, self
```

**One thing:**

```bash
agent-tools update memory      # claude-mem, and restart its worker
agent-tools update pocock      # the mattpocock skills
agent-tools update caveman     # the caveman plugin + its global skills
agent-tools update graphify    # graphify only
agent-tools update rtk
agent-tools update superpowers
agent-tools update context-mode
agent-tools update code-review-graph
agent-tools update token-savior
agent-tools update self        # git pull + ./install.sh in your checkout
```

Aliases work here too: `agent-tools update crg`, `update ts`, `update ctx`.

**`update` never installs something you don't already have.** A tool you
haven't got is reported, not added — so `update all` on a minimal machine stays
minimal.

Each component has its own footgun, which is the reason this is one command
rather than a list of incantations you have to remember:

| component | what goes wrong unattended |
|---|---|
| graphify | an upgrade can invalidate the semantic cache — hours of re-extraction |
| token-savior | `uv tool upgrade` **drops the extras**, silently disabling vector recall |
| claude-mem | the worker keeps running the old build until it is restarted |
| code-review-graph | its graph is keyed to the parser version; rebuild after a bump |
| pocock / caveman | `skills update` **exits 0 even for a skill that does not exist**, so agent-tools fingerprints the files instead of trusting the exit code |

Details and the per-tool restart requirements: [docs/UPDATING.md](docs/UPDATING.md).

### The skill packs

Two of the default tools are **skills**, not servers: `caveman` and `pocock`.
The distinction matters for your context budget.

**A skill is a markdown file.** The agent loads only its `name` and
`description` at startup — a line or two — and reads the body *only* when the
skill is invoked. **An MCP server is the expensive kind**: its full tool schema
is re-sent every session whether you call it or not. That is why
`code-review-graph` (30 MCP tools) is opt-in while four extra skills are not.

`pocock` installs four skills from [mattpocock/skills](https://github.com/mattpocock/skills):

| skill | what it does | how it fires |
|---|---|---|
| **`/grill-me`** | interviews you one question at a time until every branch of a plan is resolved, recommending an answer with each question | you invoke it |
| **`grilling`** | the engine `/grill-me` delegates to — also auto-fires on "grill" phrasing | model or `/grill-me` |
| **`/handoff`** | compacts the conversation into a handoff document for the next agent | you invoke it |
| **`/wait-what`** | re-pitches a message that didn't land, in plain Simplified Technical English | you invoke it |

All but `grilling` set `disable-model-invocation: true`, so the model can never
fire them on its own. Total standing cost for the pack is roughly **100 tokens
per session**.

**`grilling` is not optional.** `/grill-me` is a two-line stub whose entire body
is *"Call the Skill tool with 'grilling'"*. They ship as separate directories
and nothing upstream enforces the pairing, so installing `grill-me` alone gives
you a skill that fires and dead-ends. `agent-tools` installs both and treats a
partial install as broken.

```bash
agent-tools pocock status      # which of the four are present
agent-tools install pocock
agent-tools update pocock
agent-tools uninstall pocock
agent-tools install-machine --no-pocock   # skip it entirely
```

They install **globally**, into `~/.agents/skills`, symlinked into every agent's
own skills directory — so Codex, Copilot and the rest get them too, not just
Claude Code. That is the same mechanism `caveman` uses.

The repo ships 35 skills; agent-tools installs these four because they are
useful in any repo and carry no house style. The rest (`tdd`, `code-review`,
`to-spec`, `domain-modeling`, …) encode a particular way of working and overlap
with `superpowers`, which is already a default. Add any of them by hand:

```bash
npx -y skills add mattpocock/skills --skill domain-modeling --agent '*' -g -y
```

**One flag per skill.** `--skill 'a,b,c'` matches nothing, prints the repo's
catalogue, installs nothing, and **exits 0**. Repeat the flag instead.

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
| macOS | full | ✅ |
| Linux | full | ✅ Ubuntu 24.04 |
| WSL2 | full | ✅ Win 11 + Ubuntu 26.04 & 24.04 |
| Windows native | everything **except rtk**, which needs cargo or a release zip | ✅ Win 11 + Git Bash |

**Windows got better in 3.3.0.** Earlier versions said "graphify only" because
the agentmemory backend shipped no Windows engine installer. That backend is
gone, so claude-mem, the skill packs and the rest all work under Git Bash.
rtk is the only remaining gap: its `install.sh` doesn't cover native Windows,
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

**`refresh` updates every graph you've wired into the repo, and only those.**

| wired here | what refresh does |
|---|---|
| graphify (`graphify-out/graph.json` present) | structure → docs → community names |
| code-review-graph (`agent-tools wire code-review-graph`) | rebuilds its index (`code-review-graph build`) — local AST, no LLM |
| token-savior (`agent-tools wire token-savior`) | warms its daemon so it re-reads the current code |

A repo with only code-review-graph and no graphify graph refreshes just
code-review-graph — no stray LLM run. Nothing you haven't wired is touched.

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
repo size — code (the AST structure pass) is always free and near-instant.

**What a "chunk" is.** The semantic pass packs your changed docs into chunks of
up to ~60k tokens each and sends **one LLM request per chunk**. Roughly 17 docs
per chunk. The chunks run in parallel — 4 at a time by default
(`AGENT_TOOLS_CONCURRENCY` raises it).

**The startup cost you may have heard about is real, but only on `claude-cli`.**
On that backend each chunk is a *fresh* `claude -p` process (no session reuse),
so every chunk reloads Claude Code's whole system prompt and tool schemas —
on the order of ~10k tokens of fixed overhead *before* your content, every
chunk. It is not a Task/subagent; it's a full CLI process per chunk. That
overhead is why a big first run is slow, and why the `claude-cli` label step is
forced to run one-at-a-time.

**On an API backend a chunk is just one HTTPS call** — no CLI, no 10k reload,
only graphify's small extraction prompt plus your content. So the fastest big
semantic pass is an API key + higher concurrency:

```bash
AGENT_TOOLS_BACKEND=gemini AGENT_TOOLS_CONCURRENCY=8 agent-tools refresh
```

Ballpark on the serial `claude-cli` backend: ~1–2 minutes per chunk with the
default Haiku model (Opus was ~5), so ~400 cold docs is well under an hour. A
repo whose docs are already cached finishes in seconds. `status` shows chunk
progress while it runs. And nothing here touches code — only edited docs cost
anything, and `--code-only` costs nothing at all.

To auto-refresh the code graph on every commit:

```bash
touch .git/graphify-auto-update-ENABLED    # enable
rm    .git/graphify-auto-update-ENABLED    # disable (the default)
```

---

## Memory backend

**claude-mem, or nothing.** agentmemory was removed in 3.3.0 — see
[Removed: agentmemory](#removed-agentmemory) below.

| | **claude-mem** (default) |
|---|---|
| service | worker on :37701 — start with `npx claude-mem start`, **no launchd/systemd unit** |
| store | `~/.claude-mem/` (SQLite + Chroma), absolute path |
| context injection | automatic at session start |
| bulk import of past sessions | none — starts from install day |
| export to Markdown | yes (`agent-tools memory export`) |

```bash
agent-tools install-machine --memory=claude-mem    # default
agent-tools install-machine --memory=none          # graphify only, nothing captures
```

Your choice is remembered in `~/.config/agent-tools/config`.

**The worker is not autostarted.** claude-mem's own installer says so and moves
on. No worker means no capture, and the session gives you no hint. `agent-tools
doctor` checks :37701 every time you run it; [docs/SERVICES.md](docs/SERVICES.md)
has a login-time snippet if you want one.

```bash
agent-tools memory status                 # backend, what is installed
agent-tools memory export ~/notes         # memories -> portable Markdown
agent-tools memory switch none            # stop capturing (store kept)
agent-tools memory switch claude-mem      # start again
```

Switching is **machine-wide, not per-project** — memory hooks at user scope and
keeps one global store, so a per-project split would fragment your history.

### Removed: agentmemory

agentmemory was a supported backend through 3.2.x. It is gone as of **3.3.0**,
and the reason is worth stating plainly, because it is also why this repo is
simpler now:

- Its store path was **relative to the server's working directory**. Start the
  server from the wrong place and you silently got a new, empty memory.
  `AGENTMEMORY_DATA_DIR` and `--data-dir` were documented and inert.
- Surviving that required a launchd plist and a systemd unit whose only real
  job was pinning a working directory — plus `loginctl enable-linger`, plus a
  WSL reboot gap, plus a `--tools core` argument that could not be set any
  other way.
- It shipped no native-Windows engine installer, which is what pinned this
  whole project to "Windows = graphify only" for three minor versions.

**Your data was not touched.** `~/.agentmemory` is left exactly as it was.

```bash
agent-tools memory migrate-from-agentmemory
```

That exports the store to Markdown (the exact record), imports what it can into
claude-mem, then stops the server, disables the unit, disables the Claude Code
plugin, and removes the stale MCP entry. `agent-tools doctor` detects a legacy
install and tells you if it is still capturing alongside claude-mem — which is
worth fixing, because that means two hook sets fire on every tool call.

**The migration is one-way, and the tool says so rather than pretending.**
claude-mem has *no ingest API*; only its own hooks write. So the converter
synthesises a transcript and feeds claude-mem's Stop hook, which summarises and
embeds natively. **claude-mem compresses on ingest**, so the converted copies
are summaries — keep the Markdown export as ground truth.

A config file that still says `memory_backend=agentmemory` does not break:
agent-tools falls back to claude-mem, prints one notice, and leaves your store
alone.

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

## Every agent, no MCP required

```bash
agent-tools init              # DEFAULT: no MCP server. The agent uses the CLI.
agent-tools init --add-mcp    # opt THIS repo in to graphify's MCP server
agent-tools wire graphify     # add one to a repo later
agent-tools unwire graphify   # take it back out; the CLI keeps working
agent-tools agents            # which agents are here, and how each gets the tools
```

**Since 3.4.0, `init` wires no MCP server unless you ask.** An MCP server re-sends its
entire tool schema *every session whether you call it or not* — graphify's is
~1.5k tokens, code-review-graph ships 30 tools. A CLI costs **zero** until the
agent actually runs it, and any agent that can run a shell can run it.

| mechanism | reaches | cost per session |
|---|---|---|
| skills (`~/.agents/skills`) | every agent | one description line each |
| CLI (`graphify`, `ts`, `code-review-graph`, `rtk`) | every agent that can run a shell | **zero** until called |
| hooks | hosts that support them | zero |
| MCP *(opt-in)* | Claude Code only | the full schema, every session |

### Pros and cons, plainly

| | MCP server (`--add-mcp`) | CLI (default) |
|---|---|---|
| **Agent notices the tool** | **yes** — its schema is in every session's tool list, so the agent reaches for it unprompted | only if the instruction block tells it |
| **Cost per session** | the full schema whether called or not: graphify ~1.5k tokens, code-review-graph 30 tools | **zero** until the agent runs it |
| **Works in Codex / Antigravity / Cursor** | no | **yes** |
| **Same graph, same answers** | yes | yes |
| **Needs the graph built** | yes | yes |
| **Reversible any time** | yes | yes |

The MCP advantage is real: an agent that can *see* a tool uses it without being
reminded. For a graph you query constantly, that is worth the schema. The cost
is real too, and it is charged every session even on the ones where you never
ask a graph question — which is why stacking two or three code-graph servers is
the case `doctor` complains about.

**Per repo, so mix freely.** Wire the one you actually query; leave the rest on
the CLI.

**Installing a tool installs both interfaces.** `uv tool install graphifyy`
puts `graphify` (CLI) *and* `graphify-mcp` (server) on disk — one package, same
code, same `graphify-out/graph.json`. There is no separate "MCP version" to
install; `wire`/`unwire` only decide whether Claude Code *launches* the server.
Both directions work any time, on any repo, including one set up with
`--no-mcp`. Nothing is reinstalled.

The difference is not capability, it is **discoverability**: an MCP server
advertises itself in every session's tool list; a CLI has to be taught. That
teaching is the instruction block — ~40 tokens against ~1,500 for a schema.
Mixing is normal and per repo, so wire the tool you query constantly and leave
the rest on the CLI.

`agent-tools init` writes its instruction block into **`AGENTS.md`** — the
cross-agent standard file — and that block contains **no `mcp__` tool names**.
Because Claude Code reads `CLAUDE.md` (not `AGENTS.md`), init also creates a
one-line `CLAUDE.md` that `@`-imports `AGENTS.md`, so Claude picks up the exact
same instructions with nothing duplicated. `agent-tools doctor` verifies that
import is in place. It teaches the CLI:

```bash
graphify query "<question>"     graphify affected "<symbol>"     graphify god-nodes
code-review-graph query|impact|search      ts get|search|ctx
```

So the same repo works identically in Claude Code, Codex and Antigravity.
`graphify install --platform codex|antigravity|cursor|gemini|…` gives a host
graphify's own skill — again, no server. Details in
[docs/AGENTS.md](docs/AGENTS.md).

## Versions

```bash
agent-tools version            # released / installed / source — all three
agent-tools status             # every managed tool, with its version
./install.sh --version         # what this checkout would install
```

`git pull` alone changes nothing: the copy on your PATH is what runs, and only
`install.sh` replaces it. So `version` prints both and complains when they
diverge:

```
agent-tools 3.3.1   (released 2026-08-20)
  installed  2026-08-20 13:14
             /Users/you/.local/bin/agent-tools
  source     /Users/you/code/Agent-Tools
             HEAD 13b5d5c  (2026-08-04 14:16)
  ! the copy on your PATH is 3.3.0, but this file is 3.3.1
  !     re-run ./install.sh from the checkout
```

`agent-tools status` is the inventory — what is installed with its version,
what is available with the command that installs it:

```
== Installed (9) ==
  ✓ rtk                 hook     0.45.0
  ✓ caveman             skills   13/13 skills, updated 2026-08-20 12:57
  ✓ pocock              skills   4/4 skills, updated 2026-08-20 12:57
  ✓ graphify            MCP      0.9.48
  ...
== Available (1) ==
  - token-savior        MCP      agent-tools install token-savior
```

Skill packs have no version — a skill is markdown from a public repo — so they
report how many of the expected skills are present and when they last changed.
Full detail in [docs/UPDATING.md](docs/UPDATING.md).

## Removing things

```bash
agent-tools uninstall <name>       # one tool
agent-tools uninstall all          # everything agent-tools installed
```

**The tool and its data are separate decisions.** Anything a tool recorded is
named, sized and labelled regenerable-or-not *before* you are asked, and the
default is to keep it:

```
  ! removing token-savior would leave this behind:
        /Users/you/.local/share/token-savior  (412M)
            the recall store: memory engine plus vector index
            cannot be regenerated

  ? DELETE the data listed above? This cannot be undone. [y/N]
```

`--purge` deletes machine-wide data without asking, `--keep-data` keeps
without asking, and with **no terminal nothing is ever deleted**. `uninstall
all` shows the full bill, then requires you to type `REMOVE` — a keypress is
too cheap for that one.

**Per-repo data needs `--purge-repo` on top of `--purge`.** Which repo that
means depends on where you are standing, so `--purge` alone never touches it;
those rows are marked `[THIS REPO]` in the bill and are explicitly kept:

```
  ! kept (repo-scoped): /path/to/repo/graphify-out
  !     --purge covers machine-wide data only.
  !     add --purge-repo to include THIS repo's data.
```

Unregenerable: rtk's `history.db`, context-mode's index, token-savior's recall
store, claude-mem's captured sessions, graphify's config. Regenerable but
expensive: a repo's `graphify-out/` (a deep re-run costs hours).

> This guard exists because the earlier behaviour destroyed this project's own
> graph during testing: a `--purge` meant for a sandbox, run one directory too
> high. The incident is in [docs/WHY.md](docs/WHY.md).

The table of exactly what each tool leaves behind is in
[docs/UPDATING.md](docs/UPDATING.md).

## Tests

```bash
tests/run-all.sh              # both suites
tests/bash/run-tests.sh       # the bash script only
pwsh -File tests/ps1/run-tests.ps1   # the Windows wrapper only
```

Both suites are **hermetic**: they build a throwaway `HOME`, a throwaway git
repo, and — for the PowerShell suite — fake `wsl.exe` and Git Bash stubs, then
delete the lot on exit. Nothing installs a package, touches the network, or
writes outside its sandbox. That is why they only exercise commands that are
pure output (`version`, `help`, `wire`/`unwire`, config round-trips) plus the
install paths that decline at their confirm prompt when stdin is closed.

| suite | covers |
|---|---|
| `tests/bash` | static hygiene (`bash -n`, shellcheck), the scope rules (skills vs hook vs plugin vs MCP), alias resolution, `--project` refusals, the recorded-checkout round-trip, and that every tool in `OPTIONAL_TOOLS` is reachable from `install`, `uninstall` **and** `update` |
| `tests/ps1` | `agent-tools.ps1`: WSL detection including a UTF-16 distro list, the Git Bash fallback at all three install locations, the `\\wsl$` UNC guard, exit-code propagation, and argument marshalling against injection |

The PowerShell suite is **skipped, not failed**, where `pwsh` is absent — the
wrapper it tests is only reachable from Windows.

Static analysis is part of the bash suite rather than a separate step, and one
check exists because of a real regression: a `# shellcheck disable=SCxxxx  --
prose` comment does not parse, and an unparseable directive makes shellcheck
abort **the whole file**. The script sat unchecked behind one such line.

## Documentation

Every page here is written to be read by a person, not skimmed by a parser. If
you're only going to read one, make it [docs/WHY.md](docs/WHY.md) — it explains
what went wrong that made each default what it is.

| doc | what's in it |
|---|---|
| [docs/TOOLS.md](docs/TOOLS.md) | **every tool, what each is best at, and which one to keep when two overlap** |
| [docs/MEMORY.md](docs/MEMORY.md) | claude-mem, what it captures, and migrating off the removed agentmemory backend |
| [docs/USAGE.md](docs/USAGE.md) | when each tool earns its keep, what graphify is **bad** at, telling agents to use them, stale-graph behavior |
| [docs/SERVICES.md](docs/SERVICES.md) | the memory worker: startup, restarts, reboots — and why there is no longer a launchd/systemd unit |
| [docs/UPDATING.md](docs/UPDATING.md) | `agent-tools update`, per-component upgrade steps, and why upgrading graphify can cost hours |
| [docs/CAVEMAN.md](docs/CAVEMAN.md) | the output-compression skill: why it is default, its levels, and the nuance it costs |
| [docs/SKILLS.md](docs/SKILLS.md) | the skill packs: what `/grill-me`, `/handoff` and `/wait-what` do, what a skill costs vs an MCP server, adding your own |
| [docs/AGENTS.md](docs/AGENTS.md) | Codex, Cursor, Gemini CLI, Copilot and friends |
| [docs/MIGRATION.md](docs/MIGRATION.md) | moving to another computer: every out-of-repo path, what to copy vs reinstall, and rotating API keys |
| [docs/PLATFORMS.md](docs/PLATFORMS.md) | support matrix, verification status, WSL traps |
| [docs/GRAPH-HYGIENE.md](docs/GRAPH-HYGIENE.md) | keeping a graph honest: the graph is flat in time, so scope + status banners are the only levers; duplicate/oversize/stale failure modes |
| [docs/WHY.md](docs/WHY.md) | the incident record behind every default |
| [tests/](tests/) | the two hermetic suites and how to run them |

## Extras

`scripts/graphify-full-run.sh` — a detached, resumable full semantic pass for
large doc corpora (launchd/caffeinate on macOS), with retry-on-rate-limit and
self-termination. `scripts/graphify-run-status` reports its progress.

---

## A word of caution

This is a young project. It does real work on your machine, so it's worth
knowing what it touches before you point it at a computer you care about.

- **`doctor`, `status`, `version` and `agents` only read.** They never change
  anything. Start there.
- **`install-machine` and `init` write files**, and both ask before installing
  anything. `init` only touches the repo you run it in.
- **`uninstall` can delete data**, but it names and sizes anything at risk
  first, and defaults to keeping it. See [Removing things](#removing-things).

The tools it installs are other people's work and are linked from
[docs/TOOLS.md](docs/TOOLS.md). Agent Tools installs and configures them; it
doesn't replace or vendor them.

## Contributing

Found a sharp edge we haven't hit yet? That's the most useful thing you can
report. Open an issue describing what looked like success but wasn't — those
are the ones worth writing down.

If you're changing the script, run the tests first:

```bash
tests/run-all.sh
```

They're hermetic — throwaway `HOME`, throwaway git repo, no network — so
they're safe to run on your own machine.
