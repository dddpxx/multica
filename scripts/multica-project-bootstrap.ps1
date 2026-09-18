<#
新建项目标准流程（供总调度 / 人工调用）：
  1. 在 Multica 里建 Project
  2. 建一个不指派任何人的"日常直接改动记录"Issue，挂在该 Project 下
  3. 把 post-commit 钩子装进本地仓库（记录以后每次 commit，不触发任何 agent）

用法:
  powershell -File scripts\multica-project-bootstrap.ps1 `
      -Title "Gofo Club 网站改造" `
      -RepoPath "E:\APP\VSCODE-Project\Gofo-project" `
      -RepoUrl "https://github.com/xxx/gofo-club" `   # 可选
      -Description "..."                              # 可选
#>
param(
    [Parameter(Mandatory=$true)][string]$Title,
    [Parameter(Mandatory=$true)][string]$RepoPath,
    [string]$RepoUrl = "",
    [string]$Description = "",
    [string]$Profile = "cloud"
)

$ErrorActionPreference = "Stop"
$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")

function Section($t) { Write-Output ""; Write-Output "==== $t ====" }

Section "1/4 创建 Multica Project"
$projArgs = @("project", "create", "--title", $Title, "--profile", $Profile, "--output", "json")
if ($Description) { $projArgs += @("--description", $Description) }
if ($RepoUrl) { $projArgs += @("--repo", $RepoUrl) }
$projJson = & multica @projArgs
$proj = $projJson | ConvertFrom-Json
$projectId = $proj.id
Write-Output "Project: $($proj.title) ($projectId)"

Section "2/4 创建不指派的日常记录 Issue"
$issueJson = multica issue create `
    --title "📋 日常直接改动记录（自动，来自 git 钩子）" `
    --description "此 Issue 故意不指派任何人/智能体。每次在本地仓库 commit 后，post-commit 钩子会在这里追加一条纯文本评论，记录改了什么。不要 @任何人评论，否则会触发对应智能体执行。" `
    --project $projectId `
    --profile $Profile `
    --output json
$issue = $issueJson | ConvertFrom-Json
$issueId = $issue.id
Write-Output "Tracking Issue: $($issue.title) ($issueId)"

Section "3/4 把钩子装进本地仓库: $RepoPath"
if (-not (Test-Path $RepoPath)) {
    throw "仓库路径不存在: $RepoPath"
}
$hooksDir = Join-Path $RepoPath ".githooks"
New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Copy-Item (Join-Path $scriptDir "githooks\post-commit") (Join-Path $hooksDir "post-commit") -Force
Copy-Item (Join-Path $scriptDir "githooks\post-commit-log.ps1") (Join-Path $hooksDir "post-commit-log.ps1") -Force
[System.IO.File]::WriteAllText((Join-Path $hooksDir "multica-tracking-issue.txt"), $issueId, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText((Join-Path $hooksDir "multica-profile.txt"), $Profile, [System.Text.Encoding]::UTF8)

Push-Location $RepoPath
git config core.hooksPath .githooks
Pop-Location

Section "4/4 完成"
Write-Output @"
Project ID: $projectId
Tracking Issue ID: $issueId
钩子已装进: $hooksDir

记得把 .githooks 目录提交进仓库（git add .githooks && git commit），这样以后重新 clone 这个仓库后，
只需要跑一次: git config core.hooksPath .githooks
钩子和记录目标就都恢复了，不用重跑本脚本。
"@
