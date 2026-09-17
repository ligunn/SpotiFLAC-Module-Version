<#
  Starts the soundboard and publishes it on the tailnet.
  Run:  powershell -ExecutionPolicy Bypass -File .\start.ps1
  Then open the URL it prints on your iPhone.

  Default path: local server on 127.0.0.1 + `tailscale serve` (no firewall changes).
  -Direct: skip Tailscale, bind all interfaces and add a firewall rule (needs Administrator).
#>
param(
  [int]$Port = 8080,
  [switch]$Direct
)

$ErrorActionPreference = 'Continue'
$root = $PSScriptRoot

function Start-FileServer([switch]$Public) {
  $file = Join-Path $root 'serve.ps1'
  $psArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$file`"",
              '-Port',$Port,'-Root',"`"$root`"")
  if ($Public) { $psArgs += '-Public' }
  # Independent process: keeps running after this terminal closes.
  Start-Process powershell.exe -ArgumentList $psArgs -WindowStyle Hidden | Out-Null

  foreach ($i in 1..40) {
    Start-Sleep -Milliseconds 250
    try {
      $c = New-Object Net.Sockets.TcpClient
      $c.Connect('127.0.0.1', $Port); $c.Close()
      return $true
    } catch { }
  }
  return $false
}

function Find-Tailscale {
  $cmd = Get-Command tailscale.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  foreach ($p in @("$env:ProgramFiles\Tailscale\tailscale.exe",
                   "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe")) {
    if (Test-Path $p) { return $p }
  }
  return $null
}

# ---------------------------------------------------------------- direct mode
if ($Direct) {
  $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $admin) {
    Write-Host "-Direct needs an elevated PowerShell (right-click > Run as Administrator)." -ForegroundColor Red
    exit 1
  }
  $rule = "Palpatine Soundboard $Port"
  if (-not (Get-NetFirewallRule -DisplayName $rule -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName $rule -Direction Inbound -Action Allow `
      -Protocol TCP -LocalPort $Port -Profile Any | Out-Null
    Write-Host "Added firewall rule: $rule"
  }
  if (-not (Start-FileServer -Public)) { Write-Host "Server did not come up." -ForegroundColor Red; exit 1 }
  Write-Host ""
  Write-Host "  OPEN ON YOUR IPHONE:  http://100.120.230.53:$Port/" -ForegroundColor Green
  Write-Host ""
  exit 0
}

# ------------------------------------------------------------- tailscale mode
if (-not (Start-FileServer)) {
  Write-Host "Server did not come up on 127.0.0.1:$Port." -ForegroundColor Red
  exit 1
}
Write-Host "Local server up on http://127.0.0.1:$Port/"

$ts = Find-Tailscale
if (-not $ts) {
  Write-Host "tailscale.exe not found. Falling back:" -ForegroundColor Yellow
  Write-Host "  powershell -ExecutionPolicy Bypass -File .\start.ps1 -Direct   (as Administrator)"
  exit 1
}

& $ts version 2>&1 | Select-Object -First 1 | ForEach-Object { Write-Host "tailscale $_" }
& $ts serve reset 2>&1 | Out-Null   # clear any half-applied config from a previous run

# Explicit --https / --http flags first (current CLI), then the bare-target and
# legacy forms for older builds. Plain HTTP needs no tailnet HTTPS certificate.
$attempts = @(
  @{ desc = 'https=443 + url';  args = @('serve','--bg','--https=443','http://127.0.0.1:' + $Port); scheme = 'https'; port = 443 },
  @{ desc = 'https=443 + port'; args = @('serve','--bg','--https=443',"$Port");                     scheme = 'https'; port = 443 },
  @{ desc = 'bare target';      args = @('serve','--bg','http://127.0.0.1:' + $Port);               scheme = 'https'; port = 443 },
  @{ desc = "http=$Port + url"; args = @('serve','--bg',"--http=$Port",'http://127.0.0.1:' + $Port); scheme = 'http'; port = $Port },
  @{ desc = "http=$Port + port";args = @('serve','--bg',"--http=$Port","$Port");                     scheme = 'http'; port = $Port },
  @{ desc = 'legacy https:443'; args = @('serve','https:443','/','http://127.0.0.1:' + $Port);       scheme = 'https'; port = 443 }
)

$served = $null
foreach ($a in $attempts) {
  $cliArgs = $a.args
  # Render native stderr as plain text; ErrorRecords otherwise stringify into noise.
  $lines = @(& $ts @cliArgs 2>&1 | ForEach-Object { $_.ToString() })
  if ($LASTEXITCODE -eq 0) { $served = $a; Write-Host "tailscale serve: $($a.desc)" -ForegroundColor Green; break }
  # Show only the real error, not the CLI's full usage dump.
  $why = ($lines | Where-Object { $_ -match '^\s*Error' } | Select-Object -First 1)
  if (-not $why) { $why = ($lines | Where-Object { $_.Trim() } | Select-Object -First 1) }
  Write-Host ("  x {0,-18} {1}" -f $a.desc, $why) -ForegroundColor DarkGray
}

if (-not $served) {
  Write-Host "`ntailscale serve did not work on this version. Falling back:" -ForegroundColor Yellow
  Write-Host "  powershell -ExecutionPolicy Bypass -File .\start.ps1 -Direct   (as Administrator)"
  exit 1
}

# Ask Tailscale for this device's real MagicDNS name rather than guessing it.
$host_name = '100.120.230.53'
try {
  $st = & $ts status --json | ConvertFrom-Json
  if ($st.Self.DNSName) { $host_name = $st.Self.DNSName.TrimEnd('.') }
} catch { }

$url = if ($served.port -eq 443) { "https://$host_name/" } else { "$($served.scheme)://$host_name`:$($served.port)/" }
Write-Host ""
Write-Host "  OPEN ON YOUR IPHONE:  $url" -ForegroundColor Green
Write-Host "  (fallback if that stalls: run with -Direct, then http://100.120.230.53:$Port/)"
Write-Host ""
Write-Host "Stop it later with:  powershell -ExecutionPolicy Bypass -File .\stop.ps1"
