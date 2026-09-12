$ErrorActionPreference = "Continue"
$pidFile = Join-Path $PSScriptRoot "claude-science-auth-proxy.pid"

if (Test-Path -LiteralPath $pidFile) {
    $serverPid = (Get-Content -LiteralPath $pidFile -Raw).Trim()
    if ($serverPid -match '^\d+$') {
        Stop-Process -Id ([int]$serverPid) -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}
