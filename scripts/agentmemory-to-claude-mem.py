#!/usr/bin/env python3
"""Convert agentmemory's curated memories into claude-mem.

The problem
-----------
claude-mem has no ingest API. Only its own lifecycle hooks write to its store,
and the store is SQLite plus a Chroma vector index. Writing rows into the
SQLite directly would produce memories that keyword search can find but
semantic search cannot, because nothing would generate their embeddings — a
half-import that looks fine until you rely on it.

The approach
------------
Feed claude-mem a session it can ingest through its normal pipeline. We
synthesise a Claude Code transcript (JSONL, schema taken from real transcripts
in ~/.claude/projects) whose content is your memories, then hand claude-mem the
same Stop-hook payload Claude Code would send at the end of a real session:

    {"session_id":…, "transcript_path":…, "cwd":…, "hook_event_name":"Stop"}
    | node bun-runner.js worker-service.cjs hook claude-code summarize

claude-mem then summarises and embeds it itself, so the result is native: same
schema, same vectors, searchable like anything else it captured.

Trade-off, stated plainly
-------------------------
claude-mem SUMMARISES what it ingests. Your memories arrive as claude-mem's
compression of them, not verbatim. That is lossy. Keep the Markdown export
(memory-export.py) as the exact record — this converter is for making the
knowledge searchable inside claude-mem, not for archival fidelity.

Usage
-----
    agentmemory-to-claude-mem.py --dry-run       # build the transcript, show it
    agentmemory-to-claude-mem.py --go            # build it and ingest
    agentmemory-to-claude-mem.py --go --batch 5  # 5 memories per session
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.request
import uuid
from datetime import datetime, timezone

CLAUDE_DIR = os.environ.get("CLAUDE_CONFIG_DIR", os.path.expanduser("~/.claude"))


def fetch_memories(url: str):
    req = urllib.request.Request(f"{url}/agentmemory/memories?limit=1000")
    secret = os.environ.get("AGENTMEMORY_SECRET", "").strip()
    if secret:
        req.add_header("Authorization", f"Bearer {secret}")
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.loads(r.read().decode("utf-8", "replace"))
    if isinstance(data, list):
        return data
    return data.get("memories") or data.get("results") or []


def find_plugin() -> str | None:
    """Mirror claude-mem's own hook resolution order."""
    candidates = [
        os.path.join(CLAUDE_DIR, "plugins/cache/thedotmack/claude-mem/plugin"),
        os.path.join(CLAUDE_DIR, "plugins/cache/thedotmack/claude-mem"),
        os.path.join(CLAUDE_DIR, "plugins/marketplaces/thedotmack/plugin"),
        os.path.expanduser("~/.claude-mem/plugin"),
    ]
    for c in candidates:
        if os.path.isfile(os.path.join(c, "scripts/worker-service.cjs")):
            return c
    return None


def build_transcript(memories, cwd: str, path: str) -> str:
    """Write a minimal but schema-valid Claude Code transcript.

    Fields mirror real transcripts: parentUuid chain, isSidechain, uuid,
    timestamp, cwd, sessionId, version, gitBranch, and a message object whose
    shape matches the role.
    """
    session_id = str(uuid.uuid4())
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    parent = None
    lines = []

    def rec(kind: str, message: dict) -> str:
        nonlocal parent
        u = str(uuid.uuid4())
        lines.append(json.dumps({
            "parentUuid": parent,
            "isSidechain": False,
            "type": kind,
            "message": message,
            "uuid": u,
            "timestamp": now,
            "userType": "external",
            "cwd": cwd,
            "sessionId": session_id,
            "version": "2.1.208",
            "gitBranch": "main",
        }))
        parent = u
        return u

    rec("user", {"role": "user", "content":
        "Recording durable project knowledge carried over from a previous "
        "memory system. Each item below is a decision, constraint or root "
        "cause that should be retained."})

    body = []
    for m in memories:
        title = str(m.get("title") or "Untitled").strip()
        content = str(m.get("content") or "").strip()
        concepts = ", ".join(m.get("concepts") or [])
        files = ", ".join(m.get("files") or [])
        chunk = f"## {title}\n\n{content}"
        if concepts:
            chunk += f"\n\nConcepts: {concepts}"
        if files:
            chunk += f"\nFiles: {files}"
        body.append(chunk)

    rec("assistant", {
        "model": "claude-opus-4-8",
        "id": f"msg_{uuid.uuid4().hex[:24]}",
        "type": "message",
        "role": "assistant",
        "content": [{"type": "text", "text":
                     "Retained knowledge from the previous memory system:\n\n"
                     + "\n\n".join(body)}],
    })

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    return session_id


