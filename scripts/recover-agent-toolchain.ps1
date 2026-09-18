<#
系统重装/崩溃后，快速恢复 Multica + Claude Code + Codex 工具链。
覆盖 2026-09-17/18 那次从零重建踩过的全部坑：
  - winget 装 Git/Node/Go/GitHub CLI 时会弹 UAC，需要人在旁边点一下
  - WSL2/虚拟化功能显示"已启用"但要重启一次才真正生效（仅自托管 Docker 需要，云端可跳过）
  - Node 26+ 不再自带 corepack，需要 npm install -g corepack
  - npm 全局装 @anthropic-ai/claude-code 需要 --allow-scripts 放行 postinstall
  - Electron/大文件下载走 GitHub CDN 在国内很慢，可配 ELECTRON_MIRROR（仅自托管才会触发）
  - PowerShell 传中文参数给原生 exe 容易编码错乱，凡是长文本一律走文件/REST API，不走命令行参数

用法：
  powershell -File scripts\recover-agent-toolchain.ps1              # 只装云端所需（Git/Node/Go/gh/claude/codex/multica CLI）
  powershell -File scripts\recover-agent-toolchain.ps1 -SelfHost     # 额外装 Docker Desktop，用于本机自托管
#>
param(
    [switch]$SelfHost
)

$ErrorActionPreference = "Stop"

function Section($title) {
    Write-Output ""
    Write-Output "==================== $title ===================="
}

Section "1/6 基础工具链 (Git / Node.js / Go / GitHub CLI)"
Write-Output "接下来 winget 可能会弹出几次 UAC 确认框，请留意屏幕并点“是”。"
foreach ($pkg in @("Git.Git", "OpenJS.NodeJS", "GoLang.Go", "GitHub.cli")) {
    Write-Output "安装 $pkg ..."
    winget install --id $pkg --exact --silent --accept-package-agreements --accept-source-agreements
}

if ($SelfHost) {
    Section "1b/6 Docker Desktop (仅自托管需要)"
    winget install --id Docker.DockerDesktop --exact --silent --accept-package-agreements --accept-source-agreements
    Write-Output "已安装 Docker Desktop。若 WSL2 还没启用过，需要手动重启一次电脑，重启后再重新运行本脚本一次（会自动跳过已装项）。"
}

Section "2/6 刷新 PATH（同一会话内立即生效）"
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")

Section "3/6 corepack + pnpm（仅从源码构建 multica 时需要，普通使用可跳过）"
try {
    npm install -g corepack 2>&1 | Out-Null
    corepack enable 2>&1 | Out-Null
    Write-Output "corepack 就绪。"
} catch {
    Write-Output "corepack 安装跳过（非致命）：$_"
}

Section "4/6 安装 Claude Code CLI 与 Codex CLI"
npm install -g --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code
npm install -g @openai/codex
$env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
Write-Output "claude 版本: $(claude --version 2>&1)"
Write-Output "codex 版本: $(codex --version 2>&1)"
Write-Output ""
Write-Output "接下来需要你手动登录一次（浏览器授权），本脚本不会自动帮你点：
  claude auth login
  codex login
（如果之前登录过同一账号，多半会自动复用已有会话，很快就过。）"

Section "5/6 安装 Multica CLI（官方安装脚本，走官方云端，不是本次自托管 fork）"
try {
    irm https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.ps1 | iex
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
    Write-Output "multica 版本: $(multica --version 2>&1)"
} catch {
    Write-Output "官方安装脚本失败，可能需要手动执行: irm https://raw.githubusercontent.com/multica-ai/multica/main/scripts/install.ps1 | iex"
}

Section "6/6 登录 Multica 并启动 daemon"
Write-Output "运行下面两条命令完成收尾（需要浏览器登录一次 multica.ai）："
Write-Output "  multica login"
Write-Output "  multica daemon start"
Write-Output "完成后用 multica daemon status 确认 Agents 里出现 claude / codex。"

Section "完成"
Write-Output @"
恢复要点回顾：
- 项目代码、Issue/Project/Agent/Squad 配置全部在云端，本机重装不会丢——只是重装了"能干活的手脚"。
- AGENTS.md / CLAUDE.md 已经在仓库根目录，claude/codex 启动时会自动读，不需要你口头重新交代项目背景。
- 如果需要本机自托管栈（Docker 版 multica），再单独执行:
    cd <multica-project 目录>
    docker compose -f docker-compose.selfhost.yml -f docker-compose.selfhost.build.yml up -d --build
"@
