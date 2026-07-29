#!/usr/bin/env python3
"""Export agentmemory's curated memories to portable Markdown.

Why this exists
---------------
Memory backends do not interoperate. agentmemory stores iii-engine KV files;
claude-mem stores SQLite + Chroma. Neither imports the other, so "migrating"
between them is not a database problem — it is a text problem.

The good news is that the volume is small. A store with thousands of
observations typically holds only tens of *memories*: observations are raw
session capture that ages out, memories are the curated decisions worth
keeping. Exporting those to Markdown gives you something that outlives any
tool, reads fine in Obsidian, and can be pasted into a new backend's session so
it captures them natively.

Usage
-----
    memory-export.py                          # -> ./agentmemory-export/
    memory-export.py --out ~/vault/memories   # e.g. an Obsidian vault
    memory-export.py --single-file            # one file instead of one per memory
    memory-export.py --url http://host:3111
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone


def fetch(url: str, path: str, limit: int = 1000):
    req = urllib.request.Request(f"{url}/agentmemory/{path}?limit={limit}")
    secret = os.environ.get("AGENTMEMORY_SECRET", "").strip()
    if secret:
        req.add_header("Authorization", f"Bearer {secret}")
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.loads(r.read().decode("utf-8", "replace"))
    if isinstance(data, list):
        return data
    for key in ("memories", "results", "items", "lessons", "insights"):
        if isinstance(data.get(key), list):
            return data[key]
    return []


def slug(text: str, n: int = 60) -> str:
    """Filename-safe stem. Obsidian dislikes : / \\ | # ^ [ ] in names."""
    text = re.sub(r"[:/\\|#^\[\]]+", " ", str(text or "untitled"))
    text = re.sub(r"\s+", "-", text.strip()).strip("-").lower()
    return (text[:n] or "untitled").rstrip("-")


def when(value) -> str:
    if not value:
        return ""
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00")).strftime("%Y-%m-%d")
    except Exception:
        return str(value)[:10]


def as_note(m: dict) -> str:
    """One memory as a Markdown note with YAML front matter.

    Concepts become Obsidian tags AND wiki-links, so the vault's graph view
    connects memories that share a concept without any extra tooling.
    """
    title = str(m.get("title") or "Untitled").strip()
    concepts = [c for c in (m.get("concepts") or []) if c]
    files = [f for f in (m.get("files") or []) if f]

    fm = [
        "---",
        f'title: "{title.replace(chr(34), chr(39))}"',
        f"created: {when(m.get('createdAt'))}",
        f"updated: {when(m.get('updatedAt'))}",
        f"type: {m.get('type') or 'memory'}",
        f"strength: {m.get('strength', '')}",
        f"source: agentmemory",
        f"id: {m.get('id','')}",
    ]
    if concepts:
        fm.append("tags:")
        fm += [f"  - {slug(c, 40)}" for c in concepts]
    fm.append("---")

    body = [
        "",
        f"# {title}",
        "",
        str(m.get("content") or "").strip(),
        "",
    ]
    if concepts:
        body += ["## Concepts", "", " · ".join(f"[[{c}]]" for c in concepts), ""]
    if files:
        body += ["## Files", ""] + [f"- `{f}`" for f in files] + [""]
    return "\n".join(fm + body)


def main() -> int:
    ap = argparse.ArgumentParser(description="Export agentmemory memories to Markdown")
    ap.add_argument("--url", default=os.environ.get("AGENTMEMORY_URL", "http://localhost:3111"))
    ap.add_argument("--out", default="agentmemory-export")
    ap.add_argument("--single-file", action="store_true",
                    help="one combined file instead of one note per memory")
    args = ap.parse_args()

    try:
        memories = fetch(args.url, "memories")
    except urllib.error.URLError as e:
        print(f"cannot reach agentmemory at {args.url}: {e}", file=sys.stderr)
        print("is the server running?  agent-tools doctor", file=sys.stderr)
        return 1

    # Lessons and insights are also curated; include them when present.
    extras = {}
    for kind in ("lessons", "insights"):
        try:
            got = fetch(args.url, kind)
            if got:
                extras[kind] = got
        except Exception:
            pass

    if not memories and not extras:
        print("nothing to export (0 memories)")
        return 0

    os.makedirs(args.out, exist_ok=True)

    if args.single_file:
        path = os.path.join(args.out, "agentmemory-export.md")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(f"# agentmemory export\n\n_{len(memories)} memories · "
                     f"{datetime.now(timezone.utc).strftime('%Y-%m-%d')}_\n\n")
            for m in memories:
                fh.write(f"\n---\n\n## {m.get('title') or 'Untitled'}\n\n")
                fh.write(str(m.get("content") or "").strip() + "\n")
                if m.get("concepts"):
                    fh.write(f"\n*Concepts: {', '.join(m['concepts'])}*\n")
        print(f"wrote {path}  ({len(memories)} memories)")
    else:
        written = 0
        for i, m in enumerate(memories, 1):
            name = f"{when(m.get('createdAt')) or i:0>2}-{slug(m.get('title'))}.md"
            with open(os.path.join(args.out, name), "w", encoding="utf-8") as fh:
                fh.write(as_note(m))
            written += 1
        # An index so the export is navigable rather than a pile of files.
        with open(os.path.join(args.out, "INDEX.md"), "w", encoding="utf-8") as fh:
            fh.write("# agentmemory export\n\n")
            fh.write(f"_{written} memories · exported "
                     f"{datetime.now(timezone.utc).strftime('%Y-%m-%d')}_\n\n")
            for m in memories:
                stem = f"{when(m.get('createdAt'))}-{slug(m.get('title'))}"
                fh.write(f"- [[{stem}|{m.get('title') or 'Untitled'}]]\n")
        print(f"wrote {written} notes + INDEX.md to {args.out}/")

    for kind, items in extras.items():
        path = os.path.join(args.out, f"{kind}.md")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(f"# {kind}\n\n")
            for it in items:
                fh.write(f"- {it.get('content') or it.get('title') or it}\n")
        print(f"wrote {path}  ({len(items)} {kind})")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
