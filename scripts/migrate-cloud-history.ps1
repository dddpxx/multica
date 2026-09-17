param(
    [switch]$PlanOnly,
    [switch]$ValidateImport,
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

$selectedModes = @($PlanOnly, $ValidateImport, $Apply | Where-Object { $_ }).Count
if ($selectedModes -gt 1) {
    throw "Choose one mode"
}
if ($selectedModes -eq 0) {
    $PlanOnly = $true
}

$cloudConfigPath = Join-Path $env:USERPROFILE ".multica\profiles\desktop-api.multica.ai\config.json"
$localConfigPath = Join-Path $env:USERPROFILE ".multica\profiles\desktop-localhost-8080\config.json"
$cloud = Get-Content -LiteralPath $cloudConfigPath -Raw | ConvertFrom-Json
$local = Get-Content -LiteralPath $localConfigPath -Raw | ConvertFrom-Json

function Invoke-Api([string]$BaseUrl, [string]$Token, [string]$WorkspaceId, [string]$Path, [switch]$NoProxy) {
    $headers = @{ Authorization = "Bearer $Token" }
    if ($WorkspaceId) {
        $headers["X-Workspace-ID"] = $WorkspaceId
    }
    $args = @{
        Uri = "$BaseUrl$Path"
        Headers = $headers
        Method = "Get"
        TimeoutSec = 60
    }
    if ($NoProxy) {
        $args.NoProxy = $true
    }
    Invoke-RestMethod @args
}

function Get-DuplicateKeyCount($Rows, [string]$Key) {
    @($Rows | Group-Object $Key | Where-Object Count -ne 1).Count
}

function Get-UnmatchedKeyCount($SourceRows, $TargetRows, [string]$Key) {
    $target = @{}
    foreach ($row in $TargetRows) {
        $target[[string]$row.$Key] = $true
    }
    @($SourceRows | Where-Object { -not $target.ContainsKey([string]$_.$Key) }).Count
}

$cloudWorkspaces = Invoke-Api $cloud.server_url $cloud.token "" "/api/workspaces"
$localWorkspaces = Invoke-Api $local.server_url $local.token "" "/api/workspaces" -NoProxy
$localWorkspace = @($localWorkspaces | Where-Object { [string]$_.id -eq [string]$local.workspace_id })
if ($localWorkspace.Count -ne 1) {
    throw "Local workspace is missing or ambiguous"
}
$cloudWorkspace = @($cloudWorkspaces | Where-Object { [string]$_.slug -eq [string]$localWorkspace[0].slug })
if ($cloudWorkspace.Count -ne 1) {
    throw "Cloud workspace is missing or ambiguous"
}
$cloudWorkspaceId = $cloudWorkspace[0].id

$cloudIssues = (Invoke-Api $cloud.server_url $cloud.token $cloudWorkspaceId "/api/issues?workspace_id=$cloudWorkspaceId&limit=100").issues
$localIssues = (Invoke-Api $local.server_url $local.token $local.workspace_id "/api/issues?workspace_id=$($local.workspace_id)&limit=100" -NoProxy).issues
$cloudProjects = (Invoke-Api $cloud.server_url $cloud.token $cloudWorkspaceId "/api/projects?workspace_id=$cloudWorkspaceId&limit=100").projects
$localProjects = (Invoke-Api $local.server_url $local.token $local.workspace_id "/api/projects?workspace_id=$($local.workspace_id)&limit=100" -NoProxy).projects
$cloudAgents = Invoke-Api $cloud.server_url $cloud.token $cloudWorkspaceId "/api/agents?workspace_id=$cloudWorkspaceId&include_archived=true"
$localAgents = Invoke-Api $local.server_url $local.token $local.workspace_id "/api/agents?workspace_id=$($local.workspace_id)&include_archived=true" -NoProxy
$cloudChats = Invoke-Api $cloud.server_url $cloud.token $cloudWorkspaceId "/api/chat/sessions?status=all"

$cloudBase = $cloud.server_url
$cloudToken = $cloud.token
$cloudTasks = $cloudAgents | ForEach-Object -Parallel {
    $headers = @{
        Authorization = "Bearer $using:cloudToken"
        "X-Workspace-ID" = $using:cloudWorkspaceId
    }
    $tasks = Invoke-RestMethod -Uri "$using:cloudBase/api/agents/$($_.id)/tasks" -Headers $headers -TimeoutSec 60
    foreach ($task in @($tasks)) {
        $task
    }
} -ThrottleLimit 8
$cloudTasks = @($cloudTasks | Sort-Object id -Unique)

$nonTerminalStatuses = @("queued", "dispatched", "running", "waiting_local_directory", "deferred")
$mapping = [ordered]@{
    unmatched_issues = Get-UnmatchedKeyCount $cloudIssues $localIssues "number"
    unmatched_projects = Get-UnmatchedKeyCount $cloudProjects $localProjects "title"
    unmatched_agents = Get-UnmatchedKeyCount $cloudAgents $localAgents "name"
    duplicate_cloud_issue_numbers = Get-DuplicateKeyCount $cloudIssues "number"
    duplicate_local_issue_numbers = Get-DuplicateKeyCount $localIssues "number"
    duplicate_cloud_project_titles = Get-DuplicateKeyCount $cloudProjects "title"
    duplicate_local_project_titles = Get-DuplicateKeyCount $localProjects "title"
    duplicate_cloud_agent_names = Get-DuplicateKeyCount $cloudAgents "name"
    duplicate_local_agent_names = Get-DuplicateKeyCount $localAgents "name"
}
$canApply = ($mapping.Values | Measure-Object -Sum).Sum -eq 0 -and @($cloudTasks | Where-Object status -in $nonTerminalStatuses).Count -eq 0

$plan = [ordered]@{
    can_apply = $canApply
    cloud = [ordered]@{
        workspace_id = $cloudWorkspaceId
        projects = @($cloudProjects).Count
        issues = @($cloudIssues).Count
        agents = @($cloudAgents).Count
        tasks = @($cloudTasks).Count
        non_terminal_tasks = @($cloudTasks | Where-Object status -in $nonTerminalStatuses).Count
        chat_sessions = @($cloudChats).Count
    }
    local = [ordered]@{
        workspace_id = $local.workspace_id
        projects = @($localProjects).Count
        issues = @($localIssues).Count
        agents = @($localAgents).Count
    }
    mapping = $mapping
}

if ($PlanOnly) {
    $plan | ConvertTo-Json -Depth 6 -Compress
    return
}

function New-KeyMap($SourceRows, $TargetRows, [string]$Key) {
    $targets = @{}
    foreach ($row in $TargetRows) {
        $targets[[string]$row.$Key] = $row
    }
    $map = @{}
    foreach ($row in $SourceRows) {
        $map[[string]$row.id] = $targets[[string]$row.$Key]
    }
    $map
}

function Sql-Text($Value) {
    if ($null -eq $Value) {
        return "NULL"
    }
    $text = ([string]$Value).Replace([string][char]0, [string][char]0xFFFD)
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    $base64 = [Convert]::ToBase64String($bytes)
    "convert_from(decode('$base64','base64'),'UTF8')"
}

function Sql-Json($Value) {
    if ($null -eq $Value) {
        return "NULL"
    }
    $json = ConvertTo-Json -InputObject $Value -Depth 100 -Compress
    "(" + (Sql-Text $json) + ")::jsonb"
}

function Sql-Uuid($Value) {
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return "NULL"
    }
    $parsed = [Guid]::Parse([string]$Value)
    "'$($parsed.ToString())'::uuid"
}

