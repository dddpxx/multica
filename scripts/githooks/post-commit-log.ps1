<#
Runs on every commit (via core.hooksPath = .githooks). Appends a plain-text
summary of the latest commit as a comment on this repo's Multica tracking
Issue, so anyone (or any agent) opening Multica later can see what happened
directly in the CLI, outside of Multica's own task flow.

Deliberately safe: the tracking issue is unassigned and this comment never
contains "@" mentions, so per Multica's comment-trigger rules (issue_assignee /
mention_agent / mention_squad_leader / thread_parent / conversation_continuation)
it cannot wake any agent — it is a pure log.

Configuration: reads the target issue id from .githooks/multica-tracking-issue.txt
(git-tracked, one line, just the issue UUID). If that file is missing, the hook
exits silently — nothing to log to.
#>
$ErrorActionPreference = "SilentlyContinue"

$root = git rev-parse --show-toplevel 2>$null
if (-not $root) { exit 0 }
$issueFile = Join-Path $root ".githooks\multica-tracking-issue.txt"
if (-not (Test-Path $issueFile)) { exit 0 }
$issueId = (Get-Content $issueFile -Raw).Trim()
if (-not $issueId) { exit 0 }

$multicaProfile = "cloud"
$profileFile = Join-Path $root ".githooks\multica-profile.txt"
if (Test-Path $profileFile) {
    $p = (Get-Content $profileFile -Raw).Trim()
    if ($p) { $multicaProfile = $p }
}

$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [Environment]::GetEnvironmentVariable("Path","User")

$hash = git log -1 --format=%h
$author = git log -1 --format=%an
$date = git log -1 --format=%ci
$subject = git log -1 --format=%s
$branch = git rev-parse --abbrev-ref HEAD
$stat = git show --stat -1 --format="" HEAD

$body = @"
[自动记录] commit $hash（分支 $branch）
时间: $date
作者: $author
标题: $subject

改动文件:
$stat
"@

$tmpFile = Join-Path $root ".git\multica-hook-comment.txt"
[System.IO.File]::WriteAllText($tmpFile, $body, [System.Text.Encoding]::UTF8)

Push-Location $root
try {
    & multica issue comment add $issueId --profile $multicaProfile --content-file ".git/multica-hook-comment.txt" --output json 2>$null | Out-Null
} finally {
    Pop-Location
    Remove-Item $tmpFile -ErrorAction SilentlyContinue
}
exit 0
