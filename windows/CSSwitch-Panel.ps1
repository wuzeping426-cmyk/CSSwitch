Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $ScriptDir
$StateRoot = Join-Path $Root ".local"
$TaskTemp = Join-Path $StateRoot "temp"
New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
New-Item -ItemType Directory -Path $TaskTemp -Force | Out-Null
$env:TEMP = $TaskTemp
$env:TMP = $TaskTemp
$SwitchRoot = $Root
$EnvFile = Join-Path $SwitchRoot ".env"
$StartScript = Join-Path $ScriptDir "Start-ClaudeScience-CSSwitch.ps1"
$StopScript = Join-Path $ScriptDir "Stop-ClaudeScience-CSSwitch.ps1"
$OpenScript = Join-Path $ScriptDir "Open-ClaudeScience.ps1"
$SettingsFile = Join-Path $StateRoot 'panel-settings.json'
$script:Job = $null
$script:UiTicks = 0
$settings = @{ Models = @(); History = 48 }
if (Test-Path -LiteralPath $SettingsFile) {
    try { $settings = Get-Content -Raw -LiteralPath $SettingsFile | ConvertFrom-Json } catch {}
}

function Get-EnvValues {
    $values = @{}
    if (-not (Test-Path -LiteralPath $EnvFile)) { return $values }
    foreach ($line in Get-Content -LiteralPath $EnvFile) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$') {
            $values[$matches[1]] = $matches[2].Trim('"').Trim("'")
        }
    }
    return $values
}

function Set-EnvValue([string]$Name, [string]$Value) {
    $lines = if (Test-Path -LiteralPath $EnvFile) {
        [System.Collections.Generic.List[string]](Get-Content -LiteralPath $EnvFile)
    } else {
        [System.Collections.Generic.List[string]]::new()
    }
    $replacement = "$Name=$Value"
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^\s*$([regex]::Escape($Name))\s*=") {
            $lines[$i] = $replacement
            $found = $true
        }
    }
    if (-not $found) { $lines.Add($replacement) }
    [System.IO.File]::WriteAllLines($EnvFile, $lines, [System.Text.UTF8Encoding]::new($false))
}

$envValues = Get-EnvValues

$form = New-Object System.Windows.Forms.Form
$form.Text = "Claude Science Switch"
$form.Size = New-Object System.Drawing.Size(920, 650)
$form.MinimumSize = New-Object System.Drawing.Size(920, 650)
$form.StartPosition = "CenterScreen"
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)
$form.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
$form.AutoScaleMode = "Dpi"

$header = New-Object System.Windows.Forms.Panel
$header.Dock = "Top"
$header.Height = 82
$header.BackColor = [System.Drawing.Color]::FromArgb(28, 37, 52)
$form.Controls.Add($header)

$mark = New-Object System.Windows.Forms.Label
$mark.Text = "CS"
$mark.TextAlign = "MiddleCenter"
$mark.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 11)
$mark.ForeColor = [System.Drawing.Color]::White
$mark.BackColor = [System.Drawing.Color]::FromArgb(50, 129, 218)
$mark.Location = New-Object System.Drawing.Point(24, 21)
$mark.Size = New-Object System.Drawing.Size(40, 40)
$header.Controls.Add($mark)

$title = New-Object System.Windows.Forms.Label
$title.Text = "Claude Science Switch"
$title.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 16, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::White
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(78, 16)
$header.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "第三方模型配置与 Claude Science 本地运行控制"
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(190, 202, 220)
$subtitle.AutoSize = $true
$subtitle.Location = New-Object System.Drawing.Point(80, 47)
$header.Controls.Add($subtitle)

$stateDot = New-Object System.Windows.Forms.Label
$stateDot.Text = "●"
$stateDot.Font = New-Object System.Drawing.Font("Segoe UI", 13)
$stateDot.AutoSize = $true
$stateDot.Location = New-Object System.Drawing.Point(727, 25)
$header.Controls.Add($stateDot)

