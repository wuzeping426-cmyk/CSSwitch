param([string]$Action, [string]$Root, [string]$ScriptDir, [string]$BaseUrl, [string]$ApiKey, [int]$History=48)
$ErrorActionPreference = 'Stop'
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Distro = if ($env:CSSWITCH_WSL_DISTRO) { $env:CSSWITCH_WSL_DISTRO } else { 'Ubuntu' }

function Invoke-WslText([string]$Command, [int]$TimeoutMs=15000) {
    $escaped = $Command.Replace("'", "'\''")
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = 'wsl.exe'
    $info.Arguments = "-d $Distro -- bash -lc '$escaped'"
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMs)) {
            $process.Kill()
            throw "WSL command timed out after $TimeoutMs ms."
        }
        if ($process.ExitCode -ne 0) {
            throw "WSL command failed: $($stderr.Result.Trim())"
        }
        return $stdout.Result.Trim()
    } finally {
        $process.Dispose()
    }
}

if ($Action -eq 'DelayTest') { Start-Sleep -Seconds 2; return 'done' }
if ($Action -eq 'Models') {
    if (-not $ApiKey) {
        $envFile = Join-Path $Root '.env'
        if (-not (Test-Path -LiteralPath $envFile)) { throw 'Configuration file is missing.' }
        foreach ($line in Get-Content -LiteralPath $envFile) {
            if ($line -match '^CSSWITCH_OPENAI_KEY=(.*)$') { $ApiKey = $matches[1].Trim().Trim('"').Trim("'") }
        }
    }
    if (-not $ApiKey) { throw 'API Key is missing.' }
    $base = $BaseUrl.Trim().TrimEnd('/') -replace '/(chat/completions|models)$',''
    if ($base -notmatch '/v\d+$') { $base += '/v1' }
    try {
        $data = Invoke-RestMethod -Uri "$base/models" -Headers @{Authorization="Bearer $ApiKey"} -TimeoutSec 20
    } catch { throw 'Unable to fetch models. Check endpoint, key and network.' }
    $models = @($data.data | ForEach-Object { if ($_.id -is [string]) { $_.id } } | Sort-Object -Unique)
    if (-not $models.Count) { throw 'The API returned no model IDs.' }
    return $models
}
if ($Action -eq 'Start') {
    $repoWindows = (Resolve-Path -LiteralPath $Root).Path
    $repoWsl = Invoke-WslText "wslpath -a -u '$repoWindows'"
    if (Test-Path -LiteralPath (Join-Path $Root 'linux-x64')) {
        $binWsl = "$repoWsl/linux-x64"
    } else {
        $parentWsl = Invoke-WslText "wslpath -a -u '$(Split-Path -Parent $repoWindows)'"
        $binWsl = "$parentWsl/linux-x64"
    }
    $sandboxHome = if ($env:CSSWITCH_SANDBOX_HOME) { $env:CSSWITCH_SANDBOX_HOME } else { '$HOME/cs/.sandbox/h' }
    $statusText = Invoke-WslText "HOME=`"$sandboxHome`" `"$binWsl`" status --data-dir `"$sandboxHome/.claude-science`""
    try {
        $status = $statusText | ConvertFrom-Json
        if ($status.running -and -not $status.health) { throw 'Backend health unavailable. Restart blocked to protect active work.' }
        if ($status.health.active_frames -gt 0 -or $status.health.active_conversations -gt 0) {
            throw 'A conversation is running. Stop or finish it in Claude Science before switching models.'
        }
    } catch {
        if ($_.Exception.Message -match 'backend health|conversation is running') { throw }
        throw 'Cannot verify active sessions. Retry later.'
    }
    & (Join-Path $ScriptDir 'Start-ClaudeScience-CSSwitch.ps1') -Provider openai-custom -MaxHistory $History | Out-Null
}
if ($Action -eq 'Stop') { & (Join-Path $ScriptDir 'Stop-ClaudeScience-CSSwitch.ps1') | Out-Null }
if ($Action -eq 'Open') { & (Join-Path $ScriptDir 'Open-ClaudeScience.ps1') | Out-Null; return 'Browser opened' }
$backend = $false
$proxy = $false
foreach ($port in @(8002,18991)) {
    $client = New-Object Net.Sockets.TcpClient
    try {
        $pending = $client.BeginConnect('127.0.0.1', $port, $null, $null)
        if ($pending.AsyncWaitHandle.WaitOne(700)) {
            $client.EndConnect($pending)
            if ($port -eq 8002) { $backend = $true } else { $proxy = $true }
        }
    } catch {} finally { $client.Dispose() }
}
[pscustomobject]@{ Backend=$backend; Proxy=$proxy; Running=($backend -and $proxy) }
