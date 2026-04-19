# start.ps1 - Wizard-first startup
# Opens wizard.html (or live2d_chat.html if already configured) via local HTTP server.
# Usage: Right-click -> Run with PowerShell, or execute in terminal.

$port = 3000
$dir  = $PSScriptRoot

Write-Host "Starting local HTTP server on port $port..."

# Start npx serve in background
$job = Start-Job -ScriptBlock {
  param($d, $p)
  Set-Location $d
  npx serve . -p $p --no-clipboard 2>&1
} -ArgumentList $dir, $port

Start-Sleep -Seconds 2

# Check if server started
$serverOk = $false
for ($i = 0; $i -lt 5; $i++) {
  try {
    $null = Invoke-WebRequest "http://localhost:$port" -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
    $serverOk = $true
    break
  } catch {
    Start-Sleep -Seconds 1
  }
}

if (-not $serverOk) {
  Write-Host "WARNING: Could not verify server startup. Opening anyway..."
}

# Always open wizard.html first (wizard redirects to chat if already configured)
$url = "http://localhost:$port/wizard.html"
Start-Process $url
Write-Host "Opened: $url"
Write-Host ""
Write-Host "Setup wizard -> configure -> 'チャット画面を開く'"
Write-Host "Press Ctrl+C to stop the server."
Write-Host ""

try {
  while ($true) { Start-Sleep -Seconds 5 }
} finally {
  Stop-Job $job -ErrorAction SilentlyContinue
  Remove-Job $job -ErrorAction SilentlyContinue
  Write-Host "Server stopped."
}
