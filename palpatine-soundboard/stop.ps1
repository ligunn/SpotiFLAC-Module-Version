param([int]$Port = 8080)
$ts = Get-Command tailscale.exe -ErrorAction SilentlyContinue
if (-not $ts -and (Test-Path "$env:ProgramFiles\Tailscale\tailscale.exe")) {
  $ts = "$env:ProgramFiles\Tailscale\tailscale.exe"
} elseif ($ts) { $ts = $ts.Source }
if ($ts) { & $ts serve reset 2>&1 | Out-Null; Write-Host "tailscale serve reset" }

Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like '*serve.ps1*' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force; Write-Host "Stopped server PID $($_.ProcessId)" }