function Sql-Time($Value) {
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return "NULL"
    }
    $parsed = [DateTimeOffset]::Parse([string]$Value)
    "'$($parsed.ToString('o'))'::timestamptz"
}

function Sql-Int($Value, [int64]$Default = 0) {
    if ($null -eq $Value) {
        return [string]$Default
    }
    [string][int64]$Value
}

function Sql-Bool($Value) {
    if ($Value) { "TRUE" } else { "FALSE" }
}

$issueMap = New-KeyMap $cloudIssues $localIssues "number"
$projectMap = New-KeyMap $cloudProjects $localProjects "title"
$agentMap = New-KeyMap $cloudAgents $localAgents "name"

$cloudMembers = Invoke-Api $cloud.server_url $cloud.token $cloudWorkspaceId "/api/workspaces/$cloudWorkspaceId/members"
$localMembers = Invoke-Api $local.server_url $local.token $local.workspace_id "/api/workspaces/$($local.workspace_id)/members" -NoProxy
$localMembersByEmail = @{}
foreach ($member in $localMembers) {
    $localMembersByEmail[[string]$member.email] = $member
}
$userMap = @{}
foreach ($member in $cloudMembers) {
    if ($localMembersByEmail.ContainsKey([string]$member.email)) {
        $userMap[[string]$member.user_id] = $localMembersByEmail[[string]$member.email].user_id
    }
}