$stateLabel = New-Object System.Windows.Forms.Label
$stateLabel.Text = "正在检测服务"
$stateLabel.ForeColor = [System.Drawing.Color]::White
$stateLabel.AutoSize = $true
$stateLabel.Location = New-Object System.Drawing.Point(750, 29)
$header.Controls.Add($stateLabel)

$configCard = New-Object System.Windows.Forms.Panel
$configCard.BackColor = [System.Drawing.Color]::White
$configCard.BorderStyle = "FixedSingle"
$configCard.Location = New-Object System.Drawing.Point(24, 104)
$configCard.Size = New-Object System.Drawing.Size(872, 268)
$form.Controls.Add($configCard)

$configTitle = New-Object System.Windows.Forms.Label
$configTitle.Text = "当前连接"
$configTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 11, [System.Drawing.FontStyle]::Bold)
$configTitle.AutoSize = $true
$configTitle.Location = New-Object System.Drawing.Point(20, 17)
$configCard.Controls.Add($configTitle)

$configNote = New-Object System.Windows.Forms.Label
$configNote.Text = "切换模型会重启本地服务，但不会删除项目、会话或文件。"
$configNote.ForeColor = [System.Drawing.Color]::FromArgb(104, 112, 126)
$configNote.AutoSize = $true
$configNote.Location = New-Object System.Drawing.Point(20, 45)
$configCard.Controls.Add($configNote)

function Add-FieldLabel([string]$Text, [int]$X, [int]$Y) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.AutoSize = $true
    $label.ForeColor = [System.Drawing.Color]::FromArgb(63, 72, 86)
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $configCard.Controls.Add($label)
}

Add-FieldLabel "接口类型" 20 88
Add-FieldLabel "模型" 300 88
Add-FieldLabel "Base URL" 20 145
Add-FieldLabel "API Key" 20 202
Add-FieldLabel "上下文窗口" 575 202

$providerBox = New-Object System.Windows.Forms.ComboBox
$providerBox.DropDownStyle = "DropDownList"
[void]$providerBox.Items.Add("OpenAI 兼容接口")
$providerBox.SelectedIndex = 0
$providerBox.Location = New-Object System.Drawing.Point(20, 112)
$providerBox.Size = New-Object System.Drawing.Size(250, 26)
$configCard.Controls.Add($providerBox)

$modelBox = New-Object System.Windows.Forms.ComboBox
$modelBox.DropDownStyle = "DropDown"
[void]$modelBox.Items.AddRange([string[]]@(
    "gpt-6-astra",
    "gpt-5.5",
    "gpt-5.4",
    "gpt-5.6-luna",
    "gpt-5.6-sol",
    "gpt-5.6-terra",
    "codex-auto-review"
))
$modelBox.Text = if ($envValues["CSSWITCH_OPENAI_MODEL"]) { $envValues["CSSWITCH_OPENAI_MODEL"] } else { "gpt-5.5" }
$modelBox.Location = New-Object System.Drawing.Point(300, 112)
$modelBox.Size = New-Object System.Drawing.Size(280, 26)
$configCard.Controls.Add($modelBox)
$modelBox.AutoCompleteMode = 'SuggestAppend'
$modelBox.AutoCompleteSource = 'ListItems'
$modelBox.DropDownWidth = 440
foreach ($model in $settings.Models) {
    if ($model -eq 'gpt6-Astra') { $model = 'gpt-6-astra' }
    if ($model -and -not $modelBox.Items.Contains($model)) { [void]$modelBox.Items.Add([string]$model) }
}
$modelsButton = New-Object System.Windows.Forms.Button
$modelsButton.Text = '获取接口模型'
$modelsButton.Location = New-Object System.Drawing.Point(600, 108)
$modelsButton.Size = New-Object System.Drawing.Size(140, 32)
$configCard.Controls.Add($modelsButton)

$baseBox = New-Object System.Windows.Forms.TextBox
$baseBox.Text = if ($envValues["CSSWITCH_OPENAI_BASE_URL"]) { $envValues["CSSWITCH_OPENAI_BASE_URL"] } else { "" }
$baseBox.Location = New-Object System.Drawing.Point(20, 169)
$baseBox.Size = New-Object System.Drawing.Size(820, 26)
$configCard.Controls.Add($baseBox)

