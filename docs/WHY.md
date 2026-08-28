# Why every default is what it is

This is the honest version of the story. Every rule Agent Tools enforces is
here, along with what went wrong that made us add it.

We wrote this for two reasons. The first is that a default you don't
understand is a default you'll eventually "fix" — and then rediscover the
problem yourself, painfully. The second is that most of these were genuinely
hard to spot, because the tools involved failed *quietly*. If you're ever
staring at something in here thinking "surely that's over-cautious", the
paragraph underneath will tell you what it cost us.

Entries are dated and roughly chronological. You don't need to read it front to
back — it's a reference, not a narrative.

This is the evidence behind `agent-tools`. Every rule it enforces is here with
the failure that produced it, so nobody has to rediscover them.

It was written during a Linux → macOS migration of one project on 2026-07-28,
then extended by real Linux and WSL2 testing on 2026-07-29. Project-specific
paths appear in places; the lessons are general.

**Start with [../README.md](../README.md).** Read this when something breaks, or
when you want to know why a rule is a rule.

---

## 1. What does not survive a machine move

| What | Symptom | Fix |
|---|---|---|
| **node / uv** | nothing runs at all | `brew install node uv` |
| **graphify CLI** | `graphify: command not found` | `uv tool install "graphifyy[gemini]"` |
| **Hook paths in `.claude/settings.json`** | hooks silently never fire | hooks must call bare **`graphify`**, never an absolute path |
| **`graphify-out/.graphify_python`** | every graphify run fails | repoint to this machine's uv interpreter |
| **agentmemory CLI** *(legacy — removed 3.3.0)* | `agentmemory: command not found` | nothing to do; use `agent-tools memory migrate-from-agentmemory` if a store remains |
| **`~/.agentmemory/bin/iii`** | engine won't start | a copied binary is the **wrong architecture** — delete it, it re-downloads |
| **`iii.pid` / `worker.pid` / `engine-state.json`** | `stop --force` may signal an unrelated process | delete; regenerated on start |
| **MCP servers + plugins** | tools missing in Claude Code | `claude mcp add` / `claude plugin install` |
| **Memory data** | 0 sessions, 0 observations | manual copy — see §3 |
| **API keys** | LLM backends unavailable | manual — see §4 |

`.graphify_python` and `.graphify_root` pin **absolute** machine-specific paths.
They were once committed alongside an otherwise-gitignored `graphify-out/`, so a
stale interpreter path travelled with the repo — which is exactly what broke
graphify in the 2026-07-28 move. **They are now deliberately gitignored** and
each machine writes its own. Verified 2026-07-29: 0 tracked in every repo here.

`.git/hooks/` is **never version controlled**, so the post-commit and
post-checkout hooks must be reinstalled per machine — that is what
`agent-tools init` does.

**Procedure, as opposed to this incident record:** [MIGRATION.md](MIGRATION.md)
lists every out-of-repo path, what to copy, what to reinstall, and how to rotate
keys.

---

## 2. graphify

### What it is

Parses the repo with tree-sitter into a queryable graph, clusters it into
communities, and answers questions by traversing structure instead of grepping.
As of 2026-07-28: **7,001 nodes / 13,023 edges / ~534 communities** —
code (3,479), documents (2,741), rationale (764), concepts (17).

Outputs in `graphify-out/`: `graph.json`, `GRAPH_REPORT.md`, `GRAPH_TREE.html`.

### The rule that governs cost: code never uses an LLM

This was verified empirically, not assumed. In `cli.py`:

```python
semantic_files = doc_files + paper_files + image_files   # code excluded
```

and the `--mode deep` branch builds its set from `("document", "paper", "image")`
only. Extraction runs with Opus, Sonnet, Haiku, and `--mode deep` all produced
**byte-identical** code graphs (156 nodes / 290 edges on the same input).

| you changed | command | LLM? | cost |
|---|---|---|---|
| **code** | `graphify update .` | never | ~1 min, free |
| **docs / images** | `graphify extract . --backend claude-cli` | yes, only changed files | minutes |
| **community names** | `graphify label .` | yes, ~6 calls | minutes |

