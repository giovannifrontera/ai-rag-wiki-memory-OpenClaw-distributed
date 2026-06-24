import json
import subprocess
import sys
from pathlib import Path


def run_wiki(tmp_workspace, *args):
    scripts_dir = Path(__file__).parent.parent / "scripts"
    result = subprocess.run(
        [sys.executable, str(scripts_dir / "wiki.py"), *args, "--workspace", str(tmp_workspace)],
        capture_output=True,
        text=True,
    )
    return json.loads(result.stdout)


def test_cleanup_renames_double_md_extension(tmp_workspace):
    bad = tmp_workspace / "wiki" / "concepts" / "artifact.md.md"
    bad.write_text("# Artifact\n", encoding="utf-8")

    result = run_wiki(tmp_workspace, "cleanup")

    assert result["status"] == "ok"
    assert result["renamed_mdmd"] == [{
        "from": "wiki/concepts/artifact.md.md",
        "to": "wiki/concepts/artifact.md",
    }]
    assert not bad.exists()
    assert (tmp_workspace / "wiki" / "concepts" / "artifact.md").exists()


def test_cleanup_reports_double_md_conflict(tmp_workspace):
    bad = tmp_workspace / "wiki" / "concepts" / "artifact.md.md"
    good = tmp_workspace / "wiki" / "concepts" / "artifact.md"
    bad.write_text("# Bad\n", encoding="utf-8")
    good.write_text("# Good\n", encoding="utf-8")

    result = run_wiki(tmp_workspace, "cleanup")

    assert result["status"] == "ok"
    assert result["renamed_mdmd"] == []
    assert result["mdmd_conflicts"] == [{
        "source": "wiki/concepts/artifact.md.md",
        "target": "wiki/concepts/artifact.md",
    }]
    assert bad.exists()
    assert good.exists()
