# Which tool should I use?

Some of these tools overlap. That's not an accident of packaging — they're
genuinely different answers to the same question, built by different people
with different priorities. This page is here so you can pick the right one
instead of installing all of them and paying for the privilege.

If you only read one thing: **running two code-graph tools at once costs you
tokens in every single session, whether you use them or not.** Pick the one
that fits how you work, and leave the others out.

> **What do I actually have?** `agent-tools status` lists every tool below with
> its version, plus the ones you have not installed and the command for each.
> `agent-tools uninstall <name|all>` removes them, naming any data that would be
> lost first — see [UPDATING.md](UPDATING.md#removing-things).
>
> **Not using Claude Code?** Every tool below has a CLI, and the CLI costs zero
> tokens per session where an MCP server costs its whole schema. `agent-tools
> agents` shows how each installed agent gets them. Since 3.4.0 `agent-tools
> init` wires **no** MCP server by default — add one per repo with `init
> --add-mcp` or `wire <name>`. See [AGENTS.md](AGENTS.md).

`agent-tools` installs seven things. Three of them overlap heavily with each
other, and two more overlap with your memory backend. This page is the map:
what each one is genuinely best at, what it costs you, and which one to keep
when two of them do the same job.

Nothing here is a ranking. They are different trades.

---

## The bill you are actually paying

A long agent session spends tokens in five distinguishable places. Each tool
attacks exactly one of them, which is why the stack is not redundant even
though every tool's README says "saves 90% of your tokens".

| where the tokens go | what fixes it |
|---|---|
| reading source files to find things | **graphify** / code-review-graph / token-savior |
| re-deriving decisions from past sessions | **claude-mem** |
| what the model says back to you | **caveman** |
| output of shell commands (`git status`, test runs) | **rtk** |
| re-reading everything after a compaction | **context-mode** |
| doing the work the long way round | **superpowers** |
| round trips spent on a plan nobody pinned down | **pocock** (`/grill-me`) |
| re-explaining context to the next session | **pocock** (`/handoff`) |

Pick one per row. Two per row is the mistake this page exists to prevent.

---

## The full list

| tool | installed by default? | what it is | per-session cost when idle |
|---|---|---|---|
| [graphify](#graphify) | yes | code knowledge graph, MCP + CLI | 10 MCP tools (~1.5k tokens) |
| [claude-mem](MEMORY.md) | yes | persistent memory | injects context at session start |
| [caveman](CAVEMAN.md) | yes | output-compression instructions | a short instruction block |
| [rtk](#rtk) | yes | Bash output filter (hook) | zero — a hook, no schema |
| [superpowers](#superpowers) | yes | skills library | ~nothing until a skill fires |
| [pocock](SKILLS.md) | yes | 4 skills: `/grill-me`, `/handoff`, `/wait-what` (+ `grilling`) | ~100 tokens of descriptions |
| [context-mode](#context-mode) | yes | tool-output sandbox + session continuity | its MCP schema + six hooks |
| [code-review-graph](#code-review-graph) | **no — opt-in** | second code graph | **30 MCP tools** |
| [token-savior](#token-savior) | **no — opt-in** | third code graph + its own memory | its MCP schema |

```bash
agent-tools tools                       # what you have, what is wired, what overlaps
agent-tools install code-review-graph   # opt in
agent-tools wire token-savior           # add its MCP to THIS repo only
agent-tools unwire code-review-graph    # take it back out
```

**Why two are opt-in and not off by default out of caution:** an MCP server's
tool schema is re-sent **every session, whether or not you ever call it**. Ten
tools is ~1.5k tokens. Thirty is not a rounding error. Installing three code
graphs by default would spend, every session, exactly the budget the graph is
supposed to save.

---

## Code knowledge graphs — pick one

graphify, code-review-graph and token-savior answer the same question: *what is
in this codebase, and what touches what.* Running two is a defensible choice if
you know why. Running three is not.

| | **graphify** | **code-review-graph** | **token-savior** |
|---|---|---|---|
| MCP tools | 10 | 30 | its own set |
| build cost | AST free; **docs cost LLM tokens** | local parse, no LLM | local parse, no LLM |
| what it indexes | code **+ docs + images**, concepts, communities | code symbols, call graph, flows, communities | code symbols, call graph, imports |
| languages | broad | ~30 incl. Solidity, Zig, Terraform, notebooks | broad |
| semantic search | yes (paid pass) | yes (`embed`, local) | yes (local vectors) |
| storage | `graphify-out/` (JSON) | `.code-review-graph/` (SQLite) | SQLite + FTS5 |
| extras | Obsidian export, wiki, god-nodes, blast radius | wiki, dead code, refactor preview, watch daemon | **also a memory engine** |
| freshness | `agent-tools refresh` | `update` / `watch` / daemon | on demand |

### Which one

- **Default to graphify.** It is the only one of the three that indexes
  **prose** — your `docs/`, ADRs, READMEs, and images — and links them to the
  code. Ask it *"how does billing work"* and it answers from the design doc and
  the implementation together. That is a different question from *"who calls
  `charge()`"*, and the other two cannot answer it.
- **Add code-review-graph when the repo is huge and changes constantly.** It
  has a watch daemon and incremental updates measured in seconds, plus
  `dead-code`, `impact` and `refactor` previews aimed squarely at review work.
  Its whole graph is free to build — no LLM pass at all — so it stays fresh
  without a bill. If your pain is *"the graph is always stale"* rather than
  *"I want to ask it about the docs"*, it is the better tool.
- **Add token-savior when you want structural navigation and memory from one
  thing.** It is the only one that ships its own memory engine, so on a machine
  with no memory backend it covers two rows of the table at once. On a machine
  that already runs claude-mem, that half is duplicate work.

### If you keep more than one

Wire only the one you actually query into each project:

```bash
cd big-monorepo   && agent-tools wire code-review-graph
cd docs-heavy-app && agent-tools init          # graphify, as usual
```

`agent-tools doctor` counts the graph MCP servers wired in the current project
and complains when there is more than one.

---

## Output compression — they stack, they do not overlap

**caveman**, **rtk** and **context-mode** all claim to cut tokens, and all
three can run together, because they cut *different* text.

- **caveman** shortens what the model **writes**. It is instructions, nothing
  more — no process, no schema, reversible with `/caveman off`.
- **rtk** shortens what shell commands **return** before the model ever sees
  them. `git status` at 119 characters becomes 28; a 155-line `cargo test`
  becomes 3 lines. Nothing the model produces changes.
- **context-mode** intercepts **tool results** generally, stores the bulk out
  of context, and hands the model a pointer — plus it snapshots state before a
  compaction so the next stretch of the session does not start from nothing.

Running all three is the intended configuration. `agent-tools doctor` says so
explicitly when it sees rtk and context-mode both hooked on `PreToolUse/Bash`:
rtk rewrites the command, context-mode routes the result.

The one real caution is **debuggability**. When three layers filter output,
a command that "returns nothing" has three possible culprits. `rtk proxy <cmd>`
runs a command unfiltered, which is the first thing to try.

---

## Memory — one capturer, always

Covered in full in [MEMORY.md](MEMORY.md). The rule that matters here:
**exactly one thing should be capturing sessions.** claude-mem hooks the
session lifecycle; so does token-savior's memory engine; so, partly, does
context-mode. And a machine upgraded from before 3.3.0 may still be running a
legacy agentmemory, which hooks it too — `doctor` detects that and points at
`agent-tools memory migrate-from-agentmemory`.

- claude-mem: durable memory of **decisions and rationale**, searchable months
  later.
- context-mode: **session continuity** — surviving a compaction inside one
  long session. It is not a replacement for a memory backend and does not try
  to be.
- token-savior's engine: a third store. If you already run a backend, this is
  the part of token-savior to leave unwired.

`agent-tools doctor` warns when two capturers are **active**, not merely
installed — an installed-but-stopped backend is a legitimate archive.

---

## Each tool

### graphify

The default, and what `agent-tools init` wires. Read [USAGE.md](USAGE.md) for
what it is bad at (string-level detail: CSS variables, literals — use grep) and
[GRAPH-HYGIENE.md](GRAPH-HYGIENE.md) for keeping it honest.

**Best at:** questions that span code and prose. Blast radius before a
refactor. "What is risky to touch at all" (`god-nodes`).
**Costs:** the doc/image pass uses an LLM. Code is always free.

### rtk

<https://github.com/rtk-ai/rtk> — a Rust CLI proxy. A `PreToolUse` hook
rewrites every Bash call so its output arrives filtered, grouped and
deduplicated. Upstream reports 60–90% reduction on common dev operations;
that is their number, not one measured here. `rtk gain` reports your own.

**Best at:** repos with noisy tooling — test runners, build systems, `docker`,
`kubectl`, `aws`, `psql`. The savings are proportional to how chatty your
commands are.
**Costs:** nothing per session. It is a hook, not an MCP server.

Two things worth knowing, both encoded in `agent-tools`:

- **There are two different `rtk`s.** crates.io has an unrelated "Rust Type
  Kit" that installs the same binary name. `rtk --version` succeeds for both,
  so it is not a test — `rtk gain` only exists on this one, and that is what
  `doctor` checks. Homebrew's core formula is the right project.
- **`rtk init -g` prompts, and defaults to "no" when it cannot see a
  terminal** — printing a manual step and exiting 0. Scripted, it reports
  success and installs nothing. `agent-tools` writes the hook entry itself,
  idempotently, at machine or project scope, and can remove it again.

```bash
agent-tools install rtk              # binary + machine-wide hook
agent-tools install rtk --project    # hook in THIS repo's .claude/settings.json
agent-tools uninstall rtk --project  # hook out, binary stays
rtk gain                             # your measured savings
rtk proxy <cmd>                      # run something unfiltered, for debugging
```

### superpowers

<https://github.com/obra/superpowers>, distributed through Anthropic's official
marketplace. A skills library: TDD loops, systematic debugging, planning and
collaboration patterns.

**Best at:** the *method*, not the token count. It changes how work gets
approached — write the failing test first, bisect instead of guess.
**Costs:** effectively nothing until a skill is invoked; skills load on demand.

It is one of two tools here that do not claim to save tokens, and it is in the
default set because the cheapest tokens are the ones spent on the right
approach the first time.

### pocock

<https://github.com/mattpocock/skills>. Four skills installed globally into
`~/.agents/skills`, so every agent gets them and not just Claude Code.

| skill | what it does |
|---|---|
| `/grill-me` | interviews you one question at a time until every branch of a plan is resolved |
| `grilling` | the engine `/grill-me` delegates to — also fires on "grill" phrasing |
| `/handoff` | compacts the conversation into a handoff doc for the next agent |
| `/wait-what` | re-pitches a message that did not land, in Simplified Technical English |

**Best at:** the round trips you never have to spend. A plan pinned down before
implementation, or a handoff written once instead of re-derived by the next
session, is worth more than any output filter.
**Costs:** ~100 tokens of skill descriptions per session. Three of the four set
`disable-model-invocation: true`, so the model cannot fire them on its own.

Two things `agent-tools` handles:

- **`grilling` is mandatory.** `/grill-me` is a two-line stub that delegates to
  it. Installed alone it fires and dead-ends, so a partial pack is reported as
  **not installed**.
- **`skills add --skill 'a,b,c'` installs nothing and exits 0** — a comma list
  matches no skill. One flag per skill.

Full detail, including how to add the other 31 skills in that repo:
[SKILLS.md](SKILLS.md).

### context-mode

<https://github.com/mksglu/context-mode>. An MCP server plus six hooks
(`SessionStart`, `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `PreCompact`,
`Stop`). It sandboxes tool output, indexes it into a local SQLite FTS5 store,
and snapshots session state before a compaction so the following stretch
resumes with context instead of amnesia.

**Best at:** very long single sessions, and work that produces large tool
outputs you might need later but do not need *now*.
**Costs:** its MCP schema every session, plus a hook on nearly every tool call.
This is the heaviest of the default four.

**Requires Node >= 22.5.** On older Node it installs fine and then every hook
fails at runtime, which reads as a broken session rather than a version
problem — so `agent-tools` checks the version and skips it with an explanation
instead.

State lives in `~/.claude/context-mode/` (`sessions/`, `content/`) and **is
included in `agent-tools migrate export`.**

```bash
agent-tools install context-mode
agent-tools install context-mode --project   # plugin at project scope
# in a session:
/context-mode:ctx-doctor
ctx stats
```

### code-review-graph

<https://github.com/tirth8205/code-review-graph>. Opt-in. Tree-sitter parse
into SQLite, ~30 languages, 30 MCP tools, and a watch daemon.

**Best at:** large, fast-moving repos where staleness is the problem. The
entire build is local — no LLM, no bill — so `watch` or the daemon can keep it
current continuously. `dead-code`, `impact`, `flows` and `refactor` are
review-shaped commands graphify does not have.
**Costs:** 30 MCP tools is the largest per-session schema in this document.
Wire it per project, not everywhere.

```bash
agent-tools install code-review-graph
agent-tools wire code-review-graph          # this repo only; also builds the graph
agent-tools wire code-review-graph --watch  # + keep it current in the background
agent-tools unwire code-review-graph        # removes it and every trace (see below)
code-review-graph status                    # graph statistics
```

Its index lives in `.code-review-graph/` and `wire` adds a `.gitignore` rule —
it is rebuildable in seconds, so committing it is churn. `install` pulls it as
`code-review-graph[communities]`, so `igraph` comes with it and community
detection uses the Leiden algorithm rather than the slower file-based fallback.
Once wired, `agent-tools refresh` rebuilds this index alongside the graphify
graph (local AST parse, no LLM).

**`--watch`** wires the MCP server with `--auto-watch`, so it runs a filesystem
watcher in a background thread and keeps the graph current on every save. That
work is a **local parse — no LLM, no tokens, no per-session context cost** (the
watcher lives in the server process, not in Claude's context); the only cost is
a little background CPU. Off by default — the plain `wire` is a one-time build
that goes stale until the next `agent-tools refresh`. Without `--watch`, Claude
still refreshes the graph on demand: code-review-graph's own prompts have it
call `detect_changes` before a review.

**`unwire` leaves no residual trace.** It removes the MCP entry, deletes the
`.code-review-graph/` index, strips the `.gitignore` rule it added, drops the
repo from code-review-graph's global registry (`~/.code-review-graph`), and
regenerates the AGENTS.md block without the code-review-graph section. Any
background watch stops with the MCP server. `agent-tools uninstall
code-review-graph` does all of that first, then removes the binary.

### token-savior

<https://github.com/Mibayy/token-savior> (PyPI: `token-savior-recall`).
Opt-in. Symbol-level navigation plus a persistent memory engine with SQLite
WAL, FTS5 and vector embeddings. Upstream publishes strong benchmark numbers;
they are upstream's.

**Best at:** covering navigation *and* memory with one install — genuinely
attractive on a machine running `--memory=none`.
**Costs:** on a machine that already has claude-mem, half of it is a second
store recording the same sessions.

Two details `agent-tools` handles for you:

- **Extras must be re-specified on every install.** `[mcp]` is the server;
  `[memory-vector]` is `sqlite-vec` + `fastembed`. Without the second, it
  starts, prints "vector search disabled" to stderr, and quietly degrades to
  keyword-only recall. `agent-tools update token-savior` reinstalls with both
  named rather than running a bare upgrade.
- **`WORKSPACE_ROOTS` is pinned to the repo you wire it in.** Left unset it
  auto-discovers every project under your home directory — it found ten on the
  machine this was written on, including duplicates — and indexes all of them.
- **`wire` gitignores `.token-savior-cache.json`.** token-savior writes that
  per-repo cache into the repo root; it is rebuildable, so committing it is
  churn.

Unlike graphify and code-review-graph, token-savior has no snapshot to
rebuild — it indexes lazily through a file-watching daemon. So when it is wired,
`agent-tools refresh` **warms its daemon** (`ts daemon warm`) to make it re-read
the current code, rather than running a build step.

Also note **`ts` collides with moreutils' `ts`** timestamper. Use the full
`token-savior` name; `agent-tools` warns when the `ts` on your PATH is the
other one.

**Do not run `ts init` if you have rtk.** It adds **ten** hook entries to your
global `~/.claude/settings.json`, one of which is a `PreToolUse`/`Bash`
*command rewriter* — the same job rtk does. Two rewriters on one command is a
debugging problem, not a saving. `agent-tools wire token-savior` registers the
MCP server only, which does not need that hook; `doctor` flags the collision if
you installed it by hand. (Its CLI, `ts structure` and friends, needs a
registered project root and is a separate path from the MCP server — the MCP
side gets its root from the pinned `WORKSPACE_ROOTS`.)

```bash
agent-tools install token-savior
agent-tools wire token-savior           # this repo only, WORKSPACE_ROOTS pinned
```

Its store is `~/.local/share/token-savior/` and **is included in
`agent-tools migrate export`.**

---

## Scope: machine-wide or one project

Default is machine-wide. `--project` confines a tool to the repo you are
standing in.

```bash
agent-tools install rtk                 # hook in ~/.claude/settings.json
agent-tools install rtk --project       # hook in <repo>/.claude/settings.json
agent-tools install context-mode --project    # plugin at project scope
agent-tools install all --project       # everything, this repo only
```

**Binaries are still shared.** brew, uv and npm have no per-project form, so
`--project` changes *where the activation lands*, not where the executable
lives:

| | machine (default) | `--project` |
|---|---|---|
| rtk hook | `~/.claude/settings.json` | `<repo>/.claude/settings.json` |
| plugins | `--scope user` | `--scope project` |
| MCP entries | `-s local` (already per-project) | `-s local` |
| the executable | shared | shared |

### You cannot opt one repo out of a machine-wide tool

Claude Code **merges** user and project settings additively. A project file can
add a hook; it cannot cancel one `~/.claude/settings.json` already declares.
There is no negation, so `agent-tools uninstall rtk --project` on a machine
where rtk is installed machine-wide removes the project entry and changes
nothing observable. `agent-tools` prints that rather than reporting success.

Decide it at install time instead:

```bash
agent-tools install-machine --no-rtk     # never lands in ~/.claude/settings.json
cd ~/code/repo-that-wants-it
agent-tools install rtk --project        # only this repo
```

The same applies to plugins: a user-scope `superpowers` covers every repo, and
installing it again at project scope changes nothing — `agent-tools` says so
instead of pretending the flag did something.

---

## Updating

```bash
agent-tools update              # graphify + claude-mem + every installed tool + self
agent-tools update all          # same thing, explicit
agent-tools update tools        # only the optional tools
agent-tools update memory       # just claude-mem, and restart its worker
agent-tools update pocock       # just the skill pack
agent-tools update rtk          # one thing
agent-tools update crg          # aliases work: crg, ts, ctx, superpower
agent-tools update self         # git pull + ./install.sh in your checkout
```

`update` never installs something you do not already have — an update command
that quietly adds tools is not an update command. Per-tool footguns, and what
must be restarted afterwards, are in [UPDATING.md](UPDATING.md).

---

## Moving to another computer

`agent-tools migrate export` carries the **data** for every tool on this page —
rtk's savings history, context-mode's sessions, token-savior's store,
code-review-graph's registry — and deliberately not the binaries, which
reinstall. See [MIGRATION.md](MIGRATION.md).

```bash
agent-tools migrate export ~/move.tgz     # old machine
agent-tools migrate import ~/move.tgz     # new machine
agent-tools install-machine               # binaries + plugins back
agent-tools tools                         # confirm
```

---

## Platform support

| tool | macOS | Linux | WSL2 | Windows native |
|---|---|---|---|---|
| graphify | ✅ | ✅ | ✅ | ✅ |
| rtk | ✅ brew | ✅ install.sh | ✅ install.sh | ⚠️ cargo, or a release zip |
| superpowers | ✅ | ✅ | ✅ | ✅ |
| context-mode | ✅ | ✅ | ✅ | ✅ (Node >= 22.5) |
| code-review-graph | ✅ uv | ✅ uv | ✅ uv | ✅ uv |
| token-savior | ✅ uv | ✅ uv | ✅ uv | ✅ uv |
| claude-mem | ✅ | ✅ | ✅ | ✅ |
| caveman | ✅ | ✅ | ✅ | ✅ |
| pocock | ✅ | ✅ | ✅ | ✅ |

Every tool now installs on all four platforms (agentmemory, the one that used to
gap, was removed in 3.3.0). rtk was the last holdout: upstream's `install.sh`
does not cover native Windows, so there `agent-tools` downloads rtk's native
release binary automatically — which also names the repo rather than the
crates.io package, sidestepping the name collision — and falls back to `cargo
install --git` only when that download is unavailable. Everything else installs
through uv, npm or the Claude plugin system, all of which are platform-agnostic.

More: [PLATFORMS.md](PLATFORMS.md).
