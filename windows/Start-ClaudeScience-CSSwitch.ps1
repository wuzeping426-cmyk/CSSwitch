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
    [string]$WslDistro = "Ubuntu",
    [switch]$AllowPlaceholder
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

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
    return $stdout.Trim()
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
        throw "Claude Science failed to start in WSL (exit code $($process.ExitCode)): $stderr"
    }
    $stdout.TrimEnd()
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
& (Join-Path $PSScriptRoot "Start-ClaudeScience-AuthProxy.ps1") -Port 8000 -TargetPort $SciencePort | Out-Null

try {
    & (Join-Path $PSScriptRoot "Start-ClaudeScience-Link.ps1") | Out-Null
} catch {
    Write-Warning "Claude Science fixed entry failed to start: $($_.Exception.Message)"
}