$keyBox = New-Object System.Windows.Forms.TextBox
$keyBox.UseSystemPasswordChar = $true
$keyBox.Location = New-Object System.Drawing.Point(20, 226)
$keyBox.Size = New-Object System.Drawing.Size(530, 26)
$configCard.Controls.Add($keyBox)

$keyTip = New-Object System.Windows.Forms.ToolTip
$keyTip.SetToolTip($keyBox, "留空将继续使用已有 API Key；面板不会显示旧 Key。")

$historyBox = New-Object System.Windows.Forms.NumericUpDown
$historyBox.Minimum = 12
$historyBox.Maximum = 500
$historyBox.Value = [Math]::Max(12, [Math]::Min(500, [int]$settings.History))
$historyBox.Location = New-Object System.Drawing.Point(575, 226)
$historyBox.Size = New-Object System.Drawing.Size(88, 26)
$configCard.Controls.Add($historyBox)

$historyHint = New-Object System.Windows.Forms.Label
$historyHint.Text = "条消息（默认 48）"
$historyHint.AutoSize = $false
$historyHint.Size = New-Object System.Drawing.Size(164, 24)
$historyHint.ForeColor = [System.Drawing.Color]::FromArgb(104, 112, 126)
$historyHint.Location = New-Object System.Drawing.Point(676, 230)
$configCard.Controls.Add($historyHint)

$actionCard = New-Object System.Windows.Forms.Panel
$actionCard.BackColor = [System.Drawing.Color]::White
$actionCard.BorderStyle = "FixedSingle"
$actionCard.Location = New-Object System.Drawing.Point(24, 386)
$actionCard.Size = New-Object System.Drawing.Size(872, 88)
$form.Controls.Add($actionCard)

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text = "保存配置"
$saveButton.Location = New-Object System.Drawing.Point(20, 25)
$saveButton.Size = New-Object System.Drawing.Size(120, 36)
$actionCard.Controls.Add($saveButton)

$startButton = New-Object System.Windows.Forms.Button
$startButton.Text = "切换模型并启动"
$startButton.Location = New-Object System.Drawing.Point(152, 25)
$startButton.Size = New-Object System.Drawing.Size(154, 36)
$startButton.BackColor = [System.Drawing.Color]::FromArgb(38, 124, 210)
$startButton.ForeColor = [System.Drawing.Color]::White
$startButton.FlatStyle = "Flat"
$startButton.FlatAppearance.BorderSize = 0
$actionCard.Controls.Add($startButton)

$openButton = New-Object System.Windows.Forms.Button
$openButton.Text = "打开 Claude Science"
$openButton.Location = New-Object System.Drawing.Point(318, 25)
$openButton.Size = New-Object System.Drawing.Size(152, 36)
$actionCard.Controls.Add($openButton)

$stopButton = New-Object System.Windows.Forms.Button
$stopButton.Text = "停止服务"
$stopButton.Location = New-Object System.Drawing.Point(482, 25)
$stopButton.Size = New-Object System.Drawing.Size(108, 36)
$actionCard.Controls.Add($stopButton)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = "刷新状态"
$refreshButton.Location = New-Object System.Drawing.Point(722, 25)
$refreshButton.Size = New-Object System.Drawing.Size(126, 36)
$actionCard.Controls.Add($refreshButton)

$logTitle = New-Object System.Windows.Forms.Label
$logTitle.Text = "运行日志"
$logTitle.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 10, [System.Drawing.FontStyle]::Bold)
$logTitle.AutoSize = $true
$logTitle.Location = New-Object System.Drawing.Point(25, 493)
$form.Controls.Add($logTitle)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = "Vertical"
$logBox.Font = New-Object System.Drawing.Font("Cascadia Mono", 9)
$logBox.Location = New-Object System.Drawing.Point(24, 518)
$logBox.Size = New-Object System.Drawing.Size(872, 86)
$logBox.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($logBox)

