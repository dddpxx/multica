<#
Daily backup of the local self-hosted Multica Postgres database.
Skips the dump if nothing happened in the last 24h (no new tasks, chat
messages, or task messages), and prunes old backups beyond -KeepDays.
#>
param(
    [string]$ProjectDir = "E:\APP\VSCODE-Project\multica-project",
    [string]$ContainerName = "multica-postgres-1",
    [string]$DbUser = "multica",
    [string]$DbName = "multica",
    [int]$KeepDays = 30
)

$ErrorActionPreference = "Stop"
$backupDir = Join-Path $ProjectDir "backups"
$logPath = Join-Path $backupDir "backup.log"
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

function Write-Log([string]$Message) {
    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -Path $logPath -Value $line -Encoding utf8
}

try {
    $running = docker inspect -f '{{.State.Running}}' $ContainerName 2>$null
    if ($LASTEXITCODE -ne 0 -or $running -ne "true") {
        Write-Log "SKIP: container '$ContainerName' is not running (Docker Desktop off?)."
        return
    }

    $checkSql = @"
SELECT COALESCE((
    SELECT count(*) FROM agent_task_queue WHERE created_at > now() - interval '24 hours'
), 0)
+ COALESCE((
    SELECT count(*) FROM chat_message WHERE created_at > now() - interval '24 hours'
), 0)
+ COALESCE((
    SELECT count(*) FROM task_message WHERE created_at > now() - interval '24 hours'
), 0);
"@
    $activityCount = docker exec -i $ContainerName psql -U $DbUser -d $DbName -tA -c $checkSql 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Log "ERROR: activity check failed: $activityCount"
        return
    }
    $activityCount = ([string]$activityCount).Trim()
    if ($activityCount -eq "0") {
        Write-Log "SKIP: no task/chat activity in the last 24h."
        return
    }

    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $fileName = "multica-$stamp.dump"
    $containerPath = "/tmp/$fileName"
    $localPath = Join-Path $backupDir $fileName

    docker exec $ContainerName pg_dump -U $DbUser -Fc -f $containerPath $DbName 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Log "ERROR: pg_dump failed inside container."
        return
    }
    docker cp "${ContainerName}:${containerPath}" $localPath 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $localPath)) {
        Write-Log "ERROR: failed to copy dump out of container."
        return
    }
    docker exec $ContainerName rm -f $containerPath 2>&1 | Out-Null

    $sizeKb = [Math]::Round((Get-Item $localPath).Length / 1KB, 1)
    Write-Log "OK: backed up to $localPath (${sizeKb} KB, activity_count=$activityCount)"

    $cutoff = (Get-Date).AddDays(-$KeepDays)
    Get-ChildItem $backupDir -Filter "multica-*.dump" |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        ForEach-Object {
            Remove-Item $_.FullName -Force
            Write-Log "PRUNE: removed old backup $($_.Name)"
        }
} catch {
    Write-Log "ERROR: unhandled exception: $_"
}