$cloudChatMessages = $cloudChats | ForEach-Object -Parallel {
    $headers = @{
        Authorization = "Bearer $using:cloudToken"
        "X-Workspace-ID" = $using:cloudWorkspaceId
    }
    try {
        $messages = Invoke-RestMethod -Uri "$using:cloudBase/api/chat/sessions/$($_.id)/messages" -Headers $headers -TimeoutSec 60
        foreach ($message in @($messages)) {
            $message
        }
    } catch {
        [pscustomobject]@{ __read_error = "chat:$($_.id)" }
    }
} -ThrottleLimit 8

$cloudTaskMessages = $cloudTasks | ForEach-Object -Parallel {
    $taskId = $_.id
    $headers = @{
        Authorization = "Bearer $using:cloudToken"
        "X-Workspace-ID" = $using:cloudWorkspaceId
    }
    try {
        $messages = Invoke-RestMethod -Uri "$using:cloudBase/api/tasks/$taskId/messages" -Headers $headers -TimeoutSec 60
        foreach ($message in @($messages)) {
            [pscustomobject]@{
                task_id = $taskId
                seq = $message.seq
                type = $message.type
                content = $message.content
                created_at = $message.created_at
            }
        }
    } catch {
        [pscustomobject]@{ __read_error = "task:$taskId" }
    }
} -ThrottleLimit 16

$readErrors = @($cloudChatMessages | Where-Object __read_error).Count + @($cloudTaskMessages | Where-Object __read_error).Count
if ($readErrors -ne 0) {
    $failedReads = @($cloudChatMessages | Where-Object __read_error | ForEach-Object __read_error) +
        @($cloudTaskMessages | Where-Object __read_error | ForEach-Object __read_error)
    throw "Cloud history read failed for $readErrors records: $($failedReads -join ',')"
}

$cloudChatMessages = @($cloudChatMessages | Sort-Object id -Unique)
$cloudTaskMessages = @($cloudTaskMessages | Sort-Object task_id, seq -Unique)
$cloudChatAttachments = @(
    $cloudChatMessages |
        ForEach-Object { if ($_.PSObject.Properties['attachments']) { $_.attachments } } |
        Where-Object id |
        Sort-Object id -Unique
)

$taskIds = @{}
foreach ($task in $cloudTasks) { $taskIds[[string]$task.id] = $true }
$chatIds = @{}
foreach ($chat in $cloudChats) { $chatIds[[string]$chat.id] = $true }

