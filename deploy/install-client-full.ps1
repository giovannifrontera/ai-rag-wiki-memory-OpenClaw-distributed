param(
    [Parameter(Mandatory = $true)]
    [string]$QdrantHost,

    [string]$Workspace = "$HOME\.openclaw\workspace",
    [string]$OpenClawConfig = "",
    [string]$Python = "py"
)

$ErrorActionPreference = "Stop"

# Refresh PATH from machine+user env — picks up apps installed in this session (e.g. via winget)
$env:PATH = [System.Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" +
            [System.Environment]::GetEnvironmentVariable("PATH", "User")

function Step($Name) {
    Write-Host ""
    Write-Host "=== $Name ==="
}

function Need-Command($Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing required command: $Name. Install it, then re-run this installer."
    }
}

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$PluginDir = Join-Path $RepoRoot "plugins\wiki-context-plugin"

Step "Preflight"
Need-Command $Python
Need-Command "syncthing"
Need-Command "node"
Need-Command "npm.cmd"

try {
    # GET / works on all Qdrant versions; /health was removed in >=1.18
    Invoke-WebRequest -UseBasicParsing -Uri "http://$QdrantHost`:6333/" -TimeoutSec 10 | Out-Null
    Write-Host "Qdrant reachable: $QdrantHost`:6333"
} catch {
    throw "Qdrant is not reachable at http://$QdrantHost`:6333/. Fix Tailscale/hostname/firewall before continuing."
}

Step "Workspace bootstrap"
New-Item -ItemType Directory -Force -Path (Join-Path $Workspace "scripts") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Workspace "skills") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Workspace "wiki") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Workspace "wiki-works") | Out-Null
Copy-Item -Recurse -Force (Join-Path $RepoRoot "scripts\*") (Join-Path $Workspace "scripts")
Copy-Item -Recurse -Force (Join-Path $RepoRoot "skills\*") (Join-Path $Workspace "skills")
Copy-Item -Force (Join-Path $RepoRoot "deploy\syncthing-stignore") (Join-Path $Workspace ".stignore")

$ConfigPath = Join-Path $Workspace "wiki.config.json"
$TemplatePath = Join-Path $RepoRoot "wiki.config.json"
# Merge: template (all required fields) <- existing config (user customisations) <- installer params.
# Runs via Python so the write is UTF-8 NoBOM and the merge is correct for nested dicts.
$MergeScript = @'
import json, sys
from pathlib import Path

template_path = Path(sys.argv[1])
config_path   = Path(sys.argv[2])
workspace     = sys.argv[3]
qdrant_host   = sys.argv[4]

cfg = json.loads(template_path.read_text(encoding="utf-8"))
if config_path.exists():
    existing = json.loads(config_path.read_text(encoding="utf-8"))
    for k, v in existing.items():
        if isinstance(v, dict) and isinstance(cfg.get(k), dict):
            cfg[k].update(v)   # merge nested dicts; template keys not in existing are kept
        else:
            cfg[k] = v

cfg["workspace"] = workspace
cfg.setdefault("qdrant", {})
cfg["qdrant"]["host"] = qdrant_host
cfg["qdrant"].setdefault("port", 6333)
cfg["qdrant"].setdefault("collection", "wiki_pages")

config_path.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
print("wiki.config.json updated: qdrant.host =", cfg["qdrant"]["host"])
'@
$TmpScript = [System.IO.Path]::GetTempFileName() + ".py"
[System.IO.File]::WriteAllText($TmpScript, $MergeScript, [System.Text.UTF8Encoding]::new($false))
try {
    & $Python $TmpScript $TemplatePath $ConfigPath $Workspace $QdrantHost
} finally {
    Remove-Item -Force $TmpScript -ErrorAction SilentlyContinue
}

Step "Python dependencies"
& $Python -m pip install -r (Join-Path $RepoRoot "requirements.txt")

Step "OpenClaw plugin build"
& npm.cmd install --prefix $PluginDir
& npm.cmd run build --prefix $PluginDir

Step "OpenClaw plugin config"
$PythonExe = (& $Python -c "import sys; print(sys.executable)").Trim()
$SetupArgs = @((Join-Path $RepoRoot "scripts\setup_openclaw.py"), "--workspace", $Workspace, "--python", $PythonExe)
if ($OpenClawConfig) {
    $SetupArgs += @("--config", $OpenClawConfig)
}
& $Python @SetupArgs

Step "Verification"
& $Python (Join-Path $Workspace "scripts\wiki_check_setup.py") --workspace $Workspace
& $Python (Join-Path $Workspace "scripts\wiki_context.py") --workspace $Workspace --q "setup smoke test" --k 1 | Out-Null
& $Python (Join-Path $Workspace "scripts\wiki.py") query --workspace $Workspace --q "setup smoke test" --k 1 | Out-Null

Write-Host ""
Write-Host "Client install complete."
Write-Host "Workspace: $Workspace"
Write-Host "Qdrant:    $QdrantHost`:6333"
Write-Host "Next manual checks:"
Write-Host "1. Pair Syncthing with the server if not already paired."
Write-Host "2. Restart OpenClaw so the plugin config is loaded."
