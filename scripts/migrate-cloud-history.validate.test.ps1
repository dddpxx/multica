$ErrorActionPreference = "Stop"

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) {
        throw $Message
    }
}

$migration = Join-Path $PSScriptRoot "migrate-cloud-history.ps1"
$before = docker exec multica-postgres-1 psql -U multica -d multica -At -c `
    "SELECT count(*) FROM agent_task_queue; SELECT count(*) FROM chat_session; SELECT count(*) FROM chat_message; SELECT count(*) FROM task_message;"

$result = & $migration -ValidateImport | ConvertFrom-Json

$after = docker exec multica-postgres-1 psql -U multica -d multica -At -c `
    "SELECT count(*) FROM agent_task_queue; SELECT count(*) FROM chat_session; SELECT count(*) FROM chat_message; SELECT count(*) FROM task_message;"

Assert-True (($before -join ",") -eq ($after -join ",")) "validation changed the local database"
Assert-True ($result.validated -eq $true) "transactional validation did not pass"
Assert-True ($result.rows.tasks -gt 0) "no tasks were prepared"
Assert-True ($result.rows.task_messages -gt 0) "no task messages were prepared"
Assert-True ($result.rows.chat_sessions -gt 0) "no chat sessions were prepared"
Assert-True ($result.rows.chat_messages -gt 0) "no chat messages were prepared"
Assert-True ($result.unresolved.task_agents -eq 0) "some task agents were not mapped"
Assert-True ($result.unresolved.task_issues -eq 0) "some task issues were not mapped"
Assert-True ($result.unresolved.chat_agents -eq 0) "some chat agents were not mapped"
Assert-True ($result.unresolved.chat_projects -eq 0) "some chat projects were not mapped"
Assert-True ($result.unresolved.chat_creators -eq 0) "some chat creators were not mapped"
Assert-True ($result.unresolved.chat_message_tasks -eq 0) "some chat messages reference missing tasks"

"PASS: history import validates inside a rolled-back transaction"
