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

function Get-AuthProxyHealth([int]$PortToCheck) {
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$PortToCheck/health" -TimeoutSec 2
        return ([string]$response.Content).Trim() -eq "ok"
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

if (Test-LocalPort $Port -and -not (Get-AuthProxyHealth $Port)) {
    throw "端口 $Port 已被其他程序占用，不是 CSSwitch 认证代理。请关闭占用该端口的程序后重试。"
}

if (Get-AuthProxyHealth $Port) {
    Write-Output "http://localhost:$Port/"
    return
}

$env:CS_AUTH_PROXY_PORT = "$Port"
$env:CS_TARGET_PORT = "$TargetPort"
$env:CSSWITCH_WSL_DISTRO = $WslDistro
$process = Start-Process -FilePath "node.exe" -ArgumentList @($script) -WindowStyle Hidden -PassThru -RedirectStandardOutput $outLog -RedirectStandardError $errLog
[System.IO.File]::WriteAllText($pidFile, "$($process.Id)")

$ready = $false
for ($i = 0; $i -lt 25; $i++) {
    Start-Sleep -Milliseconds 200
    if ($process.HasExited) {
        break
    }
    if (Get-AuthProxyHealth $Port) {
        $ready = $true
        break
    }
}
if (-not $ready) {
    $detail = ""
    if (Test-Path -LiteralPath $errLog) {
        $detail = (Get-Content -LiteralPath $errLog -Tail 8 -ErrorAction SilentlyContinue) -join " "
    }
    if ($detail) {
        throw "Claude Science 自动登录代理未能在端口 $Port 启动：$detail"
    }
    throw "Claude Science 自动登录代理未能在端口 $Port 启动。"
}

Write-Output "http://localhost:$Port/"
