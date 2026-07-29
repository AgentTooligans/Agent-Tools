
<!-- agent-tools:managed -->
## Codebase knowledge (graphify)

Before grepping or reading files broadly, ask the graph:

    graphify query "<question>"        # scoped subgraph, cheap
    graphify affected "<symbol>"       # blast radius before refactoring
    graphify god-nodes                 # what is risky to touch at all

The graph covers code structure, docs and concepts. It does NOT index
string-level details (CSS variables, literals) — use grep for those.
If the graph looks stale, run `agent-tools refresh`.

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