function Write-PanelLog([string]$Text) {
    $Text = $Text -replace 'sk-[A-Za-z0-9_-]+','[redacted]' -replace '(nonce=)[a-f0-9]+','$1[redacted]'
    if ($Text.Trim()) { $logBox.AppendText("[$(Get-Date -Format HH:mm:ss)] " + $Text.TrimEnd() + [Environment]::NewLine) }
    if ($logBox.TextLength -gt 24000) { $logBox.Text = $logBox.Text.Substring($logBox.TextLength - 16000) }
}

function Invoke-PanelCommand([scriptblock]$Action) {
    try {
        $output = @(& $Action 2>&1) | Out-String
        Write-PanelLog $output
        return $output
    } catch {
        $message = $_.Exception.Message
        Write-PanelLog "错误：$($message)"
        [System.Windows.Forms.MessageBox]::Show($message, "Claude Science Switch", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return $null
    }
}

function Save-Configuration {
    if ($modelBox.Text.Trim() -eq 'gpt6-Astra') { $modelBox.Text = 'gpt-6-astra' }
    if (-not $modelBox.Text.Trim()) { throw "请填写模型名称。" }
    if (-not $baseBox.Text.Trim()) { throw "请填写 OpenAI 兼容接口的 Base URL。" }
    if ($modelBox.Text.Trim() -notmatch '^[A-Za-z0-9][A-Za-z0-9._:/-]*$') { throw '模型名称含不支持的字符。' }
    $uri = $null
    if (-not [Uri]::TryCreate($baseBox.Text.Trim(), [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http','https') -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) { throw '请填写有效的 HTTP(S) API 地址。' }
    if ($keyBox.Text -match '[\r\n]') { throw 'API Key 不能包含换行。' }
    Set-EnvValue "CSSWITCH_OPENAI_BASE_URL" $baseBox.Text.Trim()
    Set-EnvValue "CSSWITCH_OPENAI_MODEL" $modelBox.Text.Trim()
    if ($keyBox.Text.Trim()) { Set-EnvValue "CSSWITCH_OPENAI_KEY" $keyBox.Text.Trim() }
    if (-not $modelBox.Items.Contains($modelBox.Text.Trim())) { [void]$modelBox.Items.Add($modelBox.Text.Trim()) }
    Save-PanelSettings
    $keyBox.Clear()
    Write-PanelLog "配置已保存。API Key 留空时将保留原有值。"
}

function Save-PanelSettings {
    @{ Models=@($modelBox.Items | ForEach-Object { [string]$_ }); History=[int]$historyBox.Value } |
        ConvertTo-Json | Set-Content -LiteralPath $SettingsFile -Encoding UTF8
}

function Start-PanelJob([string]$Action) {
    if ($script:Job) { return }
    $ps = [PowerShell]::Create()
    [void]$ps.AddCommand((Join-Path $ScriptDir 'CSSwitch-PanelWorker.ps1')).AddParameter('Action',$Action).AddParameter('Root',$Root).AddParameter('ScriptDir',$ScriptDir).AddParameter('BaseUrl',$baseBox.Text.Trim()).AddParameter('ApiKey',$keyBox.Text.Trim()).AddParameter('History',[int]$historyBox.Value)
    $handle = $ps.BeginInvoke()
    $script:Job = @{ PowerShell=$ps; Handle=$handle; Action=$Action; Started=[DateTime]::Now }
    foreach ($control in @($saveButton,$startButton,$stopButton,$refreshButton,$modelsButton,$configCard,$openButton)) { $control.Enabled = $false }
    $progress.Visible = $true
    Write-PanelLog "后台操作：$Action"
}

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Style = 'Marquee'
$progress.Location = New-Object System.Drawing.Point(620, 493)
$progress.Size = New-Object System.Drawing.Size(276, 12)
$progress.Visible = $false
$form.Controls.Add($progress)
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 100
$timer.Add_Tick({
    $script:UiTicks++
    if (-not $script:Job) { return }
    $job = $script:Job
    $labels = @{Start='正在切换'; Stop='正在停止'; Models='获取模型'; Status='检测状态'; Open='打开网页'; DelayTest='测试'}
    $stateLabel.Text = '{0} {1}s' -f $labels[$job.Action],[int]([DateTime]::Now-$job.Started).TotalSeconds
    if (-not $job.Handle.IsCompleted) { return }
    try {
        $result = @($job.PowerShell.EndInvoke($job.Handle))
        if ($job.PowerShell.HadErrors) { throw $job.PowerShell.Streams.Error[0].Exception.Message }
        if ($job.Action -eq 'Models') {
            $selection = $modelBox.Text
            $modelBox.BeginUpdate()
            foreach ($id in $result) { if (-not $modelBox.Items.Contains([string]$id)) { [void]$modelBox.Items.Add([string]$id) } }
            $modelBox.EndUpdate()
            $modelBox.Text = $selection
            Save-PanelSettings
            Write-PanelLog "已获取 $($result.Count) 个模型；实际可用性以调用为准。"
            $stateLabel.Text = '模型列表已更新'
        } elseif ($job.Action -in @('Status','Start','Stop')) {
            $state = $result[-1]
            $stateLabel.Text = if ($state.Running) { '服务端口已就绪' } elseif ($state.Backend -or $state.Proxy) { '部分服务未启动' } else { '服务未启动' }
            $stateDot.ForeColor = if ($state.Running) { [Drawing.Color]::SeaGreen } else { [Drawing.Color]::DarkOrange }
            Write-PanelLog "$($stateLabel.Text)；Science=$($state.Backend)，模型代理=$($state.Proxy)"
        } else { $stateLabel.Text = '操作完成' }
        if ($env:CSSWITCH_PANEL_SMOKE -eq '1') {
            if ($script:UiTicks -lt 10) { throw 'UI timer was blocked' }
            Write-Output "Async UI PASS: $($script:UiTicks) ticks during worker execution"
        }
    } catch {
        $stateLabel.Text = '操作失败'
        if ($_.Exception.Message -match 'A conversation is running') {
            Write-PanelLog '切换已阻止：有会话正在运行。请先在网页停止或完成任务，再切换模型。'
        }
        Write-PanelLog $_.Exception.Message
        if ($env:CSSWITCH_PANEL_SMOKE -eq '1') { $script:SmokeFailed = $true }
    } finally {
        $job.PowerShell.Dispose()
        $script:Job = $null
        foreach ($control in @($saveButton,$startButton,$stopButton,$refreshButton,$modelsButton,$configCard,$openButton)) { $control.Enabled = $true }
        $progress.Visible = $false
        if ($env:CSSWITCH_PANEL_SMOKE -eq '1') { $form.Close() }
    }
})
$timer.Start()
$saveButton.Add_Click({ Invoke-PanelCommand { Save-Configuration } | Out-Null })
$startButton.Add_Click({
    $saved = Invoke-PanelCommand { Save-Configuration }
    if ($null -eq $saved) { return }
    Start-PanelJob 'Start'
})
$openButton.Add_Click({
    Start-PanelJob 'Open'
})
$stopButton.Add_Click({
    Start-PanelJob 'Stop'
})
$refreshButton.Add_Click({
    Start-PanelJob 'Status'
})
$modelsButton.Add_Click({ Start-PanelJob 'Models' })

$form.Add_Shown({
    Write-PanelLog "控制面板已就绪。当前 API Key 不会显示在界面中。"
    if ($env:CSSWITCH_PANEL_SMOKE -eq '1') { Start-PanelJob 'DelayTest' } else { Start-PanelJob 'Status' }
})

$form.Add_FormClosing({
    param($sender, $eventArgs)
    if ($script:Job) { $eventArgs.Cancel = $true; Write-PanelLog '请等待当前操作结束后关闭面板。' }
})

[void]$form.ShowDialog()
$timer.Dispose()
$form.Dispose()
if ($script:SmokeFailed) { throw 'Panel smoke test failed' }
if ($env:CSSWITCH_PANEL_SMOKE -eq '1') {
    if ($script:UiTicks -lt 10) { throw 'UI timer did not advance' }
    Write-Output "Async UI PASS: $($script:UiTicks) ticks"
}
