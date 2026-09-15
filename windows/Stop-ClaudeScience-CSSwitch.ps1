param(
    [string]$WslDistro = ""
)

$ErrorActionPreference = "Stop"

function Get-TrimmedText([object]$Value) {
    if ($null -eq $Value) { return "" }
    return ([string]$Value).Trim()
}

function Resolve-WslDistro {
    param([string]$Requested)
    $requested = Get-TrimmedText $Requested
    if ($requested) { return $requested }
    $fromEnv = Get-TrimmedText $env:CSSWITCH_WSL_DISTRO
    if ($fromEnv) { return $fromEnv }
    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) { throw "找不到 wsl.exe。" }
    $list = & wsl.exe --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0) { throw "WSL 不可用。" }
    $names = @($list | ForEach-Object {
        ((Get-TrimmedText $_) -replace "`0", "") -replace "^\*\s*", ""
    } | Where-Object { $_ })
    if (-not $names.Count) { throw "未发现 WSL Linux 发行版。" }
    $preferred = $names | Where-Object { $_ -match "^Ubuntu(?:[-\s].*)?$" } | Select-Object -First 1
    if ($preferred) { return [string]$preferred }
    return [string]$names[0]
}

$WslDistro = Resolve-WslDistro $WslDistro
& (Join-Path $PSScriptRoot "Stop-ClaudeScience-AuthProxy.ps1") -WslDistro $WslDistro
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

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
    try {
        [void]$process.Start()
        $stdout = Get-TrimmedText $process.StandardOutput.ReadToEnd()
        $stderr = Get-TrimmedText $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            $detail = if ($stderr) { $stderr } else { "没有返回详细错误。" }
            throw "Claude Science 在 WSL 中停止失败（退出码 $($process.ExitCode)）：$detail"
        }
        return $stdout
    } finally {
        $process.Dispose()
    }
}
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "wsl.exe"
$psi.Arguments = "-d $WslDistro -- wslpath -a -u `"$RepoRoot`""
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$pathProcess = New-Object System.Diagnostics.Process
$pathProcess.StartInfo = $psi
try {
    [void]$pathProcess.Start()
    $wslRepo = Get-TrimmedText $pathProcess.StandardOutput.ReadToEnd()
    $pathError = Get-TrimmedText $pathProcess.StandardError.ReadToEnd()
    $pathProcess.WaitForExit()
    if ($pathProcess.ExitCode -ne 0) {
        throw "无法把仓库路径映射到 WSL：$pathError"
    }
} finally {
    $pathProcess.Dispose()
}
if (-not $wslRepo) {
    throw "WSL 没有返回仓库路径，请确认发行版 [$WslDistro] 可用。"
}
Invoke-WslCommand "cd '$wslRepo' && chmod +x stop-csswitch-science-wsl.sh && ./stop-csswitch-science-wsl.sh"
