param(
    [ValidateSet("deepseek", "qwen")]
    [string]$Provider = "deepseek",
    [int]$Port = 18991,
    [string]$AuthToken = "localtest",
    [string]$EnvFile = ".env",
    [string]$Log = "$env:USERPROFILE\.csswitch\logs\proxy.log"
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$envPath = if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $repo $EnvFile }
$logPath = if ([System.IO.Path]::IsPathRooted($Log)) { $Log } else { Join-Path $repo $Log }
$logDir = Split-Path -Parent $logPath

if (-not (Test-Path -LiteralPath $envPath)) {
    throw "Missing env file: $envPath. Copy .env.example to .env and put your API key there."
}

if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

$env:PYTHONIOENCODING = "utf-8"
python (Join-Path $repo "proxy\csswitch_proxy.py") `
    --provider $Provider `
    --port $Port `
    --env-file $envPath `
    --auth-token $AuthToken `
    --log $logPath
