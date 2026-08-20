# Skills — small, cheap, surprisingly useful

A skill is just a markdown file with a bit of YAML at the top. That's the
entire format, and it's why skills are the cheapest thing in this stack: one
line of description sits in your assistant's context, and the body only loads
if you actually invoke it.

This page covers which skills come installed, what each one is for, what
they cost you, and the two places the skills CLI will quietly do nothing while
telling you it succeeded.

A **skill** is a markdown file with YAML frontmatter. That is the whole format.

This matters for one reason: **a skill is cheap and an MCP server is not.**

| | skill | MCP server |
|---|---|---|
| what loads at session start | `name` + `description` only — a line or two | the **full tool schema for every tool it exposes** |
| what loads on use | the body, when invoked | — (already loaded) |
| standing cost | ~20–40 tokens each | ~1k–6k tokens, **every session, whether or not you call it** |
| can it be "off"? | yes — `disable-model-invocation: true` means only you can fire it | no |

That asymmetry is why `agent-tools` installs two skill packs by default
(`caveman`, `pocock`) but makes `code-review-graph` — 30 MCP tools — opt-in.
Adding four skills costs about what one line of your `CLAUDE.md` costs. Adding
a third code-graph MCP server spends, every session, exactly the budget a graph
is supposed to save.

```bash
agent-tools tools        # what is installed
agent-tools doctor       # ...and whether it is actually wired
```

---

## Where they install, and why globally

Both packs install into **`~/.agents/skills`**, symlinked into each agent's own
skills directory (`~/.claude/skills`, and the equivalents for Codex, Copilot,
Cline and the rest).

