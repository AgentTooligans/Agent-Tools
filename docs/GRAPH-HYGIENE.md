# Graph hygiene — keeping a knowledge graph honest

Everything here was learned by breaking a real 14,647-node graph and fixing it
(2026-07-29, `a data-generator project`). The specifics of that repo do not
matter; the failure modes recur in any project you point graphify at.

---

## The one fact that drives everything

**The graph is flat in time.**

Node fields are `id, label, type, source_file, source_location, community,
community_name, ecosystem, file_type, metadata, version`. There is **no date,
no mtime, no ordering**, and `version` was null on 14,644 of 14,647 nodes.
`built_at_commit` exists once, for the whole graph.

So a ruling from July 29 and a superseded draft from July 18 sit at **exactly
equal standing**. An agent querying the graph cannot tell which one won.

That is not a bug to file. It is a property to design around, and there are
exactly two levers:

| lever | mechanism | what it is good for |
|---|---|---|
| **Scope** | `.graphifyignore` (and `.gitignore`, which graphify honors) | archives, duplicates, generated mirrors |
| **Text** | a `STATUS:` banner in the document's own prose | anything you keep but that is not current |

The text lever works because extraction reads prose. Proof: a graph contained a
node labeled *"Scenario schema v2 (superseded)"* — it knew only because the
document said so.

### The banner

Put it directly under the title, so it survives chunking:

```markdown
> **STATUS: ARCHIVED 2026-07-18** — superseded by `docs/methods/schema-v3.md`.
> Historical record. Do not treat as current.
> Authority on any conflict: `docs/RULINGS.md`, `docs/DECISIONS.md`.
```

Three flavors worth distinguishing, because they mean different things:

- **`DECISION INPUT`** — a proposal that fed a decision but was not its outcome.
  A strong, checkable signal that a doc is an input: *no living document
  references it.*
- **`ARCHIVED DISCUSSION`** — evidence of *how* something was decided. Keep it;
  it holds rationale that exists nowhere else.
- **`ARCHIVED — external reference`** — imported from another project. Its
  cross-references will dangle, which is itself evidence for the label.

**Watch the link depth.** Relative links in a banner applied across nested
directories will silently break. Compute them per file and verify every one
resolves; a broken pointer to your authority document is worse than none.

---

## Failure modes, in the order they bite

### 1. Byte-identical duplicates

22 duplicate groups accounted for **4,897 nodes — 33% of the graph**. One
1.3 MB chat log existed twice and was extracted twice at 4,653 nodes each.

Duplicates are not merely wasteful. They **double a file's weight** in
clustering and community naming, so the graph's shape is decided by whatever
you happened to copy.

```bash
# find them: group by content hash, not by name
find . -name '*.md' -not -path './.git/*' -exec md5sum {} + | sort | uniq -w32 -d
```

Common sources: `RAW/`-style paste buffers, browser re-downloads (`foo (1).md`),
and the same spec mirrored into two directories. Keep the copy your living docs
cite; exclude the rest.

### 2. Oversized documents extract non-deterministically

The same 1.3 MB file produced **4,653 nodes on one run and 254 on the next** —
an 18× swing with no change to the file. Anything large enough to be chunked
across LLM calls will do this.

Consequences: run-to-run variance you cannot reason about, and a graph whose
composition is decided by one file's mood.

**Fix: split into topic files.** Cut at natural boundaries (conversation turns,
`##` sections — check which actually exist; in that transcript the `##` headings
were all inside one reply and useless as boundaries). Target a few hundred lines
each. Then **verify zero content loss by line-count diff**, not by eyeball.

Splitting also makes banners meaningful: one status line per topic instead of a
blanket label on a megabyte.

### 3. Junk hiding inside big files

That same transcript: **8,603 of 15,508 lines (55%) were empty scaffolding** —
turn markers with no text at all, a broken export tail. Real content was 3,963
lines.

The model was being handed thousands of empty exchanges. Before splitting or
excluding anything, **measure how much of a large file is actually content.**

```bash
# lines that are not blank, not separators, not bare markers
grep -vcE '^\s*$|^=+$|^#{1,6} (ME|CLAUDE)$' bigfile.md
```

### 4. Archives that mirror living documents

The graph held a 190-line snapshot of a ledger that had grown to 3,061 lines and
was seven days behind — sitting beside the live one with equal standing.

