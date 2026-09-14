# Keeping everything up to date

Every tool in this stack updates independently, and several of them have a
sharp edge in the upgrade path specifically. One of them can quietly cost you
hours if you upgrade it at the wrong moment.

The good news is there's one command that handles all of it and knows about the
sharp edges:

### Everything at once

```bash
agent-tools update              # everything INSTALLED: graphify + claude-mem
agent-tools update all          # + every optional tool + agent-tools itself
```

`update` and `update all` are the same thing; `all` is just the explicit form.

### A group

```bash
agent-tools update tools        # only the optional tools.
                                # Skips graphify, memory and agent-tools itself.
```

### One at a time

```bash
agent-tools update graphify
agent-tools update memory       # claude-mem + restart its worker
agent-tools update rtk
agent-tools update caveman      # plugin + global skills
agent-tools update pocock       # grill-me / grilling / handoff / wait-what
agent-tools update superpowers
agent-tools update context-mode
agent-tools update crg          # code-review-graph (alias)
agent-tools update ts           # token-savior (alias)
agent-tools update self         # git pull + ./install.sh in your checkout
```

Aliases work throughout: `crg`, `ts`, `ctx`, `superpower`. For the skill packs
you can also name a skill — `agent-tools update grill-me` updates the whole
`pocock` pack.

### What each scope covers

| you run | graphify | claude-mem | rtk / caveman / pocock / superpowers / context-mode | crg / token-savior | agent-tools itself |
|---|:--:|:--:|:--:|:--:|:--:|
| `update` / `update all` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `update tools` | — | — | ✅ | ✅ | — |
| `update <name>` | only that one | | | | |

Opt-in tools (`crg`, `token-savior`) are included in `all` and `tools` **only if
you already have them** — the rule below is absolute.

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
| claude-mem | `claude plugin update claude-mem@thedotmack --scope user` | **yes** — the worker |
| caveman | `npx -y github:JuliusBrussee/caveman --force` | **yes** — your agent session |
| pocock | `npx -y skills update <name> -g -y` (once per skill) | **yes** — your agent session |
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
claude plugin update claude-mem@thedotmack --scope user
npx claude-mem start                 # restart the worker afterwards
```

Its store (`~/.claude-mem/claude-mem.db` + Chroma index) is untouched by an
upgrade. Check afterwards with `agent-tools doctor`, which verifies the worker
is answering on :37701.

Close all Claude Code sessions before **uninstalling** — its own installer
warns that active hooks will recreate `~/.claude-mem` underneath you.

## agentmemory (removed in 3.3.0)

**There is nothing to update — the backend is gone.** `agent-tools update
memory` handles claude-mem only.

If this machine still has an agentmemory server from an older install,
`agent-tools doctor` will say so, loudly if it is capturing at the same time as
claude-mem. Retire it with one command, which **does not delete your data**:

```bash
agent-tools memory migrate-from-agentmemory
```

Why it was removed, and what the migration does step by step:
[MEMORY.md](MEMORY.md) and [WHY.md](WHY.md).

---

## pocock (grill-me · grilling · handoff · wait-what)

```bash
agent-tools update pocock
```

By hand — **one flag per skill**, a comma list silently installs nothing:

```bash
npx -y skills update grill-me  -g -y
npx -y skills update grilling  -g -y
npx -y skills update handoff   -g -y
npx -y skills update wait-what -g -y
```

`agent-tools` reports one of three outcomes, based on a checksum of the files
rather than the CLI's (meaningless) exit code:

```
✓ pocock skills already current (no change)
✓ pocock skills updated (files changed)
✗ after updating, these are gone: grilling
```

That last one matters: `grill-me` is a stub that delegates to `grilling`, so
losing `grilling` leaves you with a skill that fires and dead-ends. A partial
pack reports as **not installed**. Reinstall with `agent-tools install pocock`.

**Restart your agent afterwards.** Skills are read into the session index at
startup; an updated file on disk does nothing until the next session.

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

## Upgrading to 3.4.0 — MCP is now opt-in

**Behaviour change.** `agent-tools init` no longer wires graphify's MCP server.

```bash
agent-tools init              # no server. The agent uses the CLI.
agent-tools init --add-mcp    # the old behaviour, per repo
```

**Nothing you already have changes.** Existing wired repos keep their servers;
re-running `init` reports them and leaves them alone:

```
  ✓ graphify MCP already wired here — left as-is
        remove it with:  agent-tools unwire graphify
