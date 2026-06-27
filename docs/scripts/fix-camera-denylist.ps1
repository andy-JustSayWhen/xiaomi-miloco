param(
  [string[]]$Model = @(),
  [string[]]$Did = @(),
  [string]$Distro = "",
  [int]$MilocoPort = 18860,
  [switch]$RestartService,
  [switch]$Enable,
  [switch]$Verify
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

function Write-Section {
  param([string]$Title)
  Write-Host ""
  Write-Host ("== {0} ==" -f $Title) -ForegroundColor Cyan
}

function Stop-ForUser {
  param(
    [string]$Title,
    [string[]]$Lines,
    [int]$ExitCode = 1
  )
  Write-Host ""
  Write-Host ("[ACTION REQUIRED] {0}" -f $Title) -ForegroundColor Yellow
  foreach ($line in $Lines) {
    Write-Host $line -ForegroundColor Yellow
  }
  exit $ExitCode
}

function Invoke-WslText {
  param(
    [string]$UseDistro,
    [string]$Script,
    [string[]]$ScriptArgs = @()
  )

  $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("miloco-denylist-fix-" + [guid]::NewGuid().ToString("N") + ".sh")
  [System.IO.File]::WriteAllText($tempPath, $Script, [System.Text.UTF8Encoding]::new($false))
  try {
    $baseArgs = @()
    if (-not [string]::IsNullOrWhiteSpace($UseDistro)) {
      $baseArgs += @("-d", $UseDistro)
    }

    $resolvedTemp = (Resolve-Path -LiteralPath $tempPath).Path
    if ($resolvedTemp -notmatch '^([A-Za-z]):\\(.*)$') {
      return [pscustomobject]@{
        ExitCode = 1
        Text = "Cannot convert Windows temp path to WSL path: $resolvedTemp"
      }
    }
    $drive = $matches[1].ToLowerInvariant()
    $rest = ($matches[2] -replace '\\', '/')
    $wslPath = "/mnt/$drive/$rest"

    $quotedPath = "'" + ($wslPath -replace "'", "'\''") + "'"
    $quotedArgs = @()
    foreach ($arg in $ScriptArgs) {
      $quotedArgs += ("'" + ($arg -replace "'", "'\''") + "'")
    }
    $bashCommand = "tr -d '\r' < $quotedPath | bash -s -- " + ($quotedArgs -join " ")

    $runArgs = @()
    if (-not [string]::IsNullOrWhiteSpace($UseDistro)) {
      $runArgs += @("-d", $UseDistro)
    }
    $runArgs += @("--", "bash", "-lc", $bashCommand)

    $output = & wsl.exe @runArgs 2>&1
    $code = $LASTEXITCODE
    [pscustomobject]@{
      ExitCode = $code
      Text = ($output -join "`n")
    }
  } finally {
    Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
  }
}

function Get-WslDistros {
  $raw = & wsl.exe -l -q 2>$null
  if ($LASTEXITCODE -ne 0) {
    return @()
  }
  return @(
    $raw |
      ForEach-Object { ($_ -replace "`0", "").Trim() } |
      Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
  )
}

function Resolve-Distro {
  param([string]$Requested)

  $checkScript = @'
set -e
export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"
if command -v miloco-cli >/dev/null 2>&1 && [ -x "$HOME/.local/share/uv/tools/miloco/bin/python" ]; then
  echo "ok"
else
  exit 2
fi
'@

  if (-not [string]::IsNullOrWhiteSpace($Requested)) {
    $result = Invoke-WslText -UseDistro $Requested -Script $checkScript
    if ($result.ExitCode -ne 0) {
      Stop-ForUser "Requested WSL distro is not usable" @(
        "Distro: $Requested",
        "miloco-cli or Miloco runtime Python was not found in this distro.",
        "Confirm which WSL distro has Miloco installed, or remove -Distro and let this script auto-detect it."
      )
    }
    return $Requested
  }

  $distros = Get-WslDistros
  foreach ($candidate in $distros) {
    $result = Invoke-WslText -UseDistro $candidate -Script $checkScript
    if ($result.ExitCode -eq 0) {
      return $candidate
    }
  }

  Stop-ForUser "Miloco WSL environment was not found" @(
    "The script checked distros from wsl -l -q, but did not find miloco-cli and Miloco runtime Python.",
    "Install Miloco first, or pass -Distro with the correct WSL distro name."
  )
}

if ($Model.Count -eq 0 -and $Did.Count -eq 0) {
  Stop-ForUser "Missing fix target" @(
    "Pass at least one -Model or -Did.",
    "Example: -Model chuangmi.camera.021a04 -RestartService -Verify",
    "Example: -Did 1039007350 -RestartService -Enable -Verify"
  )
}

Write-Section "Miloco camera denylist quick fix"
Write-Host "This tool only removes confirmed false-blocked runtime denylist entries."
Write-Host "Before using it, an Agent should confirm the model can produce frames with a direct SDK probe."

$resolvedDistro = Resolve-Distro -Requested $Distro
Write-Host ("Using WSL distro: {0}" -f $resolvedDistro)

$payload = @{
  models = @($Model)
  dids = @($Did)
  restart = [bool]$RestartService
  enable = [bool]$Enable
  verify = [bool]$Verify
  port = $MilocoPort
} | ConvertTo-Json -Compress
$payloadB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payload))