That is deliberate. The Claude Code plugin route would reach Claude Code only,
and half the point of this repo is that the other agents get the same
treatment. The mechanism is the [`skills`](https://www.npmjs.com/package/skills)
CLI:

```bash
npx -y skills add <repo> --skill <name> --agent '*' -g -y
```

`-g` is what makes it global. **Without it the CLI writes
`$PWD/.agents/skills`** — literally into whatever repo you happened to be
standing in. `agent-tools` runs every skill command from a throwaway temp
directory so a mistake cannot land in your project.

### Skills have no `--project` form

`agent-tools install <tool> --project` confines a tool to one repo — it moves
where the hook, plugin or MCP entry lands. **It does not apply to skills**, and
this is not an oversight in the flag:

| tool type | what `--project` changes |
|---|---|
| hook (rtk) | writes to `<repo>/.claude/settings.json` instead of `~/.claude/` |
| plugin (superpowers, context-mode) | `--scope project` instead of `--scope user` |
| MCP (code-review-graph, token-savior) | already per-project; use `wire`/`unwire` |
| **skills (caveman, pocock)** | **nothing — always `~/.agents/skills`** |

The `skills` CLI has exactly two destinations: `~/.agents/skills` with `-g`, or
`$PWD/.agents/skills` without it. The second is not a project scope. No agent
reads it; it is just a stray directory in whatever repo you were standing in.
So there is nothing for `--project` to select.

Passing it anyway is not silently ignored — `agent-tools` says so and continues
machine-wide:

```
$ agent-tools install pocock --project
  ! pocock is a skill pack — it has no per-project form.
  !     installing machine-wide (~/.agents/skills) as usual.
```

The same is true of `wire`/`unwire`: a skill pack has no MCP entry to wire, and
asking for one tells you that rather than pointing you at a flag that will not
help.

**This is also why `agent-tools init` does not install skills.** `init` is the
per-project command — `.gitignore`, git hooks, graphify's MCP entry. Skills are
one copy for every repo on the machine, so they belong to `install-machine`:

```bash
agent-tools install-machine     # installs both packs as part of the defaults
agent-tools install pocock      # or just this one, any time
```

### Native Windows: `--copy`

The symlinks are the problem there. Creating one on Windows needs
Administrator or Developer Mode, and on a filesystem without symlink support
the install can appear to succeed while leaving the agent directories empty.

The CLI ships `--copy` for exactly this — real files instead of links.
`agent-tools` passes it automatically when `PLATFORM` is `windows`, and only
then; copies would otherwise drift out of sync with `~/.agents/skills` on the
platforms where links work.

By hand, on Windows:

```bash
npx -y skills add mattpocock/skills --skill grill-me --agent '*' -g -y --copy
```

The trade-off is that `agent-tools update pocock` updates
`~/.agents/skills`, and with copies the agent directories do **not** follow
automatically. On Windows, re-run `agent-tools install pocock` after an update
to refresh the copies.

---

## The `pocock` pack

Four skills from [mattpocock/skills](https://github.com/mattpocock/skills).
Installed by default; skip with `--no-pocock`.

| skill | what it does | how it fires |
|---|---|---|
| **`/grill-me`** | Interviews you one question at a time until every branch of a plan is resolved. Each question comes with a recommended answer, so you can agree fast or push back precisely. | you invoke it |
| **`grilling`** | The engine `/grill-me` delegates to. Works the plan as a **design tree**, asking the whole "frontier" — every decision whose prerequisites are already settled — in one numbered round, then waiting. | `/grill-me`, or the model on "grill" phrasing |
| **`/handoff`** | Compacts the current conversation into a handoff document for a fresh agent, written to your OS temp directory (not your repo). Includes a "suggested skills" section, and references specs/plans/commits by path instead of duplicating them. | you invoke it |
| **`/wait-what`** | Fire it the moment a message doesn't land. The agent re-pitches with the context you were missing, in ASD-STE100 Simplified Technical English, using the vocabulary from your `CONTEXT.md`. | you invoke it |

```bash
agent-tools pocock status
agent-tools install pocock
agent-tools update pocock
agent-tools uninstall pocock
```

### `grilling` is not optional

`/grill-me`'s entire body is:

> Call the Skill tool with "grilling".

It is a two-line stub. They ship as **separate directories** and nothing
upstream enforces the pairing, so `skills add ... --skill grill-me` on its own
gives you a skill that fires and immediately dead-ends.

`agent-tools` always installs both, and `pocock_installed` is all-or-nothing:
a partial install reports as **not installed**, because a pack with a
dead-ending entry point is broken, not partially working.

```
$ agent-tools tools
  ! pocock skills missing: grilling
```

### What the pack costs you

`grill-me`, `handoff` and `wait-what` all set `disable-model-invocation: true`
— the model **cannot** fire them on its own, so they are one description line
each and nothing more.

`grilling` does **not** set it, by design: it is what `/grill-me` delegates to,
and it also auto-fires when you use "grill" phrasing naturally. That is the one
skill in the pack the model can start on its own.

Total standing cost for all four: roughly **100 tokens per session**.

### Why these four and not the other 31

The repo ships 35 skills. These four are useful in any repo and carry no house
style with them. The rest — `tdd`, `code-review`, `to-spec`, `domain-modeling`,
`implement`, `prototype`, `research`, `triage` and friends — encode a specific
way of working, and several overlap `superpowers`, which is already a default
install.

That is a judgement about defaults, not about quality. Add any of them:

```bash
npx -y skills add mattpocock/skills --skill domain-modeling --agent '*' -g -y
npx -y skills add mattpocock/skills -l          # list all 35 first
```

---

## The `caveman` pack

Compresses what the agent **says back** to you. Separate document, because it
changes the texture of every reply and that deserves its own discussion:
[CAVEMAN.md](CAVEMAN.md).

```bash
agent-tools caveman status|install|update|uninstall
```

---

## Two traps in the `skills` CLI

Both were verified 2026-08-19 and both are silent, which is what makes them
worth writing down.

### 1. `--skill 'a,b,c'` installs nothing and exits 0

A comma-separated list is treated as **one skill name**. It matches nothing, so
the CLI prints the repository's full catalogue, installs nothing, and **exits
successfully**:

```
■  No matching skills found for: grill-me,grilling,handoff,wait-what
●  Available skills:
   - ask-matt
   ...
$ echo $?
0
```

Repeat the flag instead — this is the form `agent-tools` uses:

```bash
npx -y skills add mattpocock/skills \
    --skill grill-me --skill grilling --skill handoff --skill wait-what \
    --agent '*' -g -y
```

### 2. `skills update <name>` exits 0 for a skill that does not exist

```bash
$ npx -y skills update no-such-skill-xyz -g -y ; echo $?
0
```

So its exit status proves nothing, and reporting "updated" on the strength of
it would be a lie. `agent-tools update pocock` **fingerprints the skill files
before and after** (a checksum over `~/.agents/skills/<skill>/**`) and
distinguishes the three outcomes that actually matter:

```
✓ pocock skills already current (no change)
✓ pocock skills updated (files changed)
✗ after updating, these are gone: grilling
```

---

## Updating

Skills are covered by the ordinary update commands:

```bash
agent-tools update all       # everything, skills included
agent-tools update tools     # the optional tools, skills included
agent-tools update pocock    # just this pack
agent-tools update caveman   # just that one
```

`update` never installs a pack you don't already have — it reports it and moves
on. Full matrix: [UPDATING.md](UPDATING.md).

---

## Adding your own

Any repo with `SKILL.md` files works:

```bash
npx -y skills add <owner>/<repo> -l                       # see what's in it
npx -y skills add <owner>/<repo> --skill <name> --agent '*' -g -y
```

Run it from a directory you don't care about, or pass `-g` and mean it —
without `-g` the skills land in `$PWD/.agents/skills`.

To write one, `superpowers:writing-skills` covers the house rules, or copy the
shape of any file under `~/.agents/skills/`. The frontmatter fields that matter:

```yaml
---
name: my-skill
description: One line. This is what loads every session — make it earn its tokens.
disable-model-invocation: true   # optional: only the user can fire it
argument-hint: "What should this focus on?"   # optional
---
```

`description` is the only part with a permanent cost, so it should say **when to
use this**, not what it is. That sentence is the entire basis on which the model
decides whether to invoke it.
