#!/usr/bin/env python3
"""Collect a single day's Claude Code conversation turns across all projects and
emit a compact, human-readable digest for the nightly distill pass.

Reads the JSONL transcripts under ~/.config/claude/projects/<slug>/*.jsonl, keeps
only the meaningful turns (user prose, assistant prose, and the concrete actions
we took — edits, writes, shell commands, PRs), and drops the tool-call noise.

Output:
  <out>/digest-input.md   the concatenated per-project digest fed to `claude -p`
  <out>/manifest.json     {date, projects:[{slug,cwd,memory_dir,records}], truncated}
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

# Per-message text is capped so a single huge paste can't blow up the digest.
# Truncation is marked inline (never silent) so the distiller knows it happened.
MAX_MSG_CHARS = 2000

# Total budget for digest-input.md. A very heavy day gets trimmed proportionally
# per project (middle lines of the longest sections dropped, marked inline) so
# one marathon session can't blow the distiller's context or cost.
TOTAL_BUDGET_CHARS = 400_000

# Tool calls worth recording as "what we did" — everything else (Read/Grep/Glob/
# Task/…) is navigation noise and gets dropped.
ACTION_TOOLS = {"Edit", "Write", "NotebookEdit", "MultiEdit"}


def parse_ts(rec: dict) -> datetime | None:
    ts = rec.get("timestamp")
    if not isinstance(ts, str):
        return None
    try:
        dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone()  # local time


def truncate(text: str) -> str:
    text = text.strip()
    if len(text) <= MAX_MSG_CHARS:
        return text
    return text[:MAX_MSG_CHARS] + f"\n…[truncated {len(text) - MAX_MSG_CHARS} chars]"


def is_noise_string(s: str) -> bool:
    """User 'messages' that are really harness wrappers, not the human talking."""
    head = s.lstrip()[:40]
    return head.startswith(("<system-reminder", "<command-", "<local-command", "<user-", "Caveat:"))


def extract_text_blocks(content) -> list[str]:
    out = []
    if isinstance(content, str):
        if content.strip() and not is_noise_string(content):
            out.append(content)
    elif isinstance(content, list):
        for block in content:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "text":
                t = block.get("text", "")
                if t.strip() and not is_noise_string(t):
                    out.append(t)
    return out


def extract_actions(content) -> list[str]:
    """Concrete actions taken by the assistant this turn (edits, commands)."""
    actions = []
    if not isinstance(content, list):
        return actions
    for block in content:
        if not isinstance(block, dict) or block.get("type") != "tool_use":
            continue
        name = block.get("name", "")
        inp = block.get("input", {}) or {}
        if name in ACTION_TOOLS:
            fp = inp.get("file_path") or inp.get("notebook_path") or "?"
            actions.append(f"~ {name}: {fp}")
        elif name == "Bash":
            desc = inp.get("description") or ""
            cmd = (inp.get("command") or "").replace("\n", " ")
            label = desc.strip() or cmd[:100]
            actions.append(f"$ {label}")
    return actions


def process_transcript(path: Path, target: str) -> tuple[list[str], int]:
    """Return (rendered lines for this session, count of kept records)."""
    title = None
    turns: list[str] = []
    kept = 0
    try:
        lines = path.read_text(errors="replace").splitlines()
    except OSError:
        return [], 0

    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue

        rtype = rec.get("type")
        if rtype == "ai-title" and title is None:
            t = rec.get("title") or rec.get("text")
            if isinstance(t, str) and t.strip():
                title = t.strip()
            continue

        dt = parse_ts(rec)
        if dt is None or dt.strftime("%Y-%m-%d") != target:
            continue

        msg = rec.get("message")
        if rtype == "user" and isinstance(msg, dict):
            for t in extract_text_blocks(msg.get("content")):
                turns.append(f"**Me:** {truncate(t)}")
                kept += 1
        elif rtype == "assistant" and isinstance(msg, dict):
            for t in extract_text_blocks(msg.get("content")):
                turns.append(f"**Claude:** {truncate(t)}")
                kept += 1
            for a in extract_actions(msg.get("content")):
                turns.append(a)
        elif rtype == "pr-link":
            url = rec.get("url") or rec.get("prUrl")
            if url:
                turns.append(f"→ PR: {url}")

    if not turns:
        return [], 0

    header = f"### Session: {title or path.stem[:8]}"
    return [header, *turns, ""], kept


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--date", help="YYYY-MM-DD (default: yesterday, local)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--projects-root", default=str(Path.home() / ".config/claude/projects"))
    ap.add_argument("--deny", nargs="*", default=[], help="project slugs to skip")
    args = ap.parse_args()

    if args.date:
        target = args.date
    else:
        target = (datetime.now().astimezone() - timedelta(days=1)).strftime("%Y-%m-%d")

    root = Path(args.projects_root)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    deny = set(args.deny)

    manifest_projects = []
    project_lines: list[list[str]] = []  # rendered lines per project, pre-budget

    for proj_dir in sorted(p for p in root.iterdir() if p.is_dir()):
        slug = proj_dir.name
        if slug in deny or slug.startswith("."):
            continue
        transcripts = sorted(proj_dir.glob("*.jsonl"), key=lambda p: p.stat().st_mtime)
        rendered: list[str] = []
        total_kept = 0
        cwd = ""
        for tp in transcripts:
            lines, kept = process_transcript(tp, target)
            if kept:
                rendered.extend(lines)
                total_kept += kept
                if not cwd:
                    cwd = infer_cwd(tp, slug)
        if not total_kept:
            continue
        project_lines.append([f"\n## Project: `{slug}`  (path: {cwd or '?'})\n", *rendered])
        manifest_projects.append({
            "slug": slug,
            "cwd": cwd,
            "memory_dir": str(proj_dir / "memory"),
            "records": total_kept,
        })

    truncated = enforce_budget(project_lines, manifest_projects)

    parts: list[str] = [f"# Claude Code conversations — {target}\n"]
    for lines in project_lines:
        parts.extend(lines)

    input_text = "\n".join(parts)
    (out / "digest-input.md").write_text(input_text)
    manifest = {
        "date": target,
        "projects": manifest_projects,
        "total_records": sum(p["records"] for p in manifest_projects),
        "input_chars": len(input_text),
        "truncated": truncated,
    }
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2))

    print(json.dumps({"date": target, "projects": len(manifest_projects),
                      "records": manifest["total_records"], "chars": len(input_text),
                      "truncated": truncated}))
    return 0


def enforce_budget(project_lines: list[list[str]], manifest_projects: list[dict]) -> bool:
    """Shrink each project's rendered lines to its proportional share of
    TOTAL_BUDGET_CHARS when the day is over budget. Whole lines are kept from
    the head and tail (recent context usually lives at both ends); the omitted
    middle is marked inline so the distiller knows. Returns True if trimmed."""
    sizes = [sum(len(l) + 1 for l in lines) for lines in project_lines]
    total = sum(sizes)
    if total <= TOTAL_BUDGET_CHARS:
        return False
    for i, (lines, size) in enumerate(zip(project_lines, sizes)):
        share = max(2000, TOTAL_BUDGET_CHARS * size // total)
        trimmed, omitted = trim_middle(lines, share)
        project_lines[i] = trimmed
        if omitted:
            manifest_projects[i]["omitted_lines"] = omitted
    return True


def trim_middle(lines: list[str], max_chars: int) -> tuple[list[str], int]:
    """Keep whole lines alternately from the head and tail until max_chars is
    spent; replace the omitted middle with an inline marker."""
    if sum(len(l) + 1 for l in lines) <= max_chars:
        return lines, 0
    head: list[str] = []
    tail: list[str] = []
    used = 0
    lo, hi = 0, len(lines) - 1
    take_head = True
    while lo <= hi:
        line = lines[lo] if take_head else lines[hi]
        cost = len(line) + 1
        if used + cost > max_chars:
            break
        used += cost
        if take_head:
            head.append(line)
            lo += 1
        else:
            tail.insert(0, line)
            hi -= 1
        take_head = not take_head
    omitted = hi - lo + 1
    if omitted <= 0:
        return lines, 0
    marker = f"…[{omitted} lines omitted here to fit the input budget]…"
    return [*head, marker, *tail], omitted


def infer_cwd(path: Path, slug: str) -> str:
    """Pull the real cwd from a transcript record; fall back to de-slugging."""
    try:
        for line in path.read_text(errors="replace").splitlines():
            if '"cwd"' not in line:
                continue
            rec = json.loads(line)
            if isinstance(rec.get("cwd"), str):
                return rec["cwd"]
    except (OSError, json.JSONDecodeError):
        pass
    return "/" + slug.strip("-").replace("-", "/")


if __name__ == "__main__":
    sys.exit(main())