def ingest(plugin: str, transcript: str, session_id: str, cwd: str) -> bool:
    payload = json.dumps({
        "session_id": session_id,
        "transcript_path": transcript,
        "cwd": cwd,
        "hook_event_name": "Stop",
    })
    cmd = ["node", os.path.join(plugin, "scripts/bun-runner.js"),
           os.path.join(plugin, "scripts/worker-service.cjs"),
           "hook", "claude-code", "summarize"]
    try:
        p = subprocess.run(cmd, input=payload, capture_output=True,
                           text=True, timeout=300)
        if p.returncode != 0:
            sys.stderr.write((p.stderr or "")[:400] + "\n")
        return p.returncode == 0
    except Exception as e:
        sys.stderr.write(f"ingest failed: {e}\n")
        return False


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default=os.environ.get("AGENTMEMORY_URL", "http://localhost:3111"))
    ap.add_argument("--cwd", default=os.getcwd(), help="project the memories belong to")
    ap.add_argument("--batch", type=int, default=10, help="memories per synthetic session")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--go", action="store_true")
    args = ap.parse_args()

    if not args.dry_run and not args.go:
        args.dry_run = True   # default to safe

    try:
        memories = fetch_memories(args.url)
    except Exception as e:
        print(f"cannot read agentmemory at {args.url}: {e}", file=sys.stderr)
        print("start it first, or export earlier with memory-export.py", file=sys.stderr)
        return 1
    if not memories:
        print("no memories to convert")
        return 0
    print(f"  {len(memories)} memories to convert")

    plugin = find_plugin()
    if not plugin and args.go:
        print("claude-mem plugin not found — install it first: npx claude-mem install",
              file=sys.stderr)
        return 1

    outdir = os.path.join(CLAUDE_DIR, "projects",
                          "-" + args.cwd.strip("/").replace("/", "-"))
    batches = [memories[i:i + args.batch] for i in range(0, len(memories), args.batch)]
    print(f"  {len(batches)} synthetic session(s), {args.batch} memories each")

    ok = 0
    for i, batch in enumerate(batches, 1):
        path = os.path.join(outdir, f"carryover-{uuid.uuid4()}.jsonl")
        sid = build_transcript(batch, args.cwd, path)
        if args.dry_run:
            size = os.path.getsize(path)
            print(f"  [{i}/{len(batches)}] would ingest {len(batch)} memories "
                  f"({size} bytes) -> {os.path.basename(path)}")
            os.remove(path)
            continue
        print(f"  [{i}/{len(batches)}] ingesting {len(batch)} memories ... ", end="", flush=True)
        if ingest(plugin, path, sid, args.cwd):
            print("ok"); ok += 1
        else:
            print("FAILED")

    if args.dry_run:
        print("\n  DRY RUN — nothing ingested. Re-run with --go")
    else:
        print(f"\n  {ok}/{len(batches)} sessions ingested")
        print("  verify:  claude-mem status   and search for a known decision")
        print("  note: claude-mem SUMMARISES on ingest, so text is compressed,")
        print("        not verbatim. Keep the Markdown export as the exact record.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
