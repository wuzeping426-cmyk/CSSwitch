# CSSwitch 打开后进入官方登录页：排查与解决

## 现象

使用 CSSwitch 启动 Claude Science 后，浏览器仍然进入 Claude 官方登录页面，或者提示需要登录 Claude 官方账号。

## 原理说明

CSSwitch 不是直接修改 Claude 官方网站，也不是使用 Claude 官方账号登录。

它在本机启动一套本地服务：

```text
浏览器
  -> http://localhost:8000/login
  -> Windows 本地自动登录代理
  -> Claude Science 本地服务（8002）
  -> CSSwitch 模型代理（18991）
  -> 中转站 OpenAI 兼容 API
```

各端口作用：

| 地址 | 作用 |
|---|---|
| `8000` | Windows 自动登录入口，浏览器应该打开这里 |
| `8002` | Claude Science 后端端口，不建议直接打开 |
| `18991` | CSSwitch 模型代理端口，浏览器不应直接打开 |

CSSwitch 会在本地生成虚拟 OAuth 数据，并通过本地认证代理完成 Claude Science 的本地登录。这不代表已经登录 Claude 官方账号。

## 正确启动方式

### 1. 更新项目

在项目目录执行：

```powershell
git pull
```

项目目录应类似：

```text
E:\Claude-Science\CSswitch-main
```

### 2. 确认前置条件

需要满足：

- Windows 10/11
- WSL 2
- Ubuntu 或其他可用 WSL Linux 发行版
- WSL 中安装 `python3`、`node`、`bubblewrap`、`socat`、`curl`
- Claude Science Linux 文件 `linux-x64`
- `linux-x64` 位于项目根目录，或项目目录的上一级目录

如果文件存在但没有执行权限，在 WSL 中执行：

```bash
chmod +x linux-x64
```

### 3. 配置 API

可以使用中文面板配置：

```text
windows\Open-CSSwitch-Panel.cmd
```

面板中填写：

```text
接口类型：OpenAI 兼容接口
Base URL：https://服务商提供的API根地址/v1
模型：服务商实际支持的模型名称
API Key：自己的 API Key
```

Base URL 必须是 OpenAI 兼容 API 根地址，例如：

```text
https://example.com/v1
```

不要填写：

```text
https://example.com/keys
https://example.com/login
https://claude.ai
```

`/keys` 通常是密钥管理页面，不是模型 API 根地址。

### 4. 按顺序启动

打开面板后按以下顺序操作：

1. 点击“保存配置”。
2. 点击“获取接口模型”，确认能获取模型列表。
3. 点击“切换模型并启动”。
4. 点击“打开 Claude Science”。

正确的浏览器地址应该是：

```text
http://localhost:8000/login
```

不要直接双击 `linux-x64`，不要直接打开 `8002`，也不要打开 Claude 官方网站。

## 如果仍然进入官方登录页

### 检查地址栏

必须确认地址栏是：

```text
http://localhost:8000/login
```

以下地址都不是正确入口：

```text
http://localhost:8002
http://localhost:8002/login
http://localhost:18991
https://claude.ai
```

### 检查端口

在 PowerShell 执行：

```powershell
Test-NetConnection 127.0.0.1 -Port 8000
Test-NetConnection 127.0.0.1 -Port 8002
Test-NetConnection 127.0.0.1 -Port 18991
```

期望结果：

- `8000`：成功
- `8002`：成功
- `18991`：成功

如果 `8000` 失败，说明自动登录代理没有启动。不要只重开浏览器，应重新从 CSSwitch 面板点击“切换模型并启动”。

如果 `8000` 显示端口可用，但页面仍然是官方登录页，可能是其他程序占用了 `8000`。新版启动脚本会检查：

```text
http://127.0.0.1:8000/health
```

只有返回 `ok` 才会认为这是 CSSwitch 自动登录代理。若端口被其他程序占用，面板会直接提示端口冲突；关闭占用程序后重新启动即可。

### 检查自动登录代理

查看以下日志：

```text
windows\claude-science-auth-proxy.stdout.log
windows\claude-science-auth-proxy.stderr.log
```

如果看到端口占用，关闭旧的 CSSwitch/Claude Science 进程后重新启动面板。

### 检查 WSL

执行：

```powershell
wsl.exe --list --quiet
wsl.exe -e bash -lc "command -v python3; command -v node; command -v bwrap; command -v socat; command -v curl"
```

如果缺少依赖，在 WSL Ubuntu 中执行：

```bash
sudo apt update
sudo apt install -y python3 nodejs bubblewrap socat curl
```

## “不能对 Null 值表达式调用方法”

这是旧版 Windows 面板的兼容性问题，通常发生在 Windows PowerShell 5.1 读取 WSL 命令输出时。

解决方法：

```powershell
git pull
```

然后关闭旧面板，重新打开：

```text
windows\Open-CSSwitch-Panel.cmd
```

当前版本已经修复该错误，并会显示实际的 WSL 启动失败原因。

## 重要说明：不能把 localhost 链接直接发给别人使用

`localhost` 只代表当前正在打开浏览器的那台电脑。

例如你电脑上的：

```text
http://localhost:8000
```

在别人电脑上打开时，指向的是别人的电脑，不是你的电脑。

如果要让别人使用，必须让对方在自己的电脑上：

1. 下载或更新 CSSwitch 项目。
2. 安装自己的 WSL 和依赖。
3. 放置自己的 Claude Science `linux-x64`。
4. 配置自己的中转站 API Key。
5. 从自己的 CSSwitch 面板启动。

不要把你的 `.env`、API Key 或包含密钥的日志发给别人。

## 仍无法解决时，请把这些信息发给 Codex

不要发送 API Key。只发送：

1. 浏览器当前完整地址栏。
2. CSSwitch 面板运行日志中最后 30 行。
3. 以下命令的结果：

```powershell
Test-NetConnection 127.0.0.1 -Port 8000
Test-NetConnection 127.0.0.1 -Port 8002
Test-NetConnection 127.0.0.1 -Port 18991
wsl.exe --list --quiet
```

4. `windows\claude-science-auth-proxy.stderr.log` 中的错误内容。
5. 对方使用的 Windows 版本、PowerShell 版本和 WSL 发行版名称。

可以先隐藏或删除所有 `sk-` 开头的内容，再发送日志。
