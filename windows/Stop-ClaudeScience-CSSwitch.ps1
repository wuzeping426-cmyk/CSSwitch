param(
    [string]$WslDistro = "Ubuntu"
)

$ErrorActionPreference = "Stop"
& (Join-Path $PSScriptRoot "Stop-ClaudeScience-AuthProxy.ps1")
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
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "Claude Science failed to stop in WSL (exit code $($process.ExitCode)): $stderr"
    }
    $stdout.TrimEnd()
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
[void]$pathProcess.Start()
$wslRepo = $pathProcess.StandardOutput.ReadToEnd().Trim()
$pathError = $pathProcess.StandardError.ReadToEnd()
$pathProcess.WaitForExit()
if ($pathProcess.ExitCode -ne 0) {
    throw "Cannot map the repository path into WSL: $pathError"
}
Invoke-WslCommand "cd '$wslRepo' && chmod +x stop-csswitch-science-wsl.sh && ./stop-csswitch-science-wsl.sh"
