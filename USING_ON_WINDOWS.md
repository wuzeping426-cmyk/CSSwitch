# CSSwitch on Windows

Windows 使用 WSL Ubuntu 运行 Claude Science Linux 二进制。完整安装、配置和启动说明见 [`windows/README.md`](windows/README.md)。

快速启动：

```powershell
.\windows\Open-CSSwitch-Panel.cmd
```

命令行启动：

```powershell
.\windows\Start-ClaudeScience-CSSwitch.ps1 -Provider openai-custom
.\windows\Open-ClaudeScience.ps1
.\windows\Stop-ClaudeScience-CSSwitch.ps1
```

不要把 `.env`、API Key、`linux-x64` 或 `.local/` 运行状态提交到 Git。