$unresolved = [ordered]@{
    task_agents = @($cloudTasks | Where-Object { -not $agentMap.ContainsKey([string]$_.agent_id) }).Count
    task_issues = @($cloudTasks | Where-Object { $_.issue_id -and -not $issueMap.ContainsKey([string]$_.issue_id) }).Count
    task_chats = @($cloudTasks | Where-Object { $_.chat_session_id -and -not $chatIds.ContainsKey([string]$_.chat_session_id) }).Count
    chat_agents = @($cloudChats | Where-Object { -not $agentMap.ContainsKey([string]$_.agent_id) }).Count
    chat_projects = @($cloudChats | Where-Object { $_.project_id -and -not $projectMap.ContainsKey([string]$_.project_id) }).Count
    chat_creators = @($cloudChats | Where-Object { -not $userMap.ContainsKey([string]$_.creator_id) }).Count
    chat_message_tasks = @($cloudChatMessages | Where-Object { $_.task_id -and -not $taskIds.ContainsKey([string]$_.task_id) }).Count
}
if (($unresolved.Values | Measure-Object -Sum).Sum -ne 0) {
    throw "History contains unresolved references: $($unresolved | ConvertTo-Json -Compress)"
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = "D:\APP\VSCODE-Project\Codex\multica-backups"
[IO.Directory]::CreateDirectory($backupDir) | Out-Null
$exportPath = Join-Path $backupDir "multica-cloud-history-$stamp.json"
$sqlPath = Join-Path $backupDir "multica-cloud-history-$stamp.sql"
$export = [ordered]@{
    exported_at = [DateTimeOffset]::Now.ToString("o")
    cloud_workspace_id = $cloudWorkspaceId
    local_workspace_id = $local.workspace_id
    tasks = $cloudTasks
    task_messages = $cloudTaskMessages
    chat_sessions = $cloudChats
    chat_messages = $cloudChatMessages
    chat_attachments = $cloudChatAttachments
}
[IO.File]::WriteAllText($exportPath, ($export | ConvertTo-Json -Depth 100 -Compress), [Text.UTF8Encoding]::new($false))

$attachmentUrls = @{}
foreach ($attachment in $cloudChatAttachments) {
    $extension = [IO.Path]::GetExtension([string]$attachment.filename)
    if ($extension -notmatch '^\.[A-Za-z0-9]{1,10}$') { $extension = "" }
    $attachmentUrls[[string]$attachment.id] = "/uploads/workspaces/$($local.workspace_id)/$($attachment.id)$extension"
}

$writer = [IO.StreamWriter]::new($sqlPath, $false, [Text.UTF8Encoding]::new($false))
try {
    $writer.WriteLine("BEGIN;")

    foreach ($chat in $cloudChats) {
        $localAgent = $agentMap[[string]$chat.agent_id]
        $localProjectId = if ($chat.project_id) { $projectMap[[string]$chat.project_id].id } else { $null }
        $localCreatorId = $userMap[[string]$chat.creator_id]
        $pinnedAt = if ($chat.pinned) { $chat.updated_at } else { $null }
        $writer.WriteLine((
            "INSERT INTO chat_session (id,workspace_id,agent_id,creator_id,title,status,created_at,updated_at,runtime_id,last_read_at,pinned_at,project_id,explicitly_created_at) VALUES ({0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12}) ON CONFLICT (id) DO NOTHING;" -f
            (Sql-Uuid $chat.id), (Sql-Uuid $local.workspace_id), (Sql-Uuid $localAgent.id), (Sql-Uuid $localCreatorId),
            (Sql-Text $chat.title), (Sql-Text $chat.status), (Sql-Time $chat.created_at), (Sql-Time $chat.updated_at),
            (Sql-Uuid $localAgent.runtime_id), (Sql-Time $chat.updated_at), (Sql-Time $pinnedAt), (Sql-Uuid $localProjectId), (Sql-Time $chat.created_at)
        ))
    }

    foreach ($task in $cloudTasks) {
        $localAgent = $agentMap[[string]$task.agent_id]
        $localIssueId = if ($task.issue_id) { $issueMap[[string]$task.issue_id].id } else { $null }
        $writer.WriteLine((
            "INSERT INTO agent_task_queue (id,agent_id,issue_id,status,priority,dispatched_at,started_at,completed_at,result,error,created_at,runtime_id,work_dir,chat_session_id,attempt,max_attempts,trigger_summary,delivered_comment_ids) VALUES ({0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11},{12},{13},{14},{15},{16},'{{}}'::uuid[]) ON CONFLICT (id) DO NOTHING;" -f
            (Sql-Uuid $task.id), (Sql-Uuid $localAgent.id), (Sql-Uuid $localIssueId), (Sql-Text $task.status),
            (Sql-Int $task.priority), (Sql-Time $task.dispatched_at), (Sql-Time $task.started_at), (Sql-Time $task.completed_at),
            (Sql-Json $task.result), (Sql-Text $task.error), (Sql-Time $task.created_at), (Sql-Uuid $localAgent.runtime_id),
            (Sql-Text $task.work_dir), (Sql-Uuid $task.chat_session_id), (Sql-Int $task.attempt 1), (Sql-Int $task.max_attempts 2),
            (Sql-Text $task.trigger_summary)
        ))
    }

    foreach ($message in $cloudTaskMessages) {
        $writer.WriteLine((
            "INSERT INTO task_message (task_id,seq,type,content,created_at) SELECT {0},{1},{2},{3},{4} WHERE NOT EXISTS (SELECT 1 FROM task_message WHERE task_id={0} AND seq={1});" -f
            (Sql-Uuid $message.task_id), (Sql-Int $message.seq), (Sql-Text $message.type), (Sql-Text $message.content), (Sql-Time $message.created_at)
        ))
    }

    foreach ($message in $cloudChatMessages) {
        $quickActionsSql = if ($message.PSObject.Properties['quick_actions'] -and $null -ne $message.quick_actions) {
            Sql-Json $message.quick_actions
        } else {
            "'[]'::jsonb"
        }
        $messageKind = if ($message.message_kind) { $message.message_kind } else { "message" }
        $writer.WriteLine((
            "INSERT INTO chat_message (id,chat_session_id,role,content,task_id,created_at,failure_reason,elapsed_ms,message_kind,quick_actions) VALUES ({0},{1},{2},{3},{4},{5},{6},{7},{8},{9}) ON CONFLICT (id) DO NOTHING;" -f
            (Sql-Uuid $message.id), (Sql-Uuid $message.chat_session_id), (Sql-Text $message.role), (Sql-Text $message.content),
            (Sql-Uuid $message.task_id), (Sql-Time $message.created_at), (Sql-Text $message.failure_reason),
            $(if ($null -eq $message.elapsed_ms) { "NULL" } else { Sql-Int $message.elapsed_ms }),
            (Sql-Text $messageKind), $quickActionsSql
        ))
    }

    foreach ($attachment in $cloudChatAttachments) {
        $localUploaderId = if ($attachment.uploader_type -eq "agent") {
            $agentMap[[string]$attachment.uploader_id].id
        } else {
            $userMap[[string]$attachment.uploader_id]
        }
        $writer.WriteLine((
            "INSERT INTO attachment (id,workspace_id,uploader_type,uploader_id,filename,url,content_type,size_bytes,created_at,chat_session_id,chat_message_id,task_id) VALUES ({0},{1},{2},{3},{4},{5},{6},{7},{8},{9},{10},{11}) ON CONFLICT (id) DO NOTHING;" -f
            (Sql-Uuid $attachment.id), (Sql-Uuid $local.workspace_id), (Sql-Text $attachment.uploader_type), (Sql-Uuid $localUploaderId),
            (Sql-Text $attachment.filename), (Sql-Text $attachmentUrls[[string]$attachment.id]), (Sql-Text $attachment.content_type),
            (Sql-Int $attachment.size_bytes), (Sql-Time $attachment.created_at), (Sql-Uuid $attachment.chat_session_id),
            (Sql-Uuid $attachment.chat_message_id), (Sql-Uuid $attachment.task_id)
        ))
    }

    $taskIdList = ($cloudTasks | ForEach-Object { "'$($_.id)'" }) -join ","
    $chatIdList = ($cloudChats | ForEach-Object { "'$($_.id)'" }) -join ","
    $chatMessageIdList = ($cloudChatMessages | ForEach-Object { "'$($_.id)'" }) -join ","
    $attachmentIdList = ($cloudChatAttachments | ForEach-Object { "'$($_.id)'" }) -join ","
    if (-not $attachmentIdList) { $attachmentIdList = "'00000000-0000-0000-0000-000000000000'" }
    $writer.WriteLine(
        "SELECT 'MIGRATION_COUNTS|' || " +
        "(SELECT count(*) FROM agent_task_queue WHERE id IN ($taskIdList)) || '|' || " +
        "(SELECT count(*) FROM chat_session WHERE id IN ($chatIdList)) || '|' || " +
        "(SELECT count(*) FROM chat_message WHERE id IN ($chatMessageIdList)) || '|' || " +
        "(SELECT count(*) FROM task_message WHERE task_id IN ($taskIdList)) || '|' || " +
        "(SELECT count(*) FROM attachment WHERE id IN ($attachmentIdList));"
    )
    $writer.WriteLine($(if ($ValidateImport) { "ROLLBACK;" } else { "COMMIT;" }))
} finally {
    $writer.Dispose()
}

if ($Apply) {
    $attachmentDir = Join-Path $backupDir "multica-cloud-history-attachments-$stamp"
    [IO.Directory]::CreateDirectory($attachmentDir) | Out-Null
    $containerDir = "/app/data/uploads/workspaces/$($local.workspace_id)"
    docker exec multica-backend-1 mkdir -p $containerDir | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Failed to prepare local attachment directory" }
    foreach ($attachment in $cloudChatAttachments) {
        $extension = [IO.Path]::GetExtension([string]$attachment.filename)
        if ($extension -notmatch '^\.[A-Za-z0-9]{1,10}$') { $extension = "" }
        $filePath = Join-Path $attachmentDir "$($attachment.id)$extension"
        $downloadUrl = if ([string]$attachment.download_url -match '^https?://') {
            [string]$attachment.download_url
        } elseif ($attachment.download_url) {
            "$($cloud.server_url)$($attachment.download_url)"
        } else {
            [string]$attachment.url
        }
        Invoke-WebRequest -Uri $downloadUrl -Headers @{ Authorization = "Bearer $($cloud.token)" } -OutFile $filePath -TimeoutSec 120
        if ((Get-Item -LiteralPath $filePath).Length -ne [int64]$attachment.size_bytes) {
            throw "Attachment size mismatch: $($attachment.filename)"
        }
        docker cp $filePath "multica-backend-1:$containerDir/$($attachment.id)$extension" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to copy attachment: $($attachment.filename)" }
        $metaPath = "$filePath.meta.json"
        $meta = @{ filename = $attachment.filename; content_type = $attachment.content_type } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($metaPath, $meta, [Text.UTF8Encoding]::new($false))
        docker cp $metaPath "multica-backend-1:$containerDir/$($attachment.id)$extension.meta.json" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to copy attachment metadata: $($attachment.filename)" }
    }
}

$containerSql = "/tmp/multica-cloud-history-$stamp.sql"
docker cp $sqlPath "multica-postgres-1:$containerSql" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Failed to copy migration SQL" }
$psqlOutput = docker exec multica-postgres-1 psql -X -qAt -v ON_ERROR_STOP=1 -U multica -d multica -f $containerSql 2>&1
if ($LASTEXITCODE -ne 0) {
    $tail = @($psqlOutput | Select-Object -Last 20)
    throw "History SQL failed: $($tail -join [Environment]::NewLine)"
}
$countLine = @($psqlOutput | Where-Object { $_ -like "MIGRATION_COUNTS|*" })[-1]
if (-not $countLine) { throw "History SQL did not return validation counts" }
$actual = $countLine.Split("|")
$expected = @(
    @($cloudTasks).Count,
    @($cloudChats).Count,
    @($cloudChatMessages).Count,
    @($cloudTaskMessages).Count,
    @($cloudChatAttachments).Count
)
$validated = $actual.Count -eq 6 -and
    [int64]$actual[1] -eq $expected[0] -and
    [int64]$actual[2] -eq $expected[1] -and
    [int64]$actual[3] -eq $expected[2] -and
    [int64]$actual[4] -eq $expected[3] -and
    [int64]$actual[5] -eq $expected[4]
if (-not $validated) {
    throw "History SQL counts differ: expected=$($expected -join ',') actual=$($actual -join ',')"
}

[ordered]@{
    mode = if ($ValidateImport) { "validate" } else { "apply" }
    validated = $validated
    rows = [ordered]@{
        tasks = $expected[0]
        chat_sessions = $expected[1]
        chat_messages = $expected[2]
        task_messages = $expected[3]
        chat_attachments = $expected[4]
    }
    unresolved = $unresolved
    export_path = $exportPath
    sql_path = $sqlPath
} | ConvertTo-Json -Depth 6 -Compress