**A stale copy of a living document is the single most dangerous thing in a
graph**, because it is plausible and specific. Exclude snapshots of anything you
still maintain.

### 5. The node-count guard, and why not to force it

graphify refuses to overwrite a graph with a much smaller one:

> *new graph has 3341 nodes but existing graph.json has 14647. Refusing to
> overwrite.*

**This is the tool protecting you.** `--force` / `--allow-partial` is how you
lose a good graph to a partial run.

A refusal means one of:

- a chunk failed (see below) → fix and re-run;
- you deliberately changed scope → **re-base once**, on purpose, with a backup;
- extraction is unstable → fix that first, or you will force it forever.

The re-base: `graphify update . --force` after an intentional scope change gives
an honest baseline at the new scope. graphify writes a dated backup directory
before refusing — check it exists before you re-base.

### 6. Chunk timeouts

`chunk 23/26 failed: … timed out after 600.0 seconds` loses that chunk, which
makes the whole run partial, which trips the guard, which wastes the run.

`GRAPHIFY_API_TIMEOUT` (seconds, default 600) is the knob. `agent-tools
refresh --deep` and `scripts/graphify-full-run.sh` now default it to 1800.
A retry loop without this just hits the same wall on the same oversized chunk.

### 7. Warnings that look alarming but are not

```
RuntimeWarning: semantic cache skipped out-of-scope source_file 'x.py';
the file was not dispatched for extraction
```

The model attributed nodes to a file that was not in the chunk it was given.
graphify declines to cache them, and drops them from the graph. Noisy, benign,
and **not the cause** of a node-count collapse — do not go hunting there first.
Check duplicates and extraction stability instead.

---

## Diagnosing a graph that looks wrong

Node counts alone tell you nothing. Ask what the nodes *are*:

```python
import json
from collections import Counter
d = json.load(open('graphify-out/graph.json'))
c = Counter()
for n in d['nodes']:
    f = n.get('source_file') or ''
    c['code' if f.endswith('.py') else 'docs' if f.endswith('.md') else 'other'] += 1
print(c)

# and the top contributors -- this is where the surprise lives
files = Counter(n.get('source_file') or '' for n in d['nodes'])
for f, k in files.most_common(10):
    print(k, f)
```

In the real case this showed **code was 12.5% of its own knowledge graph** and
four files held 74% of it. That single view explained everything.

Also worth checking: files on disk vs files in the graph. Most "missing" docs
turned out to be inside a gitignored worktree clone — correctly skipped, not a
coverage gap.

---

## Commit the expensive part

`graphify-out/` is derived output with two exceptions that represent **hours of
LLM work**:

- `graphify-out/cache/semantic-deep/` (and `cache/semantic/`)
- `.graphify_labels.json` + its `.sig`

Commit those; ignore the rest. A fresh clone then rebuilds the graph at **zero
LLM cost**.

```gitignore
# NEVER write `graphify-out/` or `graphify-out/**` -- git will not descend into
# an excluded directory, which silently kills every negation below.
graphify-out/*
!graphify-out/cache/
graphify-out/cache/*
!graphify-out/cache/semantic/
!graphify-out/cache/semantic-deep/
```

**Negate BOTH namespaces.** `semantic/` (standard runs) and `semantic-deep/`
(`--deep`) are separate directories, and a rule covering only one silently drops
the other. Found in a live repo 2026-07-29: 296 `semantic-deep/` files tracked
while **162 `semantic/` files sat ignored** — the standard-mode extraction was
one `rm -rf` from gone while the deep-mode extraction was safe.

`cache/ast/` is deliberately NOT committed: it is regenerated locally in seconds
with no API cost.

**Negation rules only make files addable — they do not add them.** A repo was
found with exactly these rules, a comment explaining that the cache "IS
committed", and **zero cache files actually tracked**. 1.8 MB of extraction was
one `rm -rf` from gone. Verify:

```bash
git ls-files graphify-out/cache | wc -l     # expect > 0
```

Make `git add graphify-out/` reflexive after any deep run.

---

## The routine

1. `agent-tools refresh --code-only` — cheap, no LLM, after code changes.
2. `agent-tools refresh` — code + docs + community names.
3. `agent-tools refresh --deep --detach` — inferred edges; hours on a large
   corpus. Then **commit the cache**.
4. Check composition, not just the count, before trusting a rebuild.
5. New archive material → banner it or scope it out, the same day. The graph has
   no memory of what you meant.
