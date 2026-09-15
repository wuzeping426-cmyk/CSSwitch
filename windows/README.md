# Windows + WSL 支持

Windows 版通过 WSL Ubuntu 运行 Claude Science Linux 二进制，并用 PowerShell 面板管理 CSSwitch 代理和本地服务。核心代理、配置格式和隔离方式与 macOS 版本一致。

## 前置条件

1. Windows 10/11，已安装 WSL 2 和 Ubuntu。面板会自动选择已安装的 Ubuntu；如果电脑有多个 WSL 发行版，也可以通过 `CSSWITCH_WSL_DISTRO` 指定。
2. Windows 可运行 PowerShell 5.1+，并已安装 Node.js。
3. 在 Ubuntu 中安装运行依赖：

```bash
sudo apt update
sudo apt install -y python3 nodejs bubblewrap socat curl
```

4. 从你自己的 Claude Science Linux 安装中取得 `linux-x64`，放到本仓库根目录，或放在仓库上一级目录。该大文件不会提交到 Git。

## 配置

1. 将仓库根目录的 `.env.example` 复制为 `.env`。
2. 填写服务商地址、模型和 API Key。`.env` 已被 `.gitignore` 排除，不要提交。
3. 或者直接启动面板，在“当前连接”中填写 OpenAI 兼容接口，并点击“保存配置”。

常用可选环境变量：

- `CSSWITCH_WSL_DISTRO`：WSL 发行版名称；未设置时自动选择 Ubuntu，找不到 Ubuntu 时使用第一个已安装发行版。
- `CSSWITCH_SANDBOX_HOME`：WSL 沙箱 HOME，默认 `$HOME/cs/.sandbox/h`。
- `CS_SCIENCE_BIN_WSL`：Linux 二进制在 WSL 中的绝对路径。
- `CS_SCIENCE_DATA_DIR`：Claude Science 数据目录在 WSL 中的绝对路径。

## 启动

双击：

```text
windows\Open-CSSwitch-Panel.cmd
```

面板支持保存配置、获取上游模型列表、切换模型并启动、打开页面、停止服务和刷新状态。切换模型前，面板会检查是否存在正在运行的会话，避免中断当前工作。

## 常见错误

### Base URL 不能填写 `/keys`

OpenAI 兼容接口的 Base URL 应填写服务商提供的 API 根地址，例如：

```text
https://example.com/v1
```

不要填写管理页面或密钥页面地址，例如 `https://example.com/keys`。面板会访问该地址下的 `/models` 和 `/chat/completions`，填写 `/keys` 会导致路径错误。点击“获取接口模型”时如果失败，日志会显示上游返回的具体原因。

### 不能对 Null 值表达式调用方法

这是旧版本 Windows 面板读取 WSL 输出时的兼容性问题，常见于 Windows PowerShell 5.1。请更新仓库后重新打开 `windows\Open-CSSwitch-Panel.cmd`；新版本已改为兼容 PowerShell 5.1 的异步输出读取，并会显示实际的 WSL 错误。

也可以直接运行：

```powershell
.\windows\Start-ClaudeScience-CSSwitch.ps1 -Provider openai-custom
.\windows\Open-ClaudeScience.ps1
.\windows\Stop-ClaudeScience-CSSwitch.ps1
```

## 数据位置

默认情况下，WSL 数据位于：

```text
$HOME/cs/.sandbox/h/.claude-science
```

Windows 面板的临时文件和设置位于仓库根目录的 `.local/`，该目录不会上传到 Git。把仓库放在非系统盘即可避免 Windows 侧缓存占用 C 盘。
