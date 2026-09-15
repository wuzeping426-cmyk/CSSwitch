param(
    [ValidateSet("deepseek", "qwen", "openai-custom", "relay", "glm", "xiaomi", "siliconflow", "kimi", "minimax", "openrouter", "custom")]
    [string]$Provider = "deepseek",
    [int]$ProxyPort = 18991,
    [int]$SciencePort = 8002,
    [string]$BaseUrl = "",
    [string]$Model = "",
    [ValidateSet("", "adaptive", "enabled")]
    [string]$RelayThinking = "",
    [ValidateRange(1, 500)]
    [int]$MaxHistory = 48,
    [string]$WslDistro = "",
    [switch]$AllowPlaceholder
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

function Get-TrimmedText([object]$Value) {
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Trim()
}

function Resolve-WslDistro {
    $requested = if ($WslDistro) { $WslDistro.Trim() } elseif ($env:CSSWITCH_WSL_DISTRO) { $env:CSSWITCH_WSL_DISTRO.Trim() } else { '' }
    if ($requested) { return $requested }
    $list = & wsl.exe --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0) {
        throw "WSL 不可用。请先安装 WSL 2 和 Ubuntu。"
    }
    $names = @($list | ForEach-Object {
        ((Get-TrimmedText $_) -replace "`0", "") -replace '^\*\s*', ''
    } | Where-Object { $_ })
    if (-not $names.Count) {
        throw "未发现 WSL Linux 发行版。请安装 Ubuntu，或设置 CSSWITCH_WSL_DISTRO。"
    }
    $preferred = $names | Where-Object { $_ -match '^Ubuntu(?:[-\s].*)?$' } | Select-Object -First 1
    if ($preferred) { return $preferred }
    return [string]$names[0]
}

$WslDistro = Resolve-WslDistro

function ConvertTo-WslPath([string]$WindowsPath) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "wsl.exe"
    $psi.Arguments = "-d $WslDistro -- wslpath -a -u `"$WindowsPath`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "Cannot map the repository path into WSL: $stderr"
    }
    $mapped = Get-TrimmedText $stdout
    if (-not $mapped) {
        $detail = Get-TrimmedText $stderr
        throw "WSL 没有返回仓库路径。$detail"
    }
    return $mapped
}

function Invoke-WslCommand([string]$Command) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "wsl.exe"
    $psi.Arguments = "-d $WslDistro -- bash -lc `"$Command`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        $detail = Get-TrimmedText $stderr
        if (-not $detail) { $detail = "没有返回详细错误。" }
        throw "Claude Science 在 WSL 中启动失败（发行版：$WslDistro，退出码：$($process.ExitCode)）：$detail"
    }
    return (Get-TrimmedText $stdout)
}
$WslRepo = ConvertTo-WslPath $RepoRoot
$argsList = @(
    "cd '$WslRepo'",
    "chmod +x start-csswitch-science-wsl.sh stop-csswitch-science-wsl.sh",
    "./start-csswitch-science-wsl.sh --provider $Provider --proxy-port $ProxyPort --science-port $SciencePort --max-history $MaxHistory"
)
if ($BaseUrl) {
    $argsList[2] += " --base-url '$BaseUrl'"
}
if ($Model) {
    $argsList[2] += " --model '$Model'"
}
if ($RelayThinking) {
    $argsList[2] += " --relay-thinking '$RelayThinking'"
}
if ($AllowPlaceholder) {
    $argsList[2] += " --allow-placeholder"
}

& (Join-Path $PSScriptRoot "Stop-ClaudeScience-AuthProxy.ps1")
Invoke-WslCommand ($argsList -join " && ")
& (Join-Path $PSScriptRoot "Start-ClaudeScience-AuthProxy.ps1") -Port 8000 -TargetPort $SciencePort -WslDistro $WslDistro | Out-Null

try {
    & (Join-Path $PSScriptRoot "Start-ClaudeScience-Link.ps1") | Out-Null
} catch {
    Write-Warning "Claude Science fixed entry failed to start: $($_.Exception.Message)"
}
