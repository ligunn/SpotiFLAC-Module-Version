<#
  Static file server for the Palpatine soundboard.
  Pure PowerShell 5.1 (built into Windows 11) - no Python, no install.
  Supports HEAD and byte-range requests, which iOS Safari uses for audio.

  Binds to localhost by default (no admin, no firewall rule needed) because
  `tailscale serve` proxies to it. Use -Public to bind all interfaces instead,
  which requires running elevated.
#>
param(
  [int]$Port = 8080,
  [string]$Root = $PSScriptRoot,
  [switch]$Public
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path $Root).Path

$mime = @{
  '.html'='text/html; charset=utf-8'; '.css'='text/css; charset=utf-8'
  '.js'='application/javascript; charset=utf-8'; '.json'='application/json; charset=utf-8'
  '.mp3'='audio/mpeg'; '.m4a'='audio/mp4'; '.wav'='audio/wav'; '.ogg'='audio/ogg'
  '.png'='image/png'; '.jpg'='image/jpeg'; '.svg'='image/svg+xml'; '.ico'='image/x-icon'
}

$prefix = if ($Public) { "http://+:$Port/" } else { "http://localhost:$Port/" }
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
try {
  $listener.Start()
} catch {
  Write-Host "Could not bind $prefix"
  if ($Public) { Write-Host "Binding all interfaces requires an elevated PowerShell. Run as Administrator." }
  else { Write-Host "Port $Port may already be in use." }
  exit 1
}
Write-Host "Serving $Root on $prefix"

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $req = $ctx.Request
  $res = $ctx.Response
  try {
    $rel = [Uri]::UnescapeDataString($req.Url.AbsolutePath).TrimStart('/')
    if ($rel -eq '') { $rel = 'index.html' }
    $path = Join-Path $Root $rel

    # Refuse anything that escapes the project folder.
    $full = [System.IO.Path]::GetFullPath($path)
    if (-not $full.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
      $res.StatusCode = 404
      $res.ContentLength64 = 0
      $res.Close()
      continue
    }

    $fs = [System.IO.File]::OpenRead($full)
    try {
      $total = $fs.Length
      $start = [int64]0
      $end   = $total - 1

      if ($req.Headers['Range'] -match 'bytes=(\d*)-(\d*)') {
        $s = $Matches[1]; $e = $Matches[2]
        if ($s -ne '') {
          $start = [int64]$s
          if ($e -ne '') { $end = [int64]$e }
        } elseif ($e -ne '') {
          $start = [math]::Max([int64]0, $total - [int64]$e)   # suffix range
        }
        if ($end -ge $total) { $end = $total - 1 }
        if ($start -le $end) {
          $res.StatusCode = 206
          $res.Headers.Add('Content-Range', "bytes $start-$end/$total")
        } else {
          $start = 0; $end = $total - 1
        }
      }

      $len = $end - $start + 1
      $ext = [System.IO.Path]::GetExtension($full).ToLower()
      $res.ContentType = $(if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' })
      $res.Headers.Add('Accept-Ranges', 'bytes')
      $res.Headers.Add('Cache-Control', 'no-cache')
      $res.ContentLength64 = $len

      if ($req.HttpMethod -ne 'HEAD') {
        $fs.Position = $start
        $buf = New-Object byte[] 65536
        $left = $len
        while ($left -gt 0) {
          $want = [int][math]::Min([int64]$buf.Length, $left)
          $read = $fs.Read($buf, 0, $want)
          if ($read -le 0) { break }
          $res.OutputStream.Write($buf, 0, $read)
          $left -= $read
        }
      }
    } finally { $fs.Dispose() }
  } catch {
    # Safari aborts range requests routinely; never let one kill the server.
  } finally {
    try { $res.Close() } catch { }
  }
}