**Use `label`, never `cluster-only`, to name communities.** `cluster-only`
re-clusters and, when the community set has shifted, renames every community
after its **hub node** rather than calling the LLM — it prints *"Run `graphify
label` to refresh names with the LLM"* and exits 0, so it looks successful. On
2026-07-28 this silently replaced 534 thematic names (*Billing Rules Engine*,
*Payment Retry Tests*) with hub names (*api_client.py*, *SessionCache*)
because semantic extraction had shifted the clustering 534 -> 280.

Corollary: **any run that changes the graph invalidates the labels.** Labels are
keyed to a clustering, so re-extract then re-label, in that order.

So: **code changes never need an LLM.** Doc changes do, but incrementally — the
per-file manifest plus a content+prompt-keyed cache mean editing one session note
dispatches one file, not the whole corpus.

### Backends

- `claude-cli` — uses the **Claude Code subscription**, no API key. Concurrency is
  **forced to 1**, so it is slow but free. Defaults to whatever model the CLI
  defaults to; override with `GRAPHIFY_CLAUDE_CLI_MODEL`.
- `gemini` — needs `GEMINI_API_KEY` (an AI Studio key; a Gemini *subscription*
  does not provide one). Runs 4-way parallel. Requires the `[gemini]` extra or it
  fails with *"the 'openai' package is required for this backend"*.
- There is **no** backend for a ChatGPT subscription or for Antigravity/`agy`.

**Install line (both extras + the version pin):**

```bash
uv tool install "graphifyy[gemini,mcp]" --with "mcp<2" --force
```

`mcp<2` is mandatory. graphify 0.9.29 does `from mcp.types import AnyUrl`, which
`mcp` 2.0.0 removed — and it catches that and reports *"mcp not installed. Run:
pip install graphifyy[mcp]"* when the package **is** installed. Without the pin
`graphify-mcp` never starts and the error message sends you the wrong way.

Measured on 3 docs (72 KB), same input:

| backend | nodes / edges | time | notes |
|---|---|---|---|
| claude-cli (Opus) | **111 / 134** | 6.5 min | created edges to files outside the input set |
| gemini flash | 12 / 11 | 13 sec | dropped 1 of 3 files entirely |
| gemini pro | — | — | free tier is `limit: 0` — flash-class only |

Claude is far richer for prose; Gemini flash is ~30× faster and sparse. Note that
work is **chunked** (~17 files per chunk), so cost scales with chunks, not files.

### Auto-update on commit

`.git/hooks/post-commit` runs `graphify update .` (code only, no LLM). Three
safety layers:

1. **gate file** — `.git/graphify-auto-update-ENABLED` **absent → skip**. `agent-tools
   init` creates it, so auto-update is ON after init; delete it to turn off.
2. **concurrency** — any graphify process running → skip
3. **detached** — `git commit` never waits

```bash
touch .git/graphify-auto-update-ENABLED   # enable (init already does this)
rm    .git/graphify-auto-update-ENABLED   # disable
tail  .git/graphify-auto-update.log       # what it did
```

**Why opt-in rather than a kill switch.** This started as an opt-OUT sentinel
(`.git/no-graphify-auto-update`). On 2026-07-28 that file vanished for reasons
never established, the hook silently re-enabled itself, and it re-clustered the
graph immediately after a commit. A guard whose *absence* means "run" turns
itself on through any accident. Inverted, a missing file means disabled — the
safe state. Do not flip this back.

The gate and log live under `.git/` deliberately: graphify owns
`graphify-out/`, so a sentinel stored there can be cleared by a rebuild.

### Keeping the graph current (use the script)

```bash
./scripts/graphify-refresh.sh              # full refresh, incremental
./scripts/graphify-refresh.sh --code-only  # AST only, zero LLM, ~1 min
./scripts/graphify-refresh.sh --check      # staleness report, changes nothing
./scripts/graphify-refresh.sh --no-label   # structure only, keep existing names
```

The script exists to enforce **one law**:

> **structure → labels → viz → verify.** Never label first.

It also refuses to run while another graphify process is active, and finishes
with a real query to prove the graph still answers.

**Why the order is not negotiable.** Labels are keyed to a *clustering*. Any run
that changes the graph re-clusters it, and communities that no longer match a
saved label get renamed after their hub node. Measured erosion from single runs:

| saved labels | communities after | hub-renamed |
|---|---|---|
| 536 | 535 | **501 (94%)** |
| 534 | 280 | **280 (100%)** |
| 280 | 271 | **137 (49%)** |

That is why `graphify update .` on its own quietly turns *Event Rules Engine*
back into *api_live.py*. The damage is cosmetic — nodes, edges and query results
are unaffected — and `graphify label .` repairs it in ~53 seconds.

**When to run it:** before you rely on the graph, not on a schedule. The failure
mode is not "slightly behind", it is a stale graph confidently answering with
code that no longer exists. Run it after a batch of work rather than after every
edit. A no-op refresh is free: graphify serves unchanged files from the
content-keyed cache (verified — *"535 files cached/unchanged, 0 re-extracted"*
with zero LLM calls), so you only pay for docs you actually edited.

`graphify check-update .` is the staleness probe. It is silent and exits 0 when
nothing is pending, which makes it safe for cron or a shell prompt.

### Upgrading graphify itself

```bash
uv tool install "graphifyy[gemini]" --force
./scripts/setup-dev-machine.sh --check      # confirm nothing came loose
```

**Not** plain `uv tool upgrade` — the `[gemini]` extra must be re-specified or
the gemini backend breaks again with *"the 'openai' package is required for this
backend"*.

**Upgrading can invalidate the committed semantic cache.** Entries are stamped
with the extraction prompt that produced them (upstream #1939), so a release
that changes that prompt turns all 1.6 MB into cache misses and costs a ~2-hour
re-extraction. Do not upgrade reflexively — upgrade when you have a reason (a
bug you are hitting, a feature you want) and can absorb a re-extraction window.

### Gotchas

- `graph.html` is skipped above **5,000 nodes**. Use `graphify tree` →
  `GRAPH_TREE.html`, which has no cap.
- `wiki` and `obsidian` ARE implemented — as `graphify export <format>`
  subcommands, not top-level flags. (An earlier version of this document said
  `--wiki` did not exist; that was wrong, and came from grepping only the
  top-level help.) Full list: `html`, `callflow-html`, `obsidian`, `wiki`,
  `svg`, `graphml`, `neo4j`, `falkordb`.
- The `hook-guard` PreToolUse hook is **advisory only** — it prints a nudge and
  exits. It never rebuilds anything, so it cannot conflict with a running job.

---

## 3. agentmemory — REMOVED IN 3.3.0

**This section is kept as the reason for the removal, not as instructions.**
`agent-tools` no longer installs, supervises, wires or updates agentmemory.
Everything below describes why, and remains accurate for anyone still running
one. The exit is one command, and it does not delete your data:

```bash
agent-tools memory migrate-from-agentmemory
```

### The store-location law (most important thing here)

In v0.9.28 the iii engine resolves its state path as **`./data/state_store.db`
relative to the working directory**. `AGENTMEMORY_DATA_DIR` and `--data-dir` are
documented but **not honored** — both were tested on 2026-07-28 and ignored.

Consequences:

- Launch it from a project folder and you silently get a **new, empty** memory
  store, plus a stray `data/` directory inside that repo.
- The LaunchAgent's `WorkingDirectory` (`~/.agentmemory`) is the *only* thing
  keeping one shared store. **Do not change it.**
- On another machine, the old store is wherever the server was launched from —
  **not** `~/.agentmemory`. Find it with:
  ```bash
  find / -type d -name state_store.db 2>/dev/null
  ```

### Migrating the store

**Stop the server first.** A running engine rewrites the session index while you
copy — that is how the 2026-07-28 migration lost its session list (observations
and memories survived; `mem:sessions.bin` was overwritten and had to be restored
from the source copy).

```bash
launchctl bootout gui/$(id -u)/com.agentmemory.server
cp -R /path/to/old/data/* ~/.agentmemory/data/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.agentmemory.server.plist
agentmemory status      # expect your real session/observation counts
```

The store files are JSON plus an **8-byte footer**: a 4-byte hash and a 4-byte
negative payload length. **Do not hand-edit them.** Rewriting session paths with
a corrected length but the original hash made the engine reject the file —
sessions and observations both read as 0 until the backup was restored.

### Old sessions keep the old machine's paths

Sessions record the `cwd` they ran in, and there is no supported update endpoint.
So after a move:

- `recall`, `session-history` — unaffected (no path filter)
- `/handoff` — filters by directory, but accepts a path override
- `/recap` — filters by directory, **no override**; will not see old sessions

### Scope

- **MCP server**: scoped to this project (`-s local`). A user-scope entry makes
  every `claude -p` subprocess boot a memory shim (~300 ms each) — pure waste for
  scripted fan-out like graphify's LLM backend.
- **Plugin hooks**: installed at user scope, so they fire in *every* project.
  Measured overhead: PostToolUse ~50–80 ms on every tool call, PreToolUse ~50 ms
  on Edit/Write/Read/Glob.
- **`--tools core` must be a server ARGUMENT.** The default `all` publishes 53
  MCP tools — **~5,918 tokens of schema in every session**. `core` is 8 tools,
  **~995 tokens**. Setting `AGENTMEMORY_TOOLS=core` in `~/.agentmemory/.env` had
  **no effect**, and neither did setting it in the MCP shim's environment; both
  were measured. It works only as `agentmemory --tools core`, i.e. in the
  LaunchAgent's `ProgramArguments`.

Measured MCP schema cost — this is carried in *every* session, so tool count
matters more than it looks:

| server | tools | per-session |
|---|---|---|
| agentmemory (`all`, default) | 53 | ~5,918 tokens |
| agentmemory (`--tools core`) | 8 | ~995 tokens |
| graphify-mcp | 10 | ~1,522 tokens |

graphify's MCP surface includes `get_pr_impact`, `list_prs` and `triage_prs` —
PR blast-radius analysis, which is normally cited as the reason to add a
*second* graph tool alongside it.

### Do not run `memory_heal` on a freshly restored store

Its job is to "clean up orphaned data." If the session index is missing or
mismatched, restored observations are exactly what it would classify as orphaned.

---

## 4. Secrets

Nothing migrates keys. graphify's gemini backend reads `GEMINI_API_KEY` from the
environment; keep it in `~/.config/graphify/env` (`chmod 600`) and source it.

Free-tier AI Studio keys are **flash-class only** — pro models return HTTP 429
with `limit: 0` for both request and token quotas.

---

## 5. Verification

```bash
agent-tools doctor
graphify query "how does session expiry work"
npx claude-mem status
agent-tools pocock status
```

Expected: graph present with node/edge counts, claude-mem's worker answering on
:37701, and all four pocock skills listed.


---

## 2026-07-29 — the graph has no sense of time

A real graph was found holding a 190-line snapshot of a ledger that had grown to
3,061 lines and was seven days behind, sitting beside the live one at equal
standing. Nodes carry no date and no ordering (`version` was null on 14,644 of
14,647), so nothing distinguished them.

Hence two defaults: `init` and `doctor` care about instruction-file hygiene and
duplicate sections, and the documented practice is **scope** (`.graphifyignore`)
plus **`STATUS:` banners in prose**, because prose is the only staleness signal
extraction can read. Full failure catalog: [GRAPH-HYGIENE.md](GRAPH-HYGIENE.md).

Also from that day: `GRAPHIFY_API_TIMEOUT` defaults to 1800s for deep runs. A
chunk that exceeds the 600s default is lost, which makes the run partial, which
trips the node-count guard, which wastes the entire run — and a retry loop
without the raised ceiling just hits the same wall on the same chunk.

---

## 2026-08-04 — an installer that succeeds and installs nothing

`rtk init -g` is documented as the way to wire rtk's Claude Code hook. Run
without a terminal — from a script, from CI, from another tool — it prints:

```
Patch existing /Users/<you>/.claude/settings.json? [y/N]
(non-interactive mode, defaulting to N)

  MANUAL STEP: Add this to /Users/<you>/.claude/settings.json:
```

…and **exits 0**. Anything driving it programmatically records a success. The
binary is installed, the hook is not, and the only evidence is text on stdout.
It also has no per-project form, and it appends an `@RTK.md` import to the
**global** `CLAUDE.md` — a machine-wide edit, made even when what you asked for
was one repo.

So `agent-tools` does not call it. It writes the same `PreToolUse`/`Bash` entry
itself, through a JSON edit that:

- refuses to touch a `settings.json` it cannot parse (that file is somebody's
  entire Claude Code configuration);
- is idempotent — a second run reports "already present" rather than stacking
  a duplicate hook;
- appends to an existing `Bash` matcher instead of replacing it, so a repo that
  already has `graphify hook-guard search` ends up with **both**;
- removes cleanly, leaving every unrelated hook in the file untouched.

Verified both directions on a settings file containing graphify's two hook
entries: adding rtk left them intact, removing rtk left them intact.

### The same day: two tools named `rtk`

crates.io ships an unrelated **Rust Type Kit** under the same binary name.
`rtk --version` prints a version for either one, so it is not a test. `rtk gain`
exists only on `rtk-ai/rtk`, which is what `doctor` checks. Homebrew core's
`rtk` formula is the right project (homepage `rtk-ai.app`). On native Windows,
where upstream's `install.sh` does not run, `agent-tools` downloads the release
binary straight from the `rtk-ai/rtk` repo (and the `cargo install --git`
fallback likewise names the repository), so neither route can resolve to the
wrong package.

Related, smaller, same shape as graphify's `[gemini,mcp]`: **token-savior's
extras are not remembered across an upgrade.** Without `[memory-vector]` it
starts, prints *"vector search disabled"* to stderr, and degrades to
keyword-only recall — working, quieter, worse. `agent-tools update` reinstalls
with the extras named rather than running a bare `uv tool upgrade`.

And one path detail with teeth: rtk's macOS config directory is
`~/Library/Application Support/rtk` — **it contains a space**. A `tar` line
that word-splits an unquoted path list turns that into three nonexistent
arguments and silently ships an archive without your savings history.
`migrate export` feeds tar a newline-delimited `-T` file for exactly this
reason.

### And: two Bash rewriters is not twice the saving

`ts init` (token-savior) offers to write **ten** hook entries into the global
`~/.claude/settings.json`. One of them is a `PreToolUse`/`Bash` command
rewriter — the same job rtk's hook does. Stacked, they are not additive: each
rewrites the command the other produced, and a command that returns something
unexpected now has two filters to bisect.

`agent-tools wire token-savior` therefore registers the MCP server and nothing
else; the server does not need that hook. `doctor` flags the pair if it is
already there, because the only way to end up with both is to have run
`ts init` by hand and not connected it to rtk.

(Unlike context-mode, which also hooks `PreToolUse`/`Bash`, this one genuinely
conflicts. context-mode routes the *result*; rtk and token-savior both rewrite
the *command*.)


---

## 2026-08-19 — removing a backend to delete a supervisor

agentmemory was a supported memory backend through 3.2.x. It is gone as of
3.3.0. The decision is worth recording because the cost was never the tool — it
was everything the tool forced this script to carry.

**One fact drove all of it:** the store path was relative to the server's
working directory (§3 above), and the documented overrides were inert. Keeping
one store therefore required pinning one working directory forever, which
required a supervisor, which produced:

- a launchd plist (macOS)
- a systemd `--user` unit (Linux/WSL)
- `loginctl enable-linger`, without which the server died at logout
- a `svc_install` / `svc_stop` / `svc_start` / `svc_describe` / `svc_check`
  layer in this script, ~120 lines whose entire job was those two files
- a `--tools core` LAW, because the argument form was the only one honored
  (env var and `.env` were both ignored) — the difference between 53 MCP tools
  ≈5,918 tokens per session and 8 ≈995
- a WSL reboot gap: WSL distros do not start when Windows starts, so systemd
  inside the distro was not running, so the memory server was not running
- **and a native-Windows blocker.** Upstream shipped no PowerShell/scoop/winget
  installer for the iii engine, and `agentmemory connect` was unsupported
  there. That single fact is why this project said "Windows = graphify only"
  for three minor versions.

claude-mem has none of these properties: absolute store path, its own worker,
no unit, no cwd trap, and it is plain Node so it runs anywhere Node does.

**What removal actually deleted:** the plist, the unit, the linger call, the
five `svc_*` functions, the cwd pinning, the `--tools core` law, an entire
`SERVICES.md` page of supervisor documentation — and the Windows caveat in
every table in this repo.

**What it did not delete: your data.** `~/.agentmemory` is untouched, `doctor`
still detects an install that is capturing (loudly, if claude-mem is capturing
too), `migrate export` still archives the store, and
`scripts/agentmemory-to-claude-mem.py` still converts it.

**The honest caveat:** the migration is one-way and lossy. claude-mem has no
ingest API, so the converter synthesises a transcript and feeds claude-mem's own
Stop hook — which **summarises on ingest**. The converted memories are
claude-mem's compression of yours. That is why the migration exports to Markdown
first and tells you to keep that export as the exact record. See
[MEMORY.md](MEMORY.md).

---

## 2026-08-19 — two silent no-ops in the `skills` CLI

Adding the `pocock` pack surfaced two failure modes that both **exit 0**, which
is the worst kind.

**1. `--skill` takes one name, and a comma list matches nothing.**

```
$ npx -y skills add mattpocock/skills --skill 'grill-me,grilling,handoff,wait-what' \
      --agent '*' -g -y
■  No matching skills found for: grill-me,grilling,handoff,wait-what
●  Available skills:
   - ask-matt
   ...
$ echo $?
0
```

It prints the repository's full catalogue and installs **nothing**, successfully.
The working form repeats the flag: `--skill a --skill b --skill c`.

**2. `skills update <name>` exits 0 for a skill that does not exist.**

```
$ npx -y skills update no-such-skill-xyz -g -y ; echo $?
0
```

So the exit code cannot be used to report an update. `agent-tools update pocock`
checksums `~/.agents/skills/<skill>/**` before and after and reports what
actually happened — changed, already current, or gone.

**And: `grill-me` is a stub with a hard dependency nothing enforces.**

Its entire body is *"Call the Skill tool with 'grilling'"*. `grilling` ships as
a **separate directory** in the same repo, so `--skill grill-me` alone installs
a skill that fires and dead-ends. `agent-tools` installs both and treats a
partial pack as **not installed**, because a pack whose entry point dead-ends is
broken rather than partially working.

---

## 2026-08-19 — an install script that skipped its own dependencies

`install.sh` copied `agent-tools` and two optional graphify helpers to
`~/.local/bin`, and stopped there. But `agent-tools` **shells out** to three
Python scripts it expects to find next to its own binary:

```
claude-mem-export.py          memory export + obsidian
memory-export.py              export from a legacy agentmemory server
agentmemory-to-claude-mem.py  the migration off agentmemory
```

None of them was installed. The result was a machine where
`agent-tools memory export` — and `agent-tools obsidian`, and the whole
migration path — failed with:

```
✗ claude-mem-export.py not found next to agent-tools
```

It went unnoticed because the developer machine had the files there from an
earlier manual copy, so the fallback `$(dirname "$0")/scripts/` never had to
work. Reproduced on 2026-08-19 with a clean `PATH` and a fresh install
directory. `install.sh` now copies all three and warns if the checkout is
missing any.


---

## 2026-08-19 — a restore that also littered your home directory

The manual migration instructions (Part 2 of [MIGRATION.md](MIGRATION.md)) built
the archive with two `-C` groups:

```bash
tar czf ~/agent-move.tgz \
  -C "$HOME"         .claude-mem .claude.json .config/graphify .config/agent-tools \
  -C "$HOME/.claude" CLAUDE.md RTK.md settings.json plans projects
```

That is correct, and it is the only way to pull files out of `~/.claude` without
the `.claude/` prefix riding along. But the **restore** was:

```bash
tar xzkf ~/agent-move.tgz -C "$HOME"          # <-- unpacks EVERYTHING
mkdir -p ~/.claude && tar xzkf ~/agent-move.tgz -C ~/.claude \
  CLAUDE.md RTK.md settings.json plans projects
```

The second group's members are stored under **bare names** — `CLAUDE.md`,
`plans/`, `projects/` — because that is what the second `-C` did. So the first,
unscoped extract dropped all five of them **loose into `$HOME`**, and the second
extract then put the correct copies in `~/.claude`. Net result: the right data,
plus `~/CLAUDE.md`, `~/RTK.md`, `~/settings.json`, `~/plans/` and `~/projects/`
as litter — the last two being a full copy of every session transcript in the
wrong place.

Verified 2026-08-19 by running the documented commands against a scratch profile
and listing what landed. The fix is to name the members on the first extract
too, which both the bash and PowerShell versions now do.

**`agent-tools migrate export` / `import` never had this bug.** It writes a
newline-delimited file list of full HOME-relative paths (`.claude/CLAUDE.md`,
not `CLAUDE.md`) and uses a single `-C`-free extract, so there is nothing to
mis-scope. Confirmed on the same scratch profile. This was a defect in the
hand-rolled fallback only — which is an argument for using the command.

## 2026-08-20 — a suppression comment that turned static analysis off entirely

`install_pocock` splits a newline-delimited list on purpose, so it carried a
suppression:

```bash
# shellcheck disable=SC2046  -- deliberate word splitting on a newline list
```

That line does not parse. ShellCheck expects `disable=SC2046` and nothing else;
the trailing `-- prose` makes it a malformed directive, and a malformed
directive is not a warning — it **aborts the whole file**:

```
agent-tools:1583:5: error: Couldn't parse this shellcheck directive. [SC1073]
agent-tools:1583:36: error: Expected '=' after directive key. [SC1072]
```

Two errors, zero warnings, exit non-zero. Read quickly, that looks like "one
tiny complaint about a comment". What it actually meant was that **not one line
of the 2,900-line script had been checked** for as long as the comment existed.
Moving the prose to its own line above the directive dropped six real warnings
out of hiding, one of which (`ls | grep -c`) was a genuine mis-count on
filenames.

**The law**: a directive line carries directives only. Prose goes above it.

`tests/bash/run-tests.sh` now greps for the malformed form directly, because
"shellcheck passes" and "shellcheck ran" are not the same claim, and only the
first one is visible in a CI log.

## 2026-08-20 — a scope flag that lied about what it did

`agent-tools install pocock --project` was accepted, printed nothing unusual,
and installed **machine-wide**. Same for `caveman`. The flag was silently
inert, and worse, `agent-tools unwire pocock` actively recommended it:

```
✗ pocock has no per-project MCP entry — it is a plugin
!  use: agent-tools install pocock --project
```

Both halves were wrong. pocock is not a plugin, it is a skill pack, and the
command being suggested does nothing per-project.

The underlying fact is that **skills have no project scope to select**. The
`skills` CLI writes either `~/.agents/skills` (with `-g`) or
`$PWD/.agents/skills` (without). The second is not a scope — no agent reads it.
It is a stray directory in whatever repo you were standing in, which is why
every skill command here runs from a throwaway temp directory in the first
place. So `install_pocock` hardcodes `-g`, correctly, and `--project` had
nothing to act on.

This is the same confusion that makes people expect `agent-tools init` to
install the skill packs. `init` is the per-project command; skills are one copy
for the whole machine, so they belong to `install-machine`. Nothing was broken —
but nothing said so, and the scope table in the README omitted pocock entirely,
leaving `init` as the only plausible place for it to happen.

Now: the flag says what it is doing, `unwire` classifies hook vs skill pack vs
plugin correctly, `agent-tools tools` prints the rule, and the README scope
table has the row it was missing.

**The general law**: a flag that cannot apply must say so. Accepting it and
doing something else is worse than rejecting it, because the user walks away
believing the scope changed.

## 2026-08-20 — `--purge` deleted the graph of the repo it was run in

Testing the new `uninstall all --purge` was done with a fake `HOME`, a stubbed
`PATH` and a throwaway store — but from the repo's own directory. `graphify`'s
data list includes the **per-repo** path:

```
<repo>/graphify-out      this repo's graph and semantic cache
```

which is exactly what a per-project path is supposed to mean. So `--purge`
deleted this project's `graphify-out/`. The two tracked files came back from
git; the graph and caches did not, and had to be rebuilt.

Nothing about the code was wrong. The test was wrong, in a way that fake `HOME`
does not protect against: **`HOME` isolation does not isolate the working
directory.** Any tool with per-project state has a second root, and `cd` is the
only thing that moves it.

Two changes came out of it:

* `tests/bash/run-tests.sh` refuses to run `agent-tools` with a cwd outside its
  own sandbox, exiting 99 rather than proceeding. A test that forgets to leave
  the repo now fails loudly instead of deleting real work.
* Both README and UPDATING.md carry the warning explicitly: `uninstall
  <tool> --purge` inside a repo deletes **that repo's** data.

**The law**: when a command has per-project and machine-wide effects, sandbox
BOTH roots, or do not run it.

## 2026-08-20 — a `--version` flag that starts a server

The first version of `agent-tools status` asked every tool for its version the
obvious way. For two of them that is fine. For the third:

```
$ token-savior --version
[token-savior] auto-discovered 20 project(s): Agent-Tools, a data-generator project-... 
```

It does not print a version. It boots the recall server, enumerates every
project on the machine, and blocks. `agent-tools status` inherited that and
hung past three minutes.

`uv tool list` answers for all three uv-installed tools in one fast call, so
that is what the inventory uses now, and a test asserts nothing ever probes
`token-savior --version` again.

The same shape, found the same way, one layer up: `plugin_installed` shelled
out to `claude plugin list` **twice per plugin**, which was invisible when three
commands called it and a multi-minute stall once the inventory called it for
every feature. It now reads the list once per process. Both fixes are the same
lesson — **a helper that was cheap when called three times is not automatically
cheap when called thirty.**

## 2026-08-20 — counting the wrong things

The first inventory reported `caveman  2/1 skills` and `pocock  24/4 skills`.

Both came from counting **directory entries** instead of **expected names**:

* `~/.agents/skills` is shared by every pack, so counting its entries counted
  all 24 skills on the machine and called them pocock's.
* `~/.agents/skills/caveman` is *one* skill's directory; counting the files
  inside it produced "2 of 1".

Now the count walks the list of skills the pack is supposed to install and
checks each by name — 13/13 and 4/4, which are the true answers. A number that
looks authoritative and is wrong is worse than no number.

## 2026-08-20 — MCP was never the requirement

The tools were wired as MCP servers because Claude Code was the first host, and
that quietly became the assumption: `init` added a server, `wire`/`unwire` only
knew the two opt-in ones, and every other agent got a paragraph of manual
instructions in a document.

Both halves of that were wrong.

**On cost.** An MCP server re-sends its entire tool schema **every session,
whether or not you call it**. graphify's is ~1.5k tokens; code-review-graph
ships 30 tools. The same questions are answerable from a CLI that costs
**nothing** until it runs:

```bash
graphify query "..."   graphify affected "..."   graphify god-nodes
code-review-graph query|impact|search            ts get|search|ctx
```

**On reach.** Codex, Antigravity, Cursor and Gemini do not read Claude Code's
MCP config and never will. They can all run a shell command. The MCP path was
simultaneously the most expensive one and the least portable one.

What was already right, and had simply not been named: the instruction block
`init` writes goes into **`AGENTS.md`**, the cross-agent standard, and contains
**no `mcp__` tool names** — it teaches the CLI. Every agent could already use
these tools; nothing said so.

So MCP is now explicitly the optional path:

* `agent-tools init --no-mcp` wires no server at all.
* `agent-tools wire|unwire graphify` toggles it per repo — previously graphify's
  server could be added by `init` but never removed by name.
* `agent-tools agents` detects the installed hosts and prints how each one gets
  the tools, including `graphify install --platform codex|antigravity|…`, which
  installs graphify's own **skill** rather than a server.

**The law**: pick the delivery mechanism by what it costs *per session*, not by
what the first host happened to support. A tool schema you are not using is
still a tool schema you are paying for.

## 2026-08-20 — flipping the MCP default

3.4.0 changed what `agent-tools init` does: it no longer wires graphify's MCP
server. `--add-mcp` opts a repo in.

The arithmetic is the whole argument. An MCP server re-sends its complete tool
schema **every session, whether or not it is called**. graphify's is ~1.5k
tokens. A repo where you ask two graph questions a week was paying that on
every session in between — and paying it again for `code-review-graph` (30
tools) and `token-savior` if those were wired too.

The CLI answers the same questions, from the same `graphify-out/graph.json`,
for **zero** standing cost. It is the same package: `uv tool install graphifyy`
installs `graphify` and `graphify-mcp` together, so wiring installs nothing and
unwiring removes nothing. The choice is purely which front door the agent uses.

**The MCP advantage is real and was weighed, not dismissed.** An agent that can
*see* a tool in its list reaches for it unprompted; a CLI has to be taught. But
the teaching already existed — the instruction block `init` writes into
`AGENTS.md` — and it costs roughly 40 tokens against 1,500. For a graph you
query constantly the server still earns its place, which is why `--add-mcp`,
`wire` and `unwire` are all per repo.

Two safeguards came with the flip:

* **`init` never removes a server you added.** It is idempotent and re-run
  routinely to pick up new hooks; a maintenance command that silently tore out
  configuration would be a trap. It reports `already wired here — left as-is`.
* **`doctor` stopped calling an unwired repo a problem.** It now reports `CLI
  mode (default, 0 tokens)`, because that is the recommended state, and a
  warning that fires on the correct configuration trains people to ignore
  warnings.

**The law**: choose a delivery mechanism by what it costs when you are *not*
using it. Anything charged per session is charged on the sessions where it
contributes nothing.

## 2026-08-20 — hardcoding a backend that most people don't have

`agent-tools refresh` passed `--backend claude-cli` to graphify on all three of
its LLM calls. On the machine it was written on, that was invisible: the Claude
CLI was installed, it needs no API key, and it bills against a subscription
that already existed.

On anyone else's machine it was a wall. No Claude CLI meant the semantic pass
failed, and the failure looked like a broken tool rather than a missing
dependency.

The part that makes this a genuine mistake rather than a missing feature:
**graphify already auto-detects a backend.** Its own help says so —
`--backend B  gemini|kimi|claude|openai|deepseek|ollama (default: whichever API
key is set)`. By passing an explicit `--backend` we were *overriding* working
detection. A user with `GEMINI_API_KEY` set had a perfectly good setup, and we
went out of our way to break it.

The fix restores the tool's own behaviour and adds a preference order on top:

1. `AGENT_TOOLS_BACKEND` / `GRAPHIFY_BACKEND` — an explicit choice always wins.
2. `claude-cli`, **only if the CLI is actually present**. Still the best default
   for people who have it, for the original reason: no key, no marginal cost.
3. Nothing at all — pass no `--backend` and let graphify detect from API keys.

Plus a preflight check. A semantic pass with no available model now refuses to
start and names the options, instead of dying partway through:

```
✗ no LLM backend available for the semantic pass

  The graph's STRUCTURE needs no model at all. This works right now:
        agent-tools refresh --code-only
```

`--code-only` was always the answer for a machine with no model, and nothing
said so.

**The law**: never pass an explicit flag where the tool already auto-detects,
unless you know something it doesn't. A default that hardcodes your own
environment is a default that only works for you.

## 2026-08-20 — an assistant is not a model

Two questions kept getting answered as if they were one:

* which **assistant** uses the graph (Claude Code, Codex, Antigravity, Cursor)
* which **model** builds it (claude-cli, gemini, openai, deepseek, kimi, ollama)

They are unrelated. Any assistant that can run a shell command can *use* a
graph. Very few subscriptions can *build* one — there is no `codex` backend in
graphify, and a ChatGPT or Antigravity subscription cannot drive the semantic
pass. What a Codex user normally has that does work is an `OPENAI_API_KEY`.

Conflating the two produced the hardcoded-backend bug above. Untangling them
turned up three failure modes worth knowing, each reproduced against a real
graphify rather than reasoned about:

1. **No backend at all.** Now refused before anything starts, with the options
   named. Previously it began work and died in the middle.
2. **A backend named explicitly with nothing behind it** — `AGENT_TOOLS_BACKEND=openai`
   and no key. This sailed straight past the first version of the guard, because
   an explicit choice was trusted completely. It is now trusted for *which*
   backend and verified for *whether it can run*.
3. **A key that is set but invalid.** Unknowable in advance — you only find out
   from the 401. graphify handles this exactly right: it reports the failure and
   **refuses to overwrite the graph with partial results**, which is the
   behaviour you want, since a half-written graph answers confidently and
   wrongly. All we add is a pointer to `--code-only` and a note that cached
   files make a retry cheap.

**The law**: separate "who is asking" from "who is answering". They have
different requirements and different failure modes, and a check that conflates
them will pass on the machine it was written on and fail everywhere else.
