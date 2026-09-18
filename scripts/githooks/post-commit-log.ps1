<#
Runs on every commit (via core.hooksPath = .githooks). Posts a plain-text
summary of the latest commit as a comment on a Multica Issue, so anyone (or
any agent) opening Multica later can see what happened directly in the CLI,
outside of Multica's own task flow.

Target resolution ("smart" matching):
  1. If the commit message contains a Multica issue number (write it as
     "#123" anywhere in the message), the hook resolves it via
     `multica issue search` and, on a confident exact-number match, comments
     on THAT real issue. If that issue has an assignee, this deliberately
     CAN wake it — you tagged a real issue on purpose, so it's meant to be
     seen there.
  2. Otherwise (no tag, or no confident match) it falls back to this repo's
     dedicated, permanently-UNASSIGNED tracking issue (configured by
     multica-project-bootstrap.ps1 in .githooks/multica-tracking-issue.txt).
     An unassigned issue + a comment with no "@" never wakes any agent — see
     comment.go's trigger sources (issue_assignee / mention_agent /
     mention_squad_leader / thread_parent / conversation_continuation), none
     of which apply here. The comment body below never contains "@".

Configuration:
  .githooks/multica-tracking-issue.txt   fallback issue id (required for step 2)
  .githooks/multica-profile.txt          multica CLI --profile to use (default: cloud)
#>
$ErrorActionPreference = "SilentlyContinue"

$root = git rev-parse --show-toplevel 2>$null
if (-not $root) { exit 0 }

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
$fullMessage = git log -1 --format=%B
$branch = git rev-parse --abbrev-ref HEAD
$stat = git show --stat -1 --format="" HEAD

# --- resolve target issue ---
$targetIssueId = $null
$matchNote = ""

if ($fullMessage -match '#(\d+)') {
    $num = $matches[1]
    $searchJson = & multica issue search $num --profile $multicaProfile --output json --limit 5 2>$null
    if ($searchJson) {
        try {
            $results = $searchJson | ConvertFrom-Json
            $exact = $results | Where-Object { [string]$_.number -eq $num } | Select-Object -First 1
            if ($exact) {
                $targetIssueId = $exact.id
                $matchNote = "（已匹配到 Issue #$num：$($exact.title)）"
            }
        } catch {}
    }
}

if (-not $targetIssueId) {
    $issueFile = Join-Path $root ".githooks\multica-tracking-issue.txt"
    if (-not (Test-Path $issueFile)) { exit 0 }
    $targetIssueId = (Get-Content $issueFile -Raw).Trim()
    if (-not $targetIssueId) { exit 0 }
    $matchNote = "（未在 commit message 里发现 #编号，记到日常记录日志）"
}

# --- build comment body (never contains "@", so an unassigned fallback issue can never be triggered) ---
$body = @"
[自动记录] commit $hash（分支 $branch）$matchNote
时间: $date
作者: $author
标题: $subject

改动文件:
$stat
"@
$body = $body -replace '@', '(at)'

$tmpFile = Join-Path $root ".git\multica-hook-comment.txt"
[System.IO.File]::WriteAllText($tmpFile, $body, [System.Text.Encoding]::UTF8)

Push-Location $root
try {
    & multica issue comment add $targetIssueId --profile $multicaProfile --content-file ".git/multica-hook-comment.txt" --output json 2>$null | Out-Null
} finally {
    Pop-Location
    Remove-Item $tmpFile -ErrorAction SilentlyContinue
}
exit 0
