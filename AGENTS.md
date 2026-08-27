
<!-- agent-tools:managed -->
## Codebase knowledge (graphify)

Before grepping or reading files broadly, ask the graph:

    graphify query "<question>"        # scoped subgraph, cheap
    graphify affected "<symbol>"       # blast radius before refactoring
    graphify god-nodes                 # what is risky to touch at all
    graphify path "<A>" "<B>"          # how two things connect
    graphify explain "<concept>"       # one concept, focused

If graphify-out/wiki/index.md exists, use it to navigate broadly. Read
GRAPH_REPORT.md only for whole-architecture review — it is large.

The graph covers code structure, docs and concepts. It does NOT index
string-level details (CSS variables, literals) — use grep for those.
If the graph looks stale, run `agent-tools refresh`.

## Code review (code-review-graph)

For review- and impact-shaped questions, prefer code-review-graph:

    code-review-graph query "<question>"    # scoped review context
    code-review-graph impact "<symbol>"     # what a change ripples into
    code-review-graph search "<text>"       # semantic node search

It overlaps graphify — navigate with graphify, frame a review with this.

## Symbol lookups (token-savior)

For a symbol's source without reading whole files:

    ts get "<symbol>"      # source of a function/class
    ts search "<regex>"    # regex search across code
    ts ctx "<symbol>"      # source + dependencies + callers

## Memory

Past sessions are searchable through the memory backend. Recall before
re-deriving an earlier decision, and save durable decisions explicitly.
Memory is for decisions and rationale; the graph is for what the code *is*.

## Keep this file lean

This file is read into context on EVERY session, so its size is a permanent
tax on every request. Keep it to things that do not fit anywhere else:

- build / test / lint / run commands
- hard constraints and invariants that must never be violated
- pointers to where the real documentation lives

Do NOT put here: session logs, changelogs, status updates, narrative history,
lists of what was done and when, or anything that reads like a diary. Those
belong in the memory backend (decisions, rationale) or in docs/ (long-form).
If a section is growing over time rather than being edited, it belongs
somewhere else.
<!-- /agent-tools:managed -->
