param(
    [int]$Port = 8000,
    [string]$Redirect = "/"
)

$ErrorActionPreference = "Stop"

try {
    $health = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 2
    if (([string]$health.Content).Trim() -ne "ok") { throw "unexpected health response" }
} catch {
    throw 'CSSwitch 自动登录代理没有运行。请先在面板点击「切换模型并启动」，确认 8000 端口可用后再打开 Claude Science。'
}

# Use the stable local auto-login proxy instead of the native one-time nonce URL.
$safeRedirect = [Uri]::EscapeDataString($Redirect)
$target = "http://localhost:$Port/login?redirect=$safeRedirect&v=$([DateTimeOffset]::Now.ToUnixTimeMilliseconds())"
Start-Process $target
