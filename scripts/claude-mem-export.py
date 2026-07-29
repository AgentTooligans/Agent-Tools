#!/usr/bin/env python3
"""
Export claude-mem's memory to Markdown notes (Obsidian-friendly).

WHY THIS EXISTS
    claude-mem has no export command. Its memory lives in SQLite + a Chroma
    vector index at ~/.claude-mem, readable only through its own recall path.
    That is fine for an agent and useless for a human -- and it breaks the
    "one central vault" model, where the vault is supposed to hold BOTH the
    codebase structure (graphify's Obsidian export) and the reasoning behind
    it. Without this, a claude-mem user gets structure and nothing else.

    agentmemory has `memory-export.py`; this is its claude-mem counterpart, so
    `agent-tools memory export` and `agent-tools obsidian` behave the same on
    either backend.

WHAT IT READS (read-only, never writes to the store)
    session_summaries  one row per summarized session: request, investigated,
                       learned, completed, next_steps, notes
    sdk_sessions       the project a session belonged to (summaries often
                       carry an empty project; the session row is the truth)
    observations       finer-grained notes captured during a session
    user_prompts       what was actually asked

USAGE
    claude-mem-export.py OUTDIR [--project NAME] [--db PATH]
"""

import argparse
import os
import re
import sqlite3
import sys
from collections import defaultdict
from datetime import datetime, timezone

# --- front-matter-safe helpers ---------------------------------------------


def slug(text, maxlen=60):
    """Filesystem- and wiki-link-safe name. Obsidian chokes on / : # ^ [ ] |."""
    text = re.sub(r"[\\/:#^\[\]|*?\"<>]+", " ", str(text or ""))
    text = re.sub(r"\s+", " ", text).strip()
    return (text[:maxlen].rstrip(" .") or "untitled")


def yaml_str(text):
    """Quote a scalar for YAML front matter without pulling in a dependency."""
    return '"' + str(text or "").replace("\\", "\\\\").replace('"', '\\"') + '"'


def when(row_iso, row_epoch):
    """claude-mem stores both an ISO string and epoch ms. Prefer the ISO."""
    if row_iso:
        try:
            return datetime.fromisoformat(str(row_iso).replace("Z", "+00:00"))
        except ValueError:
            pass
    if row_epoch:
        try:
            return datetime.fromtimestamp(int(row_epoch) / 1000, tz=timezone.utc)
        except (ValueError, OSError):
            pass
    return None


def section(title, body):
    """Emit a Markdown section, or nothing at all when the field is empty.

    claude-mem leaves fields as NULL or the literal string 'None' depending on
    the path that wrote them, and empty headings make the notes unreadable.
    """
    body = (body or "").strip()
    if not body or body == "None":
        return ""
    return f"## {title}\n\n{body}\n\n"


