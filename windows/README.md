# Windows + WSL 支持

Windows 版通过 WSL Ubuntu 运行 Claude Science Linux 二进制，并用 PowerShell 面板管理 CSSwitch 代理和本地服务。核心代理、配置格式和隔离方式与 macOS 版本一致。

## 前置条件

1. Windows 10/11，已安装 WSL 2 和 Ubuntu。
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

- `CSSWITCH_WSL_DISTRO`：WSL 发行版名称，默认 `Ubuntu`。
- `CSSWITCH_SANDBOX_HOME`：WSL 沙箱 HOME，默认 `$HOME/cs/.sandbox/h`。
- `CS_SCIENCE_BIN_WSL`：Linux 二进制在 WSL 中的绝对路径。
- `CS_SCIENCE_DATA_DIR`：Claude Science 数据目录在 WSL 中的绝对路径。

## 启动

双击：

```text
windows\Open-CSSwitch-Panel.cmd
```

面板支持保存配置、获取上游模型列表、切换模型并启动、打开页面、停止服务和刷新状态。切换模型前，面板会检查是否存在正在运行的会话，避免中断当前工作。

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