$fixScript = @'
set -euo pipefail
PAYLOAD_B64="$1"
python3 - "$PAYLOAD_B64" <<'PY'
import base64, json, pathlib, re, shutil, subprocess, sys, time, urllib.request

payload = json.loads(base64.b64decode(sys.argv[1]).decode("utf-8"))
models = {str(x).strip() for x in payload.get("models", []) if str(x).strip()}
dids = [str(x).strip() for x in payload.get("dids", []) if str(x).strip()]
port = int(payload.get("port") or 18860)
home = pathlib.Path.home()
workspace = home / ".openclaw" / "miloco"

def run(cmd, check=False):
    print("$ " + " ".join(cmd), flush=True)
    p = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if p.stdout:
        print(p.stdout.rstrip(), flush=True)
    if check and p.returncode != 0:
        raise SystemExit(p.returncode)
    return p

def walk_find_model(node, did):
    if isinstance(node, dict):
        if str(node.get("did")) == did and node.get("model"):
            return str(node.get("model"))
        for value in node.values():
            found = walk_find_model(value, did)
            if found:
                return found
    elif isinstance(node, list):
        for value in node:
            found = walk_find_model(value, did)
            if found:
                return found
    return None

if dids:
    config_path = workspace / "config.json"
    if not config_path.exists():
        raise SystemExit("Cannot resolve -Did because ~/.openclaw/miloco/config.json was not found. Pass -Model instead.")
    token = json.loads(config_path.read_text(encoding="utf-8")).get("server", {}).get("token", "")
    if not token:
        raise SystemExit("Cannot resolve -Did because Miloco server token is missing. Pass -Model instead.")
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}/api/miot/home",
        headers={"Authorization": f"Bearer {token}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            home_info = json.loads(resp.read().decode("utf-8"))
    except Exception as exc:
        raise SystemExit(f"Cannot resolve did via Miloco API: {exc}. Pass -Model instead.")
    for did in dids:
        model = walk_find_model(home_info, did)
        if not model:
            raise SystemExit(f"Cannot find model for did {did}. Pass -Model explicitly.")
        print(f"Resolved did {did} -> model {model}", flush=True)
        models.add(model)

if not models:
    raise SystemExit("No model to fix.")

yaml_candidates = sorted((home / ".local" / "share" / "uv" / "tools" / "miloco").glob("**/miot/configs/camera_extra_info.yaml"))
if not yaml_candidates:
    raise SystemExit("Cannot find runtime camera_extra_info.yaml under ~/.local/share/uv/tools/miloco.")
yaml_path = yaml_candidates[0]
print(f"Runtime YAML: {yaml_path}", flush=True)

workspace.mkdir(parents=True, exist_ok=True)
stamp = time.strftime("%Y%m%d-%H%M%S")
backup = workspace / f"camera_extra_info.before-denylist-fix-{stamp}.yaml"
shutil.copy2(yaml_path, backup)
print(f"Backup: {backup}", flush=True)

lines = yaml_path.read_text(encoding="utf-8").splitlines()
removed = []
missing = []
target_lines = {f"{model}:" for model in models}
out = []
i = 0
while i < len(lines):
    stripped = lines[i].strip()
    indent = len(lines[i]) - len(lines[i].lstrip(" "))
    if indent == 4 and stripped in target_lines:
        model = stripped[:-1]
        removed.append(model)
        i += 1
        while i < len(lines):
            next_line = lines[i]
            next_stripped = next_line.strip()
            next_indent = len(next_line) - len(next_line.lstrip(" "))
            if next_stripped and next_indent <= 4:
                break
            i += 1
        continue
    out.append(lines[i])
    i += 1

for model in sorted(models):
    if model not in removed:
        missing.append(model)

if removed:
    yaml_path.write_text("\n".join(out) + "\n", encoding="utf-8")
    print("Removed from denylist: " + ", ".join(sorted(removed)), flush=True)
else:
    print("No denylist entries removed.", flush=True)

if missing:
    print("Not present in runtime denylist: " + ", ".join(sorted(missing)), flush=True)

if payload.get("restart"):
    run(["bash", "-lc", 'export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; miloco-cli service restart'], check=False)
    time.sleep(10)

if payload.get("enable") and dids:
    for did in dids:
        run(["bash", "-lc", f'export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; miloco-cli scope camera enable {did} --pretty'], check=False)

if payload.get("verify"):
    run(["bash", "-lc", 'export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; miloco-cli scope camera list --pretty'], check=False)
    run(["bash", "-lc", 'export PATH="$HOME/.openclaw/bin:$HOME/.local/bin:$HOME/.local/share/uv/tools/supervisor/bin:$PATH"; miloco-cli perceive devices --pretty'], check=False)

print("Done.", flush=True)
PY
'@

Write-Section "Apply runtime fix"
$result = Invoke-WslText -UseDistro $resolvedDistro -Script $fixScript -ScriptArgs @($payloadB64)
Write-Host $result.Text
if ($result.ExitCode -ne 0) {
  exit $result.ExitCode
}

Write-Section "Next validation"
Write-Host "If the target did is connected=true and appears in perceive devices, run:"
Write-Host "miloco-cli perceive query --source <did> --query `"Describe the current camera image`" --pretty"
Write-Host "If it is still connected=false, do not keep editing denylist. Continue with LAN/PPCS/Wi-Fi/device-side triage."
