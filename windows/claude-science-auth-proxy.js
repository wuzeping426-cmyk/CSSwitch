const http = require("http");
const net = require("net");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const listenPort = Number(process.env.CS_AUTH_PROXY_PORT || 8000);
const targetPort = Number(process.env.CS_TARGET_PORT || 8002);
const targetHost = "127.0.0.1";
const logPrefix = "[cs-auth-proxy]";
const wslDistro = (process.env.CSSWITCH_WSL_DISTRO || "Ubuntu").trim();
const provider = process.env.CS_PROVIDER || "openai-custom";
const proxyPort = Number(process.env.CS_PROXY_PORT || 18991);
const maxHistory = Number(process.env.CS_MAX_HISTORY || 48);
let recoveryInProgress = false;

function shellQuote(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

function runWindowsCommand(command, args, timeout = 15_000) {
  return spawnSync(command, args, {
    encoding: "utf8",
    windowsHide: true,
    timeout,
    maxBuffer: 1024 * 1024,
  });
}

function windowsToWsl(winPath) {
  const result = runWindowsCommand("wsl.exe", ["-d", wslDistro, "--", "wslpath", "-a", "-u", winPath]);
  if (result.error || result.status !== 0) {
    throw new Error(`cannot map path into WSL: ${result.stderr || result.error?.message || "unknown error"}`);
  }
  return String(result.stdout).trim();
}

function getWslHome() {
  const result = runWindowsCommand("wsl.exe", ["-d", wslDistro, "--", "bash", "-lc", 'printf %s "$HOME"']);
  if (result.error || result.status !== 0) {
    throw new Error(`cannot read WSL home: ${result.stderr || result.error?.message || "unknown error"}`);
  }
  return String(result.stdout).trim();
}

const windowsRepo = path.resolve(__dirname, "..");
const scienceRepo = process.env.CS_SCIENCE_REPO_WSL || windowsToWsl(windowsRepo);
const localScienceBinary = path.join(windowsRepo, "linux-x64");
const scienceBinary = process.env.CS_SCIENCE_BIN_WSL || (
  fs.existsSync(localScienceBinary)
    ? `${scienceRepo}/linux-x64`
    : `${path.posix.dirname(scienceRepo)}/linux-x64`
);
const sandboxHome = process.env.CS_SANDBOX_HOME || `${getWslHome()}/cs/.sandbox/h`;
const scienceDataDir = process.env.CS_SCIENCE_DATA_DIR || `${sandboxHome}/.claude-science`;

function runWsl(args, timeout = 15_000) {
  return runWindowsCommand("wsl.exe", ["-d", wslDistro, "--", "bash", "-lc", args], timeout);
}

function scienceIsRunning() {
  const result = runWsl(
    `HOME=${shellQuote(sandboxHome)} ${shellQuote(scienceBinary)} status --data-dir ${shellQuote(scienceDataDir)}`,
  );
  if (result.error || result.status !== 0) return false;
  try {
    return JSON.parse(String(result.stdout)).running === true;
  } catch {
    return false;
  }
}

function ensureScienceRunning() {
  if (scienceIsRunning()) return;
  if (recoveryInProgress) throw new Error("Claude Science 正在恢复，请稍后刷新");
  recoveryInProgress = true;
  try {
    const command = [
      `cd ${shellQuote(scienceRepo)}`,
      "chmod +x start-csswitch-science-wsl.sh stop-csswitch-science-wsl.sh",
      `./start-csswitch-science-wsl.sh --provider ${shellQuote(provider)} --proxy-port ${proxyPort} --science-port ${targetPort} --max-history ${maxHistory}`,
    ].join(" && ");
    const result = runWsl(command, 45_000);
    if (result.error || result.status !== 0 || !scienceIsRunning()) {
      const detail = String(result.stderr || result.error?.message || "unknown start error").trim();
      throw new Error(`Claude Science 自动恢复失败${detail ? `: ${detail.slice(0, 240)}` : ""}`);
    }
    console.log(`${logPrefix} Claude Science was restarted automatically`);
  } finally {
    recoveryInProgress = false;
  }
}

function freshNonce() {
  ensureScienceRunning();
  const cmd = `export HOME=${shellQuote(sandboxHome)}; timeout 15s ${shellQuote(scienceBinary)} url --data-dir ${shellQuote(scienceDataDir)}`;
  const result = runWsl(cmd);
  if (result.status !== 0) {
    throw new Error(`url command failed: ${result.stderr || result.stdout}`);
  }
  const match = String(result.stdout).match(/http:\/\/localhost:\d+\/\?nonce=([a-f0-9]+)/);
  if (!match) throw new Error(`no nonce in output: ${result.stdout}`);
  return match[1];
}

function htmlEscape(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function autoLoginPage(dest) {
  const nonce = freshNonce();
  const safeDest = htmlEscape(dest && dest.startsWith("/") ? dest : "/");
  const safeNonce = htmlEscape(nonce);
  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>正在进入 Claude Science...</title>
  <style>
    body{font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei UI",sans-serif;display:grid;place-items:center;min-height:100vh;margin:0;color:#111827;background:#f8fafc}
    main{width:min(420px,calc(100vw - 40px));padding:28px;border:1px solid #d7dde6;border-radius:10px;background:white;box-shadow:0 16px 40px rgba(15,23,42,.08);text-align:center}
    button{margin-top:16px;border:0;border-radius:7px;padding:10px 18px;background:#111827;color:white;font:inherit;font-weight:650;cursor:pointer}
    p{margin:8px 0 0;color:#64748b}
  </style>
</head>
<body>
  <main>
    <h2>正在进入 Claude Science</h2>
    <p>正在自动完成本地登录，不需要 Claude.ai 账号。</p>
    <form id="login" method="post" action="/api/auth/nonce">
      <input type="hidden" name="nonce" value="${safeNonce}">
      <input type="hidden" name="dest" value="${safeDest}">
      <button type="submit">继续进入</button>
    </form>
  </main>
  <script>setTimeout(()=>document.getElementById("login").submit(),50)</script>
</body>
</html>`;
}

function proxyHttp(req, res) {
  const forwardedHeaders = { ...req.headers };
  const scienceOrigin = `http://localhost:${targetPort}`;
  // The browser reaches the stable auth proxy on 8000, while Science runs on
  // 8002. Rewrite browser-origin headers so Science's origin check sees its
  // own canonical origin instead of rejecting message sends.
  if (forwardedHeaders.origin) {
    forwardedHeaders.origin = scienceOrigin;
  }
  if (forwardedHeaders.referer) {
    forwardedHeaders.referer = forwardedHeaders.referer
      .replace(`http://localhost:${listenPort}`, scienceOrigin)
      .replace(`http://127.0.0.1:${listenPort}`, scienceOrigin);
  }
  const options = {
    hostname: targetHost,
    port: targetPort,
    method: req.method,
    path: req.url,
    headers: { ...forwardedHeaders, host: `localhost:${targetPort}` },
  };
  const upstream = http.request(options, (upstreamRes) => {
    res.writeHead(upstreamRes.statusCode || 502, upstreamRes.headers);
    upstreamRes.pipe(res);
  });
  upstream.on("error", (error) => {
    res.writeHead(502, { "content-type": "text/plain; charset=utf-8" });
    res.end(`Claude Science backend is not reachable on ${targetPort}: ${error.message}`);
  });
  req.pipe(upstream);
}

const server = http.createServer((req, res) => {
  try {
    const url = new URL(req.url, `http://localhost:${listenPort}`);
    if (url.pathname === "/health") {
      res.writeHead(200, { "content-type": "text/plain; charset=utf-8" });
      res.end("ok");
      return;
    }
    if (url.pathname === "/login" || url.pathname === "/__cs_auto_login") {
      const dest = url.searchParams.get("redirect") || url.searchParams.get("dest") || "/";
      const body = autoLoginPage(dest);
      res.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" });
      res.end(body);
      return;
    }
    proxyHttp(req, res);
  } catch (error) {
    res.writeHead(500, { "content-type": "text/plain; charset=utf-8" });
    res.end(`Auto login proxy error: ${error.message}`);
  }
});

server.on("upgrade", (req, socket, head) => {
  const upstream = net.connect(targetPort, targetHost, () => {
    upstream.write(`${req.method} ${req.url} HTTP/${req.httpVersion}\r\n`);
    for (const [name, value] of Object.entries(req.headers)) {
      const lowerName = name.toLowerCase();
      const forwardedValue = lowerName === "host"
        ? `localhost:${targetPort}`
        : lowerName === "origin"
          ? `http://localhost:${targetPort}`
          : value;
      upstream.write(`${name}: ${forwardedValue}\r\n`);
    }
    upstream.write("\r\n");
    if (head && head.length) upstream.write(head);
    socket.pipe(upstream);
    upstream.pipe(socket);
  });
  upstream.on("error", () => socket.destroy());
});

server.listen(listenPort, "127.0.0.1", () => {
  console.log(`${logPrefix} listening on http://localhost:${listenPort}, target http://localhost:${targetPort}`);
});
