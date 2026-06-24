param(
    [Parameter(Mandatory = $true)]
    [string]$QdrantHost,

    [string]$Workspace = "$HOME\.openclaw\workspace",
    [string]$OpenClawConfig = "",
    [string]$Python = "py"
)

$ErrorActionPreference = "Stop"

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
    Invoke-WebRequest -UseBasicParsing -Uri "http://$QdrantHost`:6333/health" -TimeoutSec 10 | Out-Null
    Write-Host "Qdrant reachable: $QdrantHost`:6333"
} catch {
    throw "Qdrant is not reachable at http://$QdrantHost`:6333/health. Fix Tailscale/hostname/firewall before continuing."
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
if (-not (Test-Path $ConfigPath)) {
    Copy-Item -Force (Join-Path $RepoRoot "wiki.config.json") $ConfigPath
}
$Cfg = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
$Cfg.workspace = $Workspace
if (-not $Cfg.qdrant) {
    $Cfg | Add-Member -MemberType NoteProperty -Name qdrant -Value ([pscustomobject]@{})
}
$Cfg.qdrant | Add-Member -Force -MemberType NoteProperty -Name host -Value $QdrantHost
if (-not $Cfg.qdrant.port) {
    $Cfg.qdrant | Add-Member -Force -MemberType NoteProperty -Name port -Value 6333
}
if (-not $Cfg.qdrant.collection) {
    $Cfg.qdrant | Add-Member -Force -MemberType NoteProperty -Name collection -Value "wiki_pages"
}
$Cfg | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -Path $ConfigPath
Write-Host "wiki.config.json updated: qdrant.host = $QdrantHost"

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
