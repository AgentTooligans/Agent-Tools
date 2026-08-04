# caveman — cutting output tokens

[github.com/JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) ·
MIT · installed by default, `--no-caveman` to skip.

## Why it is here

Every other tool in the default set attacks something the agent **reads**:
graphify answers "where does this live?" from a graph instead of ten file
reads, the memory backend keeps you from re-deriving a decision you already
made, rtk filters what shell commands return, and context-mode keeps a
compaction from erasing the session. None of them changes what the agent *says
back* — and on a long session, output is a large share of the spend, because
every reply is re-read as context by the next turn.

caveman owns that row alone. (Which row belongs to which tool:
[TOOLS.md](TOOLS.md).) It is a **skill**: instructions telling the agent to
drop filler, hedging and pleasantries while keeping technical substance exact
and code verbatim. Upstream measures ~65% fewer output tokens. That is *their*
number on their workload — we have not independently measured it, and neither
`agent-tools` nor this doc claims it.

It is also the cheapest component here to reverse. It runs no service, opens no
port, stores no data. It is text an agent reads. Turning it off is one command,
and nothing else in your setup notices.

> **It is not a compression algorithm.** Nothing is encoded or decoded. The
> agent is simply asked to be terse. Quality depends on the model honoring that,
> which is why levels exist — see below.

## What actually gets installed

Two steps, because one does not cover everything:

| step | what | where |
|---|---|---|
| caveman's own installer | Claude Code **plugin** + SessionStart / UserPromptSubmit hooks | `~/.claude/plugins/` |
| `skills add -g` | **global skills** symlinked into every other agent | `~/.agents/skills/caveman*` |

The hooks are what make it apply **from message one**, rather than only after
you type `/caveman`. They write a small flag file, `~/.claude/.caveman-active`,
holding the active level.

### Why step 2 is not redundant

caveman's installer does not pass `-g` to the skills CLI, so for non-Claude
agents it installs **project-scoped**, into `$PWD/.agents/skills`. Verified
2026-07-29: running it dropped skills into the current working directory. That
means running it from a temp directory throws the install away, and running it
from a repo litters that repo.

So `agent-tools` always runs it **from a neutral directory** and adds the
explicit global install. Two agents — Eve and PromptScript — reject global scope
by design; they are the only ones that stay project-only.

## Using it

```
/caveman              # switch on at the default level (full)
/caveman lite         # gentle
/caveman ultra        # aggressive
/caveman wenyan       # classical-Chinese-style extreme compression
/caveman off          # stop

/caveman-commit       # conventional commit, <= 50 chars
/caveman-review       # one-line PR comments
/caveman-stats        # upstream's savings estimate
/caveman-compress F   # rewrite a memory/context file smaller
```

From `agent-tools`:

```bash
agent-tools caveman status      # installed? active? at what level?
agent-tools install caveman        # (agent-tools caveman install still works)
agent-tools caveman update
agent-tools caveman uninstall
```

`agent-tools doctor` reports the same state, including whether the global skills
are present — without them, only Claude Code has caveman.

## The trade-off, stated plainly

Terse replies lose things. Nuance, caveats, the sentence that would have told
you *why* a fix works. On `ultra` and `wenyan` that is very noticeable, and
"technical accuracy preserved" is a claim about facts, not about how much
context you get around them.

That is a real cost, and whether it is worth it depends on the work. Debugging
something subtle, you probably want prose. Grinding through mechanical edits,
terse is fine and cheaper.

Practical guidance:

- **`lite`** is the safe default if you read replies carefully.
- **`full`** is the upstream default and what a fresh install activates.
- **`ultra` / `wenyan`** are for bulk work where you mostly care that it ran.
- The level is per-session and sticky — it persists in `.caveman-active` until
  changed, so a level you set once keeps applying to new sessions.

**It does not change code, commits, or file contents** — only how the agent
talks to you. Your project's own copy rules (a house style for user-facing
strings, say) are untouched, because those live in the files being edited.

## Caveats worth knowing

- **It applies everywhere, not per project.** The plugin and global skills are
  user-level. There is no per-repo on/off switch beyond typing `/caveman off`.
- **Node >= 18 required.** `agent-tools` skips caveman with a warning rather
  than failing the whole install if Node is missing or old.
- **Installed from GitHub via `npx`**, not a pinned npm version, so an update
  takes whatever `main` holds. `agent-tools caveman update` re-runs that.
- **Restart the agent after install or uninstall.** Hooks are read at session
  start; an already-running session keeps its old behavior.
- Upstream states no telemetry after installation. The skills CLI it delegates
  to has its own `--metadata` telemetry flag, which `agent-tools` does not use.

## Removing it

```bash
agent-tools caveman uninstall     # both halves, then restart your agent
```

Or skip it at install time:

```bash
agent-tools install-machine --no-caveman
```

Removal leaves nothing behind that other tooling depends on — graphify and the
memory backend never reference it.