```

`doctor` no longer treats an unwired repo as a problem — it reports `CLI mode
(default, 0 tokens)`. `--no-mcp` is still accepted and now names the default.

### What you gain and what you give up

| | MCP server (`--add-mcp`) | CLI (default) |
|---|---|---|
| agent notices the tool unprompted | **yes** | only via the instruction block |
| cost per session | full schema, called or not (~1.5k tokens for graphify) | **zero** until run |
| works outside Claude Code | no | **yes** |
| same graph and answers | yes | yes |
| reversible | yes | yes |

The server's advantage is genuine — an agent that can see a tool uses it without
being reminded. It is simply not worth charging every session by default for a
capability most repos use occasionally, and it is useless to Codex and
Antigravity, which cannot read Claude Code's MCP config.

To restore the old behaviour everywhere:

```bash
for d in ~/code/*/; do
  ( cd "$d" && git rev-parse --git-dir >/dev/null 2>&1 && agent-tools init --add-mcp )
done
```

---

## Which version am I running?

```bash
agent-tools version            # the full picture
agent-tools version --short    # just the number, for scripts
agent-tools status             # every managed tool, with its version
./install.sh --version         # what a checkout would install, without doing it
```

`agent-tools version` prints **three dates, and they can all differ**:

```
agent-tools 3.3.1   (released 2026-08-20)
  installed  2026-08-20 13:14
             /Users/you/.local/bin/agent-tools
  source     /Users/you/code/Agent-Tools
             HEAD 13b5d5c  (2026-08-04 14:16)
```

| line | what it means | changes when |
|---|---|---|
| **released** | the version baked into the file that is running | you install a new release |
| **installed** | when `install.sh` last wrote your PATH copy | every `./install.sh` |
| **source** | your checkout's HEAD commit and its date | every `git pull` or commit |

The gap between them is the failure this exists to catch: **`git pull` alone
changes nothing.** The copy on your PATH is what runs, and it only changes when
`install.sh` runs. So `version` compares the two and says so outright:

```
  ! the copy on your PATH is 3.3.0, but this file is 3.3.1
  !     re-run ./install.sh from the checkout
```

It also warns when the checkout has uncommitted changes, and when the recorded
checkout has been moved or deleted.

`install.sh` announces the same thing before it acts, so you know what you are
about to put on your PATH:

```
installing agent-tools 3.3.1 (released 2026-08-20)
  replacing 3.3.0 at /Users/you/.local/bin/agent-tools
```

### Versions of everything else

```bash
agent-tools status
```

```
== Installed (9) ==
  ✓ code-review-graph   MCP      2.3.7
  ✓ token-savior        MCP      4.21.0
  ✓ rtk                 hook     0.45.0
  ✓ context-mode        plugin   1.0.169
  ✓ superpowers         plugin   6.2.0
  ✓ caveman             skills   13/13 skills, updated 2026-08-20 12:57
  ✓ pocock              skills   4/4 skills, updated 2026-08-20 12:57
  ✓ graphify            MCP      0.9.48
  ✓ claude-mem          memory   13.15.3

== Available (0) ==
  ✓ everything agent-tools manages is installed
```

Anything not installed is listed under **Available** with the exact command
that installs it, so the inventory is also the menu.

Three different version sources, because there is no common one:

* **uv tools** (graphify, code-review-graph, token-savior) come from one cached
  `uv tool list`. **Never** ask these for their own `--version`: `token-savior
  --version` does not print one — it boots the recall server, auto-discovers
  every project on the machine and blocks. That turned an early version of this
  command into a multi-minute hang.
* **Plugins** (superpowers, context-mode, claude-mem) come from one cached
  `claude plugin list`. That call takes seconds, so it is read once per process
  rather than once per plugin — the same mistake, found the same way.
* **Skill packs** have no version at all. A skill is markdown from a public
  repo, so the honest answer is how many of the expected skills are present and
  when they last changed. Count the **expected names**, never the directory
  entries: `~/.agents/skills` is shared by every pack.

`agent-tools status refresh` still gives the old per-repo graph-refresh view.

---

## Removing things

```bash
agent-tools uninstall <name>       # one tool
agent-tools uninstall all          # everything agent-tools installed
```

Names accepted: any tool (`rtk`, `superpowers`, `context-mode`, `caveman`,
`pocock`, `code-review-graph`, `token-savior`), plus `graphify`, `claude-mem`,
and `all`. Aliases work here too (`crg`, `ts`, `grill-me`, …).

### The tool and its data are two separate decisions

Before 3.3.1 every uninstall ended with a `store kept:` line and stopped there.
Safe, but nothing ever offered to clean up, so stores sat on disk forever.

Now the data is **named, sized and labelled** before you are asked, and the
default answer is **no**:

```
  ! removing token-savior would leave this behind:
        /Users/you/.local/share/token-savior  (412M)
            the recall store: memory engine plus vector index
            cannot be regenerated

  ? DELETE the data listed above? This cannot be undone. [y/N]
```

| flag | effect |
|---|---|
| *(neither)* | ask, defaulting to **keep** |
| `--purge` | delete **machine-wide** data without asking |
| `--purge-repo` | additionally include **this repo's** data (needs `--purge` too) |
| `--keep-data` | keep everything without asking |

### Why per-repo data needs its own flag

`--purge` deliberately does **not** delete anything whose path depends on your
working directory — a repo's `graphify-out/`, `.code-review-graph/`,
`.token-savior/`. Those rows are marked `[THIS REPO]` in the bill and skipped:

```
  ! kept (repo-scoped): /path/to/repo/graphify-out
  !     --purge covers machine-wide data only.
  !     add --purge-repo to include THIS repo's data.
```

The reason is an actual incident: `--purge` intended for a sandbox, run one
directory too high, deleted this project's graph. A machine-wide flag should
not have a per-directory blast radius. `--purge --purge-repo` opts in.

Setting both keeps the data. An ambiguous destructive command should not be
resolved in favour of destruction.

**Without a terminal, nothing is ever deleted.** A piped or CI invocation with
no `--purge` keeps everything and says so, rather than guessing.

### What is actually unregenerable

| path | what it is | rebuildable? |
|---|---|---|
| `~/Library/Application Support/rtk` (or `~/.config/rtk`) | `filters.toml` **and `history.db`** — your entire savings record | **no** |
| `~/.claude/context-mode` | indexed sessions, FTS5 knowledge base | **no** |
| `~/.local/share/token-savior` | recall store: memory engine + vector index | **no** |
| `~/.claude-mem` | every session claude-mem ever captured | **no** |
| `~/.config/graphify` | graphify config, including any API key | **no** |
| `<repo>/graphify-out` | that repo's graph and semantic cache | yes — but a deep re-run costs **hours** |
| `<repo>/.code-review-graph`, `<repo>/.token-savior` | that repo's parsed index | yes — rebuilt by re-wiring |

caveman, pocock and superpowers keep **nothing of yours**. A skill is markdown
from a public repo; reinstalling restores it byte for byte.

> **Per-repo paths are relative to where you are standing**, which is why
> `--purge` alone leaves them alone and `--purge-repo` is a separate opt-in.

### `uninstall all`

Shows the complete bill first — every feature, every path, every size — then
takes a **typed** confirmation, not a keypress:

```
  ? Type REMOVE to uninstall all of the above:
```

Anything other than `REMOVE` cancels and touches nothing. `--yes` skips the
typed prompt for automated teardowns; `--purge` and `--keep-data` still control
the data separately. Non-interactive without `--yes` refuses outright.

Only features that are actually present are listed, and each is removed through
the same code path as its individual `uninstall`, so the two cannot drift apart.

Afterwards: `agent-tools install-machine` puts it all back.

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

### How `update self` finds your checkout

`install.sh` copies the script to `~/.local/bin`, so at runtime the thing you
executed is the **copy** — it has no path back to the repo it came from. To
close that gap, `install.sh` records the checkout:

```
~/.config/agent-tools/config
    source_checkout=/path/to/Agent-Tools
```

`agent-tools update self` reads it, `git pull --ff-only`s there and re-runs
`install.sh`. Two consequences worth knowing:

* **A machine installed before this existed has no such line.** `update self`
  then says so and gives you the manual commands. Running `./install.sh` once
  from the checkout records the path and fixes it permanently.
* **Move or delete the checkout and `update self` falls back to the manual
  path**, because it verifies the recorded directory is still a git repo
  before using it. Re-run `install.sh` from the new location.

`--ff-only` is deliberate: a checkout with local commits or a diverged branch
fails loudly rather than being merged behind your back.

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

**`npx skills update` cannot be trusted to report failure** — it exits 0 even
for a skill that does not exist (verified 2026-08-19):

```bash
$ npx -y skills update no-such-skill-xyz -g -y ; echo $?
0
```

That is why `agent-tools update pocock` fingerprints the skill files before and
after instead of reading the exit code. See [SKILLS.md](SKILLS.md).

`agent-tools init` re-wires the MCP entries idempotently, so re-running it after
an update is safe and is the easiest fix if a server stops loading.

---

## Checking versions

```bash
agent-tools version
agent-tools doctor        # every component, plus what's wrong
agent-tools tools         # the optional tools, and what overlaps
graphify --version
npx claude-mem --version
agent-tools caveman status
agent-tools pocock status          # which of the four skills are present
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
