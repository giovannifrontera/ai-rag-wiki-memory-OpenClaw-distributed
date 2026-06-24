#!/usr/bin/env python3
"""
wiki_check_setup.py — Session startup check for ai-wiki-system (OpenClaw).

Two outcomes:
  - Setup broken  → prints <wiki-setup-required> listing the issues
  - Setup OK      → prints <wiki-briefing> with session state + mandatory rules

Used by the OpenClaw plugin on the first before_prompt_build event.
Always exits 0 — never blocks the user's prompt.

Usage:
    python wiki_check_setup.py --workspace /path/to/workspace
"""

import argparse
import json
import sys
from pathlib import Path


def check(workspace: str) -> list[str]:
    """Returns list of problems. Empty list = everything OK."""
    issues = []
    ws = Path(workspace)

    config_path = ws / "wiki.config.json"
    if not config_path.exists():
        issues.append("wiki.config.json not found in workspace")
        return issues

    try:
        cfg = json.loads(config_path.read_text(encoding="utf-8"))
    except Exception:
        issues.append("wiki.config.json is not valid JSON")
        return issues

    has_qdrant = bool(cfg.get("qdrant", {}).get("host"))
    has_lancedb = bool(cfg.get("lancedb", {}).get("path"))
    if not has_qdrant and not has_lancedb:
        issues.append("wiki.config.json: neither qdrant nor lancedb backend configured")
    elif has_qdrant:
        try:
            from qdrant_client import QdrantClient
        except ImportError:
            issues.append("qdrant-client not installed — run: pip install -r requirements.txt")
        else:
            try:
                qcfg = cfg["qdrant"]
                client = QdrantClient(host=qcfg.get("host", "localhost"), port=qcfg.get("port", 6333))
                coll_name = qcfg.get("collection", "wiki_pages")
                collections = [c.name for c in client.get_collections().collections]
                if coll_name not in collections:
                    issues.append(f"Qdrant collection '{coll_name}' not found — run: wiki.py rebuild")
                elif client.count(coll_name).count == 0:
                    issues.append(f"Qdrant collection '{coll_name}' is empty — run: wiki.py rebuild")
            except Exception as e:
                issues.append(f"Qdrant error: {e}")
    else:
        ldb_path = ws / cfg["lancedb"]["path"]
        if not ldb_path.exists():
            issues.append(f"LanceDB not found at {ldb_path} — run: wiki.py rebuild")
        else:
            try:
                import lancedb
            except ImportError:
                issues.append("lancedb not installed — run: pip install lancedb")
            else:
                try:
                    db = lancedb.connect(str(ldb_path))
                    table_result = db.list_tables()
                    tables = getattr(table_result, "tables", None) or list(table_result)
                    if "wiki_pages" not in tables:
                        issues.append("wiki_pages table not found — run: wiki.py rebuild")
                    elif db.open_table("wiki_pages").count_rows() == 0:
                        issues.append("wiki_pages is empty — run: wiki.py rebuild")
                except Exception as e:
                    issues.append(f"LanceDB error: {e}")

    # Stale failed session check
    session_path = ws / "wiki-session.md"
    if session_path.exists():
        try:
            import datetime as _dt
            age_days = (_dt.datetime.now().timestamp() - session_path.stat().st_mtime) / 86400
            if age_days > 7:
                for line in session_path.read_text(encoding="utf-8").splitlines():
                    if line.startswith("status:") and "failed" in line.lower():
                        issues.append(
                            f"wiki-session.md shows 'failed' status for {int(age_days)} days — "
                            "run: wiki.py session-update --op ingest --status ok --detail '{}'"
                        )
                        break
        except Exception:
            pass

    return issues


def session_summary(workspace: str) -> str:
    """Returns a one-line summary of the current session state."""
    ws = Path(workspace)
    session_path = ws / "wiki-session.md"
    if not session_path.exists():
        return "no session file"
    try:
        text = session_path.read_text(encoding="utf-8")
        status = "unknown"
        last_op = "none"
        pages = "?"
        for line in text.splitlines():
            if line.startswith("status:"):
                status = line.split(":", 1)[1].strip()
            elif line.startswith("Tipo:"):
                last_op = line.split(":", 1)[1].strip()
            elif line.startswith("Pagine totali:"):
                pages = line.split(":", 1)[1].strip()
        return f"status={status} | last-op={last_op} | pages={pages}"
    except Exception:
        return "session file unreadable"


def emit_briefing(workspace: str) -> None:
    """Emits a compact <wiki-briefing> block for the agent to read at session start."""
    summary = session_summary(workspace)
    ws = Path(workspace)
    lines = [
        "<wiki-briefing>",
        f"WORKSPACE: {workspace}",
        f"SESSION:   {summary}",
        "",
        "MANDATORY BEFORE ANY WIKI OPERATION — execute these Reads now:",
        "  1. Read wiki-session.md              (current session state)",
        "  2. Read skills/wiki-core.md          (full protocol — do not skip)",
        "",
        "NON-NEGOTIABLE RULES:",
        "  - Never write directly to wiki/ or wiki-works/ — always use wiki.py",
        "  - PDF ingestion: wiki.py ingest-pdf --workspace <ws> --file <path>",
        "    (text extracted via pdfplumber, deposited in wiki-works/<project>/raw/)",
        "  - After ingest-pdf: YOU write structured .tmp pages, then call wiki.py ingest",
        "  - process-raw: ONLY for bulk re-indexing of already-deposited raw files,",
        "    NOT a substitute for the full INGEST workflow (wiki-core.md §ingest)",
        "  - wiki-setup skill: NOT a Claude Code plugin — use Read skills/wiki-setup.md",
        "  - wiki-core skill: NOT a Claude Code plugin — use Read skills/wiki-core.md",
        "</wiki-briefing>",
    ]
    print("\n".join(lines))


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")

    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", required=True)
    args = parser.parse_args()

    try:
        issues = check(args.workspace)
    except Exception as e:
        print(f"wiki_check_setup internal error: {e}", file=sys.stderr)
        sys.exit(0)

    if issues:
        lines = [
            "<wiki-setup-required>",
            "Wiki system not configured correctly.",
            "DO NOT use Skill('wiki-setup') — it is not a plugin.",
            "Instead: Read skills/wiki-setup.md and follow it step by step.\n",
            "Issues found:",
        ]
        for issue in issues:
            lines.append(f"  - {issue}")
        lines.append("</wiki-setup-required>")
        print("\n".join(lines))
    else:
        emit_briefing(args.workspace)

    sys.exit(0)


if __name__ == "__main__":
    main()