def file_list(title, raw):
    """files_read / files_edited arrive as a delimited string, or 'None'."""
    raw = (raw or "").strip()
    if not raw or raw == "None":
        return ""
    parts = [p.strip() for p in re.split(r"[,\n;]+", raw) if p.strip()]
    if not parts:
        return ""
    out = f"## {title}\n\n"
    for p in parts:
        out += f"- `{p}`\n"
    return out + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("outdir", help="directory to write notes into")
    ap.add_argument("--project", help="export only this project")
    ap.add_argument("--db", help="path to claude-mem.db")
    args = ap.parse_args()

    db = args.db or os.path.join(
        os.environ.get("CLAUDE_MEM_DATA_DIR", os.path.expanduser("~/.claude-mem")),
        "claude-mem.db",
    )
    if not os.path.exists(db):
        print(f"no claude-mem store at {db}", file=sys.stderr)
        return 1

    # Read-only URI: an export must never be able to mutate the live store,
    # and claude-mem's worker may be writing to it concurrently.
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    con.row_factory = sqlite3.Row

    # Summaries often carry project='' -- claude-mem stamps the project on the
    # session row, so resolve through the join and fall back to the summary.
    rows = con.execute("""
        SELECT s.*,
               COALESCE(NULLIF(s.project, ''), NULLIF(k.project, ''), '') AS proj
          FROM session_summaries s
          LEFT JOIN sdk_sessions k ON k.memory_session_id = s.memory_session_id
         ORDER BY s.created_at_epoch
    """).fetchall()

    obs = defaultdict(list)
    try:
        for o in con.execute("SELECT * FROM observations ORDER BY id"):
            key = o["memory_session_id"] if "memory_session_id" in o.keys() else None
            obs[key].append(o)
    except sqlite3.Error:
        pass                       # observations table is optional

    os.makedirs(args.outdir, exist_ok=True)
    written, by_project = 0, defaultdict(list)
    # Several sessions a day can share a request line (retries, resumed work,
    # replayed transcripts). Without this, note N+1 silently OVERWRITES note N
    # and the index shows the same wiki-link twice -- 13 rows produced 8 files
    # before this was added.
    used = {}

    for r in rows:
        proj = r["proj"] or "unfiled"
        if args.project and proj != args.project:
            continue

        ts = when(r["created_at"], r["created_at_epoch"])
        date = ts.strftime("%Y-%m-%d") if ts else "undated"
        title = slug(f"{date} {(r['request'] or 'session')[:70]}")
        # A session id is NOT enough to disambiguate: claude-mem writes several
        # summaries per session (one per prompt), so those share both the
        # request line and the id. Count up until the name is genuinely free.
        if title in used:
            # Append AFTER slugging. Re-slugging "base (2)" truncates it back to
            # `base` (slug caps length), so the candidate was never free and the
            # loop span forever -- caught by a 3-minute hang, not by review.
            base, n = title, used[title]
            while True:
                n += 1
                candidate = f"{base} ({n})"
                if candidate not in used:
                    break
            used[base] = n
            title = candidate
        used[title] = used.get(title, 1)
        path = os.path.join(args.outdir, f"{title}.md")

        body = "---\n"
        body += f"title: {yaml_str(title)}\n"
        body += f"project: {yaml_str(proj)}\n"
        body += f"date: {date}\n"
        body += f"session: {yaml_str(r['memory_session_id'])}\n"
        body += "source: claude-mem\n"
        body += f"tags: [agent-memory, claude-mem, {slug(proj, 40).replace(' ', '-')}]\n"
        body += "---\n\n"
        body += f"# {title}\n\n"

        body += section("Request", r["request"])
        body += section("Investigated", r["investigated"])
        body += section("Learned", r["learned"])
        body += section("Completed", r["completed"])
        body += section("Next steps", r["next_steps"])
        body += section("Notes", r["notes"])
        body += file_list("Files read", r["files_read"])
        body += file_list("Files edited", r["files_edited"])

        mine = obs.get(r["memory_session_id"], [])
        if mine:
            body += "## Observations\n\n"
            for o in mine:
                keys = o.keys()
                text = next((o[c] for c in ("content", "text", "observation", "body")
                             if c in keys and o[c]), None)
                if text:
                    body += f"- {str(text).strip()}\n"
            body += "\n"

        body += f"---\n\n_Exported from claude-mem. Project: [[{slug(proj)}]]_\n"

        with open(path, "w", encoding="utf-8") as fh:
            fh.write(body)
        written += 1
        by_project[proj].append((date, title))

    # One index, grouped by project, newest first -- the vault entry point.
    idx = "# Memories (claude-mem)\n\n"
    idx += f"_Exported {datetime.now().strftime('%Y-%m-%d %H:%M')} — "
    idx += f"{written} note(s) from {len(by_project)} project(s)._\n\n"
    idx += "> A snapshot for humans. Agents recall from the live claude-mem\n"
    idx += "> store, not from these notes.\n\n"
    for proj in sorted(by_project):
        idx += f"## {proj}\n\n"
        for date, title in sorted(by_project[proj], reverse=True):
            idx += f"- {date} — [[{title}]]\n"
        idx += "\n"
    with open(os.path.join(args.outdir, "INDEX.md"), "w", encoding="utf-8") as fh:
        fh.write(idx)

    con.close()
    print(f"wrote {written} note(s) + INDEX.md to {args.outdir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
