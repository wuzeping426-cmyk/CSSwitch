param([string]$Action, [string]$Root, [string]$ScriptDir, [string]$BaseUrl, [string]$ApiKey, [string]$Model, [int]$History=48)
$ErrorActionPreference = 'Stop'
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$Distro = if ($env:CSSWITCH_WSL_DISTRO) { $env:CSSWITCH_WSL_DISTRO.Trim() } else { '' }

function Get-TrimmedText([object]$Value) {
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Trim()
}

function Resolve-WslDistro {
    if ($Distro) { return $Distro }
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw '找不到 wsl.exe。请先安装 WSL 2 和 Ubuntu。'
    }
    $list = & wsl.exe --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw 'WSL 不可用。请先安装 WSL 2 和 Ubuntu，再重新打开面板。'
    }
    $names = @($list | ForEach-Object {
        ((Get-TrimmedText $_) -replace "`0", "") -replace '^\*\s*', ''
    } | Where-Object { $_ })
    if (-not $names.Count) {
        throw '未发现 WSL Linux 发行版。请安装 Ubuntu，或设置 CSSWITCH_WSL_DISTRO 为实际发行版名称。'
    }
    $preferred = $names | Where-Object { $_ -match '^Ubuntu(?:[-\s].*)?$' } | Select-Object -First 1
    if ($preferred) { return $preferred }
    return [string]$names[0]
}

function Ensure-WslDistro {
    if (-not $Distro) { $Distro = Resolve-WslDistro }
    return $Distro
}

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
            try { $process.Kill() } catch {}
            throw "WSL command timed out after $TimeoutMs ms."
        }
        $stdoutText = ''
        $stderrText = ''
        try { $stdoutText = Get-TrimmedText $stdout.GetAwaiter().GetResult() } catch {}
        try { $stderrText = Get-TrimmedText $stderr.GetAwaiter().GetResult() } catch {}
        if ($process.ExitCode -ne 0) {
            $detail = if ($stderrText) { $stderrText } else { '没有返回详细错误。' }
            throw "WSL 命令失败（发行版：$Distro）：$detail"
        }
        return $stdoutText
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
    $base = Get-TrimmedText $BaseUrl
    if (-not $base) { throw '请先填写 Base URL。' }
    if ($base.TrimEnd('/') -match '/keys$') {
        throw 'Base URL 不能填写 /keys。请填写 OpenAI 兼容接口根地址，例如 https://example.com/v1。'
    }
    $base = $base.TrimEnd('/') -replace '/(v\d+/)?(chat/completions|models)$',''
    if ($base -notmatch '/v\d+$') { $base += '/v1' }
    try {
        $data = Invoke-RestMethod -Uri "$base/models" -Headers @{Authorization="Bearer $ApiKey"} -TimeoutSec 20
    } catch {
        $detail = Get-TrimmedText $_.Exception.Message
        if ($detail) { throw "获取模型失败：请检查 Base URL、API Key 和网络。上游信息：$detail" }
        throw '获取模型失败：请检查 Base URL、API Key 和网络。'
    }
    $models = @($data.data | ForEach-Object { if ($_.id -is [string]) { $_.id } } | Sort-Object -Unique)
    if (-not $models.Count) { throw 'The API returned no model IDs.' }
    return $models
}
if ($Action -eq 'Start') {
    $Distro = Ensure-WslDistro
    $repoWindows = (Resolve-Path -LiteralPath $Root).Path
    $repoWsl = Invoke-WslText "wslpath -a -u '$repoWindows'"
    if (Test-Path -LiteralPath (Join-Path $Root 'linux-x64')) {
        $binWsl = "$repoWsl/linux-x64"
    } else {
        $parentWsl = Invoke-WslText "wslpath -a -u '$(Split-Path -Parent $repoWindows)'"
        $binWsl = "$parentWsl/linux-x64"
    }
    $binaryCheck = Invoke-WslText "test -x '$binWsl' && printf ready"
    if ($binaryCheck -ne 'ready') {
        throw "找不到可执行的 Claude Science Linux 文件：$binWsl。请把 linux-x64 放到仓库根目录或其上一级目录，并在 WSL 中执行 chmod +x linux-x64。"
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
        $detail = Get-TrimmedText $_.Exception.Message
        throw "无法检查当前会话。请确认 Claude Science 已正确安装并可在 WSL 中运行。$detail"
    }
    & (Join-Path $ScriptDir 'Start-ClaudeScience-CSSwitch.ps1') `
        -Provider openai-custom `
        -BaseUrl (Get-TrimmedText $BaseUrl) `
        -Model (Get-TrimmedText $Model) `
        -MaxHistory $History `
        -WslDistro $Distro | Out-Null
}
if ($Action -eq 'Stop') {
    $Distro = Ensure-WslDistro
    & (Join-Path $ScriptDir 'Stop-ClaudeScience-CSSwitch.ps1') -WslDistro $Distro | Out-Null
}
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
