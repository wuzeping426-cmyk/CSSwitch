param(
    [int]$Port = 8000,
    [int]$TargetPort = 8002,
    [string]$WslDistro = ""
)

$ErrorActionPreference = "Stop"
$WslDistro = if ($WslDistro) { $WslDistro.Trim() } elseif ($env:CSSWITCH_WSL_DISTRO) { $env:CSSWITCH_WSL_DISTRO.Trim() } else { "Ubuntu" }
$pidFile = Join-Path $PSScriptRoot "claude-science-auth-proxy.pid"
$outLog = Join-Path $PSScriptRoot "claude-science-auth-proxy.stdout.log"
$errLog = Join-Path $PSScriptRoot "claude-science-auth-proxy.stderr.log"
$script = Join-Path $PSScriptRoot "claude-science-auth-proxy.js"

function Test-LocalPort([int]$PortToCheck) {
    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect("127.0.0.1", $PortToCheck, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne(300, $false)) {
            $client.Close()
            return $false
        }
        $client.EndConnect($iar)
        $client.Close()
        return $true
    } catch {
        return $false
    }
}

if (Test-Path -LiteralPath $pidFile) {
    $oldPid = ([string](Get-Content -LiteralPath $pidFile -Raw)).Trim()
    if ($oldPid -match '^\d+$') {
        Stop-Process -Id ([int]$oldPid) -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
}

$env:CS_AUTH_PROXY_PORT = "$Port"
$env:CS_TARGET_PORT = "$TargetPort"
$env:CSSWITCH_WSL_DISTRO = $WslDistro
$process = Start-Process -FilePath "node.exe" -ArgumentList @($script) -WindowStyle Hidden -PassThru -RedirectStandardOutput $outLog -RedirectStandardError $errLog
[System.IO.File]::WriteAllText($pidFile, "$($process.Id)")

$ready = $false
for ($i = 0; $i -lt 25; $i++) {
    Start-Sleep -Milliseconds 200
    if (Test-LocalPort $Port) {
        $ready = $true
        break
    }
}
if (-not $ready) {
    throw "Claude Science auth proxy failed to start on port $Port."
}

Write-Output "http://localhost:$Port/"
