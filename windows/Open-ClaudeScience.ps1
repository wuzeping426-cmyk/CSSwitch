param(
    [int]$Port = 8000,
    [string]$Redirect = "/"
)

$ErrorActionPreference = "Stop"

# Use the stable local auto-login proxy instead of the native one-time nonce URL.
$safeRedirect = [Uri]::EscapeDataString($Redirect)
$target = "http://localhost:$Port/login?redirect=$safeRedirect&v=$([DateTimeOffset]::Now.ToUnixTimeMilliseconds())"
Start-Process $target
